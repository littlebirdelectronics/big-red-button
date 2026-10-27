package main

import (
	"fmt"
	"strings"
)

// Linux input event codes (linux/input-event-codes.h).
const (
	evSyn     = 0x00
	evKey     = 0x01
	synReport = 0

	keyEsc        = 1
	keyMinus      = 12
	keyEqual      = 13
	keyBackspace  = 14
	keyTab        = 15
	keyLeftBrace  = 26
	keyRightBrace = 27
	keyEnter      = 28
	keyLeftCtrl   = 29
	keySemicolon  = 39
	keyApostrophe = 40
	keyGrave      = 41
	keyLeftShift  = 42
	keyBackslash  = 43
	keyComma      = 51
	keyDot        = 52
	keySlash      = 53
	keyLeftAlt    = 56
	keySpace      = 57
	keyCapsLock   = 58
	keySysRq      = 99
	keyHome       = 102
	keyUp         = 103
	keyPageUp     = 104
	keyLeft       = 105
	keyRight      = 106
	keyEnd        = 107
	keyDown       = 108
	keyPageDown   = 109
	keyInsert     = 110
	keyDelete     = 111
	keyMute       = 113
	keyVolumeDown = 114
	keyVolumeUp   = 115
	keyLeftMeta   = 125
	keyNextSong   = 163
	keyPlayPause  = 164
	keyPrevSong   = 165
	keyStopCD     = 166
)

// Letter and digit codes follow the physical keyboard rows, not the alphabet.
var letterCodes = map[rune]uint16{
	'q': 16, 'w': 17, 'e': 18, 'r': 19, 't': 20, 'y': 21, 'u': 22, 'i': 23, 'o': 24, 'p': 25,
	'a': 30, 's': 31, 'd': 32, 'f': 33, 'g': 34, 'h': 35, 'j': 36, 'k': 37, 'l': 38,
	'z': 44, 'x': 45, 'c': 46, 'v': 47, 'b': 48, 'n': 49, 'm': 50,
}

var digitCodes = map[rune]uint16{
	'1': 2, '2': 3, '3': 4, '4': 5, '5': 6, '6': 7, '7': 8, '8': 9, '9': 10, '0': 11,
}

var modifierNames = map[string]uint16{
	"ctrl": keyLeftCtrl, "control": keyLeftCtrl,
	"shift": keyLeftShift,
	"alt":   keyLeftAlt, "option": keyLeftAlt,
	"super": keyLeftMeta, "win": keyLeftMeta, "cmd": keyLeftMeta, "command": keyLeftMeta, "meta": keyLeftMeta,
}

var keyNames = buildKeyNames()

func buildKeyNames() map[string]uint16 {
	m := map[string]uint16{
		"enter": keyEnter, "return": keyEnter,
		"space": keySpace, "tab": keyTab,
		"esc": keyEsc, "escape": keyEsc,
		"backspace": keyBackspace, "delete": keyDelete, "insert": keyInsert,
		"home": keyHome, "end": keyEnd, "pageup": keyPageUp, "pagedown": keyPageDown,
		"up": keyUp, "down": keyDown, "left": keyLeft, "right": keyRight,
		"minus": keyMinus, "equal": keyEqual,
		"leftbracket": keyLeftBrace, "rightbracket": keyRightBrace, "backslash": keyBackslash,
		"semicolon": keySemicolon, "quote": keyApostrophe, "apostrophe": keyApostrophe,
		"comma": keyComma, "period": keyDot, "dot": keyDot, "slash": keySlash,
		"grave": keyGrave, "backtick": keyGrave,
		"capslock": keyCapsLock, "printscreen": keySysRq,
		"volumeup": keyVolumeUp, "volumedown": keyVolumeDown, "mute": keyMute,
		"playpause": keyPlayPause,
		"nextsong":  keyNextSong, "next": keyNextSong,
		"previoussong": keyPrevSong, "previous": keyPrevSong,
		"stop": keyStopCD,
	}
	for r, c := range letterCodes {
		m[string(r)] = c
	}
	for r, c := range digitCodes {
		m[string(r)] = c
	}
	// F1-F10 are 59-68, F11/F12 are 87/88, F13-F24 are 183-194.
	for i := 1; i <= 10; i++ {
		m[fmt.Sprintf("f%d", i)] = uint16(58 + i)
	}
	m["f11"], m["f12"] = 87, 88
	for i := 13; i <= 24; i++ {
		m[fmt.Sprintf("f%d", i)] = uint16(170 + i)
	}
	return m
}

