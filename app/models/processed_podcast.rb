require 'duckdb'
require 'active_model'

class ProcessedPodcast
  include ActiveModel::Model
  include ActiveModel::Attributes

  # Define attributes corresponding to DuckDB columns
  attribute :episode_url, :string
  attribute :processed_at, :date
  attribute :summary_filename, :string
  attribute :podcast_name, :string
  attribute :host, :string
  attribute :guests, :string

  # Define the path to the DuckDB database relative to the Rails app root
  # Assumes podcast_dashboard is directly alongside whisper.cpp
  DUCKDB_PATH = Rails.root.join('..', 'whisper.cpp', 'podcast_processing.duckdb').to_s
  SUMMARY_DIR = Rails.root.join('..', 'whisper.cpp', 'podcast_summaries').to_s

  # --- Class Methods for DB Interaction ---

  # Fetches all processed podcasts from DuckDB
  def self.all
    query = "SELECT episode_url, processed_at, summary_filename, podcast_name, host, guests FROM processed_podcasts ORDER BY processed_at DESC;"
    execute_query(query)
  end

  # Finds a specific podcast by its summary filename
  # Note: summary_filename in the DB might be an absolute path
  def self.find_by_summary_filename(filename)
    # We need the absolute path stored in the DB, which includes the original whisper.cpp path
    # But the input `filename` might just be the basename. Let's search based on the basename.
    # This assumes summary filenames are unique enough by their basename.
    base_filename = File.basename(filename)
    query = "SELECT episode_url, processed_at, summary_filename, podcast_name, host, guests FROM processed_podcasts WHERE basename(summary_filename) = ? LIMIT 1;"
    results = execute_query(query, [base_filename])
    results.first
  end

  # Reads the content of the summary file
  def summary_content
    return "Summary file path not found in database record." if summary_filename.blank?

    # The summary_filename from DB is likely an absolute path already
    # Let's double-check if it exists relative to the expected SUMMARY_DIR just in case
    potential_path_relative = File.join(SUMMARY_DIR, File.basename(summary_filename))
    actual_path = nil

    if File.exist?(summary_filename)
      actual_path = summary_filename # Path from DB is valid
    elsif File.exist?(potential_path_relative)
      actual_path = potential_path_relative # Path relative to dashboard works
    end

    if actual_path && File.exist?(actual_path)
      begin
        File.read(actual_path)
      rescue StandardError => e
        Rails.logger.error("Error reading summary file #{actual_path}: #{e.message}")
        "Error reading summary file: #{e.message}"
      end
    else
      Rails.logger.error("Summary file not found at path: #{summary_filename} or relative path: #{potential_path_relative}")
      "Summary file not found at expected location."
    end
  end

  private

  # Helper method to connect to DuckDB and execute a query
  def self.execute_query(sql, params = [])
    db = nil
    con = nil
    results = []
    begin
      unless File.exist?(DUCKDB_PATH)
        Rails.logger.error("DuckDB database file not found at: #{DUCKDB_PATH}")
        return [] # Return empty if DB file doesn't exist
      end

      db = DuckDB::Database.open(DUCKDB_PATH)
      con = db.connect
      stmt = con.prepare(sql)
      # DuckDB gem uses 1-based indexing for bind params
      params.each_with_index { |param, i| stmt.bind(i + 1, param) }
      result_set = stmt.execute

      # Convert results into ProcessedPodcast objects
      result_set.each do |row|
        results << new(
          episode_url: row[0],
          # Handle potential date parsing issues if needed
          processed_at: row[1] ? Date.parse(row[1].to_s) : nil,
          summary_filename: row[2],
          podcast_name: row[3],
          host: row[4],
          guests: row[5]
        )
      end
      result_set.close
      stmt.close
    rescue DuckDB::Error => e
      Rails.logger.error("DuckDB Error executing query: #{e.message}\nSQL: #{sql}\nParams: #{params}")
      results = [] # Return empty on error
    rescue StandardError => e
       Rails.logger.error("Standard Error executing query: #{e.message}\nSQL: #{sql}\nParams: #{params}")
       results = []
    ensure
      con&.close
      db&.close
    end
    results
  end
end 