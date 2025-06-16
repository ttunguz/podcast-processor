#!/usr/bin/env ruby
# frozen_string_literal: true

# Test script for PodcastDatabase class

require 'duckdb'
require 'logger'
require 'time'
require 'date'

# --- Configuration for Test ---
# Store test DB in the same directory as the script
TEST_DB_FILE = File.expand_path('test_db.duckdb', __dir__)
TEST_URL_1 = 'http://example.com/podcast/episode1'
TEST_URL_2 = 'http://example.com/podcast/episode2'

# --- Logging ---
# Use a logger similar to the main script for consistency
LOGGER = Logger.new($stdout)
LOGGER.level = Logger::DEBUG # Use DEBUG for detailed test output

# --- Database Handling Class (Copied from podcast_orchestrator.rb) ---
class PodcastDatabase
  attr_reader :con

  def initialize(db_file)
    @con = nil
    begin
      # Delete existing test file to ensure clean start
      if File.exist?(db_file)
        File.delete(db_file)
        LOGGER.debug("Deleted existing test DB file: #{db_file}")
      end

      db = DuckDB::Database.open(db_file)
      @con = db.connect
      create_table
      LOGGER.info("Database connection established to #{db_file}")
    rescue StandardError => e
      LOGGER.error("Failed to initialize database: #{e.message}")
      @con = nil
    end
  end

  def connected?
    !@con.nil?
  end

  def already_processed?(episode_url)
    return false unless connected?
    begin
      # Ensure parameter is passed correctly for direct query
      result = @con.query("SELECT COUNT(*) FROM processed_podcasts WHERE episode_url = ?;", [episode_url]).fetch_row
      processed = result && result[0] > 0
      processed
    rescue DuckDB::Error => e
      LOGGER.error("DuckDB query error (already_processed?): #{e.message}")
      false
    end
  end

  def mark_as_processed(episode_url)
    return false unless connected?
    begin
      # Ensure parameters are passed correctly for direct query
      @con.query("INSERT OR REPLACE INTO processed_podcasts (episode_url, processed_at) VALUES (?, ?);", [episode_url, Time.now.utc.iso8601])
      LOGGER.info("Marked as processed: #{episode_url}")
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
    @con.query(<<~SQL)
      CREATE TABLE IF NOT EXISTS processed_podcasts (
        episode_url TEXT PRIMARY KEY,
        processed_at TIMESTAMP
      );
    SQL
    LOGGER.info("Ensured processed_podcasts table exists.")
  rescue DuckDB::Error => e
     LOGGER.error("Failed to create database table: #{e.message}")
  end
end

# --- Test Execution Logic ---
LOGGER.info("--- Starting PodcastDatabase Test ---")

db = PodcastDatabase.new(TEST_DB_FILE)

unless db.connected?
  LOGGER.fatal("Test failed: Could not connect to the test database.")
  exit(1)
end

# Wrap tests in a begin/rescue/ensure block for proper cleanup
passed = false
begin
  LOGGER.info("Checking URL1 before processing...")
  processed1_before = db.already_processed?(TEST_URL_1)
  LOGGER.info("URL1 processed (before)? #{processed1_before}") # Expected: false

  LOGGER.info("Marking URL1 as processed...")
  mark1_success = db.mark_as_processed(TEST_URL_1)
  LOGGER.info("Marking URL1 success? #{mark1_success}") # Expected: true

  LOGGER.info("Checking URL1 after processing...")
  processed1_after = db.already_processed?(TEST_URL_1)
  LOGGER.info("URL1 processed (after)? #{processed1_after}") # Expected: true

  LOGGER.info("Checking URL2 (should not be processed)...")
  processed2 = db.already_processed?(TEST_URL_2)
  LOGGER.info("URL2 processed? #{processed2}") # Expected: false

  LOGGER.info("Marking URL1 again (should update timestamp)...")
  mark1_again_success = db.mark_as_processed(TEST_URL_1)
  LOGGER.info("Marking URL1 again success? #{mark1_again_success}") # Expected: true

  # Verify results
  passed = !processed1_before && mark1_success && processed1_after && !processed2 && mark1_again_success

rescue StandardError => e
  LOGGER.error("An error occurred during testing: #{e.message}")
  LOGGER.error(e.backtrace.join("\n"))
  passed = false
ensure
  db&.close
  LOGGER.info("--- Test Finished ---")
  if passed
    LOGGER.info("Result: PASSED")
  else
    LOGGER.error("Result: FAILED")
  end

  # Clean up test database file
  begin
    if File.exist?(TEST_DB_FILE)
      File.delete(TEST_DB_FILE)
      LOGGER.info("Cleaned up test database file: #{TEST_DB_FILE}")
    end
  rescue StandardError => e
    LOGGER.warn("Could not clean up test database file #{TEST_DB_FILE}: #{e.message}")
  end

  exit(passed ? 0 : 1) # Exit with appropriate status code
end