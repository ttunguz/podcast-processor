#!/usr/bin/env ruby
# frozen_string_literal: true

require 'open-uri'
require 'json'
require 'time'
require 'net/http'
require 'uri'
require 'cgi'
require 'duckdb'
require 'logger'
require 'shellwords' # Added for shell command escaping
require 'date' # Added for date parsing
require 'fileutils'   # For DailySummarizer
require 'digest/sha1' # For DailySummarizer filename fallback
require 'concurrent' # Added for parallelization
require 'open3' # Added for capturing command output
require 'mutex_m' # Added for Mutex
require 'nokogiri' # Added Nokogiri

# --- Configuration ---
PODCAST_URL_FILE = File.expand_path('podcast_urls.txt', __dir__)
DATABASE_FILE = 'podcast_processing.duckdb'
SUMMARY_DIR = File.expand_path('podcast_summaries', __dir__) # Define summary dir
PROCESSOR_SCRIPT = '/Users/tomasztunguz/Documents/coding/whisper.cpp/parakeet_podcast_processor.rb'
RECENCY_THRESHOLD_HOURS = 48 # Process podcasts published in the last X hours
USER_AGENT = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36' # Standard User Agent
PROCESSOR_POOL_SIZE = 8 # Increased from 4 - transcription is I/O bound (26% CPU), safe to increase

# --- Logging ---
LOGGER = Logger.new($stdout)
LOGGER.level = Logger::INFO

# --- Helper: Filename Generation (REMOVED) ---
# This function is no longer needed as the filename is captured from the processor script.

# --- Database Handling Class (Added summary_filename column) ---
class PodcastDatabase
  attr_reader :con # Allow reading the connection if needed elsewhere, though unlikely

  def initialize(db_file)
    @con = nil
    db = nil # Keep track of the database object
    begin
      LOGGER.debug("Attempting to open database: #{db_file}")
      db = DuckDB::Database.open(db_file)
      LOGGER.debug("Attempting to connect to database...")
      @con = db.connect
      LOGGER.debug("Connection successful. Attempting to create/verify table...")
      create_table # This is where the ALTER TABLE happens
      LOGGER.info("Database connection established and table verified for #{db_file}")
    rescue DuckDB::Error => e # Catch DuckDB errors specifically first
      LOGGER.error("DuckDB Error during initialization for #{db_file}: #{e.message}")
      LOGGER.error("Backtrace:\n#{e.backtrace.join("\n")}")
      @con&.close # Close connection if open
      db&.close   # Close database if open
      @con = nil # Ensure con is nil if initialization failed
    rescue StandardError => e # Catch other potential errors
      LOGGER.error("Standard Error during initialization for #{db_file}: #{e.message}")
      LOGGER.error("Backtrace:\n#{e.backtrace.join("\n")}")
      @con&.close # Close connection if open
      db&.close   # Close database if open
      @con = nil # Ensure con is nil if initialization failed
    end
  end

  def connected?
    !@con.nil?
  end

  def get_episodes_processed_since(date_obj) # Expects a Date object
    return [] unless connected?
    episodes = []
    begin
      # Select new columns
      sql = "SELECT episode_url, summary_filename, podcast_name, host, guests FROM processed_podcasts WHERE processed_at >= $1 ORDER BY processed_at;"
      result_set = @con.prepare(sql) do |stmt|
        stmt.bind(1, date_obj)
        stmt.execute
      end
      result_set.each do |row|
        # Store as hash with new fields
        episodes << { 
          url: row[0], 
          summary_filename: row[1], 
          podcast_name: row[2], 
          host: row[3], 
          guests: row[4] 
        } if row && row[0]
      end
    rescue DuckDB::Error => e
      LOGGER.error("DuckDB query error (get_episodes_processed_since): #{e.message}")
    end
    LOGGER.debug("Found #{episodes.count} DB records processed since #{date_obj}")
    episodes
  end

  def already_processed?(episode_url)
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

  def mark_as_processed(episode_url, summary_filename = nil, podcast_name = nil, host = nil, guests = nil, date_obj = Date.today)
    return false unless connected?
    begin
      sql = "INSERT OR REPLACE INTO processed_podcasts (episode_url, processed_at, summary_filename, podcast_name, host, guests) VALUES ($1, $2, $3, $4, $5, $6);"
      @con.prepare(sql) do |stmt|
        stmt.bind(1, episode_url)
        stmt.bind(2, date_obj)
        stmt.bind(3, summary_filename)
        stmt.bind(4, podcast_name) # Bind new field
        stmt.bind(5, host)         # Bind new field
        stmt.bind(6, guests)       # Bind new field
        stmt.execute
      end
      # Enhanced logging
      log_details = []
      log_details << "Podcast: #{podcast_name}" if podcast_name
      log_details << "Host: #{host}" if host
      log_details << "Guests: #{guests}" if guests
      log_details << "Summary: #{File.basename(summary_filename)}" if summary_filename
      LOGGER.info("Marked as processed: #{episode_url} on #{date_obj.strftime('%Y-%m-%d')} (#{log_details.join(', ')})")
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
    # Add new columns to CREATE TABLE statement
    @con.query(<<~SQL)
      CREATE TABLE IF NOT EXISTS processed_podcasts (
        episode_url TEXT PRIMARY KEY NOT NULL,
        processed_at TEXT NOT NULL, -- Store as ISO8601 string
        summary_filename TEXT NULL,
        podcast_name TEXT NULL, 
        host TEXT NULL,
        guests TEXT NULL
      );
    SQL
    LOGGER.info("Ensured processed_podcasts table exists (with summary_filename, podcast_name, host, guests).")

    # Check and add columns individually if they are missing
    table_info = @con.query("PRAGMA table_info(processed_podcasts);").each.to_a
    columns_to_add = {
      'summary_filename' => 'TEXT NULL',
      'podcast_name' => 'TEXT NULL',
      'host' => 'TEXT NULL',
      'guests' => 'TEXT NULL'
    }
    
    existing_columns = table_info.map { |col| col[1] }
    
    columns_to_add.each do |col_name, col_type|
      unless existing_columns.include?(col_name)
        LOGGER.warn("Column '#{col_name}' not found in processed_podcasts. Adding it...")
        @con.execute("ALTER TABLE processed_podcasts ADD COLUMN #{col_name} #{col_type};")
        LOGGER.info("Added '#{col_name}' column to processed_podcasts table.")
      end
    end

  rescue DuckDB::Error => e
     LOGGER.error("Failed to create/alter database table: #{e.message}")
  end
