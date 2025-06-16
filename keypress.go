package main

import (
	"fmt"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/micmonay/keybd_event"
)

func main() {
	kb, err := keybd_event.NewKeyBonding()
	if err != nil {
		panic(err)
	}

	// For mac
	kb.SetKeys(keybd_event.HasALTGR)

	isPressed := false
	ticker := time.NewTicker(100 * time.Millisecond)
	defer ticker.Stop()

	// Set up signal catching
	sig := make(chan os.Signal, 1)
	signal.Notify(sig, syscall.SIGINT, syscall.SIGTERM)

	fmt.Println("Press and hold the Option key. Press Ctrl+C to exit.")

	for {
		select {
		case <-ticker.C:
			if !isPressed {
				if err := kb.Press(); err != nil {
					panic(err)
				}
				isPressed = true
				fmt.Println("Option key pressed")
			} else {
				if err := kb.Release(); err != nil {
					panic(err)
				}
				isPressed = false
				fmt.Println("Option key released")
			}
		case <-sig:
			fmt.Println("\nExiting...")
			return
		}
	}
}
