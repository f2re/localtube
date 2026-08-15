# 🚢 Release process

1. Обновить `app/VERSION` и `CHANGELOG.md`.
2. Выполнить `./scripts/test.sh`.
3. Push в `main` и дождаться зелёного CI на Linux, Windows и macOS.
4. Создать тег `vX.Y.Z`.
5. Workflow `Release` собирает и публикует:
   - `LocalTube-macOS-vX.Y.Z.zip` + `.sha256`;
   - `LocalTube-macOS-vX.Y.Z.dmg` + `.sha256`;
   - `LocalTube-Linux-vX.Y.Z.tar.gz` + `.sha256`;
   - `LocalTube-Windows-vX.Y.Z.zip` + `.sha256`.

Все bootstrap-пакеты создаются из одного commit и содержат одинаковый `app/`, различаясь платформенным installer/control слоем.

## Локальная проверка

```bash
./scripts/test.sh
python3 scripts/verify_release.py
```

Linux и Windows runtime проверяются отдельными GitHub Actions integration jobs. macOS дополнительно проверяет native universal launcher и реальный LaunchAgent-oriented runtime path.

## Developer ID и notarization macOS

Исходная macOS сборка делает ad-hoc подпись, достаточную для технической проверки bundle, но не для полного доверия Gatekeeper. Для публичного бесшовного релиза импортируйте Developer ID Application certificate во временный CI keychain, подпишите оба `.app` до упаковки и отправьте DMG через `xcrun notarytool submit --wait`, затем `xcrun stapler staple`.

Рекомендуемые GitHub Actions secrets: `MACOS_CERTIFICATE_P12`, `MACOS_CERTIFICATE_PASSWORD`, `MACOS_SIGN_IDENTITY`, `APPLE_ID`, `APPLE_TEAM_ID`, `APPLE_APP_PASSWORD`. Не храните сертификаты/пароли в репозитории.
