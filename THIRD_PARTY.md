# Third-party runtime

LocalTube source/release bootstrap does **not** vendor these tools. They are downloaded during installation and remain subject to their own licenses.

| Component | Preferred source | Purpose |
|---|---|---|
| yt-dlp | `yt-dlp/yt-dlp-nightly-builds` or stable `yt-dlp/yt-dlp` | media extraction/download |
| Deno | `denoland/deno` releases | local TypeScript runtime + YouTube JS challenge runtime |
| FFmpeg / FFprobe | `ffmpeg.martin-riedl.de` signed macOS release builds | merge/remux/audio conversion/probing |

Installer verifies published SHA-256 before activation. See each upstream project for copyright and license terms. yt-dlp may use its EJS challenge scripts according to its own project documentation.
