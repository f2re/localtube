# 🗒️ Changelog

## 1.4.1 — 2026-08-15

- bootstrap macOS/Linux больше не зависит от единственной TLS-сессии к GitHub CDN: curl пробует обычный режим, HTTP/1.1, IPv4 и TLS 1.2, затем доступные альтернативные транспорты;
- успешно проверенные Deno, yt-dlp, FFmpeg и FFprobe сразу сохраняются в persistent SHA-256 cache и переиспользуются после частично неудачной установки;
- при сетевой ошибке installer умеет переиспользовать рабочий runtime уже установленной версии LocalTube, не останавливая сервис до завершения preflight;
- для Deno добавлен официальный альтернативный маршрут через `dl.deno.land`;
- добавлены regression-тесты, воспроизводящие `curl (35) LibreSSL SSL_ERROR_SYSCALL`, полный offline-cache fallback и reuse предыдущего runtime;
- CI дополнен Intel macOS runner для проверки x86_64 runtime и bootstrap.

## Unreleased

- исправлен запуск `./INSTALL.command` непосредственно из macOS `git clone`: source tree больше не ошибочно трактуется как готовый release-пакет с `payload/`;
- source entrypoint временно синтезирует production-layout и dependency-free `LocalTube.app`, затем использует тот же транзакционный `installer/install.sh`, что и Release;
- добавлен `./INSTALL.command --layout-self-test` и macOS regression-test source-checkout layout;
- source bootstrap не требует Go, Python, Homebrew или пользовательского zsh-профиля.

## 1.4.0 — 2026-08-15

- LocalTube переведён с macOS-only на единый backend для macOS, Linux и Windows;
- добавлены Linux installer без `sudo`, user `systemd` service/fallback launcher и desktop entry;
- добавлены Windows installer/controls без admin, Start Menu shortcut и приватный runtime в `%LOCALAPPDATA%`;
- runtime bootstrap выбирает Deno, yt-dlp и FFmpeg/FFprobe по ОС и архитектуре и проверяет контрольные суммы;
- backend получил платформенные пути, `.exe`, выбор папки/cookies, открытие результата, disk info и завершение process tree;
- интерфейс очищен от macOS-only терминов (`Finder`, `⌘V`, «этот Mac»);
- release builder формирует macOS ZIP, Linux tar.gz и Windows ZIP с `.sha256` и внутренним manifest;
- CI расширен реальными Linux/Windows/macOS integration jobs;
- README, SECURITY, THIRD_PARTY, AUDIT и release-документация приведены к общей модели.

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
