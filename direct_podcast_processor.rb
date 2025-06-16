require 'net/http'
require 'json'
require 'uri'
require 'fileutils'
require 'open-uri'
require 'time'

# Downloads a podcast from a direct URL
def download_podcast(podcast_url)
  puts "[DEBUG] Starting download_podcast with URL: #{podcast_url}"
  
  if podcast_url.nil? || podcast_url.empty?
    puts "Error: Invalid podcast URL"
    return nil
  end
  
  # Extract filename from URL
  uri = URI.parse(podcast_url)
  filename = File.basename(uri.path)
  output_path = filename
  
  puts "Downloading podcast from #{podcast_url}..."
  begin
    File.open(output_path, 'wb') do |file|
      file.write(URI.open(podcast_url).read)
    end
    puts "[DEBUG] Successfully downloaded podcast to #{output_path}, size: #{File.size(output_path)} bytes"
    return output_path
  rescue => e
    puts "Error downloading podcast file: #{e.message}"
    File.delete(output_path) if File.exist?(output_path)
    return nil
  end
end

def convert_to_wav(input_audio_file)
  puts "[DEBUG] Starting convert_to_wav with file: #{input_audio_file}"
  output_wav_file = "#{File.basename(input_audio_file, File.extname(input_audio_file))}.wav"

  # Check if input file exists
  unless File.exist?(input_audio_file)
    puts "Error: Input file #{input_audio_file} does not exist."
    return nil
  end
  
  # Delete existing output WAV file
  File.delete(output_wav_file) if File.exist?(output_wav_file)

  # Check file type before conversion (just for logging, not blocking)
  file_type = `file --brief --mime-type #{input_audio_file}`.strip
  puts "[DEBUG] File type detected: #{file_type}"
  
  # Continue even if file type doesn't start with 'audio/', since we know it's a podcast download

  puts "Converting to WAV format..."
  puts "[DEBUG] Output WAV file will be: #{output_wav_file}"
  
  # Add -y flag to force overwrite and capture output for debugging
  cmd = "ffmpeg -y -i #{input_audio_file} -ar 16000 -ac 1 -c:a pcm_s16le #{output_wav_file}"
  puts "[DEBUG] Running command: #{cmd}"
  output = `#{cmd} 2>&1`
  puts "[DEBUG] ffmpeg output:\n#{output}"
  
  if File.exist?(output_wav_file) && File.size(output_wav_file) > 0
    puts "[DEBUG] WAV file created successfully, size: #{File.size(output_wav_file)} bytes"
    return output_wav_file
  else
    puts "Error: WAV file creation failed or is empty!"
    return nil
  end
end

def transcribe_audio(audio_wav_file)
  puts "[DEBUG] Starting transcribe_audio with file: #{audio_wav_file}"

  unless File.exist?(audio_wav_file)
    puts "Error: Input WAV file #{audio_wav_file} does not exist."
    return nil
  end

  # Determine the output transcript filename base and expected final name
  transcript_file_base = File.basename(audio_wav_file, ".wav")
  transcript_file_expected = transcript_file_base + '.txt'
  puts "[DEBUG] Transcript base name for whisper: #{transcript_file_base}"
  puts "[DEBUG] Expected transcript file: #{transcript_file_expected}"
  
  # Check if transcript already exists
  if File.exist?(transcript_file_expected) && File.size(transcript_file_expected) > 0
    puts "[DEBUG] Transcript file already exists, reusing it: #{transcript_file_expected}"
    return File.read(transcript_file_expected)
  end
  
  # Delete existing transcript file before transcription to ensure overwrite
  if File.exist?(transcript_file_expected)
    puts "[DEBUG] Deleting existing transcript file: #{transcript_file_expected}"
    File.delete(transcript_file_expected)
  end

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
  cmd = "#{binary_path} -m #{model_path} -f #{audio_wav_file} -otxt -of #{transcript_file_base}"
  puts "[DEBUG] Running transcription command: #{cmd}"
  system_output = system(cmd)
  puts "[DEBUG] Transcription command returned: #{system_output}"

  # Check if the transcript file was created with a wait loop
  transcript_content = nil
  if system_output
    max_wait_seconds = 5 # Wait up to 5 seconds
    wait_interval = 0.5
    start_time = Time.now
    while Time.now - start_time < max_wait_seconds
      if File.exist?(transcript_file_expected) && File.size(transcript_file_expected) > 0
        transcript_size = File.size(transcript_file_expected)
        puts "[DEBUG] Transcript file found after waiting: #{transcript_file_expected}, size: #{transcript_size} bytes"
        transcript_content = File.read(transcript_file_expected)
        break
      end
      puts "[DEBUG] Waiting for transcript file '#{transcript_file_expected}' to appear (#{Time.now - start_time}s)..."
      sleep(wait_interval)
    end
  end

  if transcript_content
    return transcript_content
  elsif system_output
    puts "Error: Transcript file '#{transcript_file_expected}' was not found or empty after waiting #{max_wait_seconds} seconds, even though command succeeded."
    return nil
  else
    puts "Error: Transcription command failed (returned #{system_output})."
    return nil
  end
