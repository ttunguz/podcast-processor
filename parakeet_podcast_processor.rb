#!/usr/bin/env ruby

require 'uri'
require 'fileutils'
require 'open-uri'
require 'set'
require 'time'
require 'net/http' # For Gemini API calls
require 'json'      # For JSON parsing
require 'open3'     # For Parakeet/ffmpeg
require 'tempfile'  # For Parakeet/ffmpeg
require 'benchmark' # For Parakeet/ffmpeg
require 'shellwords'
require 'nokogiri' # Added Nokogiri
require 'anthropic' # For Claude API (summaries) - UNCOMMENTED

# --- Configuration ---
TRANSCRIPT_DIR = "podcast_transcripts"

# Gemini API Configuration - COMMENTED OUT
# GEMINI_API_KEY = ENV.fetch("GEMINI_API_KEY") do
#   raise "GEMINI_API_KEY environment variable not set!"
# end

# Parakeet and Ollama Configuration (from your example)
PARAKEET_MODEL = 'mlx-community/parakeet-tdt-0.6b-v2'
OLLAMA_MODEL = 'gemma3'
FAST_OLLAMA_MODEL = 'gemma3'
SKIP_REFINEMENT_THRESHOLD = 20
ENABLE_OLLAMA_REFINEMENT = true # Set to true to enable Claude-based transcript refinement

# --- Logging (Reusing from claude_podcast_processor, adjust if needed) ---
# For simplicity, using puts with [DEBUG], [INFO], [WARN], [ERROR] prefixes
# You can replace this with a proper Logger instance if preferred.

# Check for Parakeet CLI tool (from your example)
unless system('command -v parakeet-mlx >/dev/null 2>&1')
  puts "[ERROR] parakeet-mlx command not found. Please install it."
  exit 1
end
unless system('command -v ffmpeg >/dev/null 2>&1')
  puts "[ERROR] ffmpeg command not found. Please install ffmpeg."
  exit 1
end


# --- Helper Functions (from claude_podcast_processor.rb, slightly adapted) ---

def fetch_html(url_string)
  puts "[DEBUG] Fetching HTML (simplified) from: #{url_string}"
  begin
    uri = URI.parse(url_string)
    response_body = URI.open(url_string, "User-Agent" => "Mozilla/5.0", :read_timeout => 60).read
    puts "[DEBUG] HTML fetched successfully (Size: #{response_body.length} bytes)"
    return response_body
  rescue OpenURI::HTTPError => e
    puts "[ERROR] HTTP error fetching HTML: #{e.message} for #{url_string}"
  rescue SocketError, Errno::ECONNREFUSED => e
    puts "[ERROR] Network error fetching HTML: #{e.message}"
  rescue Net::OpenTimeout, Net::ReadTimeout, Timeout::Error => e
    puts "[ERROR] Network error fetching HTML (Timeout): #{e.message}"
  rescue URI::InvalidURIError => e
    puts "[ERROR] Invalid URL for fetching HTML: #{e.message}"
  rescue => e
    puts "[ERROR] Unexpected error fetching HTML: #{e.message}"
  end
  nil
end