// Combo is a parsed "ctrl+alt+t" style shortcut. Key is 0 for modifier-only combos.
type Combo struct {
	Modifiers []uint16
	Key       uint16
}

// Codes returns the key codes in press order (modifiers first).
func (c Combo) Codes() []uint16 {
	codes := append([]uint16{}, c.Modifiers...)
	if c.Key != 0 {
		codes = append(codes, c.Key)
	}
	return codes
}

// ParseCombo parses names joined by '+', case-insensitively.
func ParseCombo(s string) (Combo, error) {
	var c Combo
	if strings.TrimSpace(s) == "" {
		return c, fmt.Errorf("no keys given")
	}
	seen := map[uint16]bool{}
	for _, part := range strings.Split(s, "+") {
		name := strings.ToLower(strings.TrimSpace(part))
		if name == "" {
			return c, fmt.Errorf("empty key name in %q", s)
		}
		if code, ok := modifierNames[name]; ok {
			if seen[code] {
				return c, fmt.Errorf("%q is listed twice", name)
			}
			seen[code] = true
			c.Modifiers = append(c.Modifiers, code)
			continue
		}
		code, ok := keyNames[name]
		if !ok {
			return c, fmt.Errorf("unknown key %q", name)
		}
		if c.Key != 0 {
			return c, fmt.Errorf("only one non-modifier key is allowed in %q", s)
		}
		c.Key = code
	}
	return c, nil
}

// shiftedSymbols maps US-layout symbols typed with Shift to their unshifted key.
var shiftedSymbols = map[rune]uint16{
	'!': 2, '@': 3, '#': 4, '$': 5, '%': 6, '^': 7, '&': 8, '*': 9, '(': 10, ')': 11,
	'_': keyMinus, '+': keyEqual, '{': keyLeftBrace, '}': keyRightBrace, '|': keyBackslash,
	':': keySemicolon, '"': keyApostrophe, '~': keyGrave, '<': keyComma, '>': keyDot, '?': keySlash,
}

var plainSymbols = map[rune]uint16{
	'-': keyMinus, '=': keyEqual, '[': keyLeftBrace, ']': keyRightBrace, '\\': keyBackslash,
	';': keySemicolon, '\'': keyApostrophe, '`': keyGrave, ',': keyComma, '.': keyDot, '/': keySlash,
	' ': keySpace, '\n': keyEnter, '\t': keyTab,
}

// CharToKey maps a character to a key code on a US keyboard layout.
func CharToKey(r rune) (code uint16, shift bool, ok bool) {
	switch {
	case r >= 'a' && r <= 'z':
		return letterCodes[r], false, true
	case r >= 'A' && r <= 'Z':
		return letterCodes[r+('a'-'A')], true, true
	case r >= '0' && r <= '9':
		return digitCodes[r], false, true
	}
	if c, found := plainSymbols[r]; found {
		return c, false, true
	}
	if c, found := shiftedSymbols[r]; found {
		return c, true, true
	}
	return 0, false, false
}

// allKeyCodes lists every code the virtual keyboard may emit.
func allKeyCodes() []uint16 {
	seen := map[uint16]bool{}
	var codes []uint16
	add := func(c uint16) {
		if !seen[c] {
			seen[c] = true
			codes = append(codes, c)
		}
	}
	for _, c := range modifierNames {
		add(c)
	}
	for _, c := range keyNames {
		add(c)
	}
	return codes
}
