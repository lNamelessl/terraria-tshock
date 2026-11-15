#!/usr/bin/env bash
# Terraria + TShock Railway entrypoint.
#
# Wraps the official image entrypoint with:
#   1. one consolidated volume (worlds + TShock data + logs + plugins under /data)
#   2. REST API always enabled, with a per-deploy superadmin token that is
#      generated once and persisted on the volume
#   3. a first-login watchdog that surfaces the TShock setup token as a deploy-log
#      banner plus a default-creds.txt file on the volume (marker-guarded:
#      TShock's own setup.lock/setup-code.txt lifecycle is the guard)
#   4. a graceful stop: on SIGTERM the wrapper sends the console "exit" command
#      so TShock saves the world before quitting
#
# All settings ride TShock.Server CLI flags (CLI overrides config.json on every
# boot), so user edits to config.json survive and REST survives regeneration.
set -u

DATA="${RAILWAY_VOLUME_MOUNT_PATH:-/data}"
TSHOCK_DIR="$DATA/tshock"
WORLDS_DIR="$DATA/worlds"
PLUGINS_DIR="$DATA/plugins"
GAME_PORT=7777
REST_PORT="${REST_PORT:-7878}"
WORLD_NAME="${WORLD_NAME:-Terraria}"
WORLD_SIZE="${WORLD_SIZE:-2}"
WORLD_EVIL="${WORLD_EVIL:-random}"
MAXPLAYERS="${MAXPLAYERS:-16}"
WORLD_FILE="$WORLDS_DIR/$WORLD_NAME.wld"
SAVE_WAIT="${RAILWAY_SAVE_WAIT:-45}"

mkdir -p "$TSHOCK_DIR/logs" "$TSHOCK_DIR/crashes" "$WORLDS_DIR" "$PLUGINS_DIR"

# --- REST token: env override > persisted file > freshly generated -------------
TOKEN_FILE="$TSHOCK_DIR/railway-rest-token"
if [ -z "${REST_TOKEN:-}" ]; then
  if [ -s "$TOKEN_FILE" ]; then
    REST_TOKEN="$(tr -d ' \r\n' < "$TOKEN_FILE")"
  else
    REST_TOKEN="$(head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n')"
    printf '%s' "$REST_TOKEN" > "$TOKEN_FILE"
    chmod 600 "$TOKEN_FILE"
  fi
fi

# --- Server arguments ----------------------------------------------------------
# TShock docs (command-line-parameters): to bypass the interactive startup prompt
# you must pass -world (absolute path), -port and -maxplayers. -autocreate is
# added only when the world file does not exist yet, so a restart can never
# regenerate an existing world.
ARGS=(
  -configpath "$TSHOCK_DIR"
  -logpath "$TSHOCK_DIR/logs"
  -crashdir "$TSHOCK_DIR/crashes"
  -worldselectpath "$WORLDS_DIR"
  -additionalplugins "$PLUGINS_DIR"
  -world "$WORLD_FILE"
  -worldname "$WORLD_NAME"
  -ip 0.0.0.0
  -port "$GAME_PORT"
  -maxplayers "$MAXPLAYERS"
  -noupnp
  -rest-enabled true
  -rest-port "$REST_PORT"
  -rest-token "$REST_TOKEN"
)

if [ ! -f "$WORLD_FILE" ]; then
  ARGS+=( -autocreate "$WORLD_SIZE" -worldevil "$WORLD_EVIL" )
  echo "[railway] No world at $WORLD_FILE — generating a new '$WORLD_NAME' world (size $WORLD_SIZE, evil $WORLD_EVIL)."
fi

if [ -n "${SERVER_PASSWORD:-}" ]; then
  ARGS+=( -pass "$SERVER_PASSWORD" )
fi

echo "[railway] World: $WORLD_NAME  |  Game: 0.0.0.0:$GAME_PORT  |  REST: 0.0.0.0:$REST_PORT (enabled)"

