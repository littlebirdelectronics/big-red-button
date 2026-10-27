package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
)

func TestParseCombo(t *testing.T) {
	tests := []struct {
		in   string
		want Combo
	}{
		{"space", Combo{Key: keySpace}},
		{"ctrl+alt+t", Combo{Modifiers: []uint16{keyLeftCtrl, keyLeftAlt}, Key: 20}},
		{" Ctrl + Shift + F13 ", Combo{Modifiers: []uint16{keyLeftCtrl, keyLeftShift}, Key: 183}},
		{"cmd+q", Combo{Modifiers: []uint16{keyLeftMeta}, Key: 16}},
		{"f1", Combo{Key: 59}},
		{"f10", Combo{Key: 68}},
		{"f11", Combo{Key: 87}},
		{"f24", Combo{Key: 194}},
		{"shift", Combo{Modifiers: []uint16{keyLeftShift}}},
		{"return", Combo{Key: keyEnter}},
		{"0", Combo{Key: 11}},
		{"playpause", Combo{Key: keyPlayPause}},
	}
	for _, tt := range tests {
		got, err := ParseCombo(tt.in)
		if err != nil {
			t.Errorf("ParseCombo(%q): %v", tt.in, err)
			continue
		}
		if !reflect.DeepEqual(got, tt.want) {
			t.Errorf("ParseCombo(%q) = %+v, want %+v", tt.in, got, tt.want)
		}
	}
	for _, bad := range []string{"", "ctrl+", "a+b", "ctrl+ctrl+a", "hyper+a", "f25"} {
		if _, err := ParseCombo(bad); err == nil {
			t.Errorf("ParseCombo(%q) should fail", bad)
		}
	}
}

func TestComboCodesOrder(t *testing.T) {
	c, _ := ParseCombo("ctrl+shift+4")
	if got, want := c.Codes(), []uint16{keyLeftCtrl, keyLeftShift, 5}; !reflect.DeepEqual(got, want) {
		t.Errorf("Codes() = %v, want %v", got, want)
	}
}

func TestCharToKey(t *testing.T) {
	tests := []struct {
		r     rune
		code  uint16
		shift bool
	}{
		{'a', 30, false}, {'A', 30, true}, {'z', 44, false}, {'1', 2, false}, {'0', 11, false},
		{'!', 2, true}, {'@', 3, true}, {')', 11, true}, {' ', keySpace, false}, {'\n', keyEnter, false},
		{'-', keyMinus, false}, {'_', keyMinus, true}, {'"', keyApostrophe, true}, {'?', keySlash, true},
	}
	for _, tt := range tests {
		code, shift, ok := CharToKey(tt.r)
		if !ok || code != tt.code || shift != tt.shift {
			t.Errorf("CharToKey(%q) = %d,%v,%v want %d,%v", tt.r, code, shift, ok, tt.code, tt.shift)
		}
	}
	for _, r := range []rune{'é', '€', '\r'} {
		if _, _, ok := CharToKey(r); ok {
			t.Errorf("CharToKey(%q) should not be typable", r)
		}
	}
}

func TestEveryKeyIsRegisteredWithUinput(t *testing.T) {
	registered := map[uint16]bool{}
	for _, c := range allKeyCodes() {
		registered[c] = true
	}
	for r := rune(32); r < 127; r++ {
		if code, _, ok := CharToKey(r); ok && !registered[code] {
			t.Errorf("%q maps to unregistered code %d", r, code)
		}
	}
	if !registered[keyLeftShift] {
		t.Error("shift isn't registered")
	}
}

func TestValidate(t *testing.T) {
	good := []Config{
		{Action: "enter"}, {Action: "none"},
		{Action: "keys", Keys: "ctrl+alt+t"},
		{Action: "text", Text: "Hello, World!\n"},
		{Action: "command", Command: "aplay x.wav"},
	}
	for _, c := range good {
		if err := c.Validate(); err != nil {
			t.Errorf("%+v: %v", c, err)
		}
	}
	bad := []Config{
		{}, {Action: "explode"},
		{Action: "keys"}, {Action: "keys", Keys: "nope"},
		{Action: "text"}, {Action: "text", Text: "café"},
		{Action: "command", Command: "  "},
	}
	for _, c := range bad {
		if err := c.Validate(); err == nil {
			t.Errorf("%+v should be invalid", c)
		}
	}
}