def extract_podcast_metadata(html_content, page_url)
  metadata = {
    episode_title: nil,
    show_name: nil,
    duration: nil,
    published_date: nil,
    source_url: page_url
  }
  return metadata if html_content.nil? || html_content.empty?
  puts "[DEBUG] Attempting metadata extraction with Nokogiri..."
  
  begin
    doc = Nokogiri::HTML(html_content)

    # Try to get Show Name using a specific selector (similar to orchestrator)
    show_name_element = doc.at_css('h1.product-header__title')
    if show_name_element
      metadata[:show_name] = show_name_element.text.strip
    end

    # Try to get Episode Title from <title> tag and parse it
    title_tag_content = doc.at_css('title')&.text&.strip
    if title_tag_content
      # Attempt to parse Episode Title and fallback Show Name from full title
      # Example: "Episode Name on Show Name – Apple Podcasts"
      # Example: "Episode Name - Show Name – Apple Podcasts"
      # Example: "Just Episode Name – Apple Podcasts"
      apple_suffix_removed = title_tag_content.gsub(/–\s*Apple\s+Podcasts$/i, '').strip
      apple_suffix_removed.gsub!(/-\s*Apple\s+Podcasts$/i, '') # Alternative separator

      # Split by common delimiters like " on " or " - " when a show name might be present
      # Prioritize longer part as episode if multiple parts exist before a clear show name indicator
      parts = apple_suffix_removed.split(/\s+on\s+|\s+-\s+/, 2) # Split only on the first occurrence

      if parts.length > 1
        # Heuristic: If one part is significantly shorter, it might be the show name
        # Or if a part clearly indicates a show (less reliable without more context)
        # For now, assume first part is episode, second is show if present
        metadata[:episode_title] = parts[0].strip
        # If show_name wasn't found by h1, use the parsed part from title
        metadata[:show_name] ||= parts[1].strip 
      else
        metadata[:episode_title] = apple_suffix_removed # Only episode title found
      end
      
      # Clean up common artifacts like leading/trailing hyphens or asterisks if any
      metadata[:episode_title]&.gsub!(/^\s*[-*]+\s*|\s*[-*]+\s*$/, '')
      metadata[:episode_title]&.gsub!(/&amp;/, '&')
      metadata[:show_name]&.gsub!(/&amp;/, '&')
      metadata[:show_name]&.strip!
      metadata[:episode_title]&.strip!
    else
      puts "[WARN] Could not find <title> tag for metadata."
    end

    # Fallback if show name is still nil and episode title might contain it
    if metadata[:show_name].nil? || metadata[:show_name].empty?
      if metadata[:episode_title]&.include?(' – ')
        parts = metadata[:episode_title].split(' – ', 2)
        metadata[:episode_title] = parts[0].strip
        metadata[:show_name] = parts[1].strip
      elsif metadata[:episode_title]&.include?(' - ')
         parts = metadata[:episode_title].split(' - ', 2)
        metadata[:episode_title] = parts[0].strip
        metadata[:show_name] = parts[1].strip
      end
    end

  rescue => e
    puts "[WARN] Error during Nokogiri metadata extraction: #{e.message}"
    # Fallback to basic regex for episode title if Nokogiri fails badly
    title_match = html_content.match(/<title>(.*?)<\/title>/i)
    if title_match && title_match[1]
      metadata[:episode_title] = title_match[1].gsub(/&amp;/, '&').strip.gsub(/–\s*Apple\s+Podcasts$/i, '').strip
    end
  end

  metadata[:episode_title] ||= "podcast_episode_#{Time.now.to_i}"
  metadata[:show_name] ||= "Unknown Show" # Ensure show_name has a fallback
  
  puts "[DEBUG] Extracted Metadata - Show: #{metadata[:show_name]}, Episode: #{metadata[:episode_title]}"
  metadata
end

def sanitize_filename(name)
  return "default_filename" if name.nil? || name.empty?
  sanitized = name.downcase
  sanitized.gsub!(/\s+/, '-')
  sanitized.gsub!(/[^\p{Alnum}-]/, '')
  sanitized.gsub!(/-+/, '-')
  sanitized.gsub!(/^-+|-+$/, '')
  sanitized = "untitled" if sanitized.empty?
  sanitized
end

