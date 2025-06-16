require 'fileutils'

def convert_to_wav(mp3_file)
  puts "[DEBUG] Starting convert_to_wav with file: #{mp3_file}"
  
  # Check if input file exists
  unless File.exist?(mp3_file)
    puts "Error: Input file #{mp3_file} does not exist."
    return nil
  end
  
  # Check file type before conversion
  file_type = `file --brief --mime-type #{mp3_file}`.strip
  puts "[DEBUG] File type detected: #{file_type}"
  
  unless file_type.start_with?('audio/')
    puts "Error: Input file is not an audio file (#{file_type}). Cannot convert."
    return nil
  end

  puts "Converting to WAV format..."
  wav_file = mp3_file.gsub(/\.\w+$/, '.wav')
  puts "[DEBUG] Output WAV file will be: #{wav_file}"
  
  # Add -y flag to force overwrite and capture output for debugging
  cmd = "ffmpeg -y -i #{mp3_file} -ar 16000 -ac 1 -c:a pcm_s16le #{wav_file}"
  puts "[DEBUG] Running command: #{cmd}"
  output = `#{cmd} 2>&1`
  puts "[DEBUG] ffmpeg output: #{output}"
  
  if File.exist?(wav_file)
    puts "[DEBUG] WAV file created successfully, size: #{File.size(wav_file)} bytes"
    return wav_file
  else
    puts "Error: WAV file creation failed!"
    return nil
  end
end

if __FILE__ == $0
  if ARGV.length != 1
    puts "Usage: ruby #{__FILE__} <input_audio_file>"
    exit 1
  end

  input_file = ARGV[0]
  puts "Attempting to convert file: #{input_file}"
  output_wav = convert_to_wav(input_file)

  if output_wav && File.exist?(output_wav)
    puts "\nSUCCESS: File converted successfully to #{output_wav}"
    puts "File size: #{File.size(output_wav)} bytes"
    exit 0
  else
    puts "\nFAILURE: File conversion failed."
    exit 1
  end
end 