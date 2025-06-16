#!/usr/bin/env ruby

require 'open-uri'
require 'nokogiri'
require 'json'
require 'fileutils'
require 'shellwords'
require 'logger'
require 'uri' # Added for URI parsing

# --- Configuration ---
TEMP_DIR = "temp_loom_files"
TRANSCRIPT_DIR = "loom_transcripts"
WHISPER_MODEL_PATH = "models/ggml-base.en-q5_0.bin" # Adjust if needed
WHISPER_BINARY_PATH = "./build/bin/main"          # Adjust if needed
USER_AGENT = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'

# --- Logging ---
LOGGER = Logger.new($stdout)
LOGGER.level = Logger::INFO # Change to Logger::DEBUG for more verbose output

# --- Helper Functions ---

def fetch_page_html(url_string)
  LOGGER.info("Fetching HTML from: #{url_string}")
  begin
    # Use open-uri with a user-agent
    response_body = URI.open(url_string, "User-Agent" => USER_AGENT, :read_timeout => 60).read
    LOGGER.info("HTML fetched successfully (Size: #{response_body.length} bytes)")
    return response_body
  rescue OpenURI::HTTPError => e
    LOGGER.error("HTTP error fetching HTML: #{e.message} for #{url_string}")
  rescue SocketError, Errno::ECONNREFUSED => e
    LOGGER.error("Network error fetching HTML (SocketError/ConnectionRefused): #{e.message}")
  rescue Net::OpenTimeout, Net::ReadTimeout, Timeout::Error => e
    LOGGER.error("Network error fetching HTML (Timeout): #{e.message}")
  rescue URI::InvalidURIError => e
    LOGGER.error("Invalid URL for fetching HTML: #{e.message}")
  rescue => e
    LOGGER.error("Unexpected error fetching HTML: #{e.message}")
  end
  nil
end

def extract_mp4_url_from_html(html_content, loom_url)
  LOGGER.info("Attempting to extract MP4 URL from HTML for: #{loom_url}")
  return nil if html_content.nil? || html_content.empty?

  doc = Nokogiri::HTML(html_content)
  potential_urls = []

  # Strategy 1: Look for <script type="application/ld+json">
  doc.css('script[type="application/ld+json"]').each do |script_tag|
    begin
      json_data = JSON.parse(script_tag.content)
      if json_data['@type'] == 'VideoObject'
        content_url = json_data['contentUrl']
        embed_url = json_data['embedUrl']
        potential_urls << content_url if content_url.is_a?(String) && content_url.include?('.mp4')
        potential_urls << embed_url if embed_url.is_a?(String) && embed_url.include?('.mp4')
      end
    rescue JSON::ParserError => e
      LOGGER.debug("JSON parsing error for ld+json script: #{e.message}")
    end
  end

  # Strategy 2: Search all script tags for JSON-like structures containing video URLs
  doc.css('script').each do |script_tag|
    content = script_tag.content
    next if content.nil? || content.empty?

    # Attempt to find JSON-like structures within the script content
    # This regex looks for something that starts with { and ends with }, and is likely a JSON object.
    # It's non-greedy to capture the smallest possible valid JSON-like string.
    content.scan(/(\{.*?\})/m) do |match|
      begin
        # The match is an array, take the first element which is the captured string
        json_like_string = match[0]
        # It might not be perfect JSON, so try to extract URLs with regex from this smaller chunk
        # Common keys for video URLs: downloadUrl, publicUrl, transcodedUrl, file, src, url
        json_like_string.scan(/"(?:downloadUrl|publicUrl|transcodedUrl|file|src|url|signedUrl|previewUrl)"\s*:\s*"([^"]+\.mp4[^"]*)"/i).each do |url_match|
          raw_url = url_match[0].gsub(/\\u002F/, '/') # Replace escaped slashes
          potential_urls << raw_url
        end
      rescue => e # Catch any error during this more speculative parsing
        LOGGER.debug("Error processing script content chunk: #{e.message}")
      end
    end
    
    # Simpler regex for direct MP4 links within script tags as a fallback
    content.scan(/"([^"]+\.mp4[^"]*)"/i).each do |url_match|
        raw_url = url_match[0].gsub(/\\u002F/, '/')
        potential_urls << raw_url
    end
  end

  # Strategy 3: Look for <video> tag with src attribute
  doc.css('video[src*=".mp4"]').each do |video_tag|
    potential_urls << video_tag['src'] if video_tag['src']
  end
  
  # Strategy 4: Look for <source> tag within <video>
  doc.css('video source[src*=".mp4"]').each do |source_tag|
    potential_urls << source_tag['src'] if source_tag['src']
  end

  # Filter and prioritize URLs
  # Prefer URLs that look like direct MP4s and are fully qualified
  potential_urls.compact!
  potential_urls.uniq!
  
  LOGGER.debug("Found potential MP4 URLs: #{potential_urls}")

  # Select the best candidate - often, a direct .mp4 link is best.
  # Some signed URLs might be very long or temporary.
  # Prefer shorter, clearly identified .mp4 URLs if available.
  best_url = potential_urls.find { |u| u.match?(/\.mp4(\?|$)/i) && !u.include?('gif') && u.start_with?('http')}
  
  if best_url
    LOGGER.info("Selected MP4 URL: #{best_url}")
    return best_url
  elsif !potential_urls.empty?
    # Fallback to the first plausible http URL if no clear .mp4 is found
    first_http_url = potential_urls.find { |u| u.start_with?('http') && (u.include?('.mp4') || u.include?('loom')) }
    if first_http_url
      LOGGER.info("Fallback MP4 URL (less certain): #{first_http_url}")
      return first_http_url
    end
  end

  LOGGER.warn("Could not confidently find a direct MP4 URL in the HTML content after all strategies.")
  nil
