package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"strings"

	"github.com/charmbracelet/bubbles/textarea"
	"github.com/charmbracelet/bubbles/viewport"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/glamour"
	"github.com/charmbracelet/lipgloss"
)

// --- Configuration ---
const (
	ollamaAPIURL = "http://localhost:11434/api/chat"
	modelName    = "gemma3:12b"
)

// --- Styles ---
var (
	senderStyle = lipgloss.NewStyle().Foreground(lipgloss.Color("5"))
	botStyle    = lipgloss.NewStyle().Foreground(lipgloss.Color("6"))
	errorStyle  = lipgloss.NewStyle().Foreground(lipgloss.Color("1")).Bold(true)
)

// --- Bubble Tea Model ---

type (
	errMsg            error
	ollamaResponseMsg string
)

type model struct {
	viewport    viewport.Model
	textarea    textarea.Model
	senderStyle lipgloss.Style
	err         error
	history     []ollamaMessage
	width       int
	height      int
	renderer    *glamour.TermRenderer
}

type ollamaMessage struct {
	Role    string `json:"role"`
	Content string `json:"content"`
}

func initialModel(context string) model {
	ta := textarea.New()
	ta.Placeholder = "Ask a question about the document..."
	ta.Focus()
	ta.Prompt = "┃ "
	ta.CharLimit = 0 // No limit
	ta.ShowLineNumbers = false
	ta.SetHeight(3) // Set a fixed height for textarea
	ta.SetValue("") // Ensure it starts empty

	vp := viewport.New(120, 40) // Start with larger initial dimensions
	vp.SetContent("Welcome! The document context has been loaded. Ask your first question below.\n\nControls:\n• Press Enter to send your question\n• Use Up/Down arrows, Page Up/Down, Home/End to scroll (always available)\n• Press Tab to switch focus between input and viewport\n• Space bar scrolls down when viewport is focused\n• Press Ctrl+C to quit\n\nType your question in the input area at the bottom.")

	// Setup Glamour renderer for markdown with simpler options
	renderer, err := glamour.NewTermRenderer(
		glamour.WithStandardStyle("dark"),
		glamour.WithWordWrap(116), // Wider word wrap for larger screen
	)
	if err != nil {
		// Fallback if glamour fails
		renderer = nil
	}

	systemPrompt := ollamaMessage{
		Role: "system",
		Content: fmt.Sprintf(`You are a helpful AI assistant. Answer the user's questions based *only* on the context provided below.
Your task is to be a knowledgeable expert on this specific document.
Do not use any external knowledge. If the answer is not in the document, say so clearly.

--- DOCUMENT CONTEXT ---
%s
--- END DOCUMENT CONTEXT ---`, context),
	}

	return model{
		textarea:    ta,
		viewport:    vp,
		senderStyle: senderStyle,
		history:     []ollamaMessage{systemPrompt},
		renderer:    renderer,
		width:       120, // Larger initial width
		height:      45,  // Larger initial height
	}
}

// --- Bubble Tea Program ---

func (m model) Init() tea.Cmd {
	return tea.Batch(
		textarea.Blink,
		func() tea.Msg {
			// Send an initial window size message with larger dimensions
			return tea.WindowSizeMsg{Width: 120, Height: 45}
		},
	)
}

func (m model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	var (
		tiCmd tea.Cmd
		vpCmd tea.Cmd
	)

	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.width = msg.Width
		m.height = msg.Height

		// Calculate available space for viewport - use most of the screen
		// Account for: textarea (3 lines) + minimal borders/padding (2 lines)
		availableHeight := m.height - 5
		if availableHeight < 10 {
			availableHeight = 10 // Minimum height
		}

		// Use almost full width and height
		m.viewport.Width = m.width - 2 // Minimal border padding
		m.viewport.Height = availableHeight
		m.textarea.SetWidth(m.width - 2)

		// Update renderer with new width
		if m.renderer != nil {
			newRenderer, err := glamour.NewTermRenderer(
				glamour.WithStandardStyle("dark"),
				glamour.WithWordWrap(m.width-4), // Minimal padding for word wrap
			)
			if err == nil {
				m.renderer = newRenderer
			}
		}
		m.updateViewport()

	case tea.KeyMsg:
		// Handle special keys first
		switch msg.Type {
		case tea.KeyCtrlC:
			return m, tea.Quit
		case tea.KeyTab:
			// Toggle focus between textarea and viewport
			if m.textarea.Focused() {
				m.textarea.Blur()
			} else {
				m.textarea.Focus()
			}
			return m, nil
		case tea.KeyEnter:
			if m.textarea.Focused() && m.textarea.Value() != "" {
				m.history = append(m.history, ollamaMessage{Role: "user", Content: m.textarea.Value()})
				m.updateViewport()
				m.textarea.Reset()
				return m, m.queryOllama
			}
			return m, nil
		case tea.KeyUp, tea.KeyDown:
			// Up/Down arrows always scroll viewport, regardless of focus
			m.viewport, vpCmd = m.viewport.Update(msg)
			return m, vpCmd
		case tea.KeyPgUp, tea.KeyPgDown, tea.KeyHome, tea.KeyEnd:
			// Page navigation keys always go to viewport
			m.viewport, vpCmd = m.viewport.Update(msg)
			return m, vpCmd
		}

		// Route remaining keys based on focus
		if m.textarea.Focused() {
			// When textarea is focused, let it handle text input
			m.textarea, tiCmd = m.textarea.Update(msg)
			return m, tiCmd
		} else {
			// When viewport is focused, handle space for scrolling
			switch msg.Type {
			case tea.KeySpace:
				m.viewport, vpCmd = m.viewport.Update(msg)
				return m, vpCmd
			}
		}

	case ollamaResponseMsg:
		m.history = append(m.history, ollamaMessage{Role: "assistant", Content: string(msg)})
		m.updateViewport()
	case errMsg:
		m.err = msg
	}

	return m, nil
}

