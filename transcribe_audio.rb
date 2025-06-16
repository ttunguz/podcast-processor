require 'fileutils'

def transcribe_audio(audio_file)
  puts "[DEBUG] Starting transcribe_audio with file: #{audio_file}"

  unless File.exist?(audio_file)
    puts "Error: Input WAV file #{audio_file} does not exist."
    return nil
  end

  # Determine the output transcript filename base and expected final name
  transcript_file_base = audio_file.gsub(/\.wav$/, '_transcript')
  transcript_file_expected = transcript_file_base + '.txt'
  puts "[DEBUG] Transcript base name for whisper: #{transcript_file_base}"
  puts "[DEBUG] Expected transcript file: #{transcript_file_expected}"
  
  # Delete existing transcript file before transcription to ensure overwrite
  if File.exist?(transcript_file_expected)
    puts "[DEBUG] Deleting existing transcript file: #{transcript_file_expected}"
    File.delete(transcript_file_expected)
  end

  # Run whisper transcription using the correct model and binary
  # Use a standard GGML model file; CoreML acceleration should be automatic if enabled in the build
  model_path = "models/ggml-base.en-q5_0.bin" 
  binary_path = "./build/bin/main" # Using the built binary
  
  unless File.exist?(model_path)
    puts "Error: Whisper model not found at #{model_path}"
    return nil
  end
  unless File.exist?(binary_path)
    puts "Error: Whisper binary not found at #{binary_path}"
    return nil
  end

  # Pass the base name to -of, main binary should append .txt
  cmd = "#{binary_path} -m #{model_path} -f #{audio_file} -otxt -of #{transcript_file_base}"
  puts "[DEBUG] Running transcription command: #{cmd}"
  system_output = system(cmd)
  puts "[DEBUG] Transcription command returned: #{system_output}"

  # Check if the transcript file was created
  # Add a small wait loop in case of file system delays after the process exits
  transcript_file_path = nil
  if system_output
    max_wait_seconds = 3 # Changed wait time to 3 seconds
    wait_interval = 0.5
    start_time = Time.now
    while Time.now - start_time < max_wait_seconds
      if File.exist?(transcript_file_expected) # Check for the expected file
        transcript_size = File.size(transcript_file_expected)
        puts "[DEBUG] Transcript file found after waiting: #{transcript_file_expected}, size: #{transcript_size} bytes"
        transcript_file_path = transcript_file_expected
        break
      end
      puts "[DEBUG] Waiting for transcript file '#{transcript_file_expected}' to appear (#{Time.now - start_time}s)..."
      sleep(wait_interval)
    end
  end

  if transcript_file_path
    return transcript_file_path
  elsif system_output
    puts "Error: Transcript file '#{transcript_file_expected}' was not found after waiting #{max_wait_seconds} seconds, even though command succeeded."
    return nil
  else
    puts "Error: Transcription command failed (returned #{system_output})."
    return nil
  end
end

if __FILE__ == $0
  if ARGV.length != 1
    puts "Usage: ruby #{__FILE__} <input_wav_file>"
    exit 1
  end

  input_wav = ARGV[0]
  puts "Attempting to transcribe file: #{input_wav}"
  result_path = transcribe_audio(input_wav)

  if result_path && File.exist?(result_path)
    puts "\nSUCCESS: File transcribed successfully to #{result_path}"
    puts "File size: #{File.size(result_path)} bytes"
    # Display first few lines of transcript
    puts "\nTranscript Preview:"
    puts `head -n 5 #{result_path}`
    exit 0
  else
    puts "\nFAILURE: File transcription failed."
    exit 1
  end
end 