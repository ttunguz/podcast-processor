require 'io/console'
require 'open3'
require 'thread'

# Function to copy text to clipboard and simulate paste
def copy_to_clipboard(text)
  IO.popen('pbcopy', 'w') { |clipboard| clipboard.print text }
  apple_script = <<~SCRIPT
    tell application "System Events"
      keystroke "v" using command down
    end tell
  SCRIPT
  system('osascript', '-e', apple_script)
  # Clear clipboard after pasting
  IO.popen('pbcopy', 'w') { |clipboard| clipboard.print "" }
end

# Signal handler for Ctrl+C to exit gracefully
Signal.trap("INT") do
  puts "\nExiting gracefully."
  exit
end

transcribing = false
prev_text = ""
mutex = Mutex.new
stop_thread = false
transcription_thread = nil

puts "Press F7 to start or pause the process. Press 'q' to quit."

# Function to handle transcription
def start_transcription(mutex, stop_thread, prev_text)
  Open3.popen3("gstdbuf -oL whisperkit-cli transcribe --model tiny --stream") do |_stdin, stdout, stderr, thread|
    thread.abort_on_exception = true

    begin
      stdout.each_line do |line|
        mutex.synchronize do
          break if stop_thread # Stop processing if thread is signaled to stop

          if line.include?("Current text:")
            current_text = line.split("Current text:").last.strip
            # Remove whisper tags if present
            current_text = current_text.gsub("<|startoftranscript|><|en|><|transcribe|><|notimestamps|>", "").strip

            if current_text == "Waiting for speech..." && !prev_text.empty?
              prev_text.clear
            elsif !current_text.empty? && current_text != "Waiting for speech..." && current_text != prev_text
              # Only copy and paste the new content (difference between current and previous)
              new_content = current_text[prev_text.length..-1]
              if new_content && !new_content.empty?
                copy_to_clipboard(new_content)
                puts "Transcribed and typed new content: #{new_content}"
                prev_text.replace(current_text)
              end
            end
          end
        end
      end
    rescue IOError
      puts "Stream ended."
    ensure
      thread.kill if thread
    end
  end
end

# Start hotkey monitor
hotkey_monitor = IO.popen('./hotkey_monitor', 'r')

begin
  while line = hotkey_monitor.gets
    if line.strip == "F7_PRESSED"
      if transcribing
        # Stop transcription
        mutex.synchronize { stop_thread = true }
        transcription_thread&.join
        transcription_thread = nil
        stop_thread = false
        transcribing = false
        puts "\nTranscription stopped"
      else
        # Start transcription
        transcription_thread = Thread.new do
          start_transcription(mutex, stop_thread, prev_text)
        end
        transcribing = true
        puts "\nTranscription started"
      end
    end
  end
rescue Interrupt
  Process.kill('TERM', hotkey_monitor.pid)
  mutex.synchronize { stop_thread = true }
  transcription_thread&.join
  puts "\nExiting..."
end
