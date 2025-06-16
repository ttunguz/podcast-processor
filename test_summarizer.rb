#!/usr/bin/env ruby
# frozen_string_literal: true

# Force output synchronization
$stdout.sync = true

# Test script for DailySummarizer class

require 'duckdb'
require 'logger'
require 'time'
require 'date'
require 'fileutils' # For directory creation/deletion
require 'digest/sha1' # For fallback filename generation
require 'uri' # <--- Add this require

# --- Configuration for Test ---
# Store test DB in the same directory as the script
TEST_SUMMARY_DIR = File.expand_path('test_summaries', __dir__)
TEST_DB_FILE = File.expand_path('summarizer_test_db.duckdb', __dir__)
TEST_URL_TODAY_1 = 'https://podcasts.apple.com/us/podcast/episode-today-one/id123?i=101'
TEST_URL_TODAY_2 = 'https://podcasts.apple.com/us/podcast/episode-today-two-with-symbols/id123?i=102'
TEST_URL_YESTERDAY = 'https://podcasts.apple.com/us/podcast/episode-yesterday/id123?i=99'
TEST_URL_MISSING_FILE = 'https://podcasts.apple.com/us/podcast/episode-today-no-file/id123?i=103'

# --- Logging ---
# Use a logger similar to the main script for consistency
LOGGER = Logger.new($stdout)
LOGGER.level = Logger::DEBUG # Use DEBUG for detailed test output

# --- Helper Function for Filename Generation (Simplified for Test) ---
def generate_summary_filename(url)
  begin
    uri = URI.parse(url)
    query_params = URI.decode_www_form(uri.query || '').to_h
    episode_id = query_params['i']
    if episode_id && !episode_id.empty?
      # Use episode ID for a predictable test filename
      "episode-#{episode_id}.txt"
    else
      # Fallback if 'i' param is missing
      LOGGER.warn("Could not find episode ID (i=...) in URL: #{url}. Using SHA1 hash.")
      "summary-#{Digest::SHA1.hexdigest(url)[0...8]}.txt"
    end
  rescue URI::InvalidURIError, ArgumentError => e
    LOGGER.warn("Could not parse URL or query for filename generation: #{url}. Error: #{e.message}. Using SHA1 hash.")
    "summary-#{Digest::SHA1.hexdigest(url)[0...8]}.txt"
  end
end

# --- Database Handling Class (with new method) ---
class PodcastDatabase
  attr_reader :con

  def initialize(db_file)
    @con = nil
    begin
      # Remove deletion of existing DB file for test re-opening
      # if File.exist?(db_file)
      #   File.delete(db_file)
      #   LOGGER.debug("Deleted existing test DB file: #{db_file}")
      # end
      db = DuckDB::Database.open(db_file)
      @con = db.connect
      create_table # Still ensure table exists on connect
      LOGGER.info("Database connection established to #{db_file}")
    rescue StandardError => e
      LOGGER.error("Failed to initialize database: #{e.message}")
      @con = nil
    end
  end

  def connected?
    !@con.nil?
  end

  # --- New Method ---
  def get_episodes_processed_since(date_obj) # Expects a Date object
    return [] unless connected?
    urls = []
    begin
      # Fetch ALL records and filter in Ruby to bypass DB comparison issues
      sql = "SELECT episode_url, processed_at FROM processed_podcasts ORDER BY processed_at;"
      result_set = @con.prepare(sql) do |stmt|
        stmt.execute
      end

      result_set.each do |row|
        next unless row && row[0] && row[1]
        episode_url = row[0]
        processed_date = row[1]

        # --- Debugging --- 
        LOGGER.debug("Processing row: URL=#{episode_url}, DB Date=#{processed_date.inspect}, Class=#{processed_date.class}, Comparison Date=#{date_obj.inspect}")
        # --- End Debugging ---

        # Perform filtering in Ruby using string comparison
        begin
          urls << episode_url if processed_date.strftime('%Y-%m-%d') >= date_obj.strftime('%Y-%m-%d')
        rescue ArgumentError, NoMethodError => e # Catch potential errors if processed_date is not a Date
          LOGGER.error("Error comparing dates: DB Date=#{processed_date.inspect}, Comparison Date=#{date_obj.inspect} - Error: #{e.message}")
        end
      end

    rescue DuckDB::Error => e
      LOGGER.error("DuckDB query error (get_episodes_processed_since): #{e.message}")
    rescue StandardError => e # Catch other potential errors during Ruby filtering
      LOGGER.error("Error processing results in get_episodes_processed_since: #{e.message}")
    end
    LOGGER.debug("Filtered URLs processed since #{date_obj}: #{urls.count}")
    urls
  end
  # --- End New Method ---

  def already_processed?(episode_url) # Kept for potential setup use
    return false unless connected?
    begin
      # Use prepare with numbered placeholders and bind within a block
      result_set = @con.prepare("SELECT COUNT(*) FROM processed_podcasts WHERE episode_url = $1;") do |stmt|
        stmt.bind(1, episode_url)
        stmt.execute # Execute returns a DuckDB::Result object
      end
      # Fetch the first row from the result set
      row = result_set.each.first
      processed = row && row[0] > 0
      processed
    rescue DuckDB::Error => e
      LOGGER.error("DuckDB query error (already_processed?): #{e.message}")
      false
    end
  end

  def mark_as_processed(episode_url, date_obj = Date.today) # Default to today's Date
    return false unless connected?
    begin
      # Bind the Date object for the processed_at column
      @con.prepare("INSERT OR REPLACE INTO processed_podcasts (episode_url, processed_at) VALUES ($1, $2);") do |stmt|
        stmt.bind(1, episode_url)
        stmt.bind(2, date_obj) # Bind Date object
        stmt.execute
      end
      LOGGER.info("Marked as processed: #{episode_url} on #{date_obj.strftime('%Y-%m-%d')}")
      true
    rescue DuckDB::Error => e
      LOGGER.error("DuckDB insert error (mark_as_processed): #{e.message}")
      false
    end
  end

  def close
    if connected?
      @con.close
      LOGGER.info("Database connection closed.")
      @con = nil
    end
  end

  private

  def create_table
    return unless connected?
    # Change column type to DATE
    @con.query(<<~SQL)
      CREATE TABLE IF NOT EXISTS processed_podcasts (
        episode_url TEXT PRIMARY KEY,
        processed_at DATE
      );
    SQL
    LOGGER.info("Ensured processed_podcasts table exists (using DATE).")
  rescue DuckDB::Error => e
     LOGGER.error("Failed to create database table: #{e.message}")
  end