func TestConfigRoundTripKeepsUnknownFields(t *testing.T) {
	path := filepath.Join(t.TempDir(), "bigredbutton.json")
	if err := os.WriteFile(path, []byte(`{"action":"open","open":"https://example.com","run_as":"pi"}`), 0o644); err != nil {
		t.Fatal(err)
	}
	cfg, exists, err := LoadConfig(path)
	if err != nil || !exists {
		t.Fatalf("LoadConfig: %v exists=%v", err, exists)
	}
	cfg.Action, cfg.Command = ActionCommand, "echo hi"
	if err := SaveConfig(path, cfg); err != nil {
		t.Fatal(err)
	}
	data, _ := os.ReadFile(path)
	var raw map[string]any
	if err := json.Unmarshal(data, &raw); err != nil {
		t.Fatal(err)
	}
	want := map[string]any{"action": "command", "command": "echo hi", "run_as": "pi", "open": "https://example.com"}
	if !reflect.DeepEqual(raw, want) {
		t.Errorf("saved %v, want %v", raw, want)
	}
	again, _, err := LoadConfig(path)
	if err != nil || again.Action != ActionCommand || again.Command != "echo hi" || again.RunAs != "pi" {
		t.Errorf("reload = %+v, %v", again, err)
	}
	if info, _ := os.Stat(path); info.Mode().Perm() != 0o644 {
		t.Errorf("mode = %v", info.Mode().Perm())
	}
}

func TestLoadMissingConfigMeansEnter(t *testing.T) {
	cfg, exists, err := LoadConfig(filepath.Join(t.TempDir(), "nope.json"))
	if err != nil || exists || cfg.Action != ActionEnter || cfg.Grabs() {
		t.Errorf("got %+v exists=%v err=%v", cfg, exists, err)
	}
}

func TestVendorProduct(t *testing.T) {
	if v, p := (Config{}).VendorProduct(); v != 0x8189 || p != 0x0019 {
		t.Errorf("default = %04x:%04x", v, p)
	}
	c := Config{Device: &DeviceID{VendorID: 0x1234, ProductID: 0x5678}}
	if v, p := c.VendorProduct(); v != 0x1234 || p != 0x5678 {
		t.Errorf("override = %04x:%04x", v, p)
	}
}

func TestTracker(t *testing.T) {
	tr := NewTracker()
	key := func(code uint16, v int32) InputEvent { return InputEvent{Type: evKey, Code: code, Value: v} }
	steps := []struct {
		node int
		ev   InputEvent
		want Edge
	}{
		{0, InputEvent{Type: evSyn}, EdgeNone},
		{0, key(keyEnter, 1), EdgePress},
		{0, key(keyEnter, 2), EdgeNone}, // autorepeat
		{0, key(keyEnter, 1), EdgeNone}, // duplicate down
		{1, key(keyVolumeUp, 1), EdgeNone},
		{0, key(keyEnter, 0), EdgeNone}, // still held on node 1
		{1, key(keyVolumeUp, 0), EdgeRelease},
		{1, key(keyVolumeUp, 0), EdgeNone}, // stray up
		{2, key(272, 1), EdgePress},        // BTN_LEFT from a mouse node counts too
	}
	for i, s := range steps {
		if got := tr.Feed(s.node, s.ev); got != s.want {
			t.Errorf("step %d: got %v want %v", i, got, s.want)
		}
	}
	if !tr.Reset() || tr.Pressed() {
		t.Error("Reset should report the held button and clear it")
	}
}

