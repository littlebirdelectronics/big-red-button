//go:build !linux

package main

import (
	"fmt"
	"os"
)

// The daemon only works on Linux; these stubs let the package (and its tests) build elsewhere.

func notLinux() int {
	fmt.Fprintln(os.Stderr, "bigredbutton only runs on Linux. On a Mac, use the Big Red Button app.")
	return 1
}

func runDaemon(string) int  { return notLinux() }
func listen(string) int     { return notLinux() }
func testAction(string) int { return notLinux() }
func emulateButton(int) int { return notLinux() }
func serviceState() string  { return "not Linux" }
func restartService() error { return nil }
