package main

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

type healthResponse struct {
	OK      bool `json:"ok"`
	Runtime struct {
		Ready bool `json:"ready"`
	} `json:"runtime"`
}

func runQuiet(name string, args ...string) error { return exec.Command(name, args...).Run() }

func dialog(title, message, icon string) {
	if icon != "stop" && icon != "caution" && icon != "note" {
		icon = "note"
	}
	script := "on run argv\nset dialogTitle to item 1 of argv\nset dialogMessage to item 2 of argv\ndisplay dialog dialogMessage with title dialogTitle buttons {\"OK\"} default button \"OK\" with icon " + icon + "\nend run"
	_ = runQuiet("/usr/bin/osascript", "-e", script, title, message)
}

func validPort(raw string) string {
	p, err := strconv.Atoi(strings.TrimSpace(raw))
	if err != nil || p < 1024 || p > 65535 {
		return "8765"
	}
	return strconv.Itoa(p)
}

func health(base, port string) bool {
	tokenBytes, err := os.ReadFile(filepath.Join(base, "data", "api_token"))
	if err != nil {
		return false
	}
	token := strings.TrimSpace(string(tokenBytes))
	if len(token) < 32 {
		return false
	}
	client := &http.Client{Timeout: 2500 * time.Millisecond}
	req, err := http.NewRequest(http.MethodGet, "http://127.0.0.1:"+port+"/api/health", nil)
	if err != nil {
		return false
	}
	req.Header.Set("X-LocalTube-Token", token)
	resp, err := client.Do(req)
	if err != nil {
		return false
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return false
	}
	limited := io.LimitReader(resp.Body, 64*1024)
	var status healthResponse
	if err := json.NewDecoder(limited).Decode(&status); err != nil {
		return false
	}
	return status.OK && status.Runtime.Ready
}

func main() {
	if len(os.Args) > 1 && os.Args[1] == "--self-test" {
		fmt.Println("LocalTube native launcher: OK")
		return
	}

	home, err := os.UserHomeDir()
	if err != nil || !filepath.IsAbs(home) {
		dialog("LocalTube", "Не удалось определить домашнюю папку.", "stop")
		os.Exit(2)
	}
	base := filepath.Join(home, "Library", "Application Support", "LocalTube")
	portBytes, _ := os.ReadFile(filepath.Join(base, "data", "port"))
	port := validPort(string(portBytes))
	label := "com.localtube.service"
	uid := fmt.Sprintf("%d", os.Getuid())
	domain := "gui/" + uid
	plist := filepath.Join(home, "Library", "LaunchAgents", label+".plist")

	if !health(base, port) {
		if runQuiet("/bin/launchctl", "kickstart", "-k", domain+"/"+label) != nil {
			_ = runQuiet("/bin/launchctl", "bootstrap", domain, plist)
			_ = runQuiet("/bin/launchctl", "enable", domain+"/"+label)
			_ = runQuiet("/bin/launchctl", "kickstart", "-k", domain+"/"+label)
		}
		for i := 0; i < 20 && !health(base, port); i++ {
			time.Sleep(time.Second)
		}
	}
	if health(base, port) {
		if err := runQuiet("/usr/bin/open", "http://127.0.0.1:"+port+"/"); err == nil {
			return
		}
	}
	diag := filepath.Join(home, "Applications", "LocalTube Tools", "DIAGNOSE.command")
	dialog("LocalTube", "Сервис не запустился или runtime не готов. Запустите диагностику:\n"+diag, "stop")
	os.Exit(1)
}
