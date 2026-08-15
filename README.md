<div align="center">

# 🎬 LocalTube

**Локальная загрузка видео и аудио с YouTube для macOS, Linux и Windows.**
Один интерфейс, один backend, локальное хранение и никакого облачного сервиса LocalTube.

[![CI](https://github.com/f2re/localtube/actions/workflows/ci.yml/badge.svg)](https://github.com/f2re/localtube/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/f2re/localtube?display_name=tag&sort=semver)](https://github.com/f2re/localtube/releases)
[![macOS](https://img.shields.io/badge/macOS-11%2B-111111?logo=apple)](https://github.com/f2re/localtube)
[![Linux](https://img.shields.io/badge/Linux-x86__64%20%7C%20arm64-333?logo=linux)](https://github.com/f2re/localtube)
[![Windows](https://img.shields.io/badge/Windows-10%2F11-0078d4?logo=windows)](https://github.com/f2re/localtube)
[![License: MIT](https://img.shields.io/badge/license-MIT-2ea44f)](LICENSE)
[![yt-dlp](https://img.shields.io/badge/engine-yt--dlp-ff3040)](https://github.com/yt-dlp/yt-dlp)

</div>

LocalTube превращает `yt-dlp + FFmpeg + Deno` в обычное локальное приложение: вставляете ссылку → LocalTube определяет видео и доступное качество → выбираете видео или аудио → файл сохраняется в выбранной папке.

Интерфейс открывается в браузере, но backend слушает **только `127.0.0.1`**. Данные, история и настройки остаются на компьютере.

![Главный экран LocalTube](docs/screenshots/main.png)

## ✨ Что умеет

- 🎥 видео в лучшем качестве или с ограничением 2160p / 1440p / 1080p / 720p / 480p / 360p;
- 📦 MP4, MKV или исходный контейнер; для MP4 приоритет H.264/AAC без обязательного перекодирования;
- 🎧 M4A, MP3, Opus, FLAC или исходный аудиопоток;
- 📚 плейлисты, очередь, прогресс, скорость, ETA, отмена и история;
- 📁 выбор папки и открытие готового файла средствами текущей ОС;
- 🍪 cookies из браузера или `cookies.txt`, когда YouTube требует авторизацию;
- 🩺 диагностика `yt-dlp / FFmpeg / Deno / YouTube`;
- 🔄 безопасное обновление `yt-dlp`;
- 📴 после установки интерфейс и backend не требуют npm, pip или системной Node.js;
- 🔐 localhost-only API с локальным токеном и ограниченными правами Deno.

![Аудио и дополнительные параметры](docs/screenshots/audio-settings.png)

## 🖥️ Поддерживаемые платформы

| ОС | Архитектуры | Установка | Автозапуск |
|---|---|---|---|
| **macOS 11+** | Apple Silicon, Intel x86_64 | `Install LocalTube.app` или `./INSTALL.command` из source checkout | LaunchAgent |
| **Linux** | x86_64, arm64/aarch64 | `./INSTALL.sh` без `sudo` | `systemd --user`, если доступен |
| **Windows 10/11** | x64, ARM64 | `INSTALL.ps1` без администратора | запуск из меню «Пуск» |

Все три пакета содержат одинаковый web/backend-код. Отличаются только bootstrap-установщик, управление процессом, диалоги выбора файлов и runtime-бинарники для конкретной ОС.

## 🚀 Установка

Готовые архивы публикуются в **Releases**:

- `LocalTube-macOS-vX.Y.Z.zip`
- `LocalTube-Linux-vX.Y.Z.tar.gz`
- `LocalTube-Windows-vX.Y.Z.zip`

Рядом с каждым архивом публикуется файл `.sha256`. Внутри release-пакета также есть `MANIFEST.sha256` для проверки содержимого.

### 🍎 macOS — готовый Release

1. Скачайте `LocalTube-macOS-...zip` и распакуйте.
2. Запустите **`Install LocalTube.app`**.
3. Установщик скачает Deno, `yt-dlp`, FFmpeg и FFprobe для вашего CPU, проверит SHA-256 и выполнит self-test.
4. Запускайте `~/Applications/LocalTube.app`.

Основной `.app`-установщик не зависит от `.zshrc`, Oh-My-Zsh, Homebrew shellenv или pyenv. Резервный `INSTALL.command` в release-пакете использует тот же production installer.

Если Gatekeeper предупреждает о неизвестном разработчике, откройте приложение через Finder → правый клик → **Открыть**. Полностью бесшовный Gatekeeper требует Developer ID и нотарификации Apple.

### 🍎 macOS — установка прямо из `git clone`

Source checkout и готовый Release имеют **разную структуру**. В репозитории исходники находятся в `app/`, `control/`, `installer/`, а генерируемые `payload/` и `app-template/` появляются только при сборке релиза. Поэтому **не запускайте `installer/install.sh` напрямую из клона**.

Из корня репозитория используйте:

```bash
git pull
./INSTALL.command
```

`INSTALL.command` автоматически определяет, что запущен из source checkout, собирает во временном каталоге совместимый production-layout, создаёт локальный `.app` launcher системными средствами macOS и передаёт его тому же `installer/install.sh`, который используется в GitHub Release. Для этого **не требуются Go, Python, Homebrew или zsh**. Временный каталог удаляется после завершения установки.

Для проверки только структуры, без установки runtime и без изменения системы:

```bash
./INSTALL.command --layout-self-test
```

Ожидаемый результат:

```text
LocalTube source-checkout layout self-test: OK
```

Source install намеренно доверяет содержимому текущего Git checkout; `MANIFEST.sha256` относится к собранным release-архивам. Скачиваемые Deno/yt-dlp/FFmpeg при этом проверяются теми же upstream SHA-256, что и при обычной release-установке.

### 🐧 Linux

1. Скачайте `LocalTube-Linux-...tar.gz`.
2. Распакуйте и откройте каталог:
   ```bash
   tar -xzf LocalTube-Linux-v*.tar.gz
   cd LocalTube-Linux-v*
   ```
3. Запустите:
   ```bash
   ./INSTALL.sh
   ```
4. После установки используйте пункт **LocalTube** в меню приложений или команду:
   ```bash
   ~/.local/bin/localtube
   ```

Установка выполняется **без `sudo`** в `${XDG_DATA_HOME:-~/.local/share}/localtube`. Если доступен `systemd --user`, создаётся пользовательский сервис. Если его нет, launcher запускает локальный процесс напрямую.

Для нативного графического выбора папки рекомендуется `zenity` или `kdialog`. Без них сам сервис и загрузка работают, но папку удобнее предварительно задать в настройках/конфигурации.

### 🪟 Windows

1. Скачайте `LocalTube-Windows-...zip` и распакуйте.
2. Запустите **`INSTALL.ps1`** через PowerShell.
3. Если политика Windows блокирует локальный скрипт, из каталога пакета выполните:
   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File .\INSTALL.ps1
   ```
4. После установки запускайте **LocalTube** из меню «Пуск».

Приложение устанавливается без прав администратора в `%LOCALAPPDATA%\LocalTube`. Runtime и настройки не пишутся в `Program Files` и не требуют системной установки Python/Node.js.

## 🧱 Архитектура

```text
                        ┌───────────────────────────────┐
                        │  Browser UI                  │
                        │  http://127.0.0.1:<port>/    │
                        └──────────────┬────────────────┘
                                       │ local token
                                       ▼
                         ┌──────────────────────────┐
                         │ Deno + app/server.ts     │
                         │ localhost only           │
                         └───────────┬──────────────┘
                                     │
                    ┌────────────────┼────────────────┐
                    ▼                ▼                ▼
                 yt-dlp           FFmpeg          FFprobe
                    │
                  YouTube

macOS:   LaunchAgent + LocalTube.app + Finder/osascript
Linux:   systemd --user/fallback + xdg-open + zenity/kdialog
Windows: PowerShell launcher + Explorer + Windows Forms dialogs
```

Каталоги данных:

```text
macOS    ~/Library/Application Support/LocalTube/
Linux    ${XDG_DATA_HOME:-~/.local/share}/localtube/
Windows  %LOCALAPPDATA%\LocalTube\
```

Backend, runtime, данные, логи и кэш разделены внутри каталога приложения.

## 📦 Runtime

Установщик подбирает runtime по ОС и архитектуре:

- **Deno** — официальный release;
- **yt-dlp** — официальный nightly, затем stable fallback;
- **FFmpeg / FFprobe** — готовая сборка для соответствующей платформы;
- если сетевой bootstrap недоступен, Unix/Windows installer может использовать совместимую локальную установку как fallback, не изменяя её.

Скачанные компоненты проходят SHA-256-проверку там, где upstream публикует контрольные суммы. Активные версии и происхождение компонентов записываются в `runtime/manifest.json`.

### Изоляция локального API от proxy и `.curlrc`

Запросы LocalTube к собственному API на `127.0.0.1` всегда выполняются напрямую: пользовательский `~/.curlrc` отключается (`curl -q`), а proxy обходится (`--noproxy '*'`). На macOS установщик дополнительно умеет проверить health через сырой HTTP поверх системного `nc`, поэтому локальная конфигурация curl не может сама по себе сорвать установку. Внешние загрузки runtime при этом остаются отдельным транспортным контуром.

### Устойчивость bootstrap к сетевым сбоям

Установщик не считает кратковременный сбой GitHub CDN фатальным с первой попытки. Для HTTPS-загрузок последовательно используются повторные попытки `curl`, HTTP/1.1, IPv4 и ограничение TLS 1.2; если на машине уже есть другой download transport, он также может быть использован как fallback. Deno дополнительно может быть получен с официального `dl.deno.land`.

После успешной SHA-256-проверки каждый runtime-компонент сразу сохраняется в пользовательский verified cache. Поэтому если, например, Deno уже скачался, а сеть оборвалась на yt-dlp, следующая установка **не обязана скачивать Deno заново**. При обновлении также может быть переиспользован текущий рабочий runtime. На macOS кэш находится внутри `~/Library/Application Support/LocalTube/cache/bootstrap/`, на Linux — внутри `${XDG_DATA_HOME:-~/.local/share}/localtube/cache/bootstrap/`.

## 🔐 Безопасность и приватность

- сервер привязан к `127.0.0.1`, а не к LAN-интерфейсу;
- API использует случайный локальный токен;
- проверяются `Host` и `Origin`;
- CORS не включён;
- пользовательские URL проходят allowlist YouTube/youtu.be;
- `yt-dlp` всегда запускается с `--ignore-config`;
- subprocess вызываются через `Deno.Command`, без shell-интерполяции пользовательского ввода;
- Deno получает только необходимые файловые, сетевые и process-разрешения;
- runtime хранится отдельно от системных инструментов.

Подробности: [SECURITY.md](SECURITY.md) и [AUDIT.md](AUDIT.md).

## 🔄 Обновления

Из интерфейса можно обновить собственный `yt-dlp`. Если LocalTube использует внешний fallback-runtime, самообновление этой внешней копии блокируется: системная установка пользователя не должна изменяться скрытно.

Полное обновление выполняется платформенным installer/control-механизмом. Настройки и история хранятся отдельно от кода/runtime и сохраняются при штатном обновлении.

## 🧪 Разработка и проверка

Базовые проверки:

```bash
./scripts/test.sh
```

Они выполняют:

- shell/PowerShell/static checks;
- TypeScript/JavaScript validation;
- проверку ограничений безопасности;
- сборку macOS universal launcher;
- сборку **трёх** bootstrap-пакетов;
- проверку структуры архивов и SHA-256;
- на macOS — отдельный regression-test source-checkout → temporary production-layout.

GitHub Actions дополнительно запускает integration tests на:

- Ubuntu/Linux;
- Windows;
- настоящем macOS runner.

На всех трёх ОС integration-проходы разворачивают тот же runtime, который использует пользовательский installer, и проверяют backend self-test и запуск ограниченного локального сервера. На macOS дополнительно проверяется HTTP queue/download flow; live-проверка YouTube учитывает возможную anti-bot блокировку IP GitHub-hosted runner и в таком случае отдельно проверяет локальный медиаконвейер.

См. [CONTRIBUTING.md](CONTRIBUTING.md) и [docs/RELEASING.md](docs/RELEASING.md).

## ⚖️ Использование

LocalTube — оболочка над открытыми инструментами и не обходит DRM. Сохраняйте только материалы, которые вы вправе загружать. Правила платформы и законодательство зависят от юрисдикции и конкретного контента. Проект не связан с YouTube или Google.

## 📄 Лицензия

Код LocalTube — [MIT](LICENSE). Сторонние runtime-компоненты имеют собственные лицензии; источники и лицензии перечислены в [THIRD_PARTY.md](THIRD_PARTY.md).