func (m model) View() string {
	if m.err != nil {
		return errorStyle.Render(fmt.Sprintf("Error: %v", m.err))
	}

	// Use almost full screen dimensions
	viewportWidth := m.width - 2 // Minimal border
	if viewportWidth < 20 {
		viewportWidth = 20
	}

	viewportHeight := m.height - 4 // Account for textarea and minimal padding
	if viewportHeight < 10 {
		viewportHeight = 10
	}

	// Choose border color based on focus
	borderColor := lipgloss.Color("240") // Default gray
	if !m.textarea.Focused() {
		borderColor = lipgloss.Color("6") // Cyan when viewport is focused
	}

	viewportBox := lipgloss.NewStyle().
		Border(lipgloss.RoundedBorder()).
		BorderForeground(borderColor).
		Width(viewportWidth).
		Height(viewportHeight).
		Render(m.viewport.View())

	return fmt.Sprintf("%s\n%s", viewportBox, m.textarea.View())
}

func (m *model) updateViewport() {
	var content strings.Builder
	for i, msg := range m.history {
		if i == 0 { // Skip system prompt
			continue
		}

		if msg.Role == "user" {
			// Format user message
			var userMsg string
			if m.renderer != nil {
				userMsg, _ = m.renderer.Render(fmt.Sprintf("**You:**\n%s", msg.Content))
			} else {
				userMsg = fmt.Sprintf("You:\n%s", msg.Content)
			}
			content.WriteString(m.senderStyle.Render(userMsg))
		} else if msg.Role == "assistant" {
			// Format assistant message
			var assistantMsg string
			if m.renderer != nil {
				assistantMsg, _ = m.renderer.Render(fmt.Sprintf("**Ollama:**\n%s", msg.Content))
			} else {
				assistantMsg = fmt.Sprintf("Ollama:\n%s", msg.Content)
			}
			content.WriteString(botStyle.Render(assistantMsg))
		}

		// Add spacing between messages
		content.WriteString("\n\n")
	}

	m.viewport.SetContent(content.String())
	m.viewport.GotoBottom()
}

func (m model) queryOllama() tea.Msg {
	// Don't manipulate viewport content directly here
	// The "thinking" state can be handled in the UI if needed

	type ollamaRequestBody struct {
		Model    string          `json:"model"`
		Messages []ollamaMessage `json:"messages"`
		Stream   bool            `json:"stream"`
	}

	requestBody := ollamaRequestBody{
		Model:    modelName,
		Messages: m.history,
		Stream:   false,
	}

	jsonBody, err := json.Marshal(requestBody)
	if err != nil {
		return errMsg(fmt.Errorf("error marshalling request: %w", err))
	}
	log.Printf("Sending to Ollama: %s", string(jsonBody))

	resp, err := http.Post(ollamaAPIURL, "application/json", bytes.NewBuffer(jsonBody))
	if err != nil {
		return errMsg(fmt.Errorf("http post error: %w", err))
	}
	defer resp.Body.Close()

	bodyBytes, err := io.ReadAll(resp.Body)
	if err != nil {
		return errMsg(fmt.Errorf("error reading response body: %w", err))
	}
	log.Printf("Received from Ollama: %s", string(bodyBytes))

	var ollamaResp struct {
		Message ollamaMessage `json:"message"`
		Error   string        `json:"error,omitempty"`
	}

	if err := json.Unmarshal(bodyBytes, &ollamaResp); err != nil {
		return errMsg(fmt.Errorf("failed to unmarshal ollama response: %w. Response: %s", err, string(bodyBytes)))
	}

	if ollamaResp.Error != "" {
		return errMsg(fmt.Errorf("ollama API error: %s", ollamaResp.Error))
	}

	return ollamaResponseMsg(ollamaResp.Message.Content)
}

// --- Main Function ---

func main() {
	if len(os.Args) < 2 {
		fmt.Println("Usage: ./your_app <path_to_text_file>")
		os.Exit(1)
	}

	filePath := os.Args[1]
	fullContent, err := os.ReadFile(filePath)
	if err != nil {
		log.Fatalf("Error reading file: %v", err)
	}

	// Use the full file content as context
	context := string(fullContent)
	lines := strings.Split(context, "\n")
	log.Printf("Using full document as context: %d lines, %d characters.", len(lines), len(context))

	// Setup logging to a file
	logFile, err := os.OpenFile("ollama_qa.log", os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0666)
	if err != nil {
		log.Fatal(err)
	}
	log.SetOutput(logFile)
	log.Println("Application starting...")

	// Clear any existing terminal state
	fmt.Print("\033[2J\033[H") // Clear screen and move cursor to top-left

	p := tea.NewProgram(
		initialModel(context),
		tea.WithInput(os.Stdin),
		tea.WithOutput(os.Stderr), // Use stderr to avoid mixing with stdout
	)

	if _, err := p.Run(); err != nil {
		log.Fatal(err)
	}
	log.Println("Application exiting.")
}
