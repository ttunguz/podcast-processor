require 'net/http'
require 'json'
require 'uri'
require 'fileutils'

def generate_summary(transcript_content)
  puts "[DEBUG] Starting generate_summary with transcript size: #{transcript_content.size} bytes"
  
  if ENV["ANTHROPIC_API_KEY"].nil? || ENV["ANTHROPIC_API_KEY"].empty?
    puts "[DEBUG] ANTHROPIC_API_KEY environment variable is not set or empty!"
    puts "Error: ANTHROPIC_API_KEY environment variable is not set. Cannot generate summary."
    return nil
  end
  
  uri = URI.parse("https://api.anthropic.com/v1/messages")
  request = Net::HTTP::Post.new(uri)
  request.content_type = "application/json"
  request["x-api-key"] = ENV["ANTHROPIC_API_KEY"]
  request["anthropic-version"] = "2023-06-01"

  request.body = JSON.dump({
    "model" => "claude-3-opus-20240229",
    "max_tokens" => 4096,
    "messages" => [
      {
        "role" => "user",
        "content" => "Please analyze this podcast transcript and provide a structured summary. Focus on key insights, notable technologies, companies mentioned, and people mentioned. Format the response with clear sections and bullet points where appropriate. Here's the transcript:\n\n#{transcript_content}"
      }
    ]
  })

  puts "[DEBUG] Sending request to Anthropic API..."
  response = nil
  begin
    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
      # Set timeouts
      http.open_timeout = 60 # seconds
      http.read_timeout = 300 # seconds
      http.request(request)
    end
    puts "[DEBUG] Received response from Anthropic API, status: #{response.code}"
  rescue Net::OpenTimeout => e
    puts "[DEBUG] Error: API request timed out (open): #{e.message}"
    puts "Error communicating with Anthropic API: Connection timed out."
    return nil
  rescue Net::ReadTimeout => e
    puts "[DEBUG] Error: API request timed out (read): #{e.message}"
    puts "Error communicating with Anthropic API: Reading response timed out."
    return nil
  rescue => e
    puts "[DEBUG] Error during API request: #{e.message}"
    puts "Error communicating with Anthropic API: #{e.message}"
    return nil
  end

  if response.code == "200"
    begin
      result = JSON.parse(response.body)
      summary = result["content"][0]["text"]
      puts "[DEBUG] Successfully parsed summary, size: #{summary.size} bytes"
      return summary
    rescue JSON::ParserError => e
      puts "[DEBUG] Error parsing JSON response: #{e.message}"
      puts "Error: Invalid response received from Anthropic API."
      puts "[DEBUG] Response Body: #{response.body[0..500]}..."
      return nil
    rescue => e
      puts "[DEBUG] Error processing API response: #{e.message}"
      puts "Error processing response from Anthropic API."
      return nil
    end
  else
    puts "[DEBUG] API error: #{response.code} - #{response.body}"
    puts "Error: Anthropic API returned status #{response.code}"
    return nil
  end
end

if __FILE__ == $0
  if ARGV.length != 2
    puts "Usage: ruby #{__FILE__} <transcript_file> <output_summary_file>"
    exit 1
  end

  transcript_file = ARGV[0]
  output_file = ARGV[1]

  unless File.exist?(transcript_file)
    puts "Error: Transcript file not found at #{transcript_file}"
    exit 1
  end

  puts "Reading transcript from: #{transcript_file}"
  transcript_content = File.read(transcript_file)

  puts "Attempting to generate summary..."
  summary = generate_summary(transcript_content)

  if summary
    puts "Writing summary to: #{output_file}"
    begin
      File.write(output_file, summary)
      puts "\nSUCCESS: Summary generated and saved to #{output_file}"
      puts "Summary first 200 chars: #{summary[0..200]}..."
      exit 0
    rescue => e
      puts "Error writing summary file: #{e.message}"
      exit 1
    end
  else
    puts "\nFAILURE: Summary generation failed."
    exit 1
  end
end 