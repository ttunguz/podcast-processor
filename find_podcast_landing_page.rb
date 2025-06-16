#!/usr/bin/env ruby

require 'httparty'
require 'nokogiri'

# Check if a URL argument is provided
if ARGV.empty?
  puts "Usage: ruby find_podcast_landing_page.rb <apple_podcasts_url>"
  exit(1)
end

url = ARGV[0]

begin
  # Fetch the HTML content
  response = HTTParty.get(url, headers: {
    # Some sites might block requests without a common user agent
    'User-Agent' => 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/58.0.3029.110 Safari/537.36'
  })

  unless response.success?
    puts "Error: Failed to fetch URL #{url}. Status code: #{response.code}"
    exit(1)
  end

  # Parse the HTML
  doc = Nokogiri::HTML(response.body)

  # Find the canonical link tag
  canonical_link = doc.at_css('link[rel="canonical"]')

  if canonical_link && canonical_link['href']
    puts canonical_link['href'] # Output the found URL
  else
    puts "Error: Could not find the canonical URL on the page."
    exit(1)
  end

rescue HTTParty::Error => e
  puts "Error fetching URL: #{e.message}"
  exit(1)
rescue SocketError => e
  puts "Error connecting: #{e.message}"
  exit(1)
rescue StandardError => e
  puts "An unexpected error occurred: #{e.message}"
  exit(1)
end