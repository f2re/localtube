# Third-party runtime

LocalTube source/bootstrap packages do **not** vendor these tools. Installers download platform/architecture-specific binaries during installation. Each component remains subject to its own license.

| Component | Preferred source | Platforms | Purpose |
|---|---|---|---|
| yt-dlp | `yt-dlp/yt-dlp-nightly-builds`, then stable `yt-dlp/yt-dlp` | macOS / Linux / Windows | media extraction and download |
| Deno | `denoland/deno` releases | macOS / Linux / Windows | local TypeScript backend and YouTube JS challenge runtime |
| FFmpeg / FFprobe | Martin Riedl signed builds on macOS; BtbN automated builds on Linux/Windows | macOS / Linux / Windows | merge/remux/audio conversion/probing |

Where an upstream publishes SHA-256 files, the installer verifies the selected binary/archive before activation. The final LocalTube package itself also has a `.sha256` sidecar and an internal `MANIFEST.sha256`.

If a runtime download is unavailable, an installer may use a compatible tool already present on the machine. LocalTube keeps that fallback separate and does not silently update the user's system installation.

See each upstream project for copyright and license terms. yt-dlp may use its EJS challenge components according to its project documentation.
