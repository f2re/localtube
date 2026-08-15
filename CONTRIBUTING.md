# 🛠️ Contributing

Перед PR запустите `./scripts/test.sh`. Shell-код установки должен оставаться совместимым с системным Apple Bash 3.2 и не должен source пользовательские профили. Backend не должен получать npm/jsr runtime-зависимости без отдельного обоснования: установленный LocalTube должен работать автономно после bootstrap.

Изменения download-command обязаны сохранять: YouTube URL allowlist, `--ignore-config`, выбранный предел resolution, отсутствие shell-интерполяции и rollback updater semantics.
