# Agent Zero - Home Assistant Addon

AI Assistant addon for Home Assistant based on Agent Zero.

## Installation

1. Copy this folder to your Home Assistant addons directory
2. Restart Home Assistant
3. Install the addon from the Add-on Store
4. Configure and start

## Architecture

This addon uses a wrapper approach:
- No Dockerfile modifications needed
- Uses Home Assistant's default base image
- Pulls Agent Zero image at runtime
- Runs nginx for URL rewriting
- Starts Agent Zero in a separate container

This avoids the `build_from` limitation in Home Assistant addon builds.

## Notes

- GitHub device authentication (used by GitHub CLI/Copilot tooling inside the addon) is persisted across restarts.
- If you authenticated once and still get prompted again, update to addon version `1.0.6` or newer and restart the addon once.