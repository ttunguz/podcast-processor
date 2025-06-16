package main

import (
	"bufio"
	"fmt"
	"os"
	"os/exec"
	"strings"
	"syscall"
	"time"

	hook "github.com/robotn/gohook"
)

func run() {
	var cmd *exec.Cmd
	var isRunning bool
	var lastText string

	fmt.Println("Initializing keyboard hook...")
	evChan := hook.Start()
	defer hook.End()

	fmt.Println("Press F7 to start/stop transcription. Press Ctrl+C to exit.")
	fmt.Println("Waiting for keyboard events...")

	for ev := range evChan {
		fmt.Printf("Received keyboard event - Kind: %v, Rawcode: %v\n", ev.Kind, ev.Rawcode)
		// Check if F7 is pressed (keycode 98 based on observed output)
		// Only trigger on KeyDown (Kind 4) to avoid double triggers
		if ev.Kind == 4 && ev.Rawcode == 98 {
			fmt.Println("F7 key detected")
			if !isRunning {
				fmt.Println("Preparing to start transcription...")
				// Start the transcription process
				cmd = exec.Command("whisperkit-cli", "transcribe", "--model", "tiny", "--stream")

				// Print the full command that will be executed
				fmt.Printf("Executing command: %s\n", cmd.String())

				// Print current working directory
				pwd, err := os.Getwd()
				if err == nil {
					fmt.Printf("Current working directory: %s\n", pwd)
				}

				// Create pipes for both stdout and stderr
				stdout, err := cmd.StdoutPipe()
				if err != nil {
					fmt.Printf("Error creating stdout pipe: %v\n", err)
					continue
				}

				stderr, err := cmd.StderrPipe()
				if err != nil {
					fmt.Printf("Error creating stderr pipe: %v\n", err)
					continue
				}

				// Start goroutine to monitor stderr before starting the process
				go func() {
					scanner := bufio.NewScanner(stderr)
					for scanner.Scan() {
						fmt.Printf("stderr: %s\n", scanner.Text())
					}
				}()

				// Start goroutine to monitor stdout before starting the process
				go func() {
					scanner := bufio.NewScanner(stdout)
					fmt.Println("Starting to read output stream...")
					for scanner.Scan() {
						line := scanner.Text()
						fmt.Printf("stdout: %s\n", line)
						if strings.Contains(line, "Current text:") {
							text := strings.TrimPrefix(line, "Current text:")
							text = strings.TrimSpace(text)

							// Check if the next line is "Waiting for speech..."
							if scanner.Scan() {
								nextLine := scanner.Text()
								fmt.Printf("stdout: %s\n", nextLine)
								if strings.Contains(nextLine, "Waiting for speech") && text != "" {
									lastText = text
									// Remove the markers from the text
									lastText = strings.TrimPrefix(lastText, "<|startoftranscript|><|en|><|transcribe|><|notimestamps|>")
									lastText = strings.TrimSpace(lastText)
									fmt.Printf("Processed text: %s\n", lastText)

									// Copy to clipboard using pbcopy
									copyCmd := exec.Command("pbcopy")
									stdin, err := copyCmd.StdinPipe()
									if err == nil {
										go func() {
											defer stdin.Close()
											fmt.Fprintln(stdin, lastText)
										}()
										err = copyCmd.Run()
										if err != nil {
											fmt.Printf("Error copying to clipboard: %v\n", err)
										} else {
											fmt.Println("Text successfully copied to clipboard")
										}
									}
								}
							}
						}
					}
					if err := scanner.Err(); err != nil {
						fmt.Printf("Error reading output: %v\n", err)
					}
					fmt.Println("Output stream reading completed")
				}()

				fmt.Println("Attempting to start whisperkit-cli...")
				err = cmd.Start()
				if err != nil {
					fmt.Printf("Error starting transcription: %v\n", err)
					// Print more detailed error information
					if exitErr, ok := err.(*exec.ExitError); ok {
						fmt.Printf("Exit error details: %v\n", exitErr.Error())
					}
					if pathErr, ok := err.(*os.PathError); ok {
						fmt.Printf("Path error details: %v\n", pathErr.Error())
					}
					// Check if whisperkit-cli exists in PATH
					_, err := exec.LookPath("whisperkit-cli")
					if err != nil {
						fmt.Printf("whisperkit-cli not found in PATH: %v\n", err)
					}
					continue
				}

				isRunning = true
				fmt.Printf("Transcription started with PID: %d\n", cmd.Process.Pid)

				// Add process verification
				go func() {
					time.Sleep(2 * time.Second) // Give process time to start
					if proc, err := os.FindProcess(cmd.Process.Pid); err == nil {
						// On Unix systems, this always succeeds, so we need to send signal 0 to test
						err := proc.Signal(syscall.Signal(0))
						if err == nil {
							fmt.Printf("Verified process %d is running\n", cmd.Process.Pid)
						} else {
							fmt.Printf("Process %d appears to have failed to start: %v\n", cmd.Process.Pid, err)
							isRunning = false
						}
					}
				}()

			} else {
				fmt.Println("Preparing to stop transcription...")
				// Stop the transcription process
				if cmd != nil && cmd.Process != nil {
					fmt.Printf("Attempting to kill process with PID: %d\n", cmd.Process.Pid)
					err := cmd.Process.Kill()
					if err != nil {
						fmt.Printf("Error stopping transcription: %v\n", err)
						continue
					}

					fmt.Println("Waiting for process to fully terminate...")
					err = cmd.Wait()
					if err != nil {
						fmt.Printf("Error waiting for process to end: %v\n", err)
					}

					isRunning = false
					fmt.Println("Transcription stopped successfully")
				}
			}
		}
	}
}

func main() {
	run()
}
