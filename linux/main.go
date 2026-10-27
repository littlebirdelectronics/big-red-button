// bigredbutton makes the Little Bird Big Red Button (USB 8189:0019) run a command, press keys
// or type text on Linux and Raspberry Pi.
package main

import (
	"fmt"
	"os"
	"strings"
)

var version = "dev"

const usage = `bigredbutton - make the Little Bird Big Red Button do things on Linux / Raspberry Pi

Usage:
  sudo bigredbutton set command "<shell command>"   run a command when pressed
  sudo bigredbutton set keys "<combo>"              hold keys while pressed, e.g. "space" or "ctrl+alt+t"
  sudo bigredbutton set text "<text>"               type text when pressed
  sudo bigredbutton set enter                       back to normal: the button presses Enter
  sudo bigredbutton set none                        the button does nothing
  sudo bigredbutton test                            run the action once, without pressing the button
  sudo bigredbutton listen                          show presses live (stop the service first)
  bigredbutton status                               show the config, button and service state
  bigredbutton run                                  run the daemon (systemd does this for you)
  bigredbutton version

Options:
  -config <path>   config file (default /etc/bigredbutton.json)

Key names: a-z 0-9 f1-f24 enter space tab esc backspace delete insert home end
pageup pagedown up down left right minus equal leftbracket rightbracket backslash
semicolon quote comma period slash grave capslock printscreen volumeup volumedown
mute playpause next previous stop, plus modifiers ctrl shift alt super.

Commands run as the "run_as" user in the config file. Logs: journalctl -u bigredbutton -f
Help: https://littlebirdelectronics.com.au/projects/big-game-button-setup
`

func main() {
	os.Exit(runCLI(os.Args[1:]))
}

func runCLI(args []string) int {
	cfgPath := defaultConfigPath
	var pos []string
	for i := 0; i < len(args); i++ {
		a := args[i]
		switch {
		case a == "-config" || a == "--config":
			if i+1 >= len(args) {
				fmt.Fprintln(os.Stderr, "-config needs a path")
				return 2
			}
			cfgPath = args[i+1]
			i++
		case strings.HasPrefix(a, "-config=") || strings.HasPrefix(a, "--config="):
			cfgPath = a[strings.Index(a, "=")+1:]
		default:
			pos = append(pos, a)
		}
	}
	if len(pos) == 0 {
		fmt.Print(usage)
		return 2
	}
	switch pos[0] {
	case "run":
		return runDaemon(cfgPath)
	case "listen":
		return listen(cfgPath)
	case "test":
		return testAction(cfgPath)
	case "set":
		return cmdSet(cfgPath, pos[1:])
	case "status":
		return cmdStatus(cfgPath)
	case "version", "-v", "--version":
		fmt.Println("bigredbutton", version)
		return 0
	case "help", "-h", "--help":
		fmt.Print(usage)
		return 0
	case "__emulate-button": // test helper: creates a fake button and presses it
		return emulateButton(5)
	}
	fmt.Fprintf(os.Stderr, "Unknown command %q\n\n%s", pos[0], usage)
	return 2
}

func cmdSet(cfgPath string, args []string) int {
	if len(args) == 0 {
		fmt.Fprintln(os.Stderr, "Usage: sudo bigredbutton set enter|none|command|keys|text [value]")
		return 2
	}
	if os.Geteuid() != 0 && cfgPath == defaultConfigPath {
		fmt.Fprintf(os.Stderr, "Changing the button needs root. Run:\n  sudo bigredbutton set %s\n", shellQuoteArgs(args))
		return 1
	}
	cfg, _, err := LoadConfig(cfgPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Ignoring unreadable config: %v\n", err)
		cfg = Config{}
	}
	action := strings.ToLower(args[0])
	value := strings.Join(args[1:], " ")
	switch action {
	case ActionEnter, ActionNone:
		if len(args) > 1 {
			fmt.Fprintf(os.Stderr, "%q doesn't take a value\n", action)
			return 2
		}
	case ActionCommand:
		cfg.Command = value
	case ActionKeys:
		cfg.Keys = value
	case ActionText:
		cfg.Text = value
	default:
		fmt.Fprintf(os.Stderr, "Unknown action %q: use enter, none, command, keys or text\n", args[0])
		return 2
	}
	cfg.Action = action
	if err := cfg.Validate(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 1
	}
	if err := SaveConfig(cfgPath, cfg); err != nil {
		fmt.Fprintf(os.Stderr, "Saving %s failed: %v\n", cfgPath, err)
		return 1
	}
	fmt.Printf("Saved %s: the button %s\n", cfgPath, cfg.Summary())
	if err := restartService(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 1
	}
	return 0
}

func cmdStatus(cfgPath string) int {
	fmt.Printf("bigredbutton %s\n", version)
	cfg, exists, err := LoadConfig(cfgPath)
	switch {
	case err != nil:
		fmt.Printf("Config:  %v\n", err)
	case !exists:
		fmt.Printf("Config:  none at %s, so the button presses Enter\n", cfgPath)
	default:
		fmt.Printf("Config:  %s\n", cfgPath)
		if verr := cfg.Validate(); verr != nil {
			fmt.Printf("Action:  invalid (%v), so the button presses Enter\n", verr)
		} else {
			fmt.Printf("Action:  the button %s\n", cfg.Summary())
		}
	}
	vid, pid := cfg.VendorProduct()
	if nodes := findNodes("/", vid, pid); len(nodes) > 0 {
		fmt.Printf("Button:  connected (USB %04x:%04x)\n", vid, pid)
		for _, n := range nodes {
			fmt.Printf("         %s  %s\n", n.Path, n.Name)
		}
	} else {
		fmt.Printf("Button:  not found (USB %04x:%04x). Plug it in with the supplied USB-A to USB-C cable.\n", vid, pid)
	}
	fmt.Printf("Service: %s\n", serviceState())
	return 0
}

func shellQuoteArgs(args []string) string {
	out := make([]string, len(args))
	for i, a := range args {
		if a == "" || strings.ContainsAny(a, " \t'\"$`\\!&;|<>()*?[]#~") {
			out[i] = "'" + strings.ReplaceAll(a, "'", `'\''`) + "'"
		} else {
			out[i] = a
		}
	}
	return strings.Join(out, " ")
}