end

def download_file(url, output_path)
  LOGGER.info("Downloading file from: #{url} to #{output_path}")
  begin
    File.open(output_path, 'wb') do |file|
      URI.open(url, "User-Agent" => USER_AGENT, :read_timeout => 300) do |remote_file|
        file.write(remote_file.read)
      end
    end
    LOGGER.info("File downloaded successfully: #{output_path} (Size: #{File.size(output_path)} bytes)")
    return output_path
  rescue => e
    LOGGER.error("Error downloading file #{url}: #{e.message}")
    File.delete(output_path) if File.exist?(output_path)
    return nil
  end
end

def extract_audio_from_video(video_filepath, audio_output_filepath)
  LOGGER.info("Extracting audio from #{video_filepath} to #{audio_output_filepath}")
  cmd = "ffmpeg -y -i #{Shellwords.escape(video_filepath)} -vn -ar 16000 -ac 1 -c:a pcm_s16le #{Shellwords.escape(audio_output_filepath)}"
  LOGGER.debug("Running ffmpeg command: #{cmd}")
  output = `#{cmd} 2>&1`

  if $?.success? && File.exist?(audio_output_filepath) && File.size(audio_output_filepath) > 0
    LOGGER.info("Audio extracted successfully: #{audio_output_filepath}")
    return audio_output_filepath
  else
    LOGGER.error("Failed to extract audio using ffmpeg. Exit status: #{$?.exitstatus}")
    LOGGER.error("ffmpeg output: #{output}")
    return nil
  end
end

def transcribe_audio_loom(audio_wav_file, output_transcript_path_base)
  LOGGER.info("Transcribing audio file: #{audio_wav_file}")
  
  unless File.exist?(WHISPER_MODEL_PATH)
    LOGGER.error("Whisper model not found at #{WHISPER_MODEL_PATH}")
    return nil
  end
  unless File.exist?(WHISPER_BINARY_PATH)
    LOGGER.error("Whisper binary not found at #{WHISPER_BINARY_PATH}")
    return nil
  end

  cmd = "#{WHISPER_BINARY_PATH} -m #{WHISPER_MODEL_PATH} -f #{Shellwords.escape(audio_wav_file)} -otxt -of #{Shellwords.escape(output_transcript_path_base)}"
  LOGGER.debug("Running transcription command: #{cmd}")
  
  system_output_success = system(cmd)
  actual_transcript_file = "#{output_transcript_path_base}.txt"

  if system_output_success && File.exist?(actual_transcript_file) && File.size(actual_transcript_file) > 0
    LOGGER.info("Transcription successful. Output: #{actual_transcript_file}")
    return actual_transcript_file
  else
    LOGGER.error("Transcription failed or output file is empty. Command success: #{system_output_success}")
    LOGGER.error("Expected transcript file: #{actual_transcript_file}")
    return nil
  end