def stream_and_convert_audio(page_url)
  puts "[DEBUG] Starting audio stream and conversion from URL: #{page_url}"
  output_wav_file = "temp_audio_for_transcription.wav"

  # Find the audio URL from the page content first
  page_content = fetch_html(page_url)
  unless page_content
      puts "[WARN] Could not fetch page content to find audio link for #{page_url}. Cannot stream."
      return nil
  end
  
  audio_url_match = page_content.match(/(https?:\/\/[^"'\s]+\.(mp3|m4a|wav|aac))/)
  unless audio_url_match
    puts "[ERROR] Could not find a direct audio link (.mp3, .m4a, .wav, .aac) on the page: #{page_url}"
    return nil
  end
  audio_url = audio_url_match[0]
  puts "[INFO] Found audio stream URL: #{audio_url}"
  
  # Ensure the temp WAV file is clean before starting
  File.delete(output_wav_file) if File.exist?(output_wav_file)

  # Use FFmpeg to read directly from the URL and convert to WAV
  # This avoids saving the initial download to disk.
  command = [
    'ffmpeg',
    '-y',
    '-i', audio_url, # Read directly from the audio URL
    '-ar', '16000',
    '-ac', '1',
    '-c:a', 'pcm_s16le',
    '-f', 'wav',
    output_wav_file
  ].shelljoin

  puts "[DEBUG] Running FFmpeg stream and conversion command: #{command}"

  # Use system to show live output from FFmpeg.
  success = system("#{command} 2>&1")

  if success && File.exist?(output_wav_file) && File.size(output_wav_file) > 0
    puts "\n[INFO] Audio successfully streamed and converted to #{output_wav_file}"
    return output_wav_file
  else
    puts "\n[ERROR] Audio streaming or conversion pipeline failed for #{audio_url}."
    return nil
  end
end

# --- Parakeet Transcription (New: Adapted from your example) ---
def transcribe_audio_with_parakeet(audio_wav_file_path)
  puts "\n=== Starting Parakeet Transcription Process ==="
  puts "Input audio file (WAV): #{audio_wav_file_path}"
  unless File.exist?(audio_wav_file_path)
    puts "[ERROR] Audio WAV file #{audio_wav_file_path} does not exist for Parakeet."
    return nil
  end

  temp_parakeet_output_dir = Dir.mktmpdir("parakeet_out")
  output_base_name = File.basename(audio_wav_file_path, ".wav")
  # Parakeet will append .srt to this base name when format is srt
  expected_srt_output_file = File.join(temp_parakeet_output_dir, "#{output_base_name}.srt") # CHANGED to .srt

  parakeet_command = [
    'parakeet-mlx',
    audio_wav_file_path,
    '--model', PARAKEET_MODEL,
    '--output-format', 'srt', # CHANGED to srt
    '--output-dir', temp_parakeet_output_dir,
    '--output-template', output_base_name,
    '--bf16',
    '--verbose'
  ]

  puts "[DEBUG] Running Parakeet MLX command: #{parakeet_command.join(' ')}"
  transcription_result_text = nil
  transcription_stdout, transcription_stderr, transcription_status = nil, nil, nil

  Benchmark.bm(10) do |bm|
    bm.report("Parakeet:") do
      transcription_stdout, transcription_stderr, transcription_status = Open3.capture3(*parakeet_command)
    end
  end

  if transcription_status.success? && File.exist?(expected_srt_output_file) # CHANGED to check for .srt
    puts "[INFO] Parakeet MLX transcription command successful."
    begin
      # --- Basic SRT Parser ---
      srt_content = File.read(expected_srt_output_file)
      puts "\n--- BEGIN RAW SRT OUTPUT FROM PARAKEET ---"
      puts srt_content
      puts "--- END RAW SRT OUTPUT FROM PARAKEET ---\\n"
      # Remove sequence numbers and timestamp lines
      # A simple regex approach: match lines that are just numbers (sequence)
      # or lines containing "-->" (timestamps)
      # Then collect the remaining lines (actual dialogue)
      dialogue_lines = []
      srt_content.each_line do |line|
        line.strip!
        unless line.match?(%r{^\\d+$}) || line.include?('-->') || line.empty?
          dialogue_lines << line
        end
      end
      transcription_result_text = dialogue_lines.join("\n").strip # Join with newlines, then strip leading/trailing for the whole block
      # --- End Basic SRT Parser ---

      puts "[INFO] Read and parsed transcription text from Parakeet SRT file."
      if transcription_result_text.empty?
        puts "[WARN] Parakeet SRT output file contained no dialogue lines after parsing."
        transcription_result_text = nil # Treat empty as failure to get text
      end
    rescue StandardError => e
      puts "[ERROR] Error reading or parsing Parakeet SRT file: #{e.message}"
      transcription_result_text = nil
    end
  else
    puts "[ERROR] Error transcribing audio with Parakeet MLX."
    puts "  STDOUT: #{transcription_stdout}" unless transcription_stdout.to_s.empty?
    puts "  STDERR: #{transcription_stderr}" unless transcription_stderr.to_s.empty?
    puts "  Exit Status: #{transcription_status.exitstatus}"
    puts "  Expected SRT output file: #{expected_srt_output_file} (exists?: #{File.exist?(expected_srt_output_file)})" # CHANGED message
  end

  return transcription_result_text
ensure
  FileUtils.remove_entry_secure(temp_parakeet_output_dir) if temp_parakeet_output_dir && Dir.exist?(temp_parakeet_output_dir)
end

# --- Basic Regex Cleanup (For long transcripts) ---
def apply_basic_regex_cleanup(text)
  cleaned_text = text.dup
  
  # Remove common filler words (case insensitive)
  filler_words = /\b(um|uh|like|you know|sort of|kind of|I mean|actually)\b/i
  cleaned_text.gsub!(filler_words, '')
  
  # Fix multiple spaces caused by filler word removal
  cleaned_text.gsub!(/\s{2,}/, ' ')
  
  # Basic punctuation fixes
  cleaned_text.gsub!(/\s+,/, ',') # Remove space before comma
  cleaned_text.gsub!(/\s+\./, '.') # Remove space before period
  cleaned_text.gsub!(/\s+\?/, '?') # Remove space before question mark
  cleaned_text.gsub!(/\s+!/, '!') # Remove space before exclamation
  
  # Fix common transcription artifacts
  cleaned_text.gsub!(/\bAnd and\b/i, 'And') # Duplicate "and"
  cleaned_text.gsub!(/\bThe the\b/i, 'The') # Duplicate "the"
  cleaned_text.gsub!(/\bIs is\b/i, 'Is') # Duplicate "is"
  cleaned_text.gsub!(/\bIt it\b/i, 'It') # Duplicate "it"
  
  # Ensure sentences start with capital letters
  cleaned_text.gsub!(/\.\s+([a-z])/) { ". #{$1.upcase}" }
  cleaned_text.gsub!(/\?\s+([a-z])/) { "? #{$1.upcase}" }
  cleaned_text.gsub!(/!\s+([a-z])/) { "! #{$1.upcase}" }
  
  # Capitalize first letter of text
  cleaned_text[0] = cleaned_text[0].upcase if cleaned_text.length > 0
  
  # Clean up leading/trailing whitespace
  cleaned_text.strip!
  
  puts "[INFO] Basic regex cleanup completed. Length: #{text.length} -> #{cleaned_text.length}"
  cleaned_text
end

# --- Claude-based Text Refinement (Replaces Ollama) ---
def refine_text_with_claude(text)
  return text if text.nil? || text.empty? || !ENABLE_OLLAMA_REFINEMENT # Enable/disable transcript refinement

  if text.length < SKIP_REFINEMENT_THRESHOLD
    puts "[INFO] Skipping Claude refinement (text too short)."
    return text
  end

  # Skip refinement for very long transcripts to avoid API limits
  if text.length > 50000 # ~50k chars to be safe with prompt overhead
    puts "[INFO] Text too long for Claude refinement (#{text.length} chars). Applying basic regex cleanup..."
    return apply_basic_regex_cleanup(text)
  end

  puts "\n=== Refining Text with Claude API ==="
  refined_text = text # Default to original if refinement fails

  refinement_prompt = <<~PROMPT
  You are a transcript editor. Clean up this podcast transcript while preserving ALL content.

  REQUIREMENTS:
  1. Keep roughly the same length (within 10% of original)
  2. ONLY make these improvements:
     - Fix obvious transcription errors (grammar, spelling)
     - Remove filler words (um, uh, like, you know) 
     - Capitalize proper nouns (names, companies, places)
     - Fix punctuation for better readability
     - Ensure speaker changes are clear
  3. Preserve ALL technical discussions, quotes, context, and substantive content

  Return ONLY the cleaned transcript.

  #{text}
  PROMPT

  begin
    client = Anthropic::Client.new(api_key: ENV.fetch("ANTHROPIC_API_KEY"))
    response = client.messages.create(
        model: "claude-3-5-haiku-20241022", # Use latest Haiku model
        messages: [{ role: "user", content: refinement_prompt }],
        max_tokens: 8192,
        temperature: 0.1
    )
    
    if response && response.content && response.content[0] && response.content[0].text
      refined_text = response.content[0].text.strip
      
      # Validation: Check if text was overly reduced
      original_length = text.length
      refined_length = refined_text.length
      reduction_percentage = ((original_length - refined_length).to_f / original_length * 100).round(1)
      
      if reduction_percentage > 25 # If more than 25% reduction, use original
        puts "[WARN] Claude refinement reduced text by #{reduction_percentage}% (#{original_length} -> #{refined_length}). Using original."
        refined_text = text
      else
        puts "[INFO] Claude refinement successful. Length change: #{reduction_percentage}% (#{original_length} -> #{refined_length})"
      end
    else
      puts "[ERROR] Invalid response from Claude refinement API. Using original text."
    end
  rescue => e
    puts "[ERROR] Claude refinement failed: #{e.message}. Using original text."
    puts "[DEBUG] Response details: #{e.response.body if e.respond_to?(:response)}" # More detailed error info
  end

  return refined_text
end

# --- Summary Generation using Claude API ---
def generate_summary(transcript_content, metadata)
  puts "[DEBUG] Starting generate_summary with transcript size: #{transcript_content.size} bytes"
  
  episode_title = metadata[:episode_title] || 'Unknown Episode'
  show_name = metadata[:show_name] || 'Unknown Show'
  published_date = metadata[:published_date] || 'Unknown Date'
  duration = metadata[:duration] || 'Unknown Duration'
  source_url = metadata[:source_url] || 'Unknown URL'

  summary_prompt = <<~PROMPT
  **Podcast Information:**
  * Show Name: #{show_name}
  * Episode Title: #{episode_title}
  * Published Date: #{published_date}
  * Duration: #{duration}
  * Source URL: #{source_url}

  **Instructions:**
  Please analyze the following podcast transcript and provide a two-part summary tailored for an early-stage venture capitalist.

  **Part 1: Detailed Summary with Quotes**
  Provide a comprehensive summary of the conversation. It should flow like a well-written article, integrating key quotes naturally to support the narrative. The summary should capture the main arguments, insights, and critical points of the discussion.

  **Part 2: Key Entities for VC Radar**
  List the most important companies, people, and technologies mentioned that would be relevant to an early-stage venture capitalist. For each entity, provide a brief (one-sentence) description of its relevance in the context of the conversation.

  Format the response clearly using Markdown.

  **BEGIN TRANSCRIPT**

  #{transcript_content}

  **END TRANSCRIPT**

  --- 

  **REQUIRED METADATA OUTPUT:**
  After your main summary, please include the following lines *exactly* at the end, with the identified names:
  HOST: [List Host Name(s) or 'Unknown']
  GUESTS: [List Guest Name(s) or 'None' if no guests]
  PROMPT

  extracted_host = 'Unknown'
  extracted_guests = 'None'
  full_response_text = nil
  
  max_retries = 3
  retry_delay = 5 # seconds

  max_retries.times do |i|
    begin
      # Claude API call using Anthropic gem
      client = Anthropic::Client.new(api_key: ENV.fetch("ANTHROPIC_API_KEY"))
      response = client.messages.create(
          model: "claude-3-5-sonnet-20240620",
          messages: [{ role: "user", content: summary_prompt }],
          max_tokens: 8192, # Using max for safety
          temperature: 0.1
      )

      if response && response.content && response.content[0] && response.content[0].text
        full_response_text = response.content[0].text
        
        # Regex to find HOST and GUESTS
        host_match = full_response_text.match(/^HOST: (.*)$/i)
        guests_match = full_response_text.match(/^GUESTS: (.*)$/i)
        extracted_host = host_match[1].strip if host_match && host_match[1]
        extracted_guests = guests_match[1].strip if guests_match && guests_match[1]
        
        # If we get a successful response, we break the loop
        break
      else
        puts "[WARN] API call successful but response was empty. Retrying... (#{i + 1}/#{max_retries})"
      end
    rescue Anthropic::Errors::APIError => e
      if e.message.include?("529") || e.message.include?("overloaded")
        puts "[WARN] API Overloaded (529). Retrying in #{retry_delay} seconds... (#{i + 1}/#{max_retries})"
        sleep(retry_delay)
        retry_delay *= 2 # Exponential backoff
        next # Move to the next iteration of the loop
      else
        # For other API errors, we fail immediately
        puts "[ERROR] Unrecoverable API Error in summary generation: #{e.message}"
        return "Error: Could not generate summary. #{e.message}", extracted_host, extracted_guests
      end
    rescue => e
      puts "[ERROR] A non-API error occurred during summary generation: #{e.message}"
      return "Error: Could not generate summary. #{e.message}", extracted_host, extracted_guests
    end
  end

  # If the loop finishes without a successful response, return an error
  unless full_response_text
    return "Error: Could not generate summary after #{max_retries} attempts.", extracted_host, extracted_guests
  end
  
  return full_response_text, extracted_host, extracted_guests
end

# --- Main Logic ---
def main
  puts "[INFO] Starting Parakeet Podcast Processor..."
  if ARGV.length != 1
    puts "Usage: ruby #{__FILE__} <podcast_url>"
    exit 1
  end

  podcast_url = ARGV[0]
  output_dir_summaries = "podcast_summaries" # For Claude summaries
  temp_wav_file = nil
  metadata = {}

  begin
    FileUtils.mkdir_p(output_dir_summaries)
    FileUtils.mkdir_p(TRANSCRIPT_DIR)

    puts "\n--- Step 0: Fetching Page Metadata ---"
    html_content = fetch_html(podcast_url)
    if html_content
      metadata = extract_podcast_metadata(html_content, podcast_url)
    else
      puts "[WARN] Could not fetch or parse HTML. Using URL slug for filename and skipping some metadata."
      # Fallback metadata for filenames
      uri_path = URI.parse(podcast_url).path
      slug = File.basename(uri_path).split('?').first if uri_path
      metadata[:episode_title] = slug || "podcast_#{Time.now.to_i}"
      metadata[:source_url] = podcast_url
    end

    transcript_slug = sanitize_filename(metadata[:episode_title])
    permanent_transcript_path = File.join(TRANSCRIPT_DIR, transcript_slug + '.txt')
    summary_filename_slug = sanitize_filename("summary_#{metadata[:episode_title]}") # For summary file
    output_summary_path = File.join(output_dir_summaries, summary_filename_slug + '.txt')

    puts "[DEBUG] Permanent transcript file will be: #{permanent_transcript_path}"
    puts "[DEBUG] Summary output file will be: #{output_summary_path}"

    puts "\n--- Step 1: Streaming and Converting Audio ---"
    temp_wav_file = stream_and_convert_audio(podcast_url)
    unless temp_wav_file
      puts "[ERROR] Failed to stream and convert audio."
      exit 1
    end

    puts "\n--- Step 2: Transcribing Audio with Parakeet ---"
    raw_transcript_content = transcribe_audio_with_parakeet(temp_wav_file)
    unless raw_transcript_content
      puts "[ERROR] Failed to transcribe audio using Parakeet."
      exit 1
    end
    puts "[INFO] Raw transcript length: #{raw_transcript_content.length} characters"

    puts "\n--- Step 3.1: Refining Transcript with Claude (if enabled) ---"
    final_transcript_for_summary = refine_text_with_claude(raw_transcript_content)
    puts "[INFO] Final transcript length for summary: #{final_transcript_for_summary.length} characters"


    puts "\n--- Step 4: Generating Summary with Claude ---"
    summary_text_content, extracted_host, extracted_guests = generate_summary(final_transcript_for_summary, metadata)
    unless summary_text_content
       puts "[ERROR] Failed to generate summary using Claude API. Proceeding without summary text."
       summary_text_content = "## Summary Generation Failed\nTranscript was processed but summary generation failed."
       extracted_host ||= 'Error'
       extracted_guests ||= 'Error'
    end

    puts "\n--- Step 5: Writing Summary Output ---"
    summary_header = "--- Podcast Metadata ---\n"
    summary_header << "Show: #{metadata[:show_name] || 'N/A'}\n"
    summary_header << "Episode: #{metadata[:episode_title] || 'N/A'}\n"
    summary_header << "Host: #{extracted_host || 'N/A'}\n"
    summary_header << "Guests: #{extracted_guests || 'N/A'}\n"
    summary_header << "Source URL: #{metadata[:source_url] || 'N/A'}\n"
    summary_header << "------------------------\n\n"
    final_summary_output_content = summary_header + summary_text_content
    File.write(output_summary_path, final_summary_output_content)
    puts "[INFO] Summary saved to: #{output_summary_path}"


    puts "\n--- Step 6: Writing Transcript File (with metadata) ---"
    transcript_file_header = <<~HEADER
    --- METADATA START ---
    Show: #{metadata[:show_name] || 'N/A'}
    Episode: #{metadata[:episode_title] || 'N/A'}
    Host: #{extracted_host || 'N/A'} 
    Guests: #{extracted_guests || 'N/A'}
    Source URL: #{metadata[:source_url] || 'N/A'}
    --- METADATA END ---

    HEADER
    # Use the *refined* transcript for the permanent transcript file
    final_transcript_file_content = transcript_file_header + final_transcript_for_summary 
    File.write(permanent_transcript_path, final_transcript_file_content)
    puts "[INFO] Final transcript (with metadata) saved to: #{permanent_transcript_path}"

    # Orchestrator markers
    puts "SHOW_NAME: #{metadata[:show_name] || 'Unknown'}"
    puts "HOST: #{extracted_host || 'Unknown'}"
    puts "GUESTS: #{extracted_guests || 'None'}"
    puts "SUMMARY_FILE: #{File.expand_path(output_summary_path)}"
    puts "TRANSCRIPT_FILE: #{File.expand_path(permanent_transcript_path)}"

  rescue => e
    puts "\n--- ERROR: Unhandled exception in main --- "
    puts "[DEBUG] Exception: #{e.message}"
    puts "[DEBUG] Backtrace:\n#{e.backtrace.join("\n")}"
    exit 1
  ensure
    puts "\n--- Step 7: Cleaning Up Temporary Files ---"
    if temp_wav_file && File.exist?(temp_wav_file)
      puts "[DEBUG] Deleting WAV file: #{temp_wav_file}"
      File.delete(temp_wav_file)
    end
    puts "[INFO] Parakeet Podcast Processor finished."
  end
end

if __FILE__ == $0
  main
end 