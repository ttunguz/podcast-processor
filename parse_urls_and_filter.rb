#!/usr/bin/env ruby

require 'uri'
require 'set'
require 'net/http'
require 'json'
require 'time' # For date comparison

# --- Helper Functions ---

# Updated Harmonic API Key function (from user)
def self.get_harmonic_token
  #token = `op read "op://Personal/HarmonicAPI/password"`

  token = ENV['HARMONIC_API_KEY'] || raise("Missing HARMONIC_API_KEY environment variable")
  #token = `pass harmonic`.strip
  return token
end

# Cleans a URL string to get a normalized domain
def clean_domain(url_string)
  return nil if url_string.nil? || url_string.empty?
  begin
    # Ensure scheme is present for URI.parse
    url_string = "http://#{url_string}" unless url_string.start_with?('http://', 'https://')
    uri = URI.parse(url_string)
    domain = uri.host
    domain&.sub(/^www\./, '') # Remove www. prefix
  rescue URI::InvalidURIError
    puts "[WARN] Invalid URL skipped: #{url_string}"
    nil
  end
end

# Simple formatter (from sample, handles nil)
def format_element_simple(value)
  value.nil? ? '' : value.to_s
end

# --- Harmonic API Interaction & Filtering ---

# Queries Harmonic for a single domain
def query_harmonic_for_domain(domain, api_key)
  return nil if domain.nil? || domain.empty?

  uri = URI("https://api.harmonic.ai/companies?website_domain=#{domain}")
  headers = { 'apikey' => api_key, 'accept' => 'application/json', 'content-type' => 'application/json' }
  body = {}.to_json # Empty body for POST as per sample

  puts "[DEBUG] Querying Harmonic for domain: #{domain}"
  begin
    response = Net::HTTP.post(uri, body, headers)

    unless response.is_a?(Net::HTTPSuccess)
      puts "[WARN] Harmonic API request failed for domain '#{domain}'. Status: #{response.code}, Body: #{response.body[0..200]}..."
      return nil
    end

    json_data = JSON.parse(response.body)
    puts "[DEBUG] Received data for domain: #{domain}" # Often the API returns a list, even for a single domain query
    # Assuming the API returns a list and we take the first relevant entry
    # Adjust this logic if the API behaves differently
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
  return false unless company_data # Skip if no data

  # 1. Founded in last 4 years
  begin
    founded_date_str = company_data.dig("founding_date", "date")
    if founded_date_str
      founded_date = Time.parse(founded_date_str)
      four_years_ago = Time.now - (4 * 365 * 24 * 60 * 60) # Approx 4 years
      unless founded_date >= four_years_ago
        puts "[FILTER] Skipping #{company_data['name']}: Founded before 4 years ago (#{founded_date.year})"
        return false
      end
    else
      puts "[FILTER] Skipping #{company_data['name']}: Missing founding date."
       return false # Skip if no founding date
    end
  rescue ArgumentError # Handle invalid date formats
    puts "[FILTER] Skipping #{company_data['name']}: Invalid founding date format."
    return false
  end

  # 2. Funding <= $20M
  total_funding = company_data.dig("funding", "funding_total")
  # Treat nil funding as 0 for the check
  unless total_funding.nil? || total_funding <= 20_000_000
    puts "[FILTER] Skipping #{company_data['name']}: Funding > $20M ($#{total_funding || 0})"
    return false
  end

  # 3. Customer Type is B2B
  customer_type = company_data.dig("customer_type")
  unless customer_type == "B2B"
    puts "[FILTER] Skipping #{company_data['name']}: Customer type is not B2B (#{customer_type || 'N/A'})"
    return false
  end

  # 4. Location is US
  country = company_data.dig("location", "country")
  # Handle variations like "USA", "United States", case-insensitivity
  is_us = country && ["USA", "UNITED STATES"].include?(country.upcase)
  unless is_us
    puts "[FILTER] Skipping #{company_data['name']}: Location not in US (#{country || 'N/A'})"
    return false
  end

  # If all checks pass
  puts "[FILTER] Keeping #{company_data['name']}: Meets all criteria."
  return true
end

# --- Main Execution Logic ---
if __FILE__ == $0
  if ARGV.length != 1
    puts "Usage: ruby #{__FILE__} <summary_file_path>"
    exit 1
  end

  summary_file = ARGV[0]
  harmonic_api_key = get_harmonic_token # Get API key early

  unless File.exist?(summary_file)
    puts "Error: Summary file not found at '#{summary_file}'"
    exit 1
  end

  puts "Reading summary from: #{summary_file}"
  begin
    summary_content = File.read(summary_file)
  rescue => e
    puts "Error reading file '#{summary_file}': #{e.message}"
    exit 1
  end

  # Regex to find http and https URLs
  url_regex = /(https?:\/\/[^\s<>"'\\]+)/i
  found_urls = summary_content.scan(url_regex).flatten.map(&:strip).to_set

  puts "\n--- Found Unique URLs (#{found_urls.size}) ---"
  if found_urls.empty?
    puts "No URLs found in the summary."
  else
    found_urls.each { |url| puts url }
  end

  # Extract unique, valid domains from URLs
  domains_to_query = found_urls.map { |url| clean_domain(url) }.compact.to_set
  puts "\n--- Unique Domains Extracted (#{domains_to_query.size}) ---"
  domains_to_query.each { |domain| puts domain }

  # Query Harmonic for each domain
  puts "\n--- Querying Harmonic API ---"
  harmonic_results = domains_to_query.map do |domain|
    query_harmonic_for_domain(domain, harmonic_api_key)
  end.compact # Remove nil results from failed queries

  # Filter results based on criteria
  puts "\n--- Filtering Harmonic Results ---"
  potential_investments = harmonic_results.select { |company_data| filter_company_data(company_data) }

  # Output the filtered companies
  puts "\n--- Potential Early-Stage VC Investments (#{potential_investments.size}) ---"
  if potential_investments.empty?
    puts "No companies found matching the criteria."
  else
    potential_investments.each do |company|
      puts "- Name: #{company['name']}"
      puts "  Domain: #{company.dig('website', 'domain')}"
      puts "  Founded: #{company.dig('founding_date', 'date')}"
      puts "  Funding: $#{company.dig('funding', 'funding_total') || 0}"
      puts "  Location: #{company.dig('location', 'city')}, #{company.dig('location', 'state')}, #{company.dig('location', 'country')}"
      puts "  Description: #{company['description']}"
      puts "-----"
    end
  end

  puts "\nScript finished."
end 