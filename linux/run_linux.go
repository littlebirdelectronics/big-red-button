//go:build linux

package main

import (
	"fmt"
	"log"
	"os"
	"os/exec"
	"os/signal"
	"os/user"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"
)

type daemon struct {
	cfg   Config
	combo Combo
	kb    *virtualKeyboard

	mu      sync.Mutex
	holding bool
}

func newDaemon(cfg Config) *daemon {
	d := &daemon{cfg: cfg}
	if cfg.Action == ActionKeys {
		d.combo, _ = ParseCombo(cfg.Keys) // already validated
	}
	if cfg.Action == ActionKeys || cfg.Action == ActionText {
		kb, err := newVirtualKeyboard()
		if err != nil {
			log.Printf("Can't create the virtual keyboard, so key presses won't work: %v", err)
		}
		d.kb = kb
	}
	return d
}

func (d *daemon) handle(edge Edge) {
	d.mu.Lock()
	defer d.mu.Unlock()
	if edge == EdgeRelease {
		log.Print("Button released")
		if d.holding {
			d.holding = false
			if err := d.kb.Up(d.combo); err != nil {
				log.Printf("Releasing keys failed: %v", err)
			}
		}
		return
	}
	log.Print("Button pressed")
	switch d.cfg.Action {
	case ActionKeys:
		if d.kb == nil {
			return
		}
		if err := d.kb.Down(d.combo); err != nil {
			log.Printf("Pressing keys failed: %v", err)
			return
		}
		d.holding = true
	case ActionText:
		if d.kb == nil {
			return
		}
		if err := d.kb.Type(d.cfg.Text); err != nil {
			log.Printf("Typing failed: %v", err)
		}
	case ActionCommand:
		runCommand(d.cfg)
	}
}

// shutdown lets go of any held keys so nothing is left stuck down.
func (d *daemon) shutdown() {
	d.mu.Lock()
	defer d.mu.Unlock()
	if d.holding && d.kb != nil {
		d.kb.Up(d.combo)
		d.holding = false
	}
	if d.kb != nil {
		d.kb.Close()
	}
}

func runDaemon(cfgPath string) int {
	log.SetFlags(0) // journald adds timestamps
	log.SetOutput(os.Stdout)
	log.Printf("bigredbutton %s starting", version)

	cfg, exists, err := LoadConfig(cfgPath)
	switch {
	case err != nil:
		log.Printf("Can't read config, so the button will just press Enter: %v", err)
		cfg = Config{Action: ActionEnter}
	case !exists:
		log.Printf("No config at %s, so the button will just press Enter. Set an action with e.g.: sudo bigredbutton set command 'aplay /usr/share/sounds/alsa/Front_Center.wav'", cfgPath)
	}
	if err := cfg.Validate(); err != nil {
		log.Printf("Config problem, so the button will just press Enter: %v", err)
		cfg = Config{Action: ActionEnter, RunAs: cfg.RunAs, Device: cfg.Device}
	}
	log.Printf("The button %s", cfg.Summary())

	d := newDaemon(cfg)
	sigs := make(chan os.Signal, 1)
	signal.Notify(sigs, syscall.SIGTERM, syscall.SIGINT)
	go func() {
		<-sigs
		d.shutdown()
		os.Exit(0)
	}()

	vid, pid := cfg.VendorProduct()
	watcher{
		vid: vid, pid: pid, grab: cfg.Grabs(),
		logf: log.Printf,
		onConnect: func(nodes []Node) {
			log.Printf("Button connected (%s)", describeNodes(nodes))
		},
		onDisconnect: func(err error) {
			log.Printf("Button disconnected (%v)", err)
		},
		onEdge: d.handle,
	}.run()
	return 0
}

func describeNodes(nodes []Node) string {
	parts := make([]string, len(nodes))
	for i, n := range nodes {
		parts[i] = fmt.Sprintf("%s %q", n.Path, n.Name)
	}
	return strings.Join(parts, ", ")
}

func listen(cfgPath string) int {
	cfg, _, err := LoadConfig(cfgPath)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
	}
	vid, pid := cfg.VendorProduct()
	logf := func(format string, args ...any) { fmt.Printf(format+"\n", args...) }
	stamp := func() string { return time.Now().Format("15:04:05.000") }
	fmt.Println("Listening for the button. Press it! (Ctrl-C to stop)")
	watcher{
		vid: vid, pid: pid, grab: true, logf: logf,
		onConnect: func(nodes []Node) {
			fmt.Println("Button connected:")
			for _, n := range nodes {
				fmt.Printf("  %s  %s\n", n.Path, n.Name)
			}
		},
		onDisconnect: func(err error) { fmt.Printf("Button disconnected (%v)\n", err) },
		onEdge: func(e Edge) {
			if e == EdgePress {
				fmt.Printf("%s  PRESS\n", stamp())
			} else {
				fmt.Printf("%s  RELEASE\n", stamp())
			}
		},
	}.run()
	return 0
}

