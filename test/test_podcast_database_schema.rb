require 'minitest/autorun'
require 'duckdb'
require 'fileutils'
require 'logger'
require_relative '../podcast_orchestrator' # Assuming orchestrator is in parent dir

# Suppress logger output during tests
LOGGER.level = Logger::FATAL

class TestPodcastDatabaseSchema < Minitest::Test
  TEST_DB_FILE = 'test_podcast_processing.duckdb'

  def setup
    # Clean up any previous test DB file
    FileUtils.rm_f(TEST_DB_FILE)

    # 1. Create the database with the OLD schema (no summary_filename)
    db = DuckDB::Database.open(TEST_DB_FILE)
    con = db.connect
    con.query("""
      CREATE TABLE processed_podcasts (
        episode_url TEXT PRIMARY KEY NOT NULL,
        processed_at TEXT NOT NULL
      );
    """)
    # Insert some data into the old schema using prepare/bind
    con.prepare("INSERT INTO processed_podcasts (episode_url, processed_at) VALUES ($1, $2);") do |stmt|
      stmt.bind(1, 'http://old.example.com/ep1')
      stmt.bind(2, '2025-01-01') # Keep as TEXT to match schema
      stmt.execute
    end
    con.close
    db.close
    puts "Setup: Created test DB with old schema."
  end

  def teardown
    # Clean up the test DB file
    FileUtils.rm_f(TEST_DB_FILE)
    puts "Teardown: Removed test DB."
  end

  def test_summary_filename_column_addition
    puts "Test: Running schema update test..."
    # 2. Initialize PodcastDatabase - this should trigger the ALTER TABLE
    podcast_db = PodcastDatabase.new(TEST_DB_FILE)
    assert podcast_db.connected?, "Failed to connect to test database after setup."

    # 3. Verify the column now exists
    table_info = podcast_db.con.query("PRAGMA table_info(processed_podcasts);").each.to_a
    has_summary_filename = table_info.any? { |col| col[1] == 'summary_filename' }
    assert has_summary_filename, "'summary_filename' column was not added."
    puts "Test: Verified 'summary_filename' column exists."

    # 4. Verify old data is still present
    count_result = nil
    podcast_db.con.prepare("SELECT COUNT(*) FROM processed_podcasts WHERE episode_url = $1") do |stmt|
      stmt.bind(1, 'http://old.example.com/ep1')
      result_set = stmt.execute
      count_result = result_set.each.first # Use .each.first to get the row
    end
    assert_equal 1, count_result[0], "Old data seems to be missing after ALTER TABLE."
    puts "Test: Verified old data persistence."

    # 5. Verify new data (with summary_filename) can be inserted
    success = podcast_db.mark_as_processed('http://new.example.com/ep2', '/path/to/summary.md', Date.parse('2025-01-02'))
    assert success, "Failed to mark new episode as processed with summary filename."

    new_data = nil
    podcast_db.con.prepare("SELECT summary_filename FROM processed_podcasts WHERE episode_url = $1") do |stmt|
      stmt.bind(1, 'http://new.example.com/ep2')
      result_set = stmt.execute
      new_data = result_set.each.first # Use .each.first
    end
    assert_equal '/path/to/summary.md', new_data[0], "Summary filename was not stored correctly for the new entry."
    puts "Test: Verified insertion of new data with summary filename."

  ensure
    # Ensure connection is closed even if assertions fail
    podcast_db&.close
  end
end 