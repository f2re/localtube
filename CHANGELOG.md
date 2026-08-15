# 🗒️ Changelog

## 1.3.0 — 2026-08-15

- штатная установка перенесена в нативный universal `Install LocalTube.app`, не зависящий от Terminal/zsh/.zshrc;
- bootstrap стал транзакционным: runtime скачивается и проверяется до остановки старой версии, при ошибке выполняется rollback;
- добавлена поддержка Apple Silicon и Intel одним universal Mach-O launcher;
- Deno запускается с ограниченными permissions вместо `-A` в рабочем сервисе;
- runtime скачивается по HTTPS с upstream SHA-256; добавлен manifest источников;
- Deno >= 2.3 и EJS runtime явно передаются современному yt-dlp;
- MP4 выбирает H.264/AAC при наличии, сохраняя выбранный предел разрешения;
- добавлена строгая allowlist-валидация YouTube URL и защита local API Host/Origin/token;
- безопасное обновление yt-dlp с rollback; внешние fallback-установки не модифицируются;
- добавлены CI, macOS integration tests, релизная сборка ZIP/DMG и полный набор документации.