end

# --- Networking & Parsing (Using Nokogiri) ---

# NEW: Fetches raw HTML content from a URL
def fetch_raw_html(url_string)
  LOGGER.debug("Fetching raw HTML from: #{url_string}")
  begin
    html = URI.open(url_string, "User-Agent" => USER_AGENT, :read_timeout => 60).read
    LOGGER.debug("Successfully fetched raw HTML, size: #{html.length} bytes")
    return html
  rescue OpenURI::HTTPError => e
    LOGGER.error("HTTP error fetching raw HTML: #{e.message} for #{url_string}")
    return nil
  rescue SocketError, Errno::ECONNREFUSED => e
    LOGGER.error("Network error fetching raw HTML: #{e.message}")
    return nil
  rescue Net::OpenTimeout, Net::ReadTimeout, Timeout::Error => e
    LOGGER.error("Network timeout fetching raw HTML: #{e.message}")
    return nil
  rescue URI::InvalidURIError => e
    LOGGER.error("Invalid URL for fetching raw HTML: #{e.message}")
    return nil
  rescue => e
    LOGGER.error("Unexpected error fetching raw HTML for #{url_string}: #{e.message}")
    return nil
  end
end

# --- Podcast Episode Extraction (Using Nokogiri) ---

# NEW: Helper function to extract podcast name from Nokogiri Doc
def extract_podcast_name_from_html(nokogiri_doc)
  return 'Unknown Podcast' if nokogiri_doc.nil?
  # Try H1 first, then title tag as fallback
  h1_selector = 'h1.product-header__title' # Based on inspection of search result
  title_selector = 'title'
  
  name_element = nokogiri_doc.at_css(h1_selector)
  name = name_element ? name_element.text.strip : nil
  
  if name.nil? || name.empty?
    title_element = nokogiri_doc.at_css(title_selector)
    name = title_element ? title_element.text.strip : nil
  end

  if name
    # Clean the extracted name
    name.gsub!(/\s*-\s*Apple\s+Podcasts$/i, '')
    name.gsub!(/^\**|\**$/, '') # Remove potential markdown
    return name.strip unless name.empty?
  end

  'Unknown Podcast' # Fallback
end

