A Terraria dedicated server with the TShock management layer, packaged for Railway: the official Pryaxis Docker image, digest-pinned, with permissions, chat, anti-grief, and a built-in REST API — one service, one volume, zero deploy questions.

[![Deploy on Railway](https://railway.com/button.svg)](https://railway.app/new?github_url=https://github.com/lNamelessl/terraria-tshock)

## What you get

- **Terraria 1.4.5.8 dedicated server with TShock 6.2.1** — the standard server mod for permissions, user accounts, regions, chat formatting, and grief protection. The image is the official ghcr.io/pryaxis/tshock build, pinned by digest.
- **Zero deploy prompts.** Everything has a working default: a medium world named Terraria, 16 player slots, REST API enabled with a per-deploy superadmin token generated at first boot. Tune anything later from the Variables tab (see below).
- **First-run admin made obvious.** The deploy log shows a TSHOCK FIRST LOGIN banner with the one-time setup token, and the same details land in default-creds.txt on the volume.
- **REST API as the control surface.** TShock's REST endpoints answer on port 7878 inside the container (status without a token, full management with the REST token) — usable for dashboards, bots, and health checks without a game client.
- **Persistent by design.** One volume holds the world, the TShock database and config, logs, backups, and your plugins. On stop, the wrapper asks TShock to save the world gracefully before the process exits.
- **A Railway-shaped game server.** Terraria multiplayer is TCP 7777 only — no UDP anywhere — so a single TCP proxy fronts it cleanly.

## Game version notice

This server runs **TShock 6.2.1 for Terraria PC 1.4.5.8**. Players must connect with a matching game client version. This is a game server, not a browser-playable Terraria client. When TShock ships a new Terraria version, update by re-pinning the image digest in the repo and redeploying.

## First admin, in three minutes

1. Deploy, then open Deployments and View Logs. Wait for the yellow TShock setup line and the TSHOCK FIRST LOGIN banner (first boot generates the world, which takes a minute or two).
2. Join the game via the TCP proxy address from Networking and type /setup followed by the token from the banner. You are now superadmin.
3. Create your real account and log in with it: /user add YourName YourPassword superadmin. The setup token self-disables once any account exists (TShock writes setup.lock), and the banner never re-fires.

The same details are always available via railway ssh by reading /data/tshock/default-creds.txt.

## Tunes and knobs (all optional, none required at deploy time)

| Setting | Default | How to change |
| --- | --- | --- |
| World name | Terraria | Set WORLD_NAME, then delete the old world file on the volume |
| World size (new worlds only) | 2 (1 small, 2 medium, 3 large) | Set WORLD_SIZE before the first boot |
| World evil (new worlds only) | random | Set WORLD_EVIL to corrupt or crimson |
| Player slots | 16 | Set MAXPLAYERS (up to 255) |
| Server password | empty — TShock account auth is the gate | Set SERVER_PASSWORD |
| REST token | generated once, persisted on the volume | Set REST_TOKEN to force a specific token |
| Game port | 7777 | Fixed — the TCP proxy targets it |
| REST port | 7878 | Set REST_PORT (internal only) |

TShock's own config.json, MOTD, groups, and permissions live on the volume under /data/tshock and survive redeploys; the wrapper passes CLI overrides on every boot, so REST stays enabled even if the config file is ever regenerated.

# Deploy and Host

## About Hosting

One service, one volume, one TCP proxy. The container runs the official ghcr.io/pryaxis/tshock image (digest-pinned to 6.2.1 for Terraria 1.4.5.8) behind a small wrapper entrypoint that:

- mounts a single Railway volume at /data and points TShock at /data/tshock (config, SQLite user database, logs, crash dumps, backups), /data/worlds, and /data/plugins;
- generates a world on first boot only (a -autocreate flag is passed just while the world file is absent, so a restart can never re-generate an existing world);
- enables the REST API with a per-deploy token and persists it to the volume;
- on SIGTERM, sends the console exit command so the world saves before shutdown (a graceful-save that survives Railway's drain window for typical world sizes).

Players connect through the public TCP proxy hostname and external port shown in the service Networking settings. Port 7777 is the internal game port, not the external one. There is no HTTP surface and no platform healthcheck by design — the game is a fixed-port TCP service — so deployments go active when the container starts; liveness is trivially provable with the REST status endpoint over railway ssh. World generation for a medium world used about 0.5 GB of RAM in validation; budget about 1 GB for comfort.

## Why Deploy

- **Zero prompts versus zero clicks:** the deploy form asks nothing; defaults are sensible and every one is overridable post-deploy.
- **The official image, pinned:** ghcr.io/pryaxis/tshock by digest — not a third-party repackage — with the exact TShock and Terraria versions documented here.
- **A verifiable server:** the built-in REST API answers status queries (player count, world, uptime, version) from inside the container, so you can prove the server is healthy without joining the game, and drive management tasks (raw console commands, user management, bans) with the REST token.
- **Ops details already solved:** world persistence in one volume, no-restart world regeneration guard, superadmin onboarding in the deploy log, and a saving shutdown on redeploy.

## Common Use Cases

- A persistent co-op or friends-and-family world that costs nothing while idle and is billed per second while played.
- Moderated public servers: TShock accounts, permissions, regions, ban management, anti-grief defaults.
- Plugin-driven servers: drop TShock plugins into /data/plugins (loaded in addition to the bundled ServerPlugins) and manage the server over REST.
- Automation: dashboards and bots reading server status, or issuing console commands, over the REST API.

## Dependencies for

### Deployment Dependencies

- [TShock 6.2.1](https://github.com/Pryaxis/TShock/releases/tag/v6.2.1) — for Terraria 1.4.5.8
- [Official TShock Docker image on GHCR](https://github.com/Pryaxis/TShock) — digest-pinned in the repo Dockerfile
- One Railway volume (default size is fine; worlds and TShock data are small) and one TCP proxy targeting port 7777

## Honest positioning

A Railway listing named terraria-dedicated-server (by Xav's Projects) already serves this niche on a third-party base image with seven deploy-form variables and a custom readiness endpoint. This template ships the official Pryaxis image, pins the digest, asks no deploy questions, and exposes TShock's REST API as a built-in verification and management surface. Pick whichever fits; if you want zero prompts and the official image, deploy this one.
