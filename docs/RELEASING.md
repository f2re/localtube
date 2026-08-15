# 🚢 Release process

1. Обновить `app/VERSION` и `CHANGELOG.md`.
2. Выполнить `./scripts/test.sh`.
3. Push в `main` и дождаться зелёного `CI` на macOS.
4. Создать тег `vX.Y.Z`. Workflow `Release` собирает bootstrap ZIP, SHA-256 и DMG на macOS и публикует GitHub Release через `gh`.

## Developer ID и notarization

Исходная сборка делает ad-hoc подпись, достаточную для проверки целостности bundle, но не для доверия Gatekeeper. Для публичного бесшовного релиза импортируйте Developer ID Application certificate в временный CI keychain, подпишите оба `.app` до упаковки и отправьте DMG через `xcrun notarytool submit --wait`, затем `xcrun stapler staple`.

Рекомендуемые GitHub Actions secrets: `MACOS_CERTIFICATE_P12`, `MACOS_CERTIFICATE_PASSWORD`, `MACOS_SIGN_IDENTITY`, `APPLE_ID`, `APPLE_TEAM_ID`, `APPLE_APP_PASSWORD`. Не храните сертификаты/пароли в репозитории.
