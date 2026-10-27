//go:build linux

package main

import (
	"errors"
	"fmt"
	"os"
	"syscall"
	"time"
	"unsafe"
)

const evIOCGrab = 0x40044590 // _IOW('E', 0x90, int)

func ioctl(fd int, req, arg uintptr) error {
	if _, _, errno := syscall.Syscall(syscall.SYS_IOCTL, uintptr(fd), req, arg); errno != 0 {
		return errno
	}
	return nil
}

func ioctlPtr(fd int, req uintptr, p unsafe.Pointer) error {
	if _, _, errno := syscall.Syscall(syscall.SYS_IOCTL, uintptr(fd), req, uintptr(p)); errno != 0 {
		return errno
	}
	return nil
}

// openNodes opens every node non-blocking (so Close wakes up readers) and optionally grabs
// them, which stops the button's Enter from reaching anything else on the system.
func openNodes(nodes []Node, grab bool) ([]*os.File, error) {
	var files []*os.File
	for _, n := range nodes {
		fd, err := syscall.Open(n.Path, syscall.O_RDONLY|syscall.O_NONBLOCK|syscall.O_CLOEXEC, 0)
		if err != nil {
			closeAll(files)
			return nil, fmt.Errorf("open %s: %w", n.Path, err)
		}
		if grab {
			if err := ioctl(fd, evIOCGrab, 1); err != nil {
				syscall.Close(fd)
				closeAll(files)
				return nil, fmt.Errorf("grab %s: %w", n.Path, err)
			}
		}
		files = append(files, os.NewFile(uintptr(fd), n.Path))
	}
	return files, nil
}

func closeAll(files []*os.File) {
	for _, f := range files {
		f.Close()
	}
}

type nodeEvent struct {
	node int
	ev   InputEvent
	err  error
}

func readNode(i int, f *os.File, out chan<- nodeEvent, done <-chan struct{}) {
	buf := make([]byte, eventSize*64)
	for {
		n, err := f.Read(buf)
		if err != nil {
			select {
			case out <- nodeEvent{node: i, err: err}:
			case <-done:
			}
			return
		}
		for off := 0; off+eventSize <= n; off += eventSize {
			select {
			case out <- nodeEvent{node: i, ev: decodeEvent(buf[off:], wordSize)}:
			case <-done:
				return
			}
		}
	}
}

// openHint explains the usual reasons the button's nodes can't be opened.
func openHint(err error) string {
	switch {
	case errors.Is(err, syscall.EACCES), errors.Is(err, syscall.EPERM):
		return "permission denied: run with sudo"
	case errors.Is(err, syscall.EBUSY):
		return "another program has grabbed the button (is the bigredbutton service running? stop it with: sudo systemctl stop bigredbutton)"
	}
	return ""
}

type watcher struct {
	vid, pid     int
	grab         bool
	logf         func(format string, args ...any)
	onConnect    func(nodes []Node)
	onDisconnect func(err error)
	onEdge       func(e Edge)
}

// run waits for the button, delivers press/release edges, and starts over when it's
// unplugged. It never returns.
func (w watcher) run() {
	waiting := false
	lastErr := ""
	for {
		nodes := findNodes("/", w.vid, w.pid)
		if len(nodes) == 0 {
			if !waiting {
				w.logf("Waiting for the button (USB %04x:%04x). Use the supplied USB-A cable.", w.vid, w.pid)
				waiting = true
			}
			time.Sleep(2 * time.Second)
			continue
		}
		waiting = false

		files, err := openNodes(nodes, w.grab)
		if err != nil {
			if msg := err.Error(); msg != lastErr {
				lastErr = msg
				if hint := openHint(err); hint != "" {
					msg += " (" + hint + ")"
				}
				w.logf("Can't use the button: %s", msg)
			}
			time.Sleep(2 * time.Second)
			continue
		}
		lastErr = ""
		w.onConnect(nodes)

		events := make(chan nodeEvent)
		done := make(chan struct{})
		for i, f := range files {
			go readNode(i, f, events, done)
		}
		tracker := NewTracker()
		var readErr error
		for readErr == nil {
			ne := <-events
			if ne.err != nil {
				readErr = ne.err
				break
			}
			if edge := tracker.Feed(ne.node, ne.ev); edge != EdgeNone {
				w.onEdge(edge)
			}
		}
		close(done)
		closeAll(files)
		if tracker.Reset() {
			w.onEdge(EdgeRelease)
		}
		w.onDisconnect(readErr)
		time.Sleep(time.Second)
	}
}