func TestEventDecodeEncode(t *testing.T) {
	for _, word := range []int{4, 8} {
		e := InputEvent{Type: evKey, Code: keyEnter, Value: -1}
		b := encodeEvent(e, word)
		if len(b) != 2*word+8 {
			t.Errorf("word %d: size %d", word, len(b))
		}
		if got := decodeEvent(b, word); got != e {
			t.Errorf("word %d: round trip %+v", word, got)
		}
	}
	// A real 16-byte event from 32-bit ARM: sec, usec, EV_KEY, KEY_ENTER, 1.
	arm := []byte{0x10, 0, 0, 0, 0x20, 0, 0, 0, 1, 0, 28, 0, 1, 0, 0, 0}
	if got := decodeEvent(arm, 4); got != (InputEvent{Type: 1, Code: 28, Value: 1}) {
		t.Errorf("arm decode = %+v", got)
	}
	// And a 24-byte one from arm64/amd64.
	a64 := append(make([]byte, 16), 1, 0, 28, 0, 0, 0, 0, 0)
	if got := decodeEvent(a64, 8); got != (InputEvent{Type: 1, Code: 28, Value: 0}) {
		t.Errorf("arm64 decode = %+v", got)
	}
	if eventSize != 2*wordSize+8 || (wordSize != 4 && wordSize != 8) {
		t.Errorf("eventSize %d wordSize %d", eventSize, wordSize)
	}
}

func TestFindNodes(t *testing.T) {
	root := t.TempDir()
	mk := func(event, vendor, product, name string) {
		dir := filepath.Join(root, "sys/class/input", event, "device")
		os.MkdirAll(filepath.Join(dir, "id"), 0o755)
		os.WriteFile(filepath.Join(dir, "id/vendor"), []byte(vendor+"\n"), 0o644)
		os.WriteFile(filepath.Join(dir, "id/product"), []byte(product+"\n"), 0o644)
		os.WriteFile(filepath.Join(dir, "name"), []byte(name+"\n"), 0o644)
	}
	mk("event3", "8189", "0019", "LinTx USB Keyboard")
	mk("event5", "8189", "0019", "LinTx USB Keyboard Consumer Control")
	mk("event4", "05ac", "024f", "Some Other Keyboard")
	mk("event9", "1209", "0001", "Big Red Button (virtual)")

	got := findNodes(root, 0x8189, 0x0019)
	want := []Node{
		{Path: "/dev/input/event3", Name: "LinTx USB Keyboard"},
		{Path: "/dev/input/event5", Name: "LinTx USB Keyboard Consumer Control"},
	}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("findNodes = %+v", got)
	}
	if n := findNodes(root, 0x1, 0x2); len(n) != 0 {
		t.Errorf("unexpected match %+v", n)
	}
}

func TestCLISet(t *testing.T) {
	path := filepath.Join(t.TempDir(), "c.json")
	os.WriteFile(path, []byte(`{"action":"enter","run_as":"pi"}`), 0o644)
	if code := runCLI([]string{"set", "command", "aplay", "/tmp/x.wav", "-config", path}); code != 0 {
		t.Fatalf("set command exit %d", code)
	}
	cfg, _, _ := LoadConfig(path)
	if cfg.Action != ActionCommand || cfg.Command != "aplay /tmp/x.wav" || cfg.RunAs != "pi" {
		t.Errorf("after set command: %+v", cfg)
	}
	if code := runCLI([]string{"--config=" + path, "set", "keys", "nonsense+key"}); code == 0 {
		t.Error("invalid keys should fail")
	}
	if cfg2, _, _ := LoadConfig(path); cfg2.Action != ActionCommand {
		t.Errorf("failed set must not change the file: %+v", cfg2)
	}
	if code := runCLI([]string{"set", "enter", "extra", "-config", path}); code != 2 {
		t.Errorf("enter with a value: exit %d", code)
	}
	if code := runCLI([]string{"set", "keys", "ctrl+alt+t", "-config", path}); code != 0 {
		t.Fatalf("set keys exit %d", code)
	}
	if cfg3, _, _ := LoadConfig(path); cfg3.Keys != "ctrl+alt+t" || cfg3.Command != "aplay /tmp/x.wav" {
		t.Errorf("set keys should keep the command for later: %+v", cfg3)
	}
}

func TestShellQuoteArgs(t *testing.T) {
	got := shellQuoteArgs([]string{"command", "aplay it's.wav"})
	if !strings.Contains(got, `'aplay it'\''s.wav'`) {
		t.Errorf("got %s", got)
	}
}
