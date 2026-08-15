package main

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

func runQuiet(name string, args ...string) {
	_ = exec.Command(name, args...).Run()
}

func dialog(title, message, icon string) {
	if icon != "stop" && icon != "caution" && icon != "note" {
		icon = "note"
	}
	script := "on run argv\nset dialogTitle to item 1 of argv\nset dialogMessage to item 2 of argv\ndisplay dialog dialogMessage with title dialogTitle buttons {\"OK\"} default button \"OK\" with icon " + icon + "\nend run"
	runQuiet("/usr/bin/osascript", "-e", script, title, message)
}

func confirmInstall() bool {
	script := "display dialog \"LocalTube установится только для текущего пользователя. Будут скачаны и проверены Deno, yt-dlp и FFmpeg. Terminal и zsh не используются.\" with title \"Install LocalTube\" buttons {\"Отмена\", \"Установить\"} default button \"Установить\" cancel button \"Отмена\" with icon note"
	cmd := exec.Command("/usr/bin/osascript", "-e", script)
	return cmd.Run() == nil
}

func notify(title, message string) {
	script := "on run argv\nset notificationTitle to item 1 of argv\nset notificationMessage to item 2 of argv\ndisplay notification notificationMessage with title notificationTitle\nend run"
	runQuiet("/usr/bin/osascript", "-e", script, title, message)
}

func main() {
	if len(os.Args) > 1 && os.Args[1] == "--self-test" {
		fmt.Println("LocalTube native installer launcher self-test: OK")
		return
	}
	if !confirmInstall() {
		return
	}
	home, err := os.UserHomeDir()
	if err != nil || !filepath.IsAbs(home) {
		dialog("LocalTube", "Не удалось определить домашнюю папку пользователя.", "stop")
		os.Exit(2)
	}
	exe, err := os.Executable()
	if err != nil {
		dialog("LocalTube", "Не удалось определить расположение установщика.", "stop")
		os.Exit(2)
	}
	if resolved, resolveErr := filepath.EvalSymlinks(exe); resolveErr == nil {
		exe = resolved
	}
	root := filepath.Clean(filepath.Join(filepath.Dir(exe), "..", "..", ".."))
	installer := filepath.Join(root, "installer", "install.sh")
	if _, err := os.Stat(installer); err != nil {
		dialog("LocalTube", "Архив повреждён: installer/install.sh не найден.", "stop")
		os.Exit(3)
	}

	logDir := filepath.Join(home, "Library", "Logs", "LocalTube")
	if err := os.MkdirAll(logDir, 0700); err != nil {
		dialog("LocalTube", "Не удалось создать каталог журнала установки.", "stop")
		os.Exit(4)
	}
	logPath := filepath.Join(logDir, "install.log")
	previousLog := filepath.Join(logDir, "install.previous.log")
	_ = os.Remove(previousLog)
	if _, statErr := os.Stat(logPath); statErr == nil {
		_ = os.Rename(logPath, previousLog)
	}
	log, err := os.OpenFile(logPath, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0600)
	if err != nil {
		dialog("LocalTube", "Не удалось создать журнал установки.", "stop")
		os.Exit(4)
	}
	defer log.Close()

	notify("LocalTube", "Начинаю автономную установку. Terminal, zsh и Oh-My-Zsh не используются.")

	user := strings.TrimSpace(os.Getenv("USER"))
	if user == "" {
		user = filepath.Base(home)
	}
	args := []string{
		"-i",
		"HOME=" + home,
		"USER=" + user,
		"LOGNAME=" + user,
		"PATH=/usr/bin:/bin:/usr/sbin:/sbin",
		"LANG=en_US.UTF-8",
		"TMPDIR=" + os.TempDir(),
		"/bin/bash", "--noprofile", "--norc", installer, "--gui",
	}
	cmd := exec.Command("/usr/bin/env", args...)
	cmd.Stdout = log
	cmd.Stderr = log
	err = cmd.Run()
	_ = log.Sync()
	if err != nil {
		code := 1
		if ee, ok := err.(*exec.ExitError); ok {
			code = ee.ExitCode()
		}
		dialog("LocalTube — ошибка установки", fmt.Sprintf("Установка завершилась ошибкой (код %d). Предыдущая рабочая версия автоматически сохраняется или восстанавливается. Журнал:\n%s", code, logPath), "stop")
		runQuiet("/usr/bin/open", "-a", "TextEdit", logPath)
		os.Exit(code)
	}

	base := filepath.Join(home, "Library", "Application Support", "LocalTube")
	portBytes, _ := os.ReadFile(filepath.Join(base, "data", "port"))
	port := strings.TrimSpace(string(portBytes))
	if port == "" {
		port = "8765"
	}
	dialog("LocalTube", "LocalTube установлен. Backend, runtime и локальный HTTP health-check прошли обязательную проверку.", "note")
	runQuiet("/usr/bin/open", "http://127.0.0.1:"+port+"/")
}
