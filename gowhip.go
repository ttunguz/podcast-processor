package main

import (
	"bufio"
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"io/ioutil"
	"net/http"
	"os"
	"os/exec"
	"regexp"
	"strings"
	"time"
)

const WhisperKitCliPath = "/opt/homebrew/bin/whisperkit-cli"

var (
	recording     bool
	recordingProc *os.Process
	startTime     time.Time
)

func startRecording(filePath string) error {
	// Record WAV with WhisperKit requirements (16kHz, 16-bit, mono)
	cmd := exec.Command("sox", "-d", "-b", "16", "-r", "16000", "-c", "1", filePath)

	err := cmd.Start()
	if err != nil {
		return fmt.Errorf("failed to start recording: %v", err)
	}

	recordingProc = cmd.Process
	fmt.Println("Starting recording...")
	return nil
}

func stopRecording() error {
	if recordingProc != nil {
		err := recordingProc.Signal(os.Interrupt)
		if err != nil {
			return fmt.Errorf("failed to stop recording: %v", err)
		}
		recordingProc = nil
	}
	return nil
}

func transcribeAudio(audioFile string) (string, error) {
	fmt.Println("\n=== Starting Transcription Process ===")
	fmt.Printf("Input audio file: %s\n", audioFile)

	if _, err := os.Stat(audioFile); err != nil {
		return "", fmt.Errorf("audio file does not exist: %v", err)
	}

	fileInfo, err := os.Stat(audioFile)
	if err != nil {
		return "", fmt.Errorf("failed to get file info: %v", err)
	}
	fmt.Printf("File size: %d bytes\n", fileInfo.Size())

	fmt.Println("\n=== WhisperKit Command ===")
	fmt.Printf("WhisperKit CLI Path: %s\n", WhisperKitCliPath)

	if _, err := os.Stat(WhisperKitCliPath); err != nil {
		return "", fmt.Errorf("whisperkit CLI not found: %v", err)
	}

	cmd := exec.Command(WhisperKitCliPath, "transcribe", "--audio-path", audioFile, "--model", "tiny")

	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr

	start := time.Now()
	err = cmd.Run()
	duration := time.Since(start)

	fmt.Printf("WhisperKit Status: %v\n", err)
	fmt.Printf("WhisperKit stdout: %s\n", stdout.String())
	fmt.Printf("WhisperKit stderr: %s\n", stderr.String())
	fmt.Printf("Transcription took: %.2f seconds\n", duration.Seconds())

	if err != nil {
		return "", fmt.Errorf("transcription failed: %v", err)
	}

	return strings.TrimSpace(stdout.String()), nil
}

func refineTextWithOllama(text string) string {
	if text == "" {
		return text
	}

	type Message struct {
		Role    string `json:"role"`
		Content string `json:"content"`
	}

	type Request struct {
		Model       string    `json:"model"`
		Messages    []Message `json:"messages"`
		Temperature float64   `json:"temperature"`
		MaxTokens   int       `json:"max_tokens"`
		Stream      bool      `json:"stream"`
	}

	messages := []Message{
		{
			Role:    "system",
			Content: "You are a professional transcript editor. Your task is to enhance readability while maintaining the original meaning and tone. Focus on structural improvements and clarity.",
		},
		{
			Role: "user",
			Content: fmt.Sprintf(`# Text Formatting Assistant

Format the input text according to these rules:

## Required Changes
* Fix spelling and grammar errors
* Remove filler words
* Break into paragraphs after every 3-4 sentences
* Add one blank line between paragraphs
* Format lists where appropriate
* Keep all original meaning and tone

## List Formatting
* Numbered (1., 2., 3.) for sequential items
* Bullets (-) for non-sequential items

## Do Not
* Add any introduction or explanation
* Include analysis or commentary
* Describe changes made
* Add notes or suggestions
* Offer additional help
* Add headers or subject lines
* Add asterisks or bold text
* Add any text not in the original

## Response Format
Return only the formatted text with no additional content.

Transcript: %s`, text),
		},
	}

	reqBody := Request{
		Model:       "gemma2:gguf",
		Messages:    messages,
		Temperature: 0.7,
		MaxTokens:   4096,
		Stream:      false,
	}

	jsonData, err := json.Marshal(reqBody)
	if err != nil {
		fmt.Printf("Error marshaling request: %v\n", err)
		return text
	}

	start := time.Now()
	resp, err := http.Post("http://127.0.0.1:39281/v1/chat/completions", "application/json", bytes.NewBuffer(jsonData))
	if err != nil {
		fmt.Printf("Error calling Cortex: %v\n", err)
		return text
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := ioutil.ReadAll(resp.Body)
		fmt.Printf("Error from Cortex: %s\n", string(body))
		return text
	}

	var result struct {
		Choices []struct {
			Message struct {
				Content string `json:"content"`
			} `json:"message"`
		} `json:"choices"`
	}

	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		fmt.Printf("Error decoding response: %v\n", err)
		return text
	}

	duration := time.Since(start)
	fmt.Printf("Text refinement took: %.2f seconds\n", duration.Seconds())

	if len(result.Choices) > 0 {
		return result.Choices[0].Message.Content
	}
	return text
}

