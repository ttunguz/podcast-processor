#!/usr/bin/env ruby
require 'net/http'
require 'json'
require 'uri'
require 'fileutils'
require 'open-uri'
require 'set' # Added for Harmonic logic
require 'time' # Added for Harmonic logic
require 'anthropic' # Added for Claude API

# Directory to store permanent transcripts
TRANSCRIPT_DIR = "podcast_transcripts"

# Configure Anthropic Gem
Anthropic.configure do |config|
  config.access_token = ENV.fetch("ANTHROPIC_API_KEY") do
    raise "ANTHROPIC_API_KEY environment variable not set!"
  end
end

# --- New Helper Functions ---

# Fetches HTML content from a URL - SIMPLIFIED
def fetch_html(url_string)
  puts "[DEBUG] Fetching HTML (simplified) from: #{url_string}"
  begin
    uri = URI.parse(url_string)
    # Use simple open-uri, let it handle basic redirects (less control)
    response_body = URI.open(url_string, "User-Agent" => "Mozilla/5.0", :read_timeout => 60).read
    puts "[DEBUG] HTML fetched successfully (Size: #{response_body.length} bytes)"
    return response_body
  rescue OpenURI::HTTPError => e
     puts "[ERROR] HTTP error fetching HTML: #{e.message} for #{url_string}"
     return nil
  rescue SocketError => e
     puts "[ERROR] Network error fetching HTML (SocketError): #{e.message}"
     return nil
  rescue Errno::ECONNREFUSED => e
     puts "[ERROR] Network error fetching HTML (Connection Refused): #{e.message}"
     return nil
  rescue Net::OpenTimeout, Net::ReadTimeout, Timeout::Error => e # Added Timeout::Error
     puts "[ERROR] Network error fetching HTML (Timeout): #{e.message}"
     return nil
  rescue URI::InvalidURIError => e
    puts "[ERROR] Invalid URL for fetching HTML: #{e.message}"
    return nil
  rescue => e
    puts "[ERROR] Unexpected error fetching HTML: #{e.message}"
    return nil
  end
end

# Helper to format duration from seconds to Hh Mm or Mm Ss
def format_duration(seconds)
  return nil if seconds.nil? || seconds <= 0
  minutes = seconds / 60
  hours = minutes / 60
  if hours > 0
    remaining_minutes = minutes % 60
    "#{hours}h #{remaining_minutes}m"
  else
    remaining_seconds = seconds % 60
    "#{minutes}m #{remaining_seconds}s"
  end
end

# Helper to strip basic HTML tags
def strip_html(html_string)
  return nil if html_string.nil?
  # Remove tags, replace entities, normalize spaces
  html_string.gsub(/<[^>]*>/, '').gsub(/&nbsp;/, ' ').strip.gsub(/\s+/, ' ') 
end

# Extracts metadata from Apple Podcasts HTML - REMOVED COMPLEX JSON PARSING
# This function is now less reliable and primarily for fallback/debugging
def extract_podcast_metadata(html_content, page_url)
  metadata = {
    episode_title: nil,
    show_name: nil,
    duration: nil,
    published_date: nil, 
    source_url: page_url # Always keep the source URL
  }
  return metadata if html_content.nil? || html_content.empty?
  puts "[DEBUG] Attempting basic metadata extraction (title regex)..."
  
  begin
    # Basic title extraction using regex on the <title> tag
    title_match = html_content.match(/<title>(.*?)<\/title>/i)
    if title_match && title_match[1]
      full_title = title_match[1].strip
      # Often format is "Episode Title on Show Name - Apple Podcasts"
      parts = full_title.split(/\s+on\s+|\s+-\s+Apple Podcasts/i)
      if parts.length >= 2
         metadata[:episode_title] = parts[0].strip
         # Heuristic: Assume the part after 'on' is the show name
         show_name_candidate = parts.find { |p| p.match?(/podcast/i) == false && p != metadata[:episode_title] && !p.downcase.include?('apple') }
         metadata[:show_name] = show_name_candidate || parts[1].strip # Fallback to second part
      else
         metadata[:episode_title] = full_title.gsub(/\s+-\s+Apple Podcasts$/i, '').strip
      end
      # Clean up names
      metadata[:episode_title]&.gsub!(/&amp;/, '&')
      metadata[:show_name]&.gsub!(/&amp;/, '&')
    else 
       puts "[WARN] Could not find <title> tag for basic metadata."
    end
  rescue => e
     puts "[WARN] Error during basic metadata extraction: #{e.message}"
  end

  puts "[DEBUG] Basic metadata extracted: #{metadata.select { |k, v| !v.nil? }}"
  # Fallback filename generation will rely more heavily on URL slug now
  metadata[:episode_title] ||= "podcast_episode_#{Time.now.to_i}" 
  
  metadata