end

def generate_summary(transcript_content)
  puts "[DEBUG] Starting generate_summary with transcript size: #{transcript_content.size} bytes"
  
  api_key = ENV["ANTHROPIC_API_KEY"]
  if api_key.nil? || api_key.empty?
    puts "[DEBUG] ANTHROPIC_API_KEY environment variable is not set or empty!"
    puts "Warning: ANTHROPIC_API_KEY environment variable is not set. Skipping summary generation."
    return "No summary available - ANTHROPIC_API_KEY not set.\n\nTranscript first 1000 chars:\n\n#{transcript_content[0..1000]}...\n\n(Full transcript content was not processed due to missing API key)"
  end
  
  uri = URI.parse("https://api.anthropic.com/v1/messages")
  request = Net::HTTP::Post.new(uri)
  request.content_type = "application/json"
  request["x-api-key"] = api_key
  request["anthropic-version"] = "2023-06-01"

  request.body = JSON.dump({
    "model" => "claude-3-opus-20240229",
    "max_tokens" => 4096,
    "messages" => [
      {
        "role" => "user",
        "content" => <<~PROMPT
          Please analyze the following podcast transcript and provide a structured summary based on these points:
          
          1.  **Major Themes & Technology Trends:** Identify the key overarching themes or technology trends discussed. Support each theme/trend with a representative quote from the transcript.
          2.  **Areas of Discussion/Debate:** Summarize the main topics where speakers discussed different viewpoints or debated specific points. Support each area with a representative quote illustrating the discussion or debate.
          3.  **Potential Investment Ideas:** Identify any potential investment ideas suitable for an early-stage venture capital firm that emerge from the conversation. Briefly explain the idea and why it might be relevant.
          4.  **Surprising/Counterintuitive Observations:** Summarize any observations made by the speakers that were surprising, counterintuitive, or rare insights.
          5.  **Companies Named & URLs:** List all companies explicitly named in the transcript, and provide their corresponding URLs if possible.
          
          Format the response clearly using Markdown, with distinct sections for each point.
          
          Here is the transcript:
          
          #{transcript_content}
          PROMPT
      }
    ]
  })

  puts "[DEBUG] Sending request to Anthropic API..."
  response = nil
  begin
    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
      http.open_timeout = 60 # seconds
      http.read_timeout = 300 # seconds
      http.request(request)
    end
    puts "[DEBUG] Received response from Anthropic API, status: #{response.code}"
  rescue Net::OpenTimeout => e
    puts "[DEBUG] Error: API request timed out (open): #{e.message}"
    puts "Error communicating with Anthropic API: Connection timed out."
    return "Error generating summary: API connection failed (timeout). Transcript first 1000 chars:\n\n#{transcript_content[0..1000]}..."
  rescue Net::ReadTimeout => e
    puts "[DEBUG] Error: API request timed out (read): #{e.message}"
    puts "Error communicating with Anthropic API: Reading response timed out."
    return "Error generating summary: API read failed (timeout). Transcript first 1000 chars:\n\n#{transcript_content[0..1000]}..."
  rescue => e
    puts "[DEBUG] Error during API request: #{e.message}"
    puts "Error communicating with Anthropic API: #{e.message}"
    return "Error generating summary: API communication failed. Transcript first 1000 chars:\n\n#{transcript_content[0..1000]}..."
  end

  if response.code == "200"
    begin
      result = JSON.parse(response.body)
      summary = result["content"][0]["text"]
      puts "[DEBUG] Successfully parsed summary, size: #{summary.size} bytes"
      return summary
    rescue JSON::ParserError => e
      puts "[DEBUG] Error parsing JSON response: #{e.message}"
      puts "Error: Invalid response received from Anthropic API."
      puts "[DEBUG] Response Body: #{response.body[0..500]}..."
      return "Error generating summary: Invalid API response. Transcript first 1000 chars:\n\n#{transcript_content[0..1000]}..."
    rescue => e
      puts "[DEBUG] Error processing API response: #{e.message}"
      puts "Error processing response from Anthropic API."
      return "Error generating summary: Could not process API response. Transcript first 1000 chars:\n\n#{transcript_content[0..1000]}..."
    end
  else
    puts "[DEBUG] API error: #{response.code} - #{response.body}"
    puts "Error: Anthropic API returned status #{response.code}"
    return "Error generating summary: API returned error #{response.code}. Transcript first 1000 chars:\n\n#{transcript_content[0..1000]}..."
  end
