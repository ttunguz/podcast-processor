require 'open3'
require 'tempfile'
require 'json'
require 'net/http'

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

WHISPERKIT_CLI_PATH = "/path/to/your/whisperkit_cli"

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
  stdout, stderr, status = Open3.capture3(*convert_command)
  unless status.success?
    puts "Error converting audio: #{stderr}"
    return nil
  end
  puts "FFmpeg conversion successful"
  puts "Converted file exists?: #{File.exist?(converted_file.path)}"
  puts "Converted file size: #{File.size(converted_file.path)} bytes"

  puts "\n=== WhisperKit Command ==="
  puts "WhisperKit CLI Path: #{WHISPERKIT_CLI_PATH}"
  puts "WhisperKit CLI exists?: #{File.exist?(WHISPERKIT_CLI_PATH)}"
  
  whisperkit_command = [
    WHISPERKIT_CLI_PATH,
    converted_file.path
  ]
  
  puts "Running: #{whisperkit_command.join(' ')}"
  stdout, stderr, status = Open3.capture3(*whisperkit_command)
  puts "WhisperKit Status: #{status}"
  puts "WhisperKit stdout: #{stdout}"
  puts "WhisperKit stderr: #{stderr}"
  
  if status.success?
    puts "WhisperKit transcription successful"
    return stdout.strip
  else
    puts "Error transcribing audio: #{stderr}"
    return nil
  end
ensure
  puts "\n=== Cleanup ==="
  puts "Cleaning up temporary file: #{converted_file.path}"
  converted_file.close
  converted_file.unlink
end

def refine_text_with_ollama(text)
  return text if text.nil? || text.empty?

  uri = URI('http://localhost:11434/api/generate')
  request = Net::HTTP::Post.new(uri)
  request.content_type = 'application/json'
  
  prompt = "
            This text is a transcript of a recording. Clean it up for grammar and diction keeping a casual, friendly, but professional tone and keeping it concise. Do not offer help unless explicity in the transcript.

            Do not add append statements like 'Let me know if you have any other questions or need anything else!
            
            Respond without any additonal comments or offers of assistance.

            Do not inject any other text about how you can help. 

            If the transcript is short & doesn't need editing, just return the transcript. 

            Here is the transcript: #{text}"
  
  request.body = {
    model: 'gemma2',
    prompt: prompt,
    stream: false
  }.to_json

  response = Net::HTTP.start(uri.hostname, uri.port) do |http|
    http.request(request)
  end

  if response.is_a?(Net::HTTPSuccess)
    result = JSON.parse(response.body)
    return result['response'].strip
  else
    puts "Error from Ollama: #{response.body}"
    return text
  end
rescue => e
  puts "Error calling Ollama: #{e.message}"
  return text
end

def type_text(text)
  return if text.nil? || text.empty?
  
  # Remove timestamps
  cleaned_text = text.gsub(/\[\d{2}:\d{2}:\d{2}\.\d{3} --> \d{2}:\d{2}:\d{2}\.\d{3}\]/, '')
  
  # Keep letters, numbers, spaces, basic punctuation (,.!?-) and apostrophes
  cleaned_text = cleaned_text.gsub(/[^a-zA-Z0-9\s,.!?'\-]/, '')
                            .strip
                            .squeeze(" ") # Remove multiple spaces
  
  # Refine text with Ollama
  refined_text = refine_text_with_ollama(cleaned_text)
  
  puts "\n=== Debug: Text Processing ==="
  puts "Original text: #{text}"
  puts "Cleaned text: #{cleaned_text}"
  puts "Refined text: #{refined_text}"
  puts "==========================="
  
  # Use osascript to type the refined text
  apple_script = <<~SCRIPT
    tell application "System Events"
      keystroke "#{refined_text.gsub('"', '\"')}"
    end tell
  SCRIPT
  
  system('osascript', '-e', apple_script)
end

puts "Press F7 to start/stop recording (Ctrl+C to exit)"

# Start the hotkey monitor in the background
hotkey_monitor = IO.popen('./hotkey_monitor', 'r')

# Main loop
begin
  while line = hotkey_monitor.gets
    if line.strip == "F7_PRESSED"
      if @recording
        @recording = false
        stop_recording
        puts "\nRecording stopped"
        sleep 0.5
        transcription = transcribe_audio(temp_file.path)
        sleep 1
        type_text(transcription) if transcription
      else
        @recording = true
        start_recording(temp_file, format)
        puts "\nRecording started..."
      end
    end
  end
rescue Interrupt
  Process.kill('TERM', hotkey_monitor.pid)
  puts "\nExiting..."
end
