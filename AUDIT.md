# ✅ Production audit — LocalTube 1.3.0

Дата: 2026-08-15.

## Закрытые классы отказов

| Область | Проверка / решение | Статус |
|---|---|---|
| zsh / Oh-My-Zsh | основной installer — native `.app`; shell fallback использует `/bin/bash --noprofile --norc`; user rc не source | ✅ |
| Путь `.command` | исполняемые имена ASCII; README показывает `./...` и абсолютный `/Users/...`; основной путь не `.command` | ✅ |
| CPU | launchers собираются universal Mach-O `x86_64 + arm64` | ✅ |
| macOS | минимальная версия 11; runtime выбирается по `uname -m` | ✅ |
| Частичная установка | download + checksum + self-test выполняются в staging до остановки старого сервиса | ✅ |
| Rollback | app/runtime/plist/GUI/tools/settings-history резервируются и возвращаются при final-health failure/signal | ✅ |
| Активная загрузка | safety gate находится до `TX_ACTIVE`; при недоступном health дополнительно проверяются процессы yt-dlp/FFmpeg | ✅ |
| Конкурентное обслуживание | atomic `.maintenance.lock` не допускает две параллельные установки/полные обновления; stale lock восстанавливается | ✅ |
| Supply chain | HTTPS + upstream SHA-256 + package manifest + archive SHA-256 | ✅ |
| YouTube 2026 | Deno >=2.3, explicit `--js-runtimes`, EJS component fallback | ✅ |
| MP4 | H.264/AAC preference, затем совместимый fallback; предел height не теряется | ✅ |
| Shell injection | `Deno.Command` argument arrays, без shell | ✅ |
| API exposure | `127.0.0.1`, token + Host + Origin checks, no CORS | ✅ |
| Deno privileges | production launcher без `-A`, scoped run/env/net | ✅ |
| yt-dlp config drift | `--ignore-config` | ✅ |
| Updater | staging + rollback; внешний fallback yt-dlp не модифицируется | ✅ |
| Диагностика | runtime health + YouTube extraction check + launchd/log report | ✅ |

## Автоматические проверки

`./scripts/test.sh` выполняет shell syntax, TypeScript/JS syntax, Bash 3.2 guard, cross-build двух архитектур, проверку ZIP modes/layout, package manifest и security regression assertions. `CI` дополняет это реальным macOS runner и runtime self-test.

## Осознанные ограничения

Нельзя гарантировать доступность YouTube как внешнего сервиса: extraction может временно ломаться из-за изменений сайта, геоблоков, rate limits или требования аккаунта. Поэтому yt-dlp обновляемый, диагностика проверяет extraction отдельно, а runtime updater транзакционный. Полностью бесшовный Gatekeeper требует Developer ID и Apple notarization; без Apple signing credentials релиз остаётся ad-hoc signed и открывается через стандартное Finder → Open.

- **Осиротевшие дочерние процессы:** полный install/runtime-update проверяет не только HTTP-очередь, но и процессы текущего `yt-dlp`/`FFmpeg`; runtime не перемещается, пока такой процесс работает.