func typeText(text string) {
	if text == "" {
		return
	}

	start := time.Now()

	// Remove timestamps
	re := regexp.MustCompile(`\[\d{2}:\d{2}:\d{2}\.\d{3} --> \d{2}:\d{2}:\d{2}\.\d{3}\]`)
	cleanedText := re.ReplaceAllString(text, "")

	refinedText := cleanedText

	fmt.Println("\n=== Debug: Text Processing ===")
	fmt.Printf("Original text: %s\n", text)
	fmt.Printf("Cleaned text: %s\n", cleanedText)
	fmt.Printf("Refined text: %s\n", refinedText)
	fmt.Println("===========================")

	sentences := strings.FieldsFunc(refinedText, func(r rune) bool {
		return r == '.' || r == '!' || r == '?'
	})

	for _, sentence := range sentences {
		sentence = strings.TrimSpace(sentence)
		if sentence == "" {
			continue
		}

		// Escape quotes and backslashes
		escaped := strings.ReplaceAll(sentence, "\\", "\\\\\\")
		escaped = strings.ReplaceAll(escaped, "\"", "\\\"")

		script := fmt.Sprintf(`tell application "System Events"
			keystroke "%s"
			delay 0.1
			keystroke " "
		end tell`, escaped)

		cmd := exec.Command("osascript", "-e", script)
		cmd.Run()
		time.Sleep(200 * time.Millisecond)
	}

	duration := time.Since(start)
	fmt.Printf("Text processing and typing took: %.2f seconds\n", duration.Seconds())
}

func main() {
	fmt.Println("Press F7 to start/stop recording (Ctrl+C to exit)")

	// Create temp file for recording
	tmpFile, err := ioutil.TempFile("", "recording*.wav")
	if err != nil {
		fmt.Printf("Error creating temp file: %v\n", err)
		return
	}
	defer os.Remove(tmpFile.Name())

	// Start hotkey monitor
	monitor := exec.Command("./hotkey_monitor")
	stdout, err := monitor.StdoutPipe()
	if err != nil {
		fmt.Printf("Error creating pipe: %v\n", err)
		return
	}

	if err := monitor.Start(); err != nil {
		fmt.Printf("Error starting monitor: %v\n", err)
		return
	}

	reader := bufio.NewReader(stdout)
	for {
		line, err := reader.ReadString('\n')
		if err != nil {
			if err != io.EOF {
				fmt.Printf("Error reading from monitor: %v\n", err)
			}
			break
		}

		if strings.TrimSpace(line) == "F7_PRESSED" {
			if recording {
				duration := time.Since(startTime)
				recording = false
				stopRecording()
				fmt.Printf("\nRecording stopped after %.2f seconds\n", duration.Seconds())
				time.Sleep(500 * time.Millisecond)

				if transcription, err := transcribeAudio(tmpFile.Name()); err == nil && transcription != "" {
					typeText(transcription)
				}
			} else {
				recording = true
				startTime = time.Now()
				if err := startRecording(tmpFile.Name()); err != nil {
					fmt.Printf("Error starting recording: %v\n", err)
					recording = false
					continue
				}
				fmt.Println("\nRecording started...")
			}
		}
	}

	monitor.Process.Kill()
}
