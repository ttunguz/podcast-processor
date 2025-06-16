#!/usr/bin/env ruby

require 'fileutils'
require 'time'

# Directory where transcripts are stored
TRANSCRIPT_DIR = "podcast_transcripts"
# Temporary file to hold combined transcripts
TEMP_COMBINED_FILE = "todays_combined_transcripts.txt"
# Ollama model to use
OLLAMA_MODEL = "gemma3:27b-it-qat"

# --- Helper Functions ---

# Get the start of today (00:00:00) in local time
def start_of_today
  now = Time.now
  Time.new(now.year, now.month, now.day)
end

# --- Main Script Logic ---

begin
  puts "[INFO] Starting script: Chat with Today's Podcasts"

  # 1. Check if transcript directory exists
  unless Dir.exist?(TRANSCRIPT_DIR)
    puts "[ERROR] Transcript directory not found: #{TRANSCRIPT_DIR}"
    exit 1
  end
  puts "[INFO] Transcript directory found: #{TRANSCRIPT_DIR}"

  # 2. Find transcript files modified today
  today_start_time = start_of_today
  all_transcript_files = Dir.glob(File.join(TRANSCRIPT_DIR, "*.txt"))
  
  todays_files = all_transcript_files.select do |filepath|
    File.mtime(filepath) >= today_start_time
  end

  if todays_files.empty?
    puts "[INFO] No transcript files found modified today (#{Time.now.strftime('%Y-%m-%d')}) in #{TRANSCRIPT_DIR}."
    exit 0 # Exit cleanly if no files found
  end

  puts "[INFO] Found #{todays_files.size} transcript(s) from today:"
  todays_files.each { |f| puts "  - #{File.basename(f)}" }

  # 3. Concatenate today's transcripts into a temporary file
  puts "[INFO] Concatenating transcripts into temporary file: #{TEMP_COMBINED_FILE}"
  File.open(TEMP_COMBINED_FILE, 'w') do |outfile|
    todays_files.each_with_index do |filepath, index|
      begin
        content = File.read(filepath)
        outfile.write(content)
        # Add a separator between files, but not after the last one
        if index < todays_files.size - 1
          outfile.write("\n\n---\n\n") # Separator for clarity
        end
      rescue => e
        puts "[WARN] Failed to read file #{File.basename(filepath)}: #{e.message}. Skipping."
      end
    end
  end
  puts "[INFO] Concatenation complete."

  # 4. Construct and execute the Ollama command
  ollama_cmd = "cat #{TEMP_COMBINED_FILE} | ollama run #{OLLAMA_MODEL}"
  puts "[INFO] Running Ollama command:"
  puts "$ #{ollama_cmd}"
  
  # Execute the command. This will block until Ollama finishes.
  system(ollama_cmd) 
  
  puts "[INFO] Ollama command finished."

rescue => e
  puts "\n[ERROR] An unexpected error occurred:"
  puts e.message
  puts e.backtrace.join("\n")
  exit 1
ensure
  # 5. Clean up the temporary file
  if File.exist?(TEMP_COMBINED_FILE)
    puts "[INFO] Cleaning up temporary file: #{TEMP_COMBINED_FILE}"
    begin
      File.delete(TEMP_COMBINED_FILE)
    rescue => e
      puts "[WARN] Failed to delete temporary file #{TEMP_COMBINED_FILE}: #{e.message}"
    end
  end
  puts "[INFO] Script finished."
end 