package main

import (
	"encoding/binary"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"unsafe"
)

// struct input_event is {timeval; __u16 type; __u16 code; __s32 value}. The timeval is two
// longs, so the struct is 16 bytes for 32-bit processes (including 32-bit Raspberry Pi OS on a
// 64-bit kernel, via compat) and 24 bytes for 64-bit ones.
var (
	wordSize  = int(unsafe.Sizeof(uintptr(0)))
	eventSize = 2*wordSize + 8
)

type InputEvent struct {
	Type  uint16
	Code  uint16
	Value int32
}

// All supported targets (arm, arm64, amd64) are little-endian.
func decodeEvent(b []byte, word int) InputEvent {
	off := 2 * word
	return InputEvent{
		Type:  binary.LittleEndian.Uint16(b[off:]),
		Code:  binary.LittleEndian.Uint16(b[off+2:]),
		Value: int32(binary.LittleEndian.Uint32(b[off+4:])),
	}
}

func encodeEvent(e InputEvent, word int) []byte {
	b := make([]byte, 2*word+8)
	off := 2 * word
	binary.LittleEndian.PutUint16(b[off:], e.Type)
	binary.LittleEndian.PutUint16(b[off+2:], e.Code)
	binary.LittleEndian.PutUint32(b[off+4:], uint32(e.Value))
	return b
}

// Edge is what the tracker reports for each key event.
type Edge int

const (
	EdgeNone Edge = iota
	EdgePress
	EdgeRelease
)

// Tracker turns key events from all of the button's event nodes into a single
// press/release: the button is "down" while any key on any node is down.
type Tracker struct {
	down map[[2]int]bool
}

func NewTracker() *Tracker { return &Tracker{down: map[[2]int]bool{}} }

func (t *Tracker) Pressed() bool { return len(t.down) > 0 }

func (t *Tracker) Feed(node int, e InputEvent) Edge {
	if e.Type != evKey {
		return EdgeNone
	}
	k := [2]int{node, int(e.Code)}
	switch e.Value {
	case 1:
		if t.down[k] {
			return EdgeNone
		}
		t.down[k] = true
		if len(t.down) == 1 {
			return EdgePress
		}
	case 0:
		if !t.down[k] {
			return EdgeNone
		}
		delete(t.down, k)
		if len(t.down) == 0 {
			return EdgeRelease
		}
	}
	return EdgeNone // value 2 is autorepeat
}

// Reset forgets held keys, e.g. after the button is unplugged. Reports whether it was down.
func (t *Tracker) Reset() bool {
	was := t.Pressed()
	t.down = map[[2]int]bool{}
	return was
}

type Node struct {
	Path string // /dev/input/eventN
	Name string
}

// findNodes returns every evdev node whose USB vendor/product matches. sysRoot is "/" in
// production and a fake tree in tests.
func findNodes(sysRoot string, vid, pid int) []Node {
	matches, _ := filepath.Glob(filepath.Join(sysRoot, "sys/class/input/event*"))
	var nodes []Node
	for _, dir := range matches {
		v, okV := readHex(filepath.Join(dir, "device/id/vendor"))
		p, okP := readHex(filepath.Join(dir, "device/id/product"))
		if !okV || !okP || v != vid || p != pid {
			continue
		}
		name, _ := os.ReadFile(filepath.Join(dir, "device/name"))
		nodes = append(nodes, Node{
			Path: filepath.Join("/dev/input", filepath.Base(dir)),
			Name: strings.TrimSpace(string(name)),
		})
	}
	sort.Slice(nodes, func(i, j int) bool { return nodes[i].Path < nodes[j].Path })
	return nodes
}

func readHex(path string) (int, bool) {
	data, err := os.ReadFile(path)
	if err != nil {
		return 0, false
	}
	n, err := strconv.ParseInt(strings.TrimSpace(string(data)), 16, 32)
	return int(n), err == nil
}
