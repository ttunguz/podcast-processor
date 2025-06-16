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
  recording_time = Benchmark.measure do
    stdin, stdout, wait_thread = Open3.popen2(command)
    @recording_process = wait_thread
  end
  puts "Recording setup took: #{recording_time.real.round(2)} seconds"
end

def stop_recording
  stop_time = Benchmark.measure do
    if @recording_process && @recording_process.pid
      begin
        Process.kill('INT', @recording_process.pid)
      rescue Errno::ESRCH
        puts "Process already terminated"
      end
    end
    @recording_process = nil
  end
  puts "Recording cleanup took: #{stop_time.real.round(2)} seconds"
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
  
  command_setup_time = Benchmark.measure do
    @whisperkit_command = [
      WHISPERKIT_CLI_PATH,
      'transcribe',
      '--audio-path',
      audio_file,
      '--model', 
      'tiny'
    ]
  end
  puts "Command setup took: #{command_setup_time.real.round(2)} seconds"
  
  puts "Running: #{@whisperkit_command.join(' ')}"
  
  transcription_time = Benchmark.measure do
    stdout, stderr, status = Open3.capture3(*@whisperkit_command)
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

def type_text(text)
  return if text.nil? || text.empty?
  
  processing_time = Benchmark.measure do
    # Copy text to clipboard and simulate CMD+V to paste
    IO.popen('pbcopy', 'w') { |f| f << text }
    
    apple_script = <<~SCRIPT
      tell application "System Events"
        keystroke "v" using command down
      end tell
    SCRIPT
    
    system('osascript', '-e', apple_script)
  end
  puts "Total text processing and pasting took: #{processing_time.real.round(2)} seconds"
end

puts "Press F7 to start/stop recording (Ctrl+C to exit)"

# Start the hotkey monitor in the background
monitor_start_time = Benchmark.measure do
  @hotkey_monitor = IO.popen('./hotkey_monitor', 'r')
end
puts "Hotkey monitor startup took: #{monitor_start_time.real.round(2)} seconds"

# Main loop
begin
  while line = @hotkey_monitor.gets
    if line.strip == "F7_PRESSED"
      if @recording
        recording_time = Time.now - @recording_start_time
        @recording = false
        stop_recording
        puts "\nRecording stopped after #{recording_time.round(2)} seconds"
        sleep 0.5
        
        full_cycle_time = Benchmark.measure do
          transcription, _ = transcribe_audio(temp_file.path)
          type_text(transcription) if transcription
        end
        puts "Full transcription cycle took: #{full_cycle_time.real.round(2)} seconds"
      else
        @recording = true
        @recording_start_time = Time.now
        start_recording(temp_file, format)
        puts "\nRecording started..."
      end
    end
  end
rescue Interrupt
  cleanup_time = Benchmark.measure do
    Process.kill('TERM', @hotkey_monitor.pid)
    puts "\nExiting..."
  end
  puts "Cleanup took: #{cleanup_time.real.round(2)} seconds"
end