end

# Sanitizes a string to be suitable for a filename
def sanitize_filename(name)
  return "default_filename" if name.nil? || name.empty?
  sanitized = name.downcase
  sanitized.gsub!(/\s+/, '-') # Replace spaces with hyphens
  sanitized.gsub!(/[^\p{Alnum}-]/, '') # Remove non-alphanumeric chars except hyphen
  sanitized.gsub!(/-+/, '-') # Collapse multiple hyphens
  sanitized.gsub!(/^-+|-+$/, '') # Remove leading/trailing hyphens
  sanitized = "untitled" if sanitized.empty? # Handle cases where everything is stripped
  sanitized
end

# download_audio needs to be more robust if page_content is nil
def download_audio(page_url)
  puts "[DEBUG] Starting download_audio with URL: #{page_url}"
  temp_file = "temp_audio"
  puts "Fetching page content (for audio link) from #{page_url}..."
  page_content = fetch_html(page_url) # Use the simplified fetch_html
  
  unless page_content
      puts "[WARN] Could not fetch page content to find audio link for #{page_url}. Cannot download."
      return nil
  end
  
  puts "[DEBUG] Successfully fetched page content, size: #{page_content.size} bytes"

  # Try to find MP3/M4A/WAV/AAC link using regex
  audio_url_match = page_content.match(/(https?:\/\/[^"'\s]+\.(mp3|m4a|wav|aac))/)

  if audio_url_match
    audio_url = audio_url_match[0]
    file_ext = audio_url_match[2]
    puts "Found audio URL: #{audio_url}"
    puts "Downloading audio file..."
    downloaded_file_path = "#{temp_file}.#{file_ext}"
    begin
      # Delete existing temp file if it exists
      File.delete(downloaded_file_path) if File.exist?(downloaded_file_path)
      
      File.open(downloaded_file_path, 'wb') do |file|
        # Stream download for potentially large files
        URI.open(audio_url) do |remote_file|
            file.write(remote_file.read)
        end
      end
      puts "[DEBUG] Successfully downloaded audio to #{downloaded_file_path}, size: #{File.size(downloaded_file_path)} bytes"
      return downloaded_file_path
    rescue => e
      puts "Error downloading audio file: #{e.message}"
      File.delete(downloaded_file_path) if File.exist?(downloaded_file_path)
      return nil
    end
  else
    puts "Error: Could not find a direct audio link (.mp3, .m4a, .wav, .aac) on the page: #{page_url}"
    puts "[DEBUG] Page content excerpt (first 500 chars): #{page_content[0..500]}..."
    return nil
  end
end

def convert_to_wav(input_audio_file)
  puts "[DEBUG] Starting convert_to_wav with file: #{input_audio_file}"
  output_wav_file = "temp_audio.wav"

  # Check if input file exists
  unless File.exist?(input_audio_file)
    puts "Error: Input file #{input_audio_file} does not exist."
    return nil
  end
  
  # Delete existing output WAV file
  File.delete(output_wav_file) if File.exist?(output_wav_file)

  # Check file type before conversion
  file_type = `file --brief --mime-type #{input_audio_file}`.strip
  puts "[DEBUG] File type detected: #{file_type}"
  
  # Temporarily skip the file type check if extension is mp3, m4a, wav, aac
  audio_extension = File.extname(input_audio_file).downcase
  if !file_type.start_with?('audio/') && !['.mp3', '.m4a', '.wav', '.aac'].include?(audio_extension)
    puts "Error: Input file is not a recognized audio file (#{file_type}). Cannot convert."
    return nil
  end

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

def transcribe_audio(audio_wav_file, output_transcript_path)
  puts "[DEBUG] Starting transcribe_audio with file: #{audio_wav_file}"
  puts "[DEBUG] Desired output transcript path: #{output_transcript_path}"

  unless File.exist?(audio_wav_file)
    puts "Error: Input WAV file #{audio_wav_file} does not exist."
    return nil
  end

  # Use the provided path for output
  transcript_file_path = output_transcript_path
  # Extract the base name for the whisper command's -of flag
  transcript_file_base = File.join(File.dirname(transcript_file_path), File.basename(transcript_file_path, '.txt'))
  puts "[DEBUG] Transcript base name for whisper: #{transcript_file_base}"
  
  # Delete existing transcript file before transcription to ensure overwrite
  if File.exist?(transcript_file_path)
    puts "[DEBUG] Deleting existing transcript file: #{transcript_file_path}"
    File.delete(transcript_file_path)
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

  # Pass the base name (without extension) to -of, main binary should append .txt
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
      # Check the actual output path now
      if File.exist?(transcript_file_path) && File.size(transcript_file_path) > 0
        transcript_size = File.size(transcript_file_path)
        puts "[DEBUG] Transcript file found after waiting: #{transcript_file_path}, size: #{transcript_size} bytes"
        transcript_content = File.read(transcript_file_path)
        break
      end
      puts "[DEBUG] Waiting for transcript file '#{transcript_file_path}' to appear (#{Time.now - start_time}s)..."
      sleep(wait_interval)
    end
  end

  if transcript_content
    return transcript_content
  elsif system_output
    puts "Error: Transcript file '#{transcript_file_path}' was not found or empty after waiting #{max_wait_seconds} seconds, even though command succeeded."
    return nil
  else
    puts "Error: Transcription command failed (returned #{system_output})."
    return nil
  end
end

def generate_summary(transcript_content, metadata)
  puts "[DEBUG] Starting generate_summary with transcript size: #{transcript_content.size} bytes"
  client = Anthropic::Client.new

  # Extract relevant metadata for the prompt
  episode_title = metadata[:episode_title] || 'Unknown Episode'
  show_name = metadata[:show_name] || 'Unknown Show'
  published_date = metadata[:published_date] || 'Unknown Date'
  duration = metadata[:duration] || 'Unknown Duration'

  # Construct the enhanced prompt
  summary_prompt = <<~PROMPT
  **Podcast Information:**
  * Show Name: #{show_name}
  * Episode Title: #{episode_title}
  * Published Date: #{published_date}
  * Duration: #{duration}

  Please analyze the following podcast transcript and provide a structured summary based on these points:
            
  1.  **Major Themes & Technology Trends:** Identify the key overarching themes or technology trends discussed. Support each theme/trend with a representative quote from the transcript.
  2.  **Areas of Discussion/Debate:** Summarize the main topics where speakers discussed different viewpoints or debated specific points. Support each area with a representative quote illustrating the discussion or debate.
  3.  **Potential Investment Ideas:** Identify any potential investment ideas suitable for an early-stage venture capital firm that emerge from the conversation. Briefly explain the idea and why it might be relevant.
  4.  **Surprising/Counterintuitive Observations:** Summarize any observations made by the speakers that were surprising, counterintuitive, or rare insights.
  5.  **Companies Named & URLs:** List all companies explicitly named in the transcript, and provide their corresponding URLs if possible.

  Format the response clearly using Markdown, with distinct sections for each point.

  **BEGIN TRANSCRIPT**

  #{transcript_content}

  **END TRANSCRIPT**

  --- 

  **REQUIRED METADATA OUTPUT:**
  After your main summary, please include the following lines *exactly* at the end, with the identified names:
  HOST: [List Host Name(s) or 'Unknown']
  GUESTS: [List Guest Name(s) or 'None' if no guests]
  PROMPT

  puts "[DEBUG] Prompt length: #{summary_prompt.length} characters"
  # Truncate prompt if too long? Consider token limits.

  response = nil
  extracted_host = 'Unknown' # Default value
  extracted_guests = 'None'    # Default value

  begin
    response = client.messages(
      parameters: {
        model: "claude-3-5-sonnet-20240620", # Using the latest Sonnet model
        messages: [
          {
            role: "user",
            content: summary_prompt
          }
        ],
        max_tokens: 4096,
        temperature: 0.2 # Lower temperature for more factual summary
      }
    )

    if response && response["content"] && response["content"][0] && response["content"][0]["text"]
      full_response_text = response["content"][0]["text"]
      puts "[DEBUG] Received summary text length: #{full_response_text.length} bytes"
      
      # Parse HOST and GUESTS from the end of the response
      host_match = full_response_text.match(/^HOST:\s*(.*)$/im)
      guests_match = full_response_text.match(/^GUESTS:\s*(.*)$/im)

      extracted_host = host_match[1].strip if host_match && host_match[1]
      extracted_guests = guests_match[1].strip if guests_match && guests_match[1]

      puts "[DEBUG] Extracted Host: #{extracted_host}"
      puts "[DEBUG] Extracted Guests: #{extracted_guests}"

      # Return the main summary part (remove the metadata lines if needed, or keep full)
      # Option 1: Return only summary (remove metadata lines)
      # summary_only = full_response_text.gsub(/^HOST:.*$/im, '').gsub(/^GUESTS:.*$/im, '').strip
      # return summary_only, extracted_host, extracted_guests
      
      # Option 2: Return full text + extracted metadata separately
      return full_response_text, extracted_host, extracted_guests

    else
      puts "[ERROR] Invalid response structure from Claude API."
      puts "[DEBUG] Full Response: #{response.inspect}"
      return "Error: Could not generate summary due to invalid API response.", extracted_host, extracted_guests
    end

  rescue => e
    puts "[ERROR] API Error in summary generation: #{e.message}"
    puts "[ERROR] Error class: #{e.class}"
    # Check if the error object responds to http_status or similar methods if available
    # puts "[ERROR] Response status: #{e.respond_to?(:http_status) ? e.http_status : 'unknown'}"
    puts e.backtrace.join("\n")
    return "Error: Could not generate summary. #{e.message}", extracted_host, extracted_guests
  end
end

# Updated Harmonic API Key function (from user)
def self.get_harmonic_token
  token = ENV['HARMONIC_API_KEY'] || raise("Missing HARMONIC_API_KEY environment variable")
  return token
end

# Cleans a URL string to get a normalized domain
def clean_domain(url_string)
  return nil if url_string.nil? || url_string.empty?
  begin
    url_string = "http://#{url_string}" unless url_string.start_with?('http://', 'https://')
    uri = URI.parse(url_string)
    domain = uri.host
    domain&.sub(/^www\./, '')
  rescue URI::InvalidURIError
    puts "[WARN] Invalid URL skipped for domain extraction: #{url_string}"
    nil
  end
end

# Simple formatter (from sample, handles nil)
def format_element_simple(value)
  value.nil? ? '' : value.to_s
end

# Queries Harmonic for a single domain
def query_harmonic_for_domain(domain, api_key)
  return nil if domain.nil? || domain.empty?
  uri = URI("https://api.harmonic.ai/companies?website_domain=#{domain}")
  headers = { 'apikey' => api_key, 'accept' => 'application/json', 'content-type' => 'application/json' }
  body = {}.to_json
  puts "[DEBUG] Querying Harmonic for domain: #{domain}"
  begin
    response = Net::HTTP.post(uri, body, headers)
    unless response.is_a?(Net::HTTPSuccess)
      puts "[WARN] Harmonic API request failed for domain '#{domain}'. Status: #{response.code}, Body: #{response.body[0..200]}..."
      return nil
    end
    json_data = JSON.parse(response.body)
    puts "[DEBUG] Received data for domain: #{domain}"
    return json_data.is_a?(Array) ? json_data.first : json_data
  rescue JSON::ParserError => e
    puts "[WARN] Failed to parse JSON response for domain '#{domain}': #{e.message}"
    return nil
  rescue Net::OpenTimeout, Net::ReadTimeout => e
     puts "[WARN] Network timeout accessing Harmonic API for domain '#{domain}': #{e.message}"
     return nil
  rescue => e
    puts "[WARN] Error during Harmonic API call for domain '#{domain}': #{e.message}"
    return nil
  end
end

# Filters company data based on criteria
def filter_company_data(company_data)
  return false unless company_data
  # 1. Founded in last 4 years
  begin
    founded_date_str = company_data.dig("founding_date", "date")
    if founded_date_str
      founded_date = Time.parse(founded_date_str)
      four_years_ago = Time.now - (4 * 365 * 24 * 60 * 60)
      unless founded_date >= four_years_ago
        puts "[FILTER] Skipping #{company_data['name']} (Harmonic): Founded before 4 years ago (#{founded_date.year})"
        return false
      end
    else
      puts "[FILTER] Skipping #{company_data['name']} (Harmonic): Missing founding date."
       return false
    end
  rescue ArgumentError
    puts "[FILTER] Skipping #{company_data['name']} (Harmonic): Invalid founding date format."
    return false
  end
  # 2. Funding <= $20M
  total_funding = company_data.dig("funding", "funding_total")
  unless total_funding.nil? || total_funding <= 20_000_000
    puts "[FILTER] Skipping #{company_data['name']} (Harmonic): Funding > $20M ($#{total_funding || 0})"
    return false
  end
  # 3. Customer Type is B2B
  customer_type = company_data.dig("customer_type")
  unless customer_type == "B2B"
    puts "[FILTER] Skipping #{company_data['name']} (Harmonic): Customer type is not B2B (#{customer_type || 'N/A'})"
    return false
  end
  # 4. Location is US
  country = company_data.dig("location", "country")
  is_us = country && ["USA", "UNITED STATES"].include?(country.upcase)
  unless is_us
    puts "[FILTER] Skipping #{company_data['name']} (Harmonic): Location not in US (#{country || 'N/A'})"
    return false
  end
  puts "[FILTER] Keeping #{company_data['name']} (Harmonic): Meets all criteria."
  return true
end

def process_with_attio(entities)
  puts "[DEBUG] Starting process_with_attio"
  # This is a placeholder for Attio processing
  # You can implement your own Attio integration here
  ""
end

def extract_entities(transcript)
  puts "[DEBUG] Starting extract_entities"
  # This is a placeholder for entity extraction
  # You can implement your own entity extraction logic here
  []
end

def main
  puts "[DEBUG] Starting main function"
  if ARGV.length != 1
    puts "Usage: ruby #{__FILE__} <podcast_url>"
    exit 1
  end

  podcast_url = ARGV[0]
  puts "[DEBUG] Processing podcast URL: #{podcast_url}"
  output_dir = "podcast_summaries"
  temp_wav_file = "temp_audio.wav"
  temp_transcript_file = "temp_audio_transcript.txt"
  temp_downloaded_file = nil
  output_filename = nil # Determined after fetching metadata
  metadata = {} # Store extracted metadata

  begin
    # Create output directory if it doesn't exist
    unless Dir.exist?(output_dir)
      puts "[DEBUG] Creating output directory: #{output_dir}"
      Dir.mkdir(output_dir)
    end
    # Create transcript directory if it doesn't exist
    unless Dir.exist?(TRANSCRIPT_DIR)
      puts "[DEBUG] Creating transcript directory: #{TRANSCRIPT_DIR}"
      FileUtils.mkdir_p(TRANSCRIPT_DIR)
    end

    # --- Step 0: Fetch HTML and Extract Metadata ---
    puts "\n--- Step 0: Fetching Page Metadata ---"
    html_content = fetch_html(podcast_url)
    if html_content
      metadata = extract_podcast_metadata(html_content, podcast_url)
    else
      puts "[WARN] Could not fetch or parse HTML. Using URL slug for filename and skipping header."
      # Fallback: Generate filename from URL slug
      uri = URI.parse(podcast_url)
      slug = File.basename(uri.path).split('?').first
      safe_slug = sanitize_filename(slug) # Use sanitize for consistency
      output_filename = File.join(output_dir, safe_slug + '.txt')
    end
    
    # Generate filename from extracted title if available
    if output_filename.nil? && metadata[:episode_title]
      safe_slug = sanitize_filename(metadata[:episode_title])
      output_filename = File.join(output_dir, safe_slug + '.txt')
    elsif output_filename.nil? # Fallback if title extraction also failed
       safe_slug = "podcast_#{Time.now.to_i}"
       output_filename = File.join(output_dir, safe_slug + '.txt')
    end
    puts "[DEBUG] Final output file will be: #{output_filename}"

    # Determine permanent transcript filename based on metadata or fallback
    transcript_slug = metadata[:episode_title] ? sanitize_filename(metadata[:episode_title]) : "transcript_#{Time.now.to_i}"
    permanent_transcript_path = File.join(TRANSCRIPT_DIR, transcript_slug + '.txt')
    puts "[DEBUG] Permanent transcript file path: #{permanent_transcript_path}"

    # 1. Download Audio
    puts "\n--- Step 1: Downloading Audio ---"
    temp_downloaded_file = download_audio(podcast_url)
    unless temp_downloaded_file
      puts "Error: Failed to download audio."
      exit 1
    end
    puts "[DEBUG] download_audio returned: #{temp_downloaded_file}"
    
    # 2. Convert to WAV
    puts "\n--- Step 2: Converting to WAV ---"
    wav_file_path = convert_to_wav(temp_downloaded_file)
    unless wav_file_path
      puts "Error: Failed to convert audio to WAV."
      exit 1
    end
    puts "[DEBUG] convert_to_wav returned: #{wav_file_path}"

    # 3. Transcribe Audio
    puts "\n--- Step 3: Transcribing Audio ---"
    # Pass the desired permanent path to transcribe_audio
    transcript_content = transcribe_audio(wav_file_path, permanent_transcript_path)
    unless transcript_content # Check if content was returned
      puts "Error: Failed to transcribe audio file."
      exit 1
    end
    # Original transcript now exists at permanent_transcript_path
    puts "[DEBUG] Initial transcription successful. Content stored in #{permanent_transcript_path}"

    # 4. Generate Summary
    puts "\n--- Step 4: Generating Summary ---"
    # Use the transcript content read from the permanent file (or kept in memory)
    summary_content, extracted_host, extracted_guests = generate_summary(transcript_content, metadata)
    unless summary_content
       puts "Error: Failed to generate summary (API key issue or API error). Proceeding without summary."
       summary_content = "## Summary\n\nSummary generation failed.\n\n## Transcript\n\n#{transcript_content}"
       extracted_host ||= 'Error' # Use defaults if summary failed but transcription worked
       extracted_guests ||= 'Error'
    end
    puts "[DEBUG] Summary generation complete (or fallback generated)."

    # --- NEW STEP: Prepend Metadata to Transcript File ---
    puts "\n--- Step 4.1: Adding Metadata to Transcript File ---"
    begin
      transcript_header = <<~HEADER
      --- METADATA START ---
      Show: #{metadata[:show_name] || 'N/A'}
      Episode: #{metadata[:episode_title] || 'N/A'}
      Host: #{extracted_host || 'N/A'}
      Guests: #{extracted_guests || 'N/A'}
      Source URL: #{metadata[:source_url] || 'N/A'}
      --- METADATA END ---

      HEADER

      # Combine header and original transcript content
      final_transcript_content = transcript_header + transcript_content

      # Overwrite the permanent transcript file
      File.write(permanent_transcript_path, final_transcript_content)
      puts "[DEBUG] Successfully prepended metadata and overwrote transcript file: #{permanent_transcript_path}"

    rescue => e
      puts "[WARN] Failed to prepend metadata to transcript file #{permanent_transcript_path}: #{e.message}. Transcript file may be missing metadata."
      # Continue execution even if this fails, the original transcript should still exist
    end
    # --- END NEW STEP ---
    
    # Report *absolute* transcript file path to orchestrator (points to the file with metadata now)
    puts "TRANSCRIPT_FILE: #{File.expand_path(permanent_transcript_path)}"

    # 4.5 Harmonic Filtering (Existing Step)
    puts "\n--- Step 4.5: Filtering Companies with Harmonic ---"
    potential_investments_section = ""
    begin
      harmonic_api_key = get_harmonic_token
      url_regex = /(https?:\/\/[^\s<>"'\\]+)/i
      found_urls = summary_content.scan(url_regex).flatten.map(&:strip).to_set
      puts "[DEBUG] Found #{found_urls.size} unique URLs in summary for Harmonic."
      
      domains_to_query = found_urls.map { |url| clean_domain(url) }.compact.to_set
      puts "[DEBUG] Extracted #{domains_to_query.size} unique domains for Harmonic."

      if domains_to_query.any?
        harmonic_results = domains_to_query.map do |domain|
          query_harmonic_for_domain(domain, harmonic_api_key)
        end.compact
        
        puts "[DEBUG] Received #{harmonic_results.size} results from Harmonic."
        potential_investments = harmonic_results.select { |company_data| filter_company_data(company_data) }
        puts "[DEBUG] Found #{potential_investments.size} potential investments after filtering."

        if potential_investments.any?
          potential_investments_section = "\n\n## Potential Early-Stage VC Investments (via Harmonic Filter)\n\n"
          potential_investments.each do |company|
            potential_investments_section << "- **#{company['name']}**\n"
            potential_investments_section << "  - Domain: #{company.dig('website', 'domain')}\n"
            potential_investments_section << "  - Founded: #{company.dig('founding_date', 'date')}\n"
            potential_investments_section << "  - Funding: $#{company.dig('funding', 'funding_total') || 0}\n"
            potential_investments_section << "  - Location: #{format_element_simple(company.dig('location', 'city'))}, #{format_element_simple(company.dig('location', 'state'))}, #{company.dig('location', 'country')}\n"
            potential_investments_section << "  - Description: #{company['description']}\n"
          end
        else
           potential_investments_section = "\n\n## Potential Early-Stage VC Investments (via Harmonic Filter)\n\nNo companies found matching the criteria (Founded < 4 yrs, Funding <= $20M, B2B, US)."
        end
      else
         potential_investments_section = "\n\n## Potential Early-Stage VC Investments (via Harmonic Filter)\n\nNo valid domains found in the summary to query Harmonic."
      end
    rescue => e # Catch error getting API key or during Harmonic processing
      puts "[WARN] Harmonic processing failed: #{e.message}"
      potential_investments_section = "\n\n## Potential Early-Stage VC Investments (via Harmonic Filter)\n\nProcessing failed due to error: #{e.message}"
    end

    # 5. Write Final Output (Prepend Header)
    puts "\n--- Step 5: Writing Final Output ---"
    
    # Construct Header
    header = "--- Podcast Metadata ---\n"
    header << "Show: #{metadata[:show_name] || 'N/A'}\n"
    header << "Episode: #{metadata[:episode_title] || 'N/A'}"
    header << " (##{metadata[:episode_number]})" if metadata[:episode_number]
    header << "\n"
    header << "Channel: #{metadata[:channel] || 'N/A'}\n" if metadata[:channel]
    header << "Guest: #{metadata[:guest] || 'N/A'}\n" if metadata[:guest] # Only add if guest found
    header << "Published: #{metadata[:published_date] || 'N/A'}\n"
    header << "Duration: #{metadata[:duration] || 'N/A'}\n"
    header << "Source URL: #{metadata[:source_url] || 'N/A'}\n"
    header << "------------------------\n\n"

    # Combine Header, Summary, and Harmonic section 
    final_content = (metadata[:show_name] ? header : "") + summary_content + potential_investments_section
    
    begin
      # Determine output filename using metadata if available, fallback otherwise
      if metadata[:episode_title]
        safe_slug = sanitize_filename(metadata[:episode_title])
        output_filename = File.join("podcast_summaries", safe_slug + '.txt') # Put in summaries dir
      else
        # Fallback if title extraction failed earlier
        safe_slug = "podcast_#{Time.now.to_i}"
        output_filename = File.join("podcast_summaries", safe_slug + '.txt')
      end
      FileUtils.mkdir_p(File.dirname(output_filename))
      
      File.write(output_filename, final_content)
      puts "\nSUCCESS: Summary (and potential investments) generated and saved to #{output_filename}"
      
      # Report markers to stdout for the orchestrator
      absolute_output_path = File.expand_path(output_filename)
      puts "SHOW_NAME: #{metadata[:show_name] || 'Unknown'}" # NEW MARKER
      puts "HOST: #{extracted_host}"
      puts "GUESTS: #{extracted_guests}"
      puts "SUMMARY_FILE: #{absolute_output_path}"
    rescue => e
       puts "Error writing final output file: #{e.message}"
       # Make sure to exit non-zero if output fails
       exit 1
    end

  rescue => e
    puts "\n--- ERROR: Unhandled exception in main --- "
    puts "[DEBUG] Exception: #{e.message}"
    puts "[DEBUG] Backtrace:\n#{e.backtrace.join("\n")}"
    puts "Error: An unexpected error occurred during processing."
     # Attempt to save partial transcript if available, using determined output filename
     if File.exist?(temp_transcript_file)
        begin
          final_error_output = "Processing failed due to error: #{e.message}\n\nPartial transcript follows:\n\n" + File.read(temp_transcript_file)
          # Ensure output_filename has a value even if error happened very early
          output_filename ||= File.join(output_dir, "error_output_#{Time.now.to_i}.txt") 
          File.write(output_filename, final_error_output)
          puts "Saved partial transcript due to error to #{output_filename}"
        rescue => write_err
           puts "Could not save partial transcript after error: #{write_err.message}"
        end
     end
    exit 1
  ensure
    # 6. Clean up temporary files
    puts "\n--- Step 6: Cleaning Up Temporary Files ---"
    if temp_downloaded_file && File.exist?(temp_downloaded_file)
      puts "[DEBUG] Deleting downloaded file: #{temp_downloaded_file}"
      File.delete(temp_downloaded_file)
    end
    if File.exist?(temp_wav_file)
      puts "[DEBUG] Deleting WAV file: #{temp_wav_file}"
      File.delete(temp_wav_file)
    end
    # Explicitly delete the temp transcript file now as it's no longer needed after main processing
    # Removing deletion of temp_transcript_file as we now use permanent files
    # if File.exist?(temp_transcript_file)
    #    puts "[DEBUG] Deleting transcript file: #{temp_transcript_file}"
    #    File.delete(temp_transcript_file)
    # end
    puts "[DEBUG] Main function finished."
  end
end

if __FILE__ == $0
  main
end