# NEW: Extracts episode URLs and dates from Nokogiri Doc
def extract_episodes_from_html(nokogiri_doc, landing_page_url)
  episodes = []
  return episodes if nokogiri_doc.nil?
  
  # Selector for episode links - highly dependent on Apple's structure
  # This targets links within likely episode list items
  # episode_link_selector = 'ol.tracks a.link[href*="?i="]'
  # Selector based on testing with lenny_podcast_sample.html:
  episode_link_selector = 'ol[data-testid="episodes-list"] li div.episode a.link-action[href*="?i="]' # Updated selector
  
  nokogiri_doc.css(episode_link_selector).each do |link|
    begin
      episode_url = link['href']
      next unless episode_url && episode_url.match?(/\/id\d+\?i=\d+/)
      
      # Attempt to find date - look for time element nearby or in parent?
      # This is VERY speculative - needs inspection of actual HTML structure
      # Find a common ancestor that might contain both link and date
      # list_item = link.ancestors('li').first # Find parent list item
      # date_element = list_item&.at_css('time') # Look for <time> within parent li
      # Updated based on testing:
      common_ancestor = link.ancestors('li').first || link # Look within the list item containing the link
      date_element = common_ancestor&.at_css('p.episode-details__published-date[data-testid="episode-details__published-date"]') # Updated selector
      date_str = date_element ? date_element.text.strip : nil
      
      # Fallback: Look for text node sibling with date pattern? (Less reliable)
      if date_str.nil? && common_ancestor
         # Example: Find sibling spans/divs with date-like text
         potential_date_nodes = common_ancestor.css('span, div').select { |n| n.text.match?(/(ago|\b(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\b)/i) }
         date_str = potential_date_nodes.first&.text&.strip if potential_date_nodes.any?
      end

      unless date_str
        LOGGER.warn("Could not find date string for potential episode: #{episode_url}")
        next
      end

      parsed_date = parse_relative_date(date_str, landing_page_url)

      if parsed_date
        episodes << { url: episode_url, published_at: parsed_date }
        LOGGER.debug("Found potential episode via HTML: #{episode_url} published around #{parsed_date}")
      else
        LOGGER.warn("Could not parse date string '#{date_str}' for episode link: #{episode_url}")
      end
    rescue => e
       LOGGER.warn("Error processing potential episode link: #{link['href']} - #{e.message}")
    end
  end
  
  LOGGER.info("Extracted #{episodes.count} potential episodes via HTML parsing for #{landing_page_url}.")
  episodes.uniq { |e| e[:url] } # Return unique episodes based on URL
end

# Helper function to parse relative date strings
def parse_relative_date(date_str, context_url)
  now = Time.now.utc # Use UTC for consistency
  original_date_str = date_str # Keep original for logging
  date_str = date_str.strip

  # Handle simple relative dates like "X days/weeks/months/years ago"
  if (m = date_str.match(/^(\d+)\s+(day|week|month|year)s?\s+ago$/i))
    num = m[1].to_i
    unit = m[2].downcase
    case unit
    when 'day' then return (Date.today - num).to_time.utc
    when 'week' then return (Date.today - (num * 7)).to_time.utc
    # Approximations for month/year
    when 'month' then return (Date.today << num).to_time.utc # Go back num months
    when 'year' then return (Date.today << (num * 12)).to_time.utc # Go back num years
    end
  elsif (m = date_str.match(/^(\d+)\s+(hour|minute|min)s?\s+ago$/i))
      num = m[1].to_i
      unit = m[2].downcase
      seconds_ago = case unit
                    when 'hour' then num * 3600
                    when 'minute', 'min' then num * 60
                    else 0
                    end
      return now - seconds_ago
  # Add handling for compact "XD AGO" format
  elsif (m = date_str.match(/^(\d+)D\s+AGO$/i)) # Matches "1D AGO", "5D AGO", etc.
    num = m[1].to_i
    return (Date.today - num).to_time.utc
  # Add handling for compact "XH AGO" format
  elsif (m = date_str.match(/^(\d+)H\s+AGO$/i)) # Matches "18H AGO", etc.
    num = m[1].to_i
    return now - (num * 3600)
  end

  # Handle absolute dates like "Jan 15, 2024" or "Jan 15" or "2024-01-15" or "MM/DD/YYYY"
  begin
    # Try parsing common absolute formats directly with Date.parse first
    # It handles "YYYY-MM-DD", "MMM DD, YYYY", "MMM DD"
    # It *should* handle "MM/DD/YYYY" but might fail depending on system locale/settings
    parsed_date = Date.parse(date_str)
    parsed_time = parsed_date.to_time.utc

    # If year was missing (like "MMM DD") and parsed date is in the future, assume previous year
    if !date_str.match?(/\d{4}/) && parsed_time > now
      parsed_date = Date.parse("#{date_str} #{now.year - 1}") rescue parsed_date
      parsed_time = parsed_date.to_time.utc
    end
    return parsed_time

  rescue Date::Error, ArgumentError => e # Catch specific parsing errors
    # If Date.parse failed, specifically try the MM/DD/YYYY format
    if date_str.match?(%r{^\d{1,2}/\d{1,2}/\d{4}$})
      begin
        parsed_date = Date.strptime(date_str, '%m/%d/%Y')
        return parsed_date.to_time.utc
      rescue Date::Error, ArgumentError => strptime_e
        LOGGER.warn("Could not parse date string '#{original_date_str}' using strptime('%m/%d/%Y') after initial parse failed for #{context_url}. Error: #{strptime_e.message}")
        return nil
      end
    else
      # Log the original error if it wasn't the MM/DD/YYYY format we tried to rescue
      LOGGER.warn("Could not parse date string '#{original_date_str}' using standard Date.parse for #{context_url}. Error: #{e.message}")
      return nil
    end
  rescue => e # Catch other potential errors during parsing
    LOGGER.error("Unexpected error parsing date string '#{original_date_str}' for #{context_url}: #{e.message}")
    return nil
  end
end

# --- Daily Summarizer Class (Uses DB filename) ---
class DailySummarizer
  def initialize(database, summary_dir)
    @db = database
    @summary_dir = summary_dir # Note: summary_dir in orchestrator might not be needed by processor
    FileUtils.mkdir_p(@summary_dir)
  end

  def generate_summary_document
    today_str = Date.today.strftime('%Y-%m-%d')
    output_filename = "daily_summary_podcasts_#{today_str}.md"
    # Save directly inside the summary directory
    output_path = File.join(@summary_dir, output_filename)

    LOGGER.info("Generating daily summary document: #{output_path}")
    start_of_today_date = Date.today

    # Get hash including new fields: {url:, summary_filename:, podcast_name:, host:, guests:}
    processed_episodes = @db.get_episodes_processed_since(start_of_today_date)
    LOGGER.info("Found #{processed_episodes.count} episodes processed on or after #{start_of_today_date.strftime('%Y-%m-%d')}")

    unless processed_episodes.empty?
      begin
        File.open(output_path, 'w') do |outfile|
          outfile.puts("# Podcast Summaries for #{today_str}")
          outfile.puts("---<CUT>---")

          processed_episodes.each do |episode|
            # Extract data from the episode hash
            url = episode[:url]
            db_summary_filename = episode[:summary_filename]
            podcast_name = episode[:podcast_name] || 'Unknown Podcast' # Provide fallback
            host = episode[:host] || 'N/A' # Provide fallback
            guests = episode[:guests] || 'N/A' # Provide fallback

            # Updated header
            outfile.puts("\n## #{podcast_name} - Episode: #{url}")
            outfile.puts("Host(s): #{host}")
            outfile.puts("Guest(s): #{guests}\n") # Add newline for spacing

            # Logic for appending summary content (remains the same)
            if db_summary_filename && !db_summary_filename.empty?
              summary_filepath = db_summary_filename
              if File.exist?(summary_filepath)
                begin
                  raw_summary_content = File.read(summary_filepath)
                  summary_content_to_write = clean_summary_from_processor(raw_summary_content)
                  outfile.puts(summary_content_to_write)
                  LOGGER.debug("Appended summary for: #{url} from #{File.basename(summary_filepath)}")
                rescue StandardError => e
                  LOGGER.error("Failed to read summary file #{summary_filepath}: #{e.message}")
                  outfile.puts("*Error reading summary file.*")
                end
              else
                LOGGER.error("Summary file path from DB does not exist: #{summary_filepath} for URL: #{url}")
                outfile.puts("*Summary file path recorded in DB, but file not found.*")
              end
            else
              LOGGER.warn("No summary filename recorded in DB for episode #{url}")
              outfile.puts("*Summary filename not recorded in database.*")
            end
            outfile.puts("\n---<CUT>---")
          end
        end
        LOGGER.info("Successfully generated daily summary: #{output_path}")
        return output_path # Return the path if successful
      rescue StandardError => e
        LOGGER.error("Failed to write daily summary document #{output_path}: #{e.message}")
        return nil # Return nil on error
      end
    else
      LOGGER.info("No episodes processed today. Skipping summary generation.")
      return nil # Return nil if no episodes
    end
  end

  private

  def clean_summary_from_processor(content)
    # Regex to match the block:
    # Starts with "--- Podcast Metadata ---"
    # Ends with "------------------------"
    # Allows any characters (including newlines) in between, non-greedy.
    # Anchored to start of lines with ^
    # The /m modifier makes . match newline characters.
    block_regex = /^--- Podcast Metadata ---
(?:.|
)*?^------------------------
?/m

    if content.match?(block_regex)
      cleaned_content = content.sub(block_regex, '')
      LOGGER.info("Removed metadata block from processor's summary content.")
      return cleaned_content.strip # Also strip leading/trailing whitespace from the whole cleaned content
    else
      LOGGER.debug("Standard processor metadata block not found in its summary content. Using raw content.")
      return content # Return original if block not found
    end
  end
end

# --- Clean Markdown Email Function ---
def send_email_with_summary(summary_file_path, recipient_email)
  return unless summary_file_path && File.exist?(summary_file_path)

  original_summary_content = File.read(summary_file_path)
  
  # Clean up the markdown for better email readability
  email_content = clean_summary_for_email(original_summary_content)
  
  email_script_path = File.expand_path('~/.mutt/msmtp-enqueue.sh')
  subject = "🎧 Podcast Digest - #{Date.today.strftime('%B %d, %Y')}"
  from_address = "podcast-digest@theory.ventures"

  email_data = <<~EMAIL
  To: #{recipient_email}
  From: #{from_address}
  Subject: #{subject}
  Content-Type: text/plain; charset="UTF-8"

  #{email_content}
  EMAIL

  begin
    unless File.executable?(email_script_path)
      LOGGER.error("msmtp-enqueue.sh not found or not executable at #{email_script_path}")
      return
    end

    stdout, stderr, status = Open3.capture3(email_script_path, '-t', stdin_data: email_data)

    if status.success?
      LOGGER.info("Successfully sent markdown email to #{recipient_email}.")
      LOGGER.debug("msmtp-enqueue stdout: #{stdout}") unless stdout.empty?
    else
      LOGGER.error("Failed to send email via #{email_script_path} for recipient #{recipient_email}.")
      LOGGER.error("msmtp-enqueue stderr: #{stderr}") unless stderr.empty?
      LOGGER.error("msmtp-enqueue exit status: #{status.exitstatus}")
    end
  rescue StandardError => e
    LOGGER.error("Error executing email script #{email_script_path}: #{e.message}")
  end
end

# --- Clean Summary for Email ---
def clean_summary_for_email(content)
  lines = content.split("\n")
  cleaned_lines = []
  
  # Add enhanced header
  cleaned_lines << "🎧 PODCAST DIGEST - #{Date.today.strftime('%A, %B %d, %Y').upcase}"
  cleaned_lines << "═" * 64
  cleaned_lines << ""
  
  # Process each line
  in_episode = false
  episode_count = 0
  skip_section = false  # Use local variable instead of instance variable
  
  lines.each do |line|
    case line.strip
    when /^# Podcast Summaries/
      next # Skip main header
    when /^## (.+) - Episode: (.+)$/
      # Episode header with enhanced formatting
      podcast_name = $1
      episode_url = $2
      episode_count += 1
      in_episode = true
      
      cleaned_lines << ""
      cleaned_lines << "📈 #{episode_count}. #{podcast_name.upcase}"
      cleaned_lines << "─" * 64
      cleaned_lines << "🔗 #{episode_url}"
    when /^Host\(s\): (.+)$/
      cleaned_lines << "👤 Host: #{$1}"
    when /^Guest\(s\): (.+)$/
      cleaned_lines << "🎙️  Guests: #{$1}"
      cleaned_lines << ""
    when /^---<CUT>---$/
      if in_episode
        cleaned_lines << ""
        cleaned_lines << "─" * 64
        in_episode = false
      end
      next
    when ""
      cleaned_lines << line if in_episode # Preserve spacing within episodes
    else
      # Regular content with enhanced formatting
      if in_episode
        clean_line = line.dup
        
                  # Convert headers with visual indicators - skip certain sections
          if clean_line.match(/^\*\*(\d+)\. (.+):\*\*$/)
            section_num = $1.to_i
            section_name = $2
            # Skip sections 3 (Investment Theses) and 4 (Noteworthy Observations)
            if section_num == 3 && section_name.include?("Investment Theses")
              skip_section = true
              next
            elsif section_num == 4 && section_name.include?("Noteworthy Observations")
              skip_section = true
              next
            else
              skip_section = false
              cleaned_lines << ""
              cleaned_lines << "    🎯 #{section_num}. #{section_name.upcase}:"
              cleaned_lines << ""
            end
          elsif clean_line.match(/^\*\*(.+):\*\*$/)
            # Other bold headers like "**Overall Summary:**"
            next if skip_section
            cleaned_lines << ""
            cleaned_lines << "    ▶ #{$1.upcase}:"
            cleaned_lines << ""
          elsif clean_line.match(/^## (.+)$/)
            next if skip_section
            cleaned_lines << ""
            cleaned_lines << "    ▶ #{$1.upcase}:"
            cleaned_lines << ""
          elsif clean_line.match(/^### (.+)$/)
            next if skip_section
            cleaned_lines << ""
            cleaned_lines << "    ▶ #{$1}:"
          elsif clean_line.match(/^\* (.+)$/) || clean_line.match(/^- (.+)$/)
            next if skip_section
            cleaned_lines << "      • #{$1}"
          elsif clean_line.match(/^\d+\. (.+)$/)
            next if skip_section
            cleaned_lines << "      #{clean_line}"
                  else
            # Skip content if we're in a skipped section
            next if skip_section
            
            # Handle special content types
            if clean_line.strip.match(/^Quote: "(.+)"$/)
              # Handle "Quote: ..." format
              cleaned_lines << ""
              cleaned_lines << "    💬 \"#{$1}\""
              cleaned_lines << ""
            elsif clean_line.include?('"') && clean_line.length > 50
              # Format long quotes with indentation
              clean_line.gsub!(/\*\*(.+?)\*\*/, '\1')
              if clean_line.strip.start_with?('"') || clean_line.include?('Quote:')
                cleaned_lines << ""
                cleaned_lines << "    💬 #{clean_line.strip}"
                cleaned_lines << ""
              else
                cleaned_lines << "      #{clean_line.strip}" unless clean_line.strip.empty?
              end
            elsif clean_line.strip.match(/^Title: "(.+)"$/)
              # Handle blog post titles
              cleaned_lines << "      📝 #{$1}"
            elsif clean_line.strip.match(/^Core [Aa]rgument: (.+)$/)
              # Handle blog post core arguments
              cleaned_lines << "      💡 #{$1}"
            elsif clean_line.strip.match(/^(\d+)\.\s+(.+)\s+-\s+(.+)\s+\((.+)\)$/)
              # Handle company listings like "1. Company Name - Description (URL)"
              cleaned_lines << "      🏢 #{$2} - #{$3}"
            elsif clean_line.strip.match(/^\$[\d,]+[BMK]?|\b\d+%|\b\d+[BMK]?\s+(users|customers|employees|revenue|ARR|valuation)/i)
              # Handle metrics and numbers
              cleaned_lines << "      📊 #{clean_line.strip}"
            elsif clean_line.strip.match(/^(Book|Paper|Study|Tool|Platform|Resource):\s*(.+)$/i)
              # Handle follow-up resources
              resource_type = $1
              resource_name = $2
              emoji = case resource_type.downcase
                      when 'book' then '📚'
                      when 'paper', 'study' then '📄'
                      when 'tool', 'platform' then '🛠️'
                      else '🔗'
                      end
              cleaned_lines << "      #{emoji} #{resource_name}"
            else
              # Regular text - remove bold markdown and add proper indentation
              clean_line.gsub!(/\*\*(.+?)\*\*/, '\1')
              unless clean_line.strip.empty?
                cleaned_lines << "      #{clean_line.strip}"
              end
            end
          end
      end
    end
  end
  
  # Add enhanced footer
  cleaned_lines << ""
  cleaned_lines << "═" * 64
  cleaned_lines << "📊 PROCESSED #{episode_count} EPISODES TODAY"
  cleaned_lines << "🤖 Generated by Theory Ventures AI • Parakeet MLX + Claude"
  cleaned_lines << "⏱️  Processing completed at #{Time.now.strftime('%I:%M %p')}"
  cleaned_lines << ""
  
  cleaned_lines.join("\n")
end

# --- Main Orchestration Logic (Capture Output) ---
def main
  LOGGER.info("Starting Parallel Podcast Orchestrator...")
  unless File.exist?(PODCAST_URL_FILE)
    LOGGER.fatal("Input file not found: #{PODCAST_URL_FILE}. Please create it with one podcast landing page URL per line.")
    exit(1)
  end

  db = PodcastDatabase.new(DATABASE_FILE)
  unless db.connected?
    LOGGER.fatal("Failed to connect to database. Exiting.")
    exit(1)
  end

  podcast_source_urls = File.readlines(PODCAST_URL_FILE, chomp: true).map(&:strip).reject(&:empty?).reject { |line| line.start_with?('#') }.uniq
  LOGGER.info("Found #{podcast_source_urls.count} unique podcast source URLs to check.")

  # Create a Mutex for synchronizing chdir
  chdir_mutex = Mutex.new

  # --- Separate episode URLs from landing page URLs --- 
  direct_episode_urls = []
  landing_page_urls = []
  episode_url_regex = /\/id\d+\?i=\d+/ # Regex to identify episode URLs

  podcast_source_urls.each do |url|
    if url.match?(episode_url_regex)
      direct_episode_urls << url
    else
      landing_page_urls << url
    end
  end
  LOGGER.info("Identified #{direct_episode_urls.count} direct episode URLs and #{landing_page_urls.count} landing page URLs.")

  # --- Process Landing Pages (Fetch HTML & Extract with Nokogiri) --- 
  extracted_episodes_from_landing = []
  if landing_page_urls.any?
    LOGGER.info("Fetching landing page HTML concurrently (Pool Size: #{PROCESSOR_POOL_SIZE})...") # Adjusted pool size name if desired
    html_fetch_pool = Concurrent::ThreadPoolExecutor.new(
      min_threads: 1,
      max_threads: PROCESSOR_POOL_SIZE, # Use general processor pool size
      max_queue: landing_page_urls.count * 2 
    )
    fetch_futures = landing_page_urls.map do |landing_page_url|
      Concurrent::Future.execute(executor: html_fetch_pool) do
        html_string = fetch_raw_html(landing_page_url) 
        # No sleep needed here, fetches are local/faster than API
        [landing_page_url, html_string]
      end
    end
    fetched_html_data = fetch_futures.map(&:value).compact.to_h
    html_fetch_pool.shutdown
    html_fetch_pool.wait_for_termination(600)
    LOGGER.info("Finished fetching HTML for #{fetched_html_data.count}/#{landing_page_urls.count} pages.")

    LOGGER.info("Parsing HTML and extracting episodes...")
    time_threshold = Time.now.utc - (RECENCY_THRESHOLD_HOURS * 3600)
    fetched_html_data.each do |landing_page_url, html_string|
      if html_string.nil? || html_string.empty?
        LOGGER.warn("No HTML content fetched for #{landing_page_url}, skipping extraction.")
        next
      end
      
      # Parse HTML with Nokogiri
      nokogiri_doc = Nokogiri::HTML(html_string)
      unless nokogiri_doc
        LOGGER.warn("Failed to parse HTML for #{landing_page_url}, skipping extraction.")
        next
      end
      
      podcast_name = extract_podcast_name_from_html(nokogiri_doc)
      LOGGER.debug("Extracting episodes from '#{podcast_name}' (HTML): #{landing_page_url}")
      
      episodes = extract_episodes_from_html(nokogiri_doc, landing_page_url)
      episodes.each do |episode|
        if episode[:published_at] && episode[:published_at] >= time_threshold
           extracted_episodes_from_landing << { url: episode[:url], podcast_name: podcast_name, published_at: episode[:published_at] }
        else
           reason = episode[:published_at] ? "old" : "no date parsed"
           LOGGER.debug("Skipping episode from landing page (#{reason}): #{episode[:url]}")
        end
      end
    end
  end
  # --- End Landing Page Processing --- 

  # --- Combine and Filter Episodes --- 
  LOGGER.info("Filtering all potential episodes (direct + extracted)...")
  new_episodes_to_process = [] 
  processed_landing_page_names = {} 

  # Filter direct episode URLs
  direct_episode_urls.each do |episode_url|
    if db.already_processed?(episode_url)
      LOGGER.debug("Skipping already processed direct URL: #{episode_url}")
    else
      LOGGER.info("Found new direct episode URL: #{episode_url}")
      
      # --- Get Podcast Name for Direct URL (using Nokogiri now) ---
      podcast_id_match = episode_url.match(/\/id(\d+)/)
      podcast_name = 'Unknown Podcast' # Default
      if podcast_id_match
        podcast_id = podcast_id_match[1]
        landing_page_url_for_name = "https://podcasts.apple.com/us/podcast/id#{podcast_id}"
        
        if processed_landing_page_names.key?(landing_page_url_for_name)
          podcast_name = processed_landing_page_names[landing_page_url_for_name]
          LOGGER.debug("Using cached podcast name '#{podcast_name}' for #{episode_url}")
        else
          LOGGER.info("Fetching landing page HTML for name: #{landing_page_url_for_name}")
          html_for_name = fetch_raw_html(landing_page_url_for_name)
          if html_for_name
            doc_for_name = Nokogiri::HTML(html_for_name)
            if doc_for_name
              podcast_name = extract_podcast_name_from_html(doc_for_name)
              processed_landing_page_names[landing_page_url_for_name] = podcast_name
              LOGGER.info("Extracted podcast name '#{podcast_name}' for #{episode_url}")
            else
               LOGGER.warn("Could not parse landing page HTML to get podcast name for #{episode_url}")
               processed_landing_page_names[landing_page_url_for_name] = podcast_name
            end
          else
            LOGGER.warn("Could not fetch landing page HTML to get podcast name for #{episode_url}")
            processed_landing_page_names[landing_page_url_for_name] = podcast_name
          end
          # No sleep needed for local fetch
        end
      else 
        LOGGER.warn("Could not extract podcast ID from direct URL: #{episode_url}")
      end
      # --- End Get Podcast Name ---
      
      new_episodes_to_process << { url: episode_url, podcast_name: podcast_name }
    end
  end

  # Filter episodes extracted from landing pages
  extracted_episodes_from_landing.each do |episode|
    if db.already_processed?(episode[:url])
      LOGGER.debug("Skipping already processed extracted URL: #{episode[:url]}")
    else
      LOGGER.info("Found new extracted episode for '#{episode[:podcast_name]}': #{episode[:url]}")
      new_episodes_to_process << { url: episode[:url], podcast_name: episode[:podcast_name] }
    end
  end

  unique_new_episodes = new_episodes_to_process.uniq { |ep| ep[:url] }
  LOGGER.info("Found #{unique_new_episodes.count} total unique new episodes to process.")

  # --- Parallel Episode Processing (Capture Output & Synchronized chdir) --- 
  processed_count = 0
  failed_count = 0
  processor_results = [] # Store { url:, success:, summary_filename:, podcast_name:, host:, guests: }

  if unique_new_episodes.any?
    LOGGER.info("Processing new episodes concurrently (Pool Size: #{PROCESSOR_POOL_SIZE})...")
    processor_pool = Concurrent::ThreadPoolExecutor.new(
      min_threads: 1,
      max_threads: PROCESSOR_POOL_SIZE,
      max_queue: unique_new_episodes.count * 2
    )
    processor_dir = File.dirname(PROCESSOR_SCRIPT)

    processing_futures = unique_new_episodes.map do |episode| # episode is {url:, podcast_name: (can be nil)}
      Concurrent::Future.execute(executor: processor_pool) do
        LOGGER.info("Starting processing for: #{episode[:url]}")
        start_time = Time.now
        success = false
        stdout_str = ''
        stderr_str = ''
        status = nil
        summary_file = nil
        captured_show_name = nil # NEW
        captured_host = nil
        captured_guests = nil

        begin
          chdir_mutex.synchronize do
            Dir.chdir(processor_dir) do
              # Modify command to redirect stderr to stdout for capture
              cmd = "ruby #{File.basename(PROCESSOR_SCRIPT)} #{Shellwords.escape(episode[:url])} 2>&1"
              LOGGER.debug("Executing command in #{Dir.pwd}: #{cmd}")
              
              # Use popen3 to capture combined output and status
              stdout_stderr_str, status = Open3.capture2e(cmd)
              success = status.success?

              # Assign combined output to stdout_str for parsing
              stdout_str = stdout_stderr_str 
              # Clear stderr_str as it's now included in stdout_str
              stderr_str = "" 

              if success
                # Parse combined stdout/stderr for markers
                stdout_str.each_line do |line|
                  line.strip!
                  if line.start_with?('SUMMARY_FILE:')
                    summary_file_relative = line.split(':', 2)[1]&.strip
                    if summary_file_relative && !summary_file_relative.empty?
                      absolute_summary_file = File.expand_path(summary_file_relative, __dir__)
                      summary_file = absolute_summary_file
                      LOGGER.debug("Captured summary file: #{summary_file}")
                    end
                  elsif line.start_with?('SHOW_NAME:') # Capture SHOW_NAME
                    captured_show_name = line.split(':', 2)[1]&.strip
                    LOGGER.debug("Captured show name: #{captured_show_name}")
                  elsif line.start_with?('HOST:')
                    captured_host = line.split(':', 2)[1]&.strip
                    LOGGER.debug("Captured host: #{captured_host}")
                  elsif line.start_with?('GUESTS:')
                    captured_guests = line.split(':', 2)[1]&.strip
                    LOGGER.debug("Captured guests: #{captured_guests}")
                  end
                end
                LOGGER.warn("Processor script succeeded but did not output SUMMARY_FILE: line for #{episode[:url]}") unless summary_file
                # Optional: Warn if host/guests markers are missing?
                LOGGER.debug("Host or Guests markers not found in output for #{episode[:url]}") if captured_host.nil? || captured_guests.nil?
              else
                # Log the combined output on failure
                LOGGER.error("Processor script failed for #{episode[:url]}. Status: #{status.exitstatus}. Combined Output: #{stdout_str.strip}")
              end
            end # End Dir.chdir block
          end # End Mutex synchronize block
        rescue StandardError => e
          LOGGER.error("Error during processor execution or chdir for #{episode[:url]}: #{e.message}")
          success = false
        end

        # Determine final podcast name: use from input if available, else use captured show name
        final_podcast_name = episode[:podcast_name] || captured_show_name || 'Unknown Podcast'
        
        end_time = Time.now
        duration = end_time - start_time
        status_msg = success ? "successfully" : "failed"
        LOGGER.info("Finished processing #{episode[:url]} for '#{final_podcast_name}' #{status_msg} in #{duration.round(2)} seconds.")
        
        # Return hash including final podcast_name, host, and guests
        {
          url: episode[:url],
          success: success,
          summary_filename: summary_file,
          podcast_name: final_podcast_name,
          host: captured_host,
          guests: captured_guests
        }
      end
    end

    processor_results = processing_futures.map(&:value).compact
    processor_pool.shutdown
    processor_pool.wait_for_termination
    LOGGER.info("Finished concurrent processing of all episodes.")
  else
      LOGGER.info("No new episodes to process.")
  end
  # --- End Parallel Episode Processing ---

  # --- Sequential Database Marking (Uses updated results hash) --- 
  LOGGER.info("Marking processed episodes in database sequentially...")
  processor_results.each do |result|
      if result[:success]
          # Pass all captured/determined fields to mark_as_processed
          if db.mark_as_processed(result[:url], result[:summary_filename], result[:podcast_name], result[:host], result[:guests])
              processed_count += 1
          else
              LOGGER.warn("Processed #{result[:url]} successfully but failed to mark as processed in DB.")
              failed_count += 1
          end
      else
          failed_count += 1
      end
  end
  LOGGER.info("Finished marking database. Final counts - Processed: #{processed_count}, Failed: #{failed_count}")
  # --- End Sequential Database Marking --- 

  LOGGER.info("Orchestration finished processing episodes.")

  # --- Generate Daily Summary (Uses DB Filename) --- 
  LOGGER.info("Attempting to generate daily summary...")
  summarizer = DailySummarizer.new(db, SUMMARY_DIR)
  daily_summary_file_path = summarizer.generate_summary_document
  # --- End Daily Summary --- 

  # --- Send Email with Daily Summary ---
  if daily_summary_file_path
    recipient_email = 'tt@theory.ventures' # Your email address
    LOGGER.info("Attempting to email daily summary to #{recipient_email}...")
    send_email_with_summary(daily_summary_file_path, recipient_email)
  else
    LOGGER.info("No daily summary file generated, skipping email.")
  end
  # --- END Send Email ---

ensure
  db&.close
end

# --- Run ---
main if __FILE__ == $PROGRAM_NAME 