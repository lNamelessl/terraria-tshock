# Terraria + TShock on Railway — thin wrapper around the OFFICIAL Pryaxis image.
#
# Digest-pinned to ghcr.io/pryaxis/tshock:6.2.1 (Terraria 1.4.5.8, TShock 6.2.1,
# published 2026-09-27; multi-arch index digest, linux/amd64 manifest
# sha256:95e82b0c42df7df042c002a6c07b9d175501bce65038baed859653d6690b2195).
# To upgrade: verify the new multi-arch index digest via the GHCR registry API
# (GET https://ghcr.io/v2/pryaxis/tshock/manifests/<tag> with a bearer token from
# https://ghcr.io/token?scope=repository:pryaxis/tshock:pull), replace the digest
# below, rebuild, and re-read https://github.com/Pryaxis/TShock/releases for
# Terraria-version coupling. The --platform pin is load-bearing: the index also
# carries arm64/armv7/windows manifests and some builders resolve the wrong one.
FROM --platform=linux/amd64 ghcr.io/pryaxis/tshock:6.2.1@sha256:70e59a8e6b4c79b5fad469d320962c1fc98625ed3a955510a2f2641dbff2f7e7

# The base image runs as root and ships the Terraria server binary at /server.
# It has NO env-var conventions: every setting is a TShock.Server CLI flag, so
# the wrapper entrypoint below builds the full argument list from these ENVs.
# All of them are overridable post-deploy (Railway Variables tab) — the template
# itself ships with ZERO variables so fresh deploys ask nothing.
ENV WORLD_NAME=Terraria \
    WORLD_SIZE=2 \
    WORLD_EVIL=random \
    MAXPLAYERS=16 \
    REST_PORT=7878

# curl + ss/iproute2 exist purely for operator batteries (railway ssh):
# in-container REST round-trips and listening-port checks. /proc/net/tcp works
# without them, but the whole point of the REST surface is cheap verification.
RUN apt-get update \
 && apt-get install -y --no-install-recommends curl iproute2 \
 && rm -rf /var/lib/apt/lists/*

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

WORKDIR /server
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
