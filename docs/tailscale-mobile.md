# Mobile access via Tailscale

The dispatch server (`dispatch/server.py`) is a phone-friendly chat over the whole agent roster. [Tailscale](https://tailscale.com) makes it reachable from your phone over an encrypted WireGuard tunnel. No public-internet exposure, no port forwarding, no reverse proxy.

## Prerequisites

- Tailscale installed and logged in on both the host (running the server) and your phone, on the same tailnet. Check with `tailscale status`. Your phone should be listed.
- The dispatch server running and bound to `0.0.0.0` (the default), so both `localhost` and the tailnet address reach it.

## Start the server

```bash
bin/gen-profiles.sh          # the server reads agents from ~/.hermes/profiles
python3 dispatch/server.py   # Hermes Dispatch on http://0.0.0.0:7777
```

## Reach it by tailnet hostname (works immediately)

Every device on your tailnet has a name. The server is reachable at:

```
http://<your-host>.<tailnet>.ts.net:7777
```

Find `<your-host>.<tailnet>.ts.net` in `tailscale status` (the host's MagicDNS name). Open that URL on your phone and you're done. If you prefer the raw IP, `tailscale ip -4` on the host gives a `100.x.y.z` address, and `http://100.x.y.z:7777` also works.

## Optional: a clean, port-free URL with tailscale serve

To drop the `:7777` and serve on plain port 80 over the tunnel:

```bash
# Set up the clean URL (persists in tailscaled across reboots):
tailscale serve --bg --http=80 http://127.0.0.1:7777

tailscale serve status        # inspect
tailscale serve --http=80 off # remove
```

After that the server is at `http://<your-host>.<tailnet>.ts.net` with no port. Bookmark it on your phone's home screen.

`tailscale serve --http=80` terminates plain HTTP inside the tunnel. The traffic is still encrypted by WireGuard end to end and never touches the public internet. Use `--https=443` instead if you want TLS terminated at the node.

## Configuration

The server binds and routes via environment variables (or `config.yaml`, applied by `setup.sh`):

| Var | Default | Meaning |
|-----|---------|---------|
| `HERMES_DISPATCH_HOST` | `0.0.0.0` | bind host; keep `0.0.0.0` for tailnet reach |
| `HERMES_DISPATCH_PORT` | `7777` | bind port |

## Troubleshooting

- Page won't load: is the phone on the tailnet? `tailscale status` on the host should list it. Is the server up? `curl localhost:7777/healthz` returns `ok`.
- Clean URL down but `:7777` works: re-run the `tailscale serve --bg --http=80` command. If the host's tailnet name changed, `tailscale status` shows the new one.
- Connection refused from the tailnet: the server is bound to `127.0.0.1` instead of `0.0.0.0`. Set `HERMES_DISPATCH_HOST=0.0.0.0`.
- Run it as a background service: wrap `python3 dispatch/server.py` in a launchd (macOS) or systemd (Linux) unit so it survives reboots. The server is stdlib only, so the system `python3` is enough.