end

# --- Daily Summarizer Class ---
class DailySummarizer
  def initialize(database, summary_dir)
    @db = database
    @summary_dir = summary_dir
  end

  def generate_summary_document
    today_str = Date.today.strftime('%Y-%m-%d')
    output_filename = "daily_summary_podcasts_#{today_str}.md"
    # Place summary doc in the directory ABOVE the summary_dir (e.g., whisper.cpp/ daily_summary...md)
    output_path = File.expand_path(output_filename, File.join(@summary_dir, ".."))

    LOGGER.info("Generating daily summary document: #{output_path}")

    # Use Date.today for querying
    start_of_today_date = Date.today

    processed_urls = @db.get_episodes_processed_since(start_of_today_date)
    LOGGER.info("Found #{processed_urls.count} episodes processed on or after #{start_of_today_date.strftime('%Y-%m-%d')}")

    unless processed_urls.empty?
      begin
        File.open(output_path, 'w') do |outfile|
          outfile.puts("# Podcast Summaries for #{today_str}")
          outfile.puts("---")

          processed_urls.each do |url|
            summary_filename = generate_summary_filename(url) # Use helper
            summary_filepath = File.join(@summary_dir, summary_filename)

            outfile.puts("\n## Episode: #{url}\n")

            if File.exist?(summary_filepath)
              begin
                summary_content = File.read(summary_filepath)
                outfile.puts(summary_content)
                LOGGER.debug("Appended summary for: #{url} from #{summary_filename}")
              rescue StandardError => e
                LOGGER.error("Failed to read summary file #{summary_filepath}: #{e.message}")
                outfile.puts("*Error reading summary file.*")
              end
            else
              LOGGER.warn("Summary file not found for episode #{url} (Expected: #{summary_filename})")
              outfile.puts("*Summary file not found.*")
            end
            outfile.puts("\n---")
          end
        end
        LOGGER.info("Successfully generated daily summary: #{output_path}")
        return output_path # Return path for verification
      rescue StandardError => e
        LOGGER.error("Failed to write daily summary document #{output_path}: #{e.message}")
        return nil
      end
    else
      LOGGER.info("No episodes processed today. Skipping summary generation.")
      return nil
    end
  end
end

