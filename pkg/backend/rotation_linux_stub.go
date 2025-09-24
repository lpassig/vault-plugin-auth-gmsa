//go:build windows
// +build windows

package backend

import (
	"fmt"
	"runtime"
)

// NewLinuxRotationManager is a stub for Windows builds
func NewLinuxRotationManager(backend *gmsaBackend, config *RotationConfig) RotationManagerInterface {
	panic(fmt.Sprintf("NewLinuxRotationManager called on Windows platform (GOOS=%s)", runtime.GOOS))
}
