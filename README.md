# terraria-tshock

Terraria dedicated server with the TShock management layer (permissions, accounts, anti-grief, REST API) — packaged for Railway with zero deploy-time prompts.

Official image, digest-pinned: `ghcr.io/pryaxis/tshock:6.2.1` (index `sha256:70e59a8e6b4c79b5fad469d320962c1fc98625ed3a955510a2f2641dbff2f7e7`), which bundles **Terraria 1.4.5.8** — connecting clients must match that game version.

[![Deploy on Railway](https://railway.com/button.svg)](https://railway.app/new?github_url=https://github.com/lNamelessl/terraria-tshock)

## How it works

- Single service, single volume at `/data`, single TCP proxy on the game port (7777 internal; Terraria multiplayer is TCP-only — no UDP anywhere).
- The wrapper entrypoint runs the official image's own server binary with image-native CLI flags: consolidated paths under `/data`, REST enabled with a per-deploy token, and `-autocreate` passed **only while the world file is absent** so a restart can never re-generate an existing world.
- On SIGTERM the wrapper sends the console `exit` command so TShock saves the world before the process quits.
- No platform healthcheck by design (the game is a fixed-port TCP service; Railway's probe targets the injected PORT variable — wrong port). Deployments go active on container start; liveness is provable via the REST status endpoint.

## First admin

1. Deploy. Open View Logs and wait for the `TSHOCK FIRST LOGIN` banner (first boot generates the world, ~1–2 min).
2. Join via the TCP proxy host:port (Networking tab) and type `/setup TOKEN` from the banner — you are superadmin.
3. Create your account and log in with it: `/user add YourName YourPassword superadmin`.

The same details live at `/data/tshock/default-creds.txt` on the volume (`railway ssh`). The setup token self-disables once any account exists (TShock writes `setup.lock`); the banner never re-fires.

## REST API (internal to the container / private network)

Enabled on port 7878. Token auth is a query parameter; the token is generated once at first boot, persisted to `/data/tshock/railway-rest-token`, and registered with superadmin rights.

```bash
railway ssh -s terraria
curl -s http://127.0.0.1:7878/v2/server/status                     # no token needed
# {"name":"Terraria","tshockversion":"6.2.1.0","port":7777,"playercount":0,...}
curl -s "http://127.0.0.1:7878/tokentest?token=$REST_TOKEN"        # token proof
curl -s -X POST "http://127.0.0.1:7878/v3/server/rawcmd" \
     -d "cmd=whoami&token=$REST_TOKEN"                             # management
```

Rate limit: 5 requests per minute bucket by default (`RESTMaximumRequestsPerInterval` in config.json). The REST surface is deliberately not exposed publicly; use `railway ssh` or a private-network caller.

## Volume layout

```
/data
├── tshock/           TShock data: config.json, tshock.db, setup-code.txt / setup.lock,
│   ├── logs/         daily text logs
│   ├── crashes/      crash dumps
│   ├── backups/      automatic world backups (interval/keep in config.json)
│   ├── default-creds.txt     first-login details (safe to delete once configured)
│   └── railway-rest-token    REST API token (mode 600)
├── worlds/           Terraria.wld and friends
└── plugins/          extra TShock plugins (loaded in addition to bundled ServerPlugins)
```

TShock's config.json is user-editable and survives redeploys; REST stays enabled regardless because the wrapper passes CLI overrides on every boot.

## Variables (all optional — deploy asks nothing)

| Variable | Default | Notes |
| --- | --- | --- |
| `WORLD_NAME` | `Terraria` | Changes which world file is loaded (and generated if absent) |
| `WORLD_SIZE` | `2` | New worlds only: 1 small, 2 medium, 3 large |
| `WORLD_EVIL` | `random` | New worlds only: `random`, `corrupt`, `crimson` |
| `MAXPLAYERS` | `16` | Up to 255 |
| `SERVER_PASSWORD` | empty | Empty = TShock account auth is the gate |
| `REST_TOKEN` | generated | Forces a specific REST token instead of the persisted one |
| `REST_PORT` | `7878` | Internal REST listen port |
| `RAILWAY_SAVE_WAIT` | `45` | Seconds to wait for the graceful save on SIGTERM |

## Local development

```bash
docker build -t terraria-tshock .
docker run --rm -p 7777:7777 -p 7878:7878 -e RAILWAY_VOLUME_MOUNT_PATH=/data \
  -v "$PWD/data:/data" terraria-tshock
```

## Upgrading

Bump the pinned digest in the Dockerfile to the new `ghcr.io/pryaxis/tshock` tag and check the [TShock releases](https://github.com/Pryaxis/TShock/releases) for the coupled Terraria version — clients must match. Back up the volume (or at least `/data/tshock` + `/data/worlds`) before changing TShock versions.