# --- First-login watchdog (runs alongside the server) ---------------------------
write_creds() {
  # $1 = mode: "first-login" or "configured"
  local SETUP_TOKEN_LINE=""
  if [ -f "$TSHOCK_DIR/setup-code.txt" ]; then
    SETUP_TOKEN_LINE="Setup token : $(cat "$TSHOCK_DIR/setup-code.txt")"
  fi
  {
    echo "# Terraria + TShock on Railway — connection and credentials"
    echo "# (regenerated on boot while TShock's first-run setup is pending)"
    echo ""
    echo "Join address  : ${RAILWAY_TCP_PROXY_DOMAIN:-<tcp-proxy-host>}:${RAILWAY_TCP_PROXY_PORT:-$GAME_PORT}"
    [ -n "$SETUP_TOKEN_LINE" ] && echo "$SETUP_TOKEN_LINE"
    echo "REST API      : http://localhost:$REST_PORT inside the container (railway ssh)"
    echo "REST token    : $REST_TOKEN"
    echo ""
    echo "First admin   : join the game, type /setup followed by the setup token"
    echo "                to become superadmin, then create your real account:"
    echo "                /user add YourName YourPassword superadmin"
    echo "                and log in with it. The setup token self-disables once"
    echo "                any account exists (TShock writes setup.lock)."
  } > "$CREDS_FILE"
  chmod 600 "$CREDS_FILE"
}

(
  CREDS_FILE="$TSHOCK_DIR/default-creds.txt"
  SETUP_CODE="$TSHOCK_DIR/setup-code.txt"
  SETUP_LOCK="$TSHOCK_DIR/setup.lock"
  if [ -f "$SETUP_LOCK" ]; then
    write_creds configured
    echo "[railway] TShock is already configured (setup.lock present) — no first-login action needed."
    exit 0
  fi
  waited=0
  while [ "$waited" -lt 300 ]; do
    if [ -f "$SETUP_CODE" ]; then
      SETUP_TOKEN="$(tr -d ' \r\n' < "$SETUP_CODE")"
      write_creds first-login
      echo "=============================================================="
      echo "TSHOCK FIRST LOGIN"
      echo "Join the game and type: /setup $SETUP_TOKEN"
      echo "That grants superadmin. Then create your own account:"
      echo "  /user add YourName YourPassword superadmin"
      echo "Credentials also written to $CREDS_FILE (on the volume)."
      echo "REST token: $REST_TOKEN"
      echo "=============================================================="
      exit 0
    fi
    sleep 5
    waited=$((waited + 5))
  done
  echo "[railway] Watchdog: setup-code.txt did not appear within 300s (world may still be generating)."
) &

# --- Graceful stop: FIFO stdin + SIGTERM -> console "exit" ----------------------
# TShock reads console commands from stdin. A FIFO held open on fd 3 keeps the
# pipe from EOF-ing; on SIGTERM we write "exit" so TShock saves the world.
FIFO="/tmp/tshock-commands"
rm -f "$FIFO"
mkfifo "$FIFO"
exec 3<>"$FIFO"

./TShock.Server "${ARGS[@]}" <"$FIFO" &
GAME_PID=$!

term() {
  echo "[railway] SIGTERM — asking TShock to save the world and exit (up to ${SAVE_WAIT}s)..."
  echo exit >&3
  i=0
  while kill -0 "$GAME_PID" 2>/dev/null && [ "$i" -lt "$SAVE_WAIT" ]; do
    sleep 1
    i=$((i + 1))
  done
  if kill -0 "$GAME_PID" 2>/dev/null; then
    echo "[railway] Graceful save timed out — terminating the server process."
    kill -TERM "$GAME_PID" 2>/dev/null
    sleep 3
    kill -KILL "$GAME_PID" 2>/dev/null
  fi
}
trap term TERM INT

wait "$GAME_PID"
CODE=$?
echo "[railway] TShock exited with code $CODE."
exit "$CODE"
