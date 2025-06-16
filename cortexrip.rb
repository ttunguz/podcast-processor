require 'open3'
require 'tempfile'
require 'json'
require 'net/http'
require 'benchmark'

# Set up audio recording parameters
format = 'wav'  # Changed to wav format for better compatibility
temp_file = Tempfile.new(['recording', ".#{format}"])
@recording = false

def start_recording(file, format)
  # Record in WAV format with WhisperKit requirements (16kHz, 16-bit, mono)
  command = "sox -d -b 16 -r 16000 -c 1 #{file.path}"
  puts "Starting recording..."
  stdin, stdout, wait_thread = Open3.popen2(command)
  @recording_process = wait_thread
end

def stop_recording
  if @recording_process && @recording_process.pid
    begin
      Process.kill('INT', @recording_process.pid)
    rescue Errno::ESRCH
      puts "Process already terminated"
    end
  end
  @recording_process = nil
end

WHISPERKIT_CLI_PATH = "/opt/homebrew/bin/whisperkit-cli"

def transcribe_audio(audio_file)
  puts "\n=== Starting Transcription Process ==="
  puts "Input audio file: #{audio_file}"
  puts "File exists?: #{File.exist?(audio_file)}"
  puts "File size: #{File.size(audio_file)} bytes"

  puts "\n=== WhisperKit Command ==="
  puts "WhisperKit CLI Path: #{WHISPERKIT_CLI_PATH}"
  puts "WhisperKit CLI exists?: #{File.exist?(WHISPERKIT_CLI_PATH)}"
  
  whisperkit_command = [
    WHISPERKIT_CLI_PATH,
    'transcribe',
    '--audio-path',
    audio_file,
    '--model', 
    'tiny'
  ]
  
  puts "Running: #{whisperkit_command.join(' ')}"
  
  transcription_time = Benchmark.measure do
    stdout, stderr, status = Open3.capture3(*whisperkit_command)
    puts "WhisperKit Status: #{status}"
    puts "WhisperKit stdout: #{stdout}"
    puts "WhisperKit stderr: #{stderr}"
    
    if status.success?
      puts "WhisperKit transcription successful"
      @transcription_result = stdout.strip
    else
      puts "Error transcribing audio: #{stderr}"
      @transcription_result = nil
    end
  end
  puts "Transcription took: #{transcription_time.real.round(2)} seconds"
  
  return @transcription_result, nil
end

def refine_text_with_ollama(text)
  return text if text.nil? || text.empty?

  uri = URI('http://127.0.0.1:39281/v1/chat/completions')
  request = Net::HTTP::Post.new(uri)
  request.content_type = 'application/json'
  
  messages = [{
    role: "system",
    content: "You are a professional transcript editor. Your task is to enhance readability while maintaining the original meaning and tone. Focus on structural improvements and clarity."
  }, {
    role: "user", 
    content: <<~PROMPT
    # Text Formatting Assistant

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

Transcript: #{text}

    PROMPT
  }]

  puts "\n=== Debug: User Message Content ==="
  puts messages[1][:content]
  puts "==================================="

  request.body = {
    model: 'gemma2:gguf',
    messages: messages,
    temperature: 0.7,
    max_tokens: 4096,
    stream: false
  }.to_json

  refinement_time = Benchmark.measure do
    response = Net::HTTP.start(uri.hostname, uri.port) do |http|
      http.request(request)
    end

    if response.is_a?(Net::HTTPSuccess)
      result = JSON.parse(response.body)
      @refined_text = result['choices'][0]['message']['content']
    else
      puts "Error from Cortex: #{response.body}"
      @refined_text = text
    end
  end
  puts "Text refinement took: #{refinement_time.real.round(2)} seconds"
  
  return @refined_text
rescue => e
  puts "Error calling Cortex: #{e.message}"
  return text
end

def type_text(text)
  return if text.nil? || text.empty?
  
  processing_time = Benchmark.measure do
    # Remove timestamps
    cleaned_text = text.gsub(/\[\d{2}:\d{2}:\d{2}\.\d{3} --> \d{2}:\d{2}:\d{2}\.\d{3}\]/, '')
    
    # Keep letters, numbers, spaces, basic punctuation (,.!?-) and apostrophes
    #cleaned_text = cleaned_text.gsub(/[^a-zA-Z0-9\s,.!?'\-%]/, '') .strip
    
    
    # Refine text with Ollama
    #refined_text = refine_text_with_ollama(cleaned_text)
    refined_text = cleaned_text
    
    puts "\n=== Debug: Text Processing ==="
    puts "Original text: #{text}"
    puts "Cleaned text: #{cleaned_text}"
    puts "Refined text: #{refined_text}"
    puts "==========================="
    
    # Split text into sentences and type each one
    sentences = refined_text.split(/(?<=[.!?])\s+/)
    sentences.each do |sentence|
      # Escape any double quotes and backslashes in the sentence
      escaped_sentence = sentence.gsub('\\', '\\\\\\').gsub('"', '\\"')
      
      apple_script = <<~SCRIPT
        tell application "System Events"
          keystroke "#{escaped_sentence}"
          delay 0.1
          keystroke " "
        end tell
      SCRIPT
      
      system('osascript', '-e', apple_script)
      sleep 0.2 # Slightly longer delay between sentences
    end
  end
  puts "Text processing and typing took: #{processing_time.real.round(2)} seconds"
end

puts "Press F7 to start/stop recording (Ctrl+C to exit)"

# Start the hotkey monitor in the background
hotkey_monitor = IO.popen('./hotkey_monitor', 'r')

# Main loop
begin
  while line = hotkey_monitor.gets
    if line.strip == "F7_PRESSED"
      if @recording
        recording_time = Time.now - @recording_start_time
        @recording = false
        stop_recording
        puts "\nRecording stopped after #{recording_time.round(2)} seconds"
        sleep 0.5
        transcription, _ = transcribe_audio(temp_file.path)
        type_text(transcription) if transcription
      else
        @recording = true
        @recording_start_time = Time.now
        start_recording(temp_file, format)
        puts "\nRecording started..."
      end
    end
  end
rescue Interrupt
  Process.kill('TERM', hotkey_monitor.pid)
  puts "\nExiting..."
end
