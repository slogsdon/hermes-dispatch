# Private overlay

Contents of this directory are gitignored. Drop Shane-specific (private)
agents here, one per subdirectory (`agents/private/<name>/` with `SOUL.md`,
`agent.yaml`, `run.sh`). They are layered in from the `hermes-private` overlay
repo via its `install-overlay.sh`; nothing here is committed to this public repo.