end

def save_output_files(transcript, summary, base_filename)
  output_dir = "podcast_summaries"
  
  # Create output directory if it doesn't exist
  unless Dir.exist?(output_dir)
    puts "[DEBUG] Creating output directory: #{output_dir}"
    Dir.mkdir(output_dir)
  end
  
  # Save transcript
  transcript_filename = "#{base_filename}.txt"
  puts "[DEBUG] Saving transcript to: #{transcript_filename}"
  File.write(transcript_filename, transcript)
  
  # Save summary
  summary_filename = "#{base_filename}_summary.txt"
  puts "[DEBUG] Saving summary to: #{summary_filename}"
  File.write(summary_filename, summary)
  
  return [transcript_filename, summary_filename]
end

def main
  puts "[DEBUG] Starting main function"
  if ARGV.length != 1
    puts "Usage: ruby #{__FILE__} <podcast_direct_url>"
    exit 1
  end

  podcast_url = ARGV[0]
  puts "[DEBUG] Processing podcast URL: #{podcast_url}"
  
  begin
    # 1. Download podcast
    puts "\n--- Step 1: Downloading Podcast ---"
    podcast_file = download_podcast(podcast_url)
    unless podcast_file
      puts "Error: Failed to download podcast."
      exit 1
    end
    puts "[DEBUG] download_podcast returned: #{podcast_file}"
    
    # Generate base filename
    base_filename = File.basename(podcast_file, File.extname(podcast_file))
    
    # 2. Convert to WAV
    puts "\n--- Step 2: Converting to WAV ---"
    wav_file_path = convert_to_wav(podcast_file)
    unless wav_file_path
      puts "Error: Failed to convert audio to WAV."
      exit 1
    end
    puts "[DEBUG] convert_to_wav returned: #{wav_file_path}"

    # 3. Transcribe Audio
    puts "\n--- Step 3: Transcribing Audio ---"
    transcript = transcribe_audio(wav_file_path)
    unless transcript
      puts "Error: Failed to transcribe audio file."
      exit 1
    end
    puts "[DEBUG] Transcription successful."
    
    # 4. Generate Summary
    puts "\n--- Step 4: Generating Summary ---"
    summary_content = generate_summary(transcript)
    unless summary_content
      puts "Error: Failed to generate summary (API key issue or API error). Proceeding without summary."
      summary_content = "## Summary\n\nSummary generation failed.\n\n## Transcript\n\n#{transcript}" 
    end
    puts "[DEBUG] Summary generation complete (or fallback generated)."
    
    # 5. Save Output Files
    puts "\n--- Step 5: Writing Final Output ---"
    transcript_file, summary_file = save_output_files(transcript, summary_content, base_filename)
    puts "\nSUCCESS: Transcript saved to #{transcript_file}"
    puts "\nSUCCESS: Summary saved to #{summary_file}"
    
    # Report the exact *absolute* filename to stdout
    absolute_transcript_path = File.expand_path(transcript_file)
    absolute_summary_path = File.expand_path(summary_file)
    puts "TRANSCRIPT_FILE:#{absolute_transcript_path}"
    puts "SUMMARY_FILE:#{absolute_summary_path}"
    
  rescue => e
    puts "\n--- ERROR: Unhandled exception in main --- "
    puts "[DEBUG] Exception: #{e.message}"
    puts "[DEBUG] Backtrace:\n#{e.backtrace.join("\n")}"
    puts "Error: An unexpected error occurred during processing."
    exit 1
  end
end

if __FILE__ == $0
  main
end