# --- Test Setup ---
def setup_test_environment
  LOGGER.info("--- Setting up Test Environment ---")
  FileUtils.mkdir_p(TEST_SUMMARY_DIR)
  LOGGER.debug("Created directory: #{TEST_SUMMARY_DIR}")

  # Create dummy summary files using the *same* helper function
  file1_name = generate_summary_filename(TEST_URL_TODAY_1) # Should be episode-101.txt
  File.write(File.join(TEST_SUMMARY_DIR, file1_name), "Summary content for episode today one.")
  LOGGER.debug("Created dummy file: #{file1_name}")

  file2_name = generate_summary_filename(TEST_URL_TODAY_2) # Should be episode-102.txt
  File.write(File.join(TEST_SUMMARY_DIR, file2_name), "Summary for episode today two.")
  LOGGER.debug("Created dummy file: #{file2_name}")

  # Don't create file for TEST_URL_MISSING_FILE

  # 3. Create and populate test database
  db = PodcastDatabase.new(TEST_DB_FILE)
  unless db.connected?
    LOGGER.fatal("Setup failed: Could not connect to the test database.")
    exit(1)
  end
  # Mark episodes with specific Dates
  db.mark_as_processed(TEST_URL_TODAY_1, Date.today)
  db.mark_as_processed(TEST_URL_TODAY_2, Date.today)
  db.mark_as_processed(TEST_URL_YESTERDAY, Date.today - 1) # Processed yesterday
  db.mark_as_processed(TEST_URL_MISSING_FILE, Date.today)

  # --- Add diagnostic query --- 
  LOGGER.debug("--- Querying DB content immediately after setup --- ")
  begin
    query_sql = "SELECT episode_url, processed_at FROM processed_podcasts;"
    result_set = db.con.query(query_sql)
    result_set.each do |row|
        LOGGER.debug("DB Content Check: URL=#{row[0]}, Date=#{row[1].inspect}, Class=#{row[1].class}")
    end
    LOGGER.debug("--- Finished querying DB content --- ")
  rescue => e
      LOGGER.error("Error during diagnostic DB query: #{e.message}")
  end
  # --- End diagnostic query --- 

  db.close
  LOGGER.debug("Populated test database: #{TEST_DB_FILE}")
  LOGGER.info("--- Test Setup Complete ---")
end

# --- Test Cleanup ---
def cleanup_test_environment(generated_summary_file)
  LOGGER.info("--- Cleaning up Test Environment ---")
  db = PodcastDatabase.new(TEST_DB_FILE) # Reconnect briefly if needed for inspection before delete
  db.close

  # Delete generated summary file
  if generated_summary_file && File.exist?(generated_summary_file)
    File.delete(generated_summary_file)
    LOGGER.debug("Deleted generated summary file: #{generated_summary_file}")
  end

  # Delete test database file
  if File.exist?(TEST_DB_FILE)
    File.delete(TEST_DB_FILE)
    LOGGER.debug("Deleted test database file: #{TEST_DB_FILE}")
  end

  # Delete test summaries directory
  if Dir.exist?(TEST_SUMMARY_DIR)
    FileUtils.rm_rf(TEST_SUMMARY_DIR)
    LOGGER.debug("Deleted test summaries directory: #{TEST_SUMMARY_DIR}")
  end
  LOGGER.info("--- Test Cleanup Complete ---")
end

# --- Test Execution Logic ---
generated_file_path = nil
passed = false
begin
  setup_test_environment

  LOGGER.info("--- Starting DailySummarizer Test ---")
  db = PodcastDatabase.new(TEST_DB_FILE) # Re-open DB for the test
  summarizer = DailySummarizer.new(db, TEST_SUMMARY_DIR)
  generated_file_path = summarizer.generate_summary_document
  db.close # Close DB after summarizer is done

  # Verification
  if generated_file_path && File.exist?(generated_file_path)
    LOGGER.info("Generated summary file exists: #{generated_file_path}")
    content = File.read(generated_file_path)
    # Basic checks (improve as needed)
    check1 = content.include?(TEST_URL_TODAY_1) && content.include?("Summary content for episode today one.")
    check2 = content.include?(TEST_URL_TODAY_2) && content.include?("Summary for episode today two.")
    check3 = content.include?(TEST_URL_MISSING_FILE) && content.include?("*Summary file not found.*")
    check4 = !content.include?(TEST_URL_YESTERDAY) # Ensure old episode is not included

    passed = check1 && check2 && check3 && check4
    LOGGER.info("Content Check 1 (URL1 Today Present): #{check1}")
    LOGGER.info("Content Check 2 (URL2 Today Present): #{check2}")
    LOGGER.info("Content Check 3 (Missing File URL Present with Note): #{check3}")
    LOGGER.info("Content Check 4 (Yesterday URL Absent): #{check4}")
  else
    LOGGER.error("Generated summary file was not created or path was not returned.")
    passed = false
  end

rescue StandardError => e
  LOGGER.error("An error occurred during testing: #{e.message}")
  LOGGER.error(e.backtrace.join("\n"))
  passed = false
ensure
  LOGGER.info("--- Test Finished ---")
  if passed
    LOGGER.info("Result: PASSED")
  else
    LOGGER.error("Result: FAILED")
  end
  cleanup_test_environment(generated_file_path)
  exit(passed ? 0 : 1) # Exit with appropriate status code
end
