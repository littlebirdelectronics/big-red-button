//go:build linux

package main

import (
	"encoding/binary"
	"fmt"
	"os"
	"runtime"
	"syscall"
	"time"
	"unsafe"
)

const (
	uiSetEvBit   = 0x40045564 // _IOW('U', 100, int)
	uiSetKeyBit  = 0x40045565 // _IOW('U', 101, int)
	uiDevSetup   = 0x405c5503 // _IOW('U', 3, struct uinput_setup)
	uiDevCreate  = 0x5501     // _IO('U', 1)
	uiDevDestroy = 0x5502     // _IO('U', 2)

	busUSB = 0x03

	// pid.codes test IDs, deliberately different from the real button so we never grab
	// our own virtual keyboard.
	virtualVendorID  = 0x1209
	virtualProductID = 0x0001
)

type virtualKeyboard struct {
	fd int
}

func newVirtualKeyboard() (*virtualKeyboard, error) {
	return newUinput(virtualVendorID, virtualProductID, "Big Red Button (virtual)", allKeyCodes())
}

func newUinput(vid, pid uint16, name string, codes []uint16) (*virtualKeyboard, error) {
	fd, err := syscall.Open("/dev/uinput", syscall.O_WRONLY|syscall.O_NONBLOCK|syscall.O_CLOEXEC, 0)
	if err != nil {
		return nil, fmt.Errorf("open /dev/uinput: %w (try: sudo modprobe uinput)", err)
	}
	fail := func(step string, err error) (*virtualKeyboard, error) {
		syscall.Close(fd)
		return nil, fmt.Errorf("uinput %s: %w", step, err)
	}
	for _, ev := range []uintptr{evKey, evSyn} {
		if err := ioctl(fd, uiSetEvBit, ev); err != nil {
			return fail("set event bit", err)
		}
	}
	for _, c := range codes {
		if err := ioctl(fd, uiSetKeyBit, uintptr(c)); err != nil {
			return fail("set key bit", err)
		}
	}
	// struct uinput_setup { struct input_id id; char name[80]; __u32 ff_effects_max; }
	setup := make([]byte, 92)
	binary.LittleEndian.PutUint16(setup[0:], busUSB)
	binary.LittleEndian.PutUint16(setup[2:], vid)
	binary.LittleEndian.PutUint16(setup[4:], pid)
	binary.LittleEndian.PutUint16(setup[6:], 1)
	copy(setup[8:87], name)
	if err := ioctlPtr(fd, uiDevSetup, unsafe.Pointer(&setup[0])); err != nil {
		return fail("setup", err)
	}
	runtime.KeepAlive(setup)
	if err := ioctl(fd, uiDevCreate, 0); err != nil {
		return fail("create", err)
	}
	// Give udev and the desktop a moment to pick up the new keyboard.
	time.Sleep(500 * time.Millisecond)
	return &virtualKeyboard{fd: fd}, nil
}

func (k *virtualKeyboard) emit(code uint16, value int32) error {
	buf := append(encodeEvent(InputEvent{Type: evKey, Code: code, Value: value}, wordSize),
		encodeEvent(InputEvent{Type: evSyn, Code: synReport}, wordSize)...)
	_, err := syscall.Write(k.fd, buf)
	return err
}

func (k *virtualKeyboard) Down(c Combo) error {
	for _, code := range c.Codes() {
		if err := k.emit(code, 1); err != nil {
			return err
		}
	}
	return nil
}

func (k *virtualKeyboard) Up(c Combo) error {
	codes := c.Codes()
	for i := len(codes) - 1; i >= 0; i-- {
		if err := k.emit(codes[i], 0); err != nil {
			return err
		}
	}
	return nil
}

func (k *virtualKeyboard) Type(text string) error {
	for _, r := range text {
		code, shift, ok := CharToKey(r)
		if !ok {
			continue
		}
		c := Combo{Key: code}
		if shift {
			c.Modifiers = []uint16{keyLeftShift}
		}
		if err := k.Down(c); err != nil {
			return err
		}
		if err := k.Up(c); err != nil {
			return err
		}
		time.Sleep(5 * time.Millisecond)
	}
	return nil
}

func (k *virtualKeyboard) Close() {
	ioctl(k.fd, uiDevDestroy, 0)
	syscall.Close(k.fd)
}

// emulateButton creates a fake Big Red Button and presses it, for end-to-end tests on
// machines without the real hardware.
func emulateButton(presses int) int {
	kb, err := newUinput(defaultVendorID, defaultProductID, "LinTx USB Keyboard (emulated)", []uint16{keyEnter})
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 1
	}
	defer kb.Close()
	time.Sleep(3 * time.Second) // let a watcher polling every 2s find it
	for i := 0; i < presses; i++ {
		fmt.Printf("emulated press %d\n", i+1)
		kb.emit(keyEnter, 1)
		time.Sleep(150 * time.Millisecond)
		kb.emit(keyEnter, 0)
		time.Sleep(700 * time.Millisecond)
	}
	return 0
}