// testAction runs the configured action once, as if the button had been pressed and released.
func testAction(cfgPath string) int {
	cfg, _, err := LoadConfig(cfgPath)
	if err == nil {
		err = cfg.Validate()
	}
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 1
	}
	log.SetFlags(0)
	fmt.Printf("Testing: the button %s\n", cfg.Summary())
	d := newDaemon(cfg)
	d.handle(EdgePress)
	time.Sleep(200 * time.Millisecond)
	d.handle(EdgeRelease)
	d.shutdown()
	if cfg.Action == ActionCommand {
		time.Sleep(500 * time.Millisecond) // let quick commands print before we exit
	}
	return 0
}

func runCommand(cfg Config) {
	cmd := exec.Command("/bin/sh", "-c", cfg.Command)
	cmd.Stdout, cmd.Stderr = os.Stdout, os.Stderr
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	env, dir, cred, err := commandEnv(cfg.RunAs)
	if err != nil {
		log.Printf("Can't run as %q: %v", cfg.RunAs, err)
		return
	}
	cmd.Env, cmd.Dir = env, dir
	cmd.SysProcAttr.Credential = cred
	if err := cmd.Start(); err != nil {
		log.Printf("Command failed to start: %v", err)
		return
	}
	go func() {
		if err := cmd.Wait(); err != nil {
			log.Printf("Command finished: %v", err)
		}
	}()
}

const commandPath = "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

// commandEnv builds the environment for a command run as runAs, including what desktop
// programs need to find the user's display, sound server and session bus.
func commandEnv(runAs string) (env []string, dir string, cred *syscall.Credential, err error) {
	lang := os.Getenv("LANG")
	if lang == "" {
		lang = "C.UTF-8"
	}
	if runAs == "" || runAs == "root" {
		return []string{"PATH=" + commandPath, "HOME=/root", "USER=root", "LOGNAME=root", "LANG=" + lang}, "/root", nil, nil
	}
	u, err := user.Lookup(runAs)
	if err != nil {
		return nil, "", nil, err
	}
	uid, _ := strconv.ParseUint(u.Uid, 10, 32)
	gid, _ := strconv.ParseUint(u.Gid, 10, 32)
	env = []string{
		"PATH=" + commandPath, "HOME=" + u.HomeDir, "USER=" + u.Username, "LOGNAME=" + u.Username,
		"LANG=" + lang, "DISPLAY=:0",
	}
	runtimeDir := fmt.Sprintf("/run/user/%d", uid)
	if _, err := os.Stat(runtimeDir); err == nil {
		env = append(env, "XDG_RUNTIME_DIR="+runtimeDir)
		if sockets, _ := filepath.Glob(filepath.Join(runtimeDir, "wayland-*")); len(sockets) > 0 {
			for _, s := range sockets {
				if !strings.HasSuffix(s, ".lock") {
					env = append(env, "WAYLAND_DISPLAY="+filepath.Base(s))
					break
				}
			}
		}
		if _, err := os.Stat(filepath.Join(runtimeDir, "bus")); err == nil {
			env = append(env, "DBUS_SESSION_BUS_ADDRESS=unix:path="+filepath.Join(runtimeDir, "bus"))
		}
	}
	if os.Geteuid() != 0 {
		return env, u.HomeDir, nil, nil // can't switch users; run as ourselves
	}
	cred = &syscall.Credential{Uid: uint32(uid), Gid: uint32(gid)}
	if ids, err := u.GroupIds(); err == nil {
		for _, id := range ids {
			if g, err := strconv.ParseUint(id, 10, 32); err == nil {
				cred.Groups = append(cred.Groups, uint32(g))
			}
		}
	}
	return env, u.HomeDir, cred, nil
}

func hasSystemd() bool {
	_, err := os.Stat("/run/systemd/system")
	return err == nil
}

func serviceState() string {
	if !hasSystemd() {
		return "systemd not found"
	}
	out, _ := exec.Command("systemctl", "is-active", "bigredbutton").Output()
	return strings.TrimSpace(string(out))
}

func restartService() error {
	if !hasSystemd() {
		return nil
	}
	if err := exec.Command("systemctl", "cat", "bigredbutton").Run(); err != nil {
		return nil // service not installed (e.g. trying it out by hand)
	}
	out, err := exec.Command("systemctl", "restart", "bigredbutton").CombinedOutput()
	if err != nil {
		return fmt.Errorf("systemctl restart bigredbutton: %v: %s", err, strings.TrimSpace(string(out)))
	}
	fmt.Println("Restarted the bigredbutton service.")
	return nil
}
