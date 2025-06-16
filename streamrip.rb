require 'open3'
require 'tempfile'
require 'json'
require 'net/http'
require 'benchmark'

# Set up audio recording parameters
format = 'wav'  # Changed to wav format for better compatibility
temp_file = Tempfile.new(['recording', ".#{format}"])
@recording = false
@transcription_thread = nil
@stop_transcription = false

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

def start_transcription
  @transcription_thread = Thread.new do
    Open3.popen3("gstdbuf -oL whisperkit-cli transcribe --model tiny --stream") do |_stdin, stdout, stderr, thread|
      thread.abort_on_exception = true
      
      begin
        stdout.each_line do |line|
          break if @stop_transcription
          
          if line.include?("Current text:")
            text = line.split("Current text:").last.strip
            text = text.gsub("<|startoftranscript|><|en|><|transcribe|><|notimestamps|>", "").strip
            
            if !text.empty? && text != "Waiting for speech..."
              type_text(text)
              puts "Transcribed and typed: #{text}"
            end
          end
        end
      rescue IOError
        puts "Transcription stream ended"
      ensure
        thread.kill if thread
      end
    end
  end
end

def stop_transcription
  if @transcription_thread&.alive?
    @stop_transcription = true
    @transcription_thread.join
    @transcription_thread = nil
    @stop_transcription = false
  end
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
        stop_transcription
        puts "\nRecording stopped after #{recording_time.round(2)} seconds"
      else
        @recording = true
        @recording_start_time = Time.now
        start_recording(temp_file, format)
        start_transcription
        puts "\nRecording and transcription started..."
      end
    end
  end
rescue Interrupt
  cleanup_time = Benchmark.measure do
    stop_transcription
    Process.kill('TERM', @hotkey_monitor.pid)
    puts "\nExiting..."
  end
  puts "Cleanup took: #{cleanup_time.real.round(2)} seconds"
end