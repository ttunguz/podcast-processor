require 'net/http'
require 'json'
require 'uri'
require 'fileutils'

def generate_summary(transcript_file)
  puts "[DEBUG] Starting generate_summary with transcript file: #{transcript_file}"
  
  # Check if transcript file exists
  unless File.exist?(transcript_file)
    puts "Error: Transcript file does not exist: #{transcript_file}"
    exit 1
  end
  
  # Read transcript content
  transcript_content = File.read(transcript_file)
  
  api_key = ENV["ANTHROPIC_API_KEY"]
  if api_key.nil? || api_key.empty?
    puts "[DEBUG] ANTHROPIC_API_KEY environment variable is not set or empty!"
    puts "Warning: ANTHROPIC_API_KEY environment variable is not set. Skipping summary generation."
    return "No summary available - ANTHROPIC_API_KEY not set.\n\nTranscript first 1000 chars:\n\n#{transcript_content[0..1000]}...\n\n(Full transcript content was not processed due to missing API key)"
  end
  
  uri = URI.parse("https://api.anthropic.com/v1/messages")
  request = Net::HTTP::Post.new(uri)
  request.content_type = "application/json"
  request["x-api-key"] = api_key
  request["anthropic-version"] = "2023-06-01"

  request.body = JSON.dump({
    "model" => "claude-3-opus-20240229",
    "max_tokens" => 4096,
    "messages" => [
      {
        "role" => "user",
        "content" => <<~PROMPT
          Please analyze the following podcast transcript and provide a structured summary based on these points:
          
          1.  **Major Themes & Technology Trends:** Identify the key overarching themes or technology trends discussed. Support each theme/trend with a representative quote from the transcript.
          2.  **Areas of Discussion/Debate:** Summarize the main topics where speakers discussed different viewpoints or debated specific points. Support each area with a representative quote illustrating the discussion or debate.
          3.  **Potential Investment Ideas:** Identify any potential investment ideas suitable for an early-stage venture capital firm that emerge from the conversation. Briefly explain the idea and why it might be relevant.
          4.  **Surprising/Counterintuitive Observations:** Summarize any observations made by the speakers that were surprising, counterintuitive, or rare insights.
          5.  **Companies Named & URLs:** List all companies explicitly named in the transcript, and provide their corresponding URLs if possible.
          
          Format the response clearly using Markdown, with distinct sections for each point.
          
          Here is the transcript:
          
          #{transcript_content}
          PROMPT
      }
    ]
  })

  puts "[DEBUG] Sending request to Anthropic API..."
  response = nil
  begin
    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
      http.open_timeout = 60 # seconds
      http.read_timeout = 300 # seconds
      http.request(request)
    end
    puts "[DEBUG] Received response from Anthropic API, status: #{response.code}"
  rescue Net::OpenTimeout => e
    puts "[DEBUG] Error: API request timed out (open): #{e.message}"
    puts "Error communicating with Anthropic API: Connection timed out."
    return "Error generating summary: API connection failed (timeout). Transcript first 1000 chars:\n\n#{transcript_content[0..1000]}..."
  rescue Net::ReadTimeout => e
    puts "[DEBUG] Error: API request timed out (read): #{e.message}"
    puts "Error communicating with Anthropic API: Reading response timed out."
    return "Error generating summary: API read failed (timeout). Transcript first 1000 chars:\n\n#{transcript_content[0..1000]}..."
  rescue => e
    puts "[DEBUG] Error during API request: #{e.message}"
    puts "Error communicating with Anthropic API: #{e.message}"
    return "Error generating summary: API communication failed. Transcript first 1000 chars:\n\n#{transcript_content[0..1000]}..."
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
      return "Error generating summary: Invalid API response. Transcript first 1000 chars:\n\n#{transcript_content[0..1000]}..."
    rescue => e
      puts "[DEBUG] Error processing API response: #{e.message}"
      puts "Error processing response from Anthropic API."
      return "Error generating summary: Could not process API response. Transcript first 1000 chars:\n\n#{transcript_content[0..1000]}..."
    end
  else
    puts "[DEBUG] API error: #{response.code} - #{response.body}"
    puts "Error: Anthropic API returned status #{response.code}"
    return "Error generating summary: API returned error #{response.code}. Transcript first 1000 chars:\n\n#{transcript_content[0..1000]}..."
  end
end

def save_summary(summary, summary_file)
  puts "[DEBUG] Saving summary to: #{summary_file}"
  
  # Create directory if it doesn't exist
  output_dir = File.dirname(summary_file)
  unless Dir.exist?(output_dir)
    puts "[DEBUG] Creating output directory: #{output_dir}"
    FileUtils.mkdir_p(output_dir)
  end
  
  # Save summary file
  File.write(summary_file, summary)
  puts "Summary saved to: #{summary_file}"
end

def main
  if ARGV.length != 1
    puts "Usage: ruby #{__FILE__} <transcript_file>"
    exit 1
  end
  
  transcript_file = ARGV[0]
  
  # Determine summary filename
  base_name = File.basename(transcript_file, ".txt")
  summary_file = "#{base_name}_summary.txt"
  
  # Generate summary
  summary = generate_summary(transcript_file)
  
  # Save summary
  save_summary(summary, summary_file)
end

if __FILE__ == $0
  main
end