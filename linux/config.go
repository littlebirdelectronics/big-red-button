package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"strings"
)

const (
	defaultConfigPath = "/etc/bigredbutton.json"
	defaultVendorID   = 0x8189
	defaultProductID  = 0x0019
)

// Actions, shared with the macOS app's config format.
const (
	ActionEnter   = "enter"
	ActionNone    = "none"
	ActionKeys    = "keys"
	ActionText    = "text"
	ActionCommand = "command"
)

type DeviceID struct {
	VendorID  int `json:"vendor_id"`
	ProductID int `json:"product_id"`
}

type Config struct {
	Action  string    `json:"action"`
	Keys    string    `json:"keys,omitempty"`
	Text    string    `json:"text,omitempty"`
	Command string    `json:"command,omitempty"`
	RunAs   string    `json:"run_as,omitempty"`
	Device  *DeviceID `json:"device,omitempty"`
}

// VendorProduct returns the USB IDs to look for, falling back to the Big Red Button's.
func (c Config) VendorProduct() (int, int) {
	vid, pid := defaultVendorID, defaultProductID
	if c.Device != nil {
		if c.Device.VendorID != 0 {
			vid = c.Device.VendorID
		}
		if c.Device.ProductID != 0 {
			pid = c.Device.ProductID
		}
	}
	return vid, pid
}

// Grabs reports whether the button should be taken away from the rest of the system.
func (c Config) Grabs() bool {
	return c.Action != ActionEnter
}

func (c Config) Validate() error {
	switch c.Action {
	case ActionEnter, ActionNone:
	case ActionKeys:
		if _, err := ParseCombo(c.Keys); err != nil {
			return fmt.Errorf("keys: %w", err)
		}
	case ActionText:
		if c.Text == "" {
			return errors.New(`text: "text" is empty`)
		}
		for _, r := range c.Text {
			if _, _, ok := CharToKey(r); !ok {
				return fmt.Errorf("text: can't type %q (only US keyboard characters are supported)", r)
			}
		}
	case ActionCommand:
		if strings.TrimSpace(c.Command) == "" {
			return errors.New(`command: "command" is empty`)
		}
	case "":
		return errors.New(`"action" is missing (use enter, none, keys, text or command)`)
	default:
		return fmt.Errorf("unknown action %q (use enter, none, keys, text or command)", c.Action)
	}
	return nil
}

// Summary describes what the button does, for status output and logs.
func (c Config) Summary() string {
	switch c.Action {
	case ActionEnter:
		return "presses Enter (default; not grabbed)"
	case ActionNone:
		return "does nothing"
	case ActionKeys:
		return fmt.Sprintf("holds keys %q while pressed", c.Keys)
	case ActionText:
		return fmt.Sprintf("types %q", c.Text)
	case ActionCommand:
		who := c.RunAs
		if who == "" {
			who = "root"
		}
		return fmt.Sprintf("runs %q as %s", c.Command, who)
	}
	return c.Action
}

// LoadConfig reads the config. A missing file is not an error: it means "enter".
func LoadConfig(path string) (Config, bool, error) {
	data, err := os.ReadFile(path)
	if errors.Is(err, fs.ErrNotExist) {
		return Config{Action: ActionEnter}, false, nil
	}
	if err != nil {
		return Config{}, false, err
	}
	var c Config
	if err := json.Unmarshal(data, &c); err != nil {
		return Config{}, true, fmt.Errorf("%s: %w", path, err)
	}
	c.Action = strings.ToLower(strings.TrimSpace(c.Action))
	return c, true, nil
}

// SaveConfig writes the config atomically, keeping any fields this program doesn't know
// about (the macOS app shares the format and may add its own).
func SaveConfig(path string, c Config) error {
	merged := map[string]json.RawMessage{}
	if data, err := os.ReadFile(path); err == nil {
		_ = json.Unmarshal(data, &merged)
	}
	if merged == nil { // the file held a bare "null"
		merged = map[string]json.RawMessage{}
	}
	known, err := json.Marshal(c)
	if err != nil {
		return err
	}
	var knownFields map[string]json.RawMessage
	if err := json.Unmarshal(known, &knownFields); err != nil {
		return err
	}
	for _, k := range []string{"action", "keys", "text", "command", "run_as", "device"} {
		if v, ok := knownFields[k]; ok {
			merged[k] = v
		} else {
			delete(merged, k)
		}
	}
	out, err := json.MarshalIndent(merged, "", "  ")
	if err != nil {
		return err
	}
	out = append(out, '\n')

	tmp, err := os.CreateTemp(filepath.Dir(path), ".bigredbutton-*.json")
	if err != nil {
		return err
	}
	defer os.Remove(tmp.Name())
	if _, err := tmp.Write(out); err != nil {
		tmp.Close()
		return err
	}
	if err := tmp.Chmod(0o644); err != nil {
		tmp.Close()
		return err
	}
	if err := tmp.Close(); err != nil {
		return err
	}
	return os.Rename(tmp.Name(), path)
}