end

def sanitize_filename_component(name)
  return "untitled_loom" if name.nil? || name.empty?
  sanitized = name.gsub(/[^a-zA-Z0-9_-]+/, '_')
  sanitized.gsub(/_+/, '_')
  sanitized.gsub(/^_|_$/, '')
  sanitized = "loom_video" if sanitized.empty?
  sanitized.downcase
end

# --- Main Logic ---
def main
  if ARGV.length != 1
    puts "Usage: ruby #{__FILE__} <loom_share_url>"
    exit 1
  end

  loom_url = ARGV[0]
  LOGGER.info("Processing Loom URL: #{loom_url}")

  FileUtils.mkdir_p(TEMP_DIR)
  FileUtils.mkdir_p(TRANSCRIPT_DIR)

  temp_video_file = nil
  temp_audio_file = nil
  final_transcript_file = nil

  begin
    html_content = fetch_page_html(loom_url)
    unless html_content
      LOGGER.fatal("Failed to fetch Loom page HTML. Exiting.")
      exit 1
    end

    # --- NEW: Save HTML content for inspection ---
    html_output_path = "loom_page_content.html"
    begin
      File.write(html_output_path, html_content)
      LOGGER.info("Saved Loom page HTML to: #{html_output_path}")
    rescue => e
      LOGGER.warn("Failed to save Loom page HTML: #{e.message}")
    end
    # --- END NEW --- 

    mp4_url = extract_mp4_url_from_html(html_content, loom_url)
    unless mp4_url
      LOGGER.fatal("Failed to extract MP4 URL from Loom page (HTML saved to loom_page_content.html). Exiting.")
      exit 1
    end
    LOGGER.info("Extracted MP4 URL: #{mp4_url}")

    loom_id = URI.parse(loom_url).path.split('/').last
    file_basename = sanitize_filename_component(loom_id || "loom_video_#{Time.now.to_i}")

    temp_video_file = File.join(TEMP_DIR, "#{file_basename}.mp4")
    temp_audio_file = File.join(TEMP_DIR, "#{file_basename}.wav")
    transcript_basepath = File.join(TRANSCRIPT_DIR, file_basename)

    downloaded_video_path = download_file(mp4_url, temp_video_file)
    unless downloaded_video_path
      LOGGER.fatal("Failed to download MP4 video. Exiting.")
      exit 1
    end

    extracted_audio_path = extract_audio_from_video(downloaded_video_path, temp_audio_file)
    unless extracted_audio_path
      LOGGER.fatal("Failed to extract audio from video. Exiting.")
      exit 1
    end

    final_transcript_file = transcribe_audio_loom(extracted_audio_path, transcript_basepath)
    if final_transcript_file
      LOGGER.info("SUCCESS: Loom video transcribed. Transcript saved to: #{final_transcript_file}")
    else
      LOGGER.error("Failed to transcribe Loom video audio.")
    end

  rescue => e
    LOGGER.fatal("An unexpected error occurred: #{e.message}")
    LOGGER.fatal(e.backtrace.join("\n"))
  ensure
    # Optional: Uncomment to clean up temporary files
    # if temp_video_file && File.exist?(temp_video_file)
    #   LOGGER.info("Deleting temporary video file: #{temp_video_file}")
    #   File.delete(temp_video_file)
    # end
    # if temp_audio_file && File.exist?(temp_audio_file)
    #   LOGGER.info("Deleting temporary audio file: #{temp_audio_file}")
    #   File.delete(temp_audio_file)
    # end
    LOGGER.info("Script finished.")
  end
end

if __FILE__ == $0
  main
end 