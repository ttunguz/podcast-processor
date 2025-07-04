require 'open3'
require 'tempfile'
require 'json'
require 'net/http'
require 'benchmark'

# Set up audio recording parameters
format = 'wav'
temp_file = Tempfile.new(['recording', ".#{format}"])
@recording = false

def start_recording(file, format)
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
  
  converted_file = Tempfile.new(['converted', '.wav'])
  puts "Created temp file at: #{converted_file.path}"
  
  convert_command = [
    'ffmpeg',
    '-y',
    '-i', audio_file,
    '-ar', '16000',
    '-ac', '1',
    '-c:a', 'pcm_s16le',
    '-v', 'verbose',
    converted_file.path
  ]
  
  puts "\n=== FFmpeg Command ==="
  puts "Running: #{convert_command.join(' ')}"
  
  conversion_time = Benchmark.measure do
    stdout, stderr, status = Open3.capture3(*convert_command)
    unless status.success?
      puts "Error converting audio: #{stderr}"
      return nil
    end
  end
  puts "FFmpeg conversion took: #{conversion_time.real.round(2)} seconds"
  
  puts "FFmpeg conversion successful"
  puts "Converted file exists?: #{File.exist?(converted_file.path)}"
  puts "Converted file size: #{File.size(converted_file.path)} bytes"

  puts "\n=== WhisperKit Command ==="
  puts "WhisperKit CLI Path: #{WHISPERKIT_CLI_PATH}"
  puts "WhisperKit CLI exists?: #{File.exist?(WHISPERKIT_CLI_PATH)}"
  
  whisperkit_command = [
    WHISPERKIT_CLI_PATH,
    'transcribe',
    '--audio-path',
    converted_file.path,
    '--model', 
    'small'
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
  
  return @transcription_result, converted_file
end

def refine_text_with_ollama(text)
  return text if text.nil? || text.empty?

  uri = URI('http://localhost:11434/api/chat')
  request = Net::HTTP::Post.new(uri)
  request.content_type = 'application/json'
  
  messages = [{
    role: "system", 
    content: "You are a professional transcript editor. Your task is to enhance readability while maintaining the original meaning and tone. Focus on structural improvements and clarity.",
    role: "user",
    content: "
# Email Formatting

You are an AI specializing in email formatting. Given a raw text transcript, transform it into a professional email.

## Formatting Instructions

*   **Structure:**
    *   Separate topics into paragraphs with a blank line between each. This should happen every 3rd or 4th sentence. 
    *   Identify and create ordered (numbered) or unordered (bulleted) lists.
        *   Ordered lists: Use \"1\.\", \"2\.\", \"3\.\", etc.
        *   Unordered lists: Use \"\-\" or \"\*\" for each item. 
*   **Style:**
    *   Maintain the original tone.
    *   Remove filler words (\"um\", \"uh\", \"like\", etc.).
    *   Correct grammar and spelling.
    *   Remove redundancy.

## Strict Output Rules

*   **Output ONLY the formatted email:** No introductions, conclusions, or explanations.
*   **Stay faithful to the original content:** Only reformat and clean up.
*   **Break up longer tracts into paragraphs of 2-3 sentences.

## Transcript

\`\`\`
\#{text}
\`\`\`

\## **Now, format the transcript above, following all instructions precisely.**"

  }]

  request.body = {
    model: 'gemma2:2b',
    messages: messages
  }.to_json

  refinement_time = Benchmark.measure do
    response = Net::HTTP.start(uri.hostname, uri.port) do |http|
      http.request(request)
    end

    if response.is_a?(Net::HTTPSuccess)
      result = JSON.parse(response.body)
      @refined_text = result['response']
    else
      puts "Error from Ollama: #{response.body}"
      @refined_text = text
    end
  end
  puts "Text refinement took: #{refinement_time.real.round(2)} seconds"
  
  return @refined_text
rescue => e
  puts "Error calling Ollama: #{e.message}"
  return text
end

def type_text(text)
  return if text.nil? || text.empty?
  
  processing_time = Benchmark.measure do
    # Remove timestamps
    cleaned_text = text.gsub(/\[\d{2}:\d{2}:\d{2}\.\d{3} --> \d{2}:\d{2}:\d{2}\.\d{3}\]/, '')
    
    # Keep letters, numbers, spaces, basic punctuation (,.!?-) and apostrophes
    cleaned_text = cleaned_text.gsub(/[^a-zA-Z0-9\s,.!?'\-%]/, '')
                              .strip
    
    
    # Refine text with Ollama
    refined_text = refine_text_with_ollama(cleaned_text)
    
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
        transcription, converted_file = transcribe_audio(temp_file.path)
        type_text(transcription) if transcription
        
        puts "\n=== Cleanup ==="
        puts "Cleaning up temporary file: #{converted_file.path}"
        converted_file.close
        converted_file.unlink
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
