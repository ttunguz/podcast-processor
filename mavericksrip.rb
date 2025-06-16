require 'open3'
require 'tempfile'
require 'benchmark'

# Set up audio recording parameters
format = 'wav'
temp_file = Tempfile.new(['recording', ".#{format}"])
@recording = false

def start_recording(file, format)
  command = "sox -d -b 16 -r 16000 -c 1 #{file.path}"
  puts "Starting recording..."
  @recording_process = Process.spawn(command)
  Process.detach(@recording_process)
end

def stop_recording
  if @recording_process
    begin
      Process.kill('INT', @recording_process)
      Process.wait(@recording_process)
    rescue Errno::ECHILD
      puts "Recording process already terminated."
    rescue Errno::ESRCH
      puts "Recording process not found."
    ensure
      @recording_process = nil
    end
  else
    puts "No recording process to stop."
  end
end

WHISPERKIT_CLI_PATH = "/opt/homebrew/bin/whisperkit-cli"

def transcribe_audio(audio_file)
  puts "\n=== Starting Transcription Process ==="
  @whisperkit_command = [
    WHISPERKIT_CLI_PATH,
    'transcribe',
    '--audio-path',
    audio_file,
    '--model',
    'tiny'
  ]

  stdout, stderr, status = Open3.capture3(*@whisperkit_command)
  if status.success?
    puts "WhisperKit transcription successful"
    return stdout.strip
  else
    puts "Error transcribing audio: #{stderr}"
    return nil
  end
end

def type_text(text)
  return if text.nil? || text.empty?

  # Copy text to clipboard
  IO.popen('pbcopy', 'w') { |f| f << text }
  
  # Simulate CMD+V to paste
  apple_script = <<~SCRIPT
    tell application "System Events"
      keystroke "v" using command down
    end tell
  SCRIPT

  system('osascript', '-e', apple_script)
end

def process_recording(file_path)
  transcription = nil

  transcription_thread = Thread.new do
    transcription = transcribe_audio(file_path)
  end

  transcription_thread.join
  type_text(transcription) if transcription
end

puts "Press F7 to start/stop recording (Ctrl+C to exit)"

@hotkey_monitor = IO.popen('./hotkey_monitor', 'r')

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
          process_recording(temp_file.path)
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
  Process.kill('TERM', @hotkey_monitor.pid)
  puts "\nExiting..."
ensure
  temp_file.unlink
end
