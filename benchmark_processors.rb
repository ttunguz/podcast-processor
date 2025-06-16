#!/usr/bin/env ruby

require 'open3'
require 'benchmark'
require 'fileutils'
require 'shellwords'

CLAUDE_PROCESSOR_SCRIPT = './claude_podcast_processor.rb'
PARAKEET_PROCESSOR_SCRIPT = './parakeet_podcast_processor.rb'
PODCAST_URL = 'https://podcasts.apple.com/us/podcast/228-elad-gil-how-to-spot-a-billion-dollar-startup/id990149481?i=1000708306340'

# Ensure processor scripts are executable
[CLAUDE_PROCESSOR_SCRIPT, PARAKEET_PROCESSOR_SCRIPT].each do |script|
  unless File.executable?(script)
    puts "ERROR: Processor script #{script} is not executable. Please run 'chmod +x #{script}'."
    exit 1
  end
end

def benchmark_script(script_path, url)
  puts "\n--- Benchmarking #{File.basename(script_path)} ---"
  puts "URL: #{url}"

  # Temporary files known to be created by the processors in the CWD
  temp_download_files_glob = "temp_audio_download.*"
  temp_wav_file = "temp_audio_for_transcription.wav"

  files_to_delete_after_run = []

  # Pre-cleanup of known temporary files from previous runs (if any)
  puts "Pre-cleaning known temporary files..."
  FileUtils.rm_f(Dir.glob(temp_download_files_glob))
  FileUtils.rm_f(temp_wav_file)
  # Also clean potential output dirs if they exist from a failed previous run, 
  # but be careful not to delete user data. For this benchmark, we only delete specific files.

  command = "#{script_path} #{Shellwords.escape(url)}"
  stdout_str, stderr_str, status = nil, nil, nil
  
  duration = Benchmark.realtime do
    # Ensure the processor script runs in the context of its own directory if it relies on relative paths for its own assets
    # However, for these scripts, they are designed to be run from the workspace root.
    # The CWD for Open3.capture3 will be the CWD of this benchmark script.
    stdout_str, stderr_str, status = Open3.capture3(command)
  end

  puts "Execution finished in #{duration.round(4)} seconds."
  puts "Status: #{status.success? ? 'Success' : "Failure (Exit Code: #{status.exitstatus})"}"
  
  # Force encoding to UTF-8 and replace invalid/undefined characters
  stdout_str = stdout_str.to_s.encode('UTF-8', invalid: :replace, undef: :replace, replace: '?')
  stderr_str = stderr_str.to_s.encode('UTF-8', invalid: :replace, undef: :replace, replace: '?')

  puts "\n--- Output from #{File.basename(script_path)} ---"
  puts "STDOUT:"
  puts stdout_str.empty? ? "<empty>" : stdout_str
  puts "\nSTDERR:"
  puts stderr_str.empty? ? "<empty>" : stderr_str
  puts "--- End of Output ---"

  # Parse stdout for SUMMARY_FILE and TRANSCRIPT_FILE to clean them up
  if stdout_str
    stdout_str.each_line do |line|
      line.strip!
      if line.start_with?('SUMMARY_FILE:')
        file_path = line.split(':', 2)[1]&.strip
        # Ensure the path is absolute or resolve it relative to PWD if necessary
        # The processor scripts should output absolute paths for these markers.
        files_to_delete_after_run << file_path if file_path && !file_path.empty?
      elsif line.start_with?('TRANSCRIPT_FILE:')
        file_path = line.split(':', 2)[1]&.strip
        files_to_delete_after_run << file_path if file_path && !file_path.empty?
      end
    end
  end

  # Add the common temporary files to the deletion list
  # These are created in the CWD from which the script was run (i.e., where benchmark_processors.rb is)
  files_to_delete_after_run += Dir.glob(temp_download_files_glob)
  files_to_delete_after_run << temp_wav_file

  files_to_delete_after_run.uniq! # Remove duplicates

  puts "\nAttempting to clean up generated files:"
  files_to_delete_after_run.each do |file_path|
    next if file_path.nil? || file_path.strip.empty?
    # Check if it's a directory first, for safety, though we expect files.
    if File.directory?(file_path)
      puts "  Skipping deletion of directory: #{file_path}" # Should not happen with current markers
      next
    end
    if File.exist?(file_path)
      begin
        FileUtils.rm_f(file_path)
        puts "  Deleted: #{file_path}"
      rescue StandardError => e
        puts "  WARN: Could not delete #{file_path}: #{e.message}"
      end
    else
      # This is normal if the script failed before creating the file
      # puts "  INFO: File not found for deletion (may have failed before creation): #{file_path}"
    end
  end
  puts "Cleanup attempt finished."
  
  return duration
end

puts "Starting podcast processor benchmark..."
puts "This will run each processor script once. Ensure ANTHROPIC_API_KEY is set."
puts "Ensure parakeet-mlx, ffmpeg are installed and Ollama is running if refinement is enabled."

# --- Ensure ANTHROPIC_API_KEY is set --- (Important for both scripts if they use Claude for summaries)
unless ENV['ANTHROPIC_API_KEY']
  puts "\n[FATAL ERROR] ANTHROPIC_API_KEY environment variable is not set."
  puts "Both processor scripts require this for summary generation."
  puts "Please set it and try again."
  exit 1
end

claude_time = nil
parakeet_time = nil

begin
  # Benchmark Claude Processor
  puts "\n=================================================="
  puts "Benchmarking Claude-based Processor (claude_podcast_processor.rb)"
  puts "=================================================="
  claude_time = benchmark_script(CLAUDE_PROCESSOR_SCRIPT, PODCAST_URL)
rescue StandardError => e
  puts "[ERROR] An error occurred while benchmarking #{CLAUDE_PROCESSOR_SCRIPT}: #{e.message}"
  puts e.backtrace.join("\n")
end

begin
  # Benchmark Parakeet Processor
  puts "\n=================================================="
  puts "Benchmarking Parakeet-based Processor (parakeet_podcast_processor.rb)"
  puts "=================================================="
  parakeet_time = benchmark_script(PARAKEET_PROCESSOR_SCRIPT, PODCAST_URL)
rescue StandardError => e
  puts "[ERROR] An error occurred while benchmarking #{PARAKEET_PROCESSOR_SCRIPT}: #{e.message}"
  puts e.backtrace.join("\n")
end

puts "\n\n--- Benchmark Results ---"
if claude_time
  printf "Claude Processor Time:   %.4f seconds\n", claude_time
else
  puts "Claude Processor Time:   Failed or not run."
end

if parakeet_time
  printf "Parakeet Processor Time: %.4f seconds\n", parakeet_time
else
  puts "Parakeet Processor Time: Failed or not run."
end

if claude_time && parakeet_time
  if parakeet_time < claude_time
    diff = claude_time - parakeet_time
    percentage = (diff / claude_time) * 100
    puts "Parakeet processor was %.4f seconds (%.2f%%) faster." % [diff, percentage]
  elsif claude_time < parakeet_time
    diff = parakeet_time - claude_time
    # percentage against parakeet_time doesn't make sense here, it should be against the faster one or a baseline
    # For simplicity, let's show how much slower parakeet was in terms of claude_time
    percentage_slower = (diff / claude_time) * 100 
    puts "Claude processor was %.4f seconds faster. Parakeet was %.2f%% slower than Claude." % [diff, percentage_slower]
  else
    puts "Both processors took approximately the same time."
  end
end

puts "\nBenchmark finished." 