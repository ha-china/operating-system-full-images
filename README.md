# HAOS Full Images

This repository contains a builder for Home Assistant OS images with preloaded
images of the latest Home Assistant components. This allows for offline
installation of Home Assistant OS with the latest versions and minimal wait
on the first boot.

## Usage

```bash
# Build the builder container
make docker-image

# Build a single image
make build IMAGE=haos_green-17.0.img.xz

# Build all images in input/
make build-all

# Use beta channel
make build IMAGE=haos_green-17.0.img.xz CHANNEL=beta

# Pre-fetch containers
make fetch BOARD=green

# Interactive shell for debugging
make shell
```

## Make Targets

| Target | Description |
|--------|-------------|
| `docker-image` | Build the builder container |
| `build IMAGE=<file>` | Build single full image |
| `build-all` | Build all images in `input/` |
| `fetch BOARD=<name>` | Download containers only |
| `clean` | Clean work directory |
| `shell` | Interactive shell in container |

## Directories

| Path | Description |
|------|-------------|
| `cache/` | Container image cache |
| `input/` | Place HAOS images here |
| `output/` | Built images appear here |


## Embedded Containers

Latest supervisor, homeassistant, dns, audio, cli, multicast, observer

Versions fetched from `version.home-assistant.io` based on `CHANNEL` (default: `stable`).
