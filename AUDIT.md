# ✅ Production audit — LocalTube 1.4.0

Дата: 2026-08-15.

## Поддерживаемые платформы

| Платформа | Архитектуры | Runtime | Управление |
|---|---|---|---|
| macOS 11+ | arm64, x86_64 | Deno + yt-dlp + FFmpeg/FFprobe | LaunchAgent + native launcher |
| Linux | arm64/aarch64, x86_64 | Deno + yt-dlp + FFmpeg/FFprobe | systemd --user или direct fallback |
| Windows 10/11 | ARM64, x64 | Deno.exe + yt-dlp.exe + FFmpeg/FFprobe | user PowerShell launcher |

## Закрытые классы отказов

| Область | Проверка / решение | Статус |
|---|---|---|
| Один backend | `app/server.ts` содержит платформенный слой, бизнес-логика и HTTP API общие | ✅ |
| Runtime paths | `.exe` выбирается только на Windows; Unix использует обычные executable names | ✅ |
| Пользовательская установка | Linux без `sudo`, Windows без admin, macOS в user space | ✅ |
| CPU | runtime выбирается по архитектуре; macOS launchers universal `x86_64 + arm64` | ✅ |
| Частичная установка | runtime разворачивается в staging и проходит self-test до активации | ✅ |
| Supply chain | HTTPS + upstream SHA-256 там, где опубликован + package manifest + archive SHA-256 | ✅ |
| YouTube 2026 | Deno >=2.3, explicit JS runtime, EJS component support | ✅ |
| MP4 | H.264/AAC preference, совместимый fallback, предел height сохраняется | ✅ |
| Shell injection | `Deno.Command` argument arrays, без shell-интерполяции URL | ✅ |
| API exposure | `127.0.0.1`, token + Host + Origin checks, no CORS | ✅ |
| Deno privileges | production launchers без `-A`, scoped run/env/net | ✅ |
| yt-dlp config drift | `--ignore-config` | ✅ |
| Native UX | Finder/osascript, xdg-open + zenity/kdialog, Explorer + Windows Forms | ✅ |
| CI | static + Linux integration + Windows integration + macOS integration | ✅ |
| Release | macOS ZIP/DMG, Linux tar.gz, Windows ZIP, SHA-256 для каждого | ✅ |

## Автоматические проверки

`./scripts/test.sh` выполняет shell/static проверки, TypeScript/JavaScript syntax, Bash 3.2 guard, кросс-сборку macOS native launchers, сборку трёх bootstrap-пакетов, проверку archive layout/modes/manifests и security regression assertions.

GitHub Actions дополняет это реальными platform runners. Linux/Windows/macOS integration разворачивают runtime тем же кодом, что пользовательский installer, и выполняют backend self-test. Linux и Windows проверяют запуск ограниченного локального сервера и health API; macOS дополнительно проверяет HTTP queue/download flow.

## Осознанные ограничения

Доступность YouTube как внешнего сервиса не гарантируется: extraction может временно ломаться из-за изменений сайта, геоблоков, rate limits, anti-bot ограничений datacenter IP или требования аккаунта. Поэтому runtime health и YouTube extraction проверяются отдельно, а CI не принимает сетевую anti-bot блокировку GitHub runner за поломку локального runtime.

На Linux нативный выбор папки требует установленного `zenity` или `kdialog`; сам backend от них не зависит. На macOS бесшовный Gatekeeper требует Developer ID/notarization. На Windows локальный PowerShell script может потребовать разовый `-ExecutionPolicy Bypass` в зависимости от политики машины.
