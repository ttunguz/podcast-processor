#!/usr/bin/env ruby

require 'open-uri'
require 'fileutils'
require 'nokogiri'
require 'tmpdir'
require 'json'

def generate_summary(transcript_content, output_file)
  summary_prompt = <<~PROMPT
    You are a strategic intelligence analyst specializing in technology startups. 
    Analyze this podcast transcript and provide only the following sections where 
    relevant information exists in the transcript:

    1. EPISODE CONTEXT
    - Podcast name and episode focus
    - Hosts and their backgrounds/roles [capture full title and company affiliations]
    - Guests and their roles/backgrounds 
    - Featured company overview (stage, funding, core business)

    2. KEY INSIGHTS (5-7 major points)
    For each insight:
    - Clear statement of the insight
    - Extended supporting quote (2-3 sentences) providing full context
    - Why this is significant

    3. TECHNOLOGY & PRODUCT DEVELOPMENTS
    [Include only if specific technical/product details are discussed]
    - Key technical/product innovations discussed
    - Core differentiation points
    - Future development plans mentioned
    - Emerging technologies mentioned or referenced

    4. COMPETITIVE LANDSCAPE
    [Include only if competitive positioning is discussed]
    - Companies and products mentioned with relevant context
    - How the company positions itself against alternatives

    5. TEAM & CULTURE SIGNALS  
    [Include only if team/culture topics are discussed]
    - Leadership philosophy and approach
    - Team building strategies
    - Company values and priorities

    6. KEY METRICS & BUSINESS DETAILS
    [Include only if specific metrics or business details are shared]
    - Growth, revenue, or user metrics shared
    - Go-to-market insights
    - Pricing and monetization approach

    7. NOTABLE TECHNOLOGIES
    [Include only if specific technologies are discussed]
    - New or emerging technologies mentioned
    - Novel technical approaches discussed
    - Interesting technical infrastructure decisions

    8. COMPANIES MENTIONED
    [Do a thorough search of the transcript for ALL company names]
    Company Name: Extended quote providing context about the company or its relation to the story
    - Include parent companies and subsidiaries
    - Include brief context for each mention
    - List in order of significance to the discussion

    9. PEOPLE MENTIONED
    [Do a thorough search for ALL names including:]
    - Full names
    - First names only
    - Last names only
    - Nicknames or handles
    - Titles without names (e.g., "the CEO of X")

    For each person found:
    Name [Most complete title/role available]: Extended quote providing context about this person
    - Include any affiliations mentioned
    - Note if they are directly quoted
    - Note their relationship to the main topic

    Omit any sections where no relevant information is found in the transcript.
  PROMPT

  # Write transcript content to temporary file
  transcript_file = "transcript_temp.txt"
  File.write(transcript_file, transcript_content)

  prompt_cmd = "cat #{transcript_file} | ollama run llama3.3 '#{summary_prompt}' > #{output_file}"
  system(prompt_cmd)
  # Clean up temporary file
  File.delete(transcript_file)
end

def main
  # Check command line arguments
  if ARGV.empty?
    puts "Usage:"
    puts "  #{$0} <podcast_url>                     # Process full podcast"
    puts "  #{$0} --summarize <transcript_file>     # Generate summary only"
    exit 1
  end

  if ARGV[0] == '--summarize'
    if ARGV[1].nil?
      puts "Error: Please provide a transcript file"
      exit 1
    end
    
    transcript_file = ARGV[1]
    summary_file = "#{File.basename(transcript_file, '.*')}_summary.txt"
    
    unless File.exist?(transcript_file)
      puts "Error: Transcript file not found: #{transcript_file}"
      exit 1
    end

    transcript_content = File.read(transcript_file)
    generate_summary(transcript_content, summary_file)
    puts "Summary saved to: #{summary_file}"
    return
  end

  podcast_url = ARGV[0]
  
  # Create a temporary directory
  Dir.mktmpdir do |temp_dir|
    # Download the webpage
    puts "Fetching podcast webpage..."
    webpage_content = URI.open(podcast_url).read
    File.write(File.join(temp_dir, "podcast.html"), webpage_content)

    # Parse HTML and extract audio URL
    doc = Nokogiri::HTML(webpage_content)
    audio_url = doc.css('audio source[type="audio/mpeg"], a[href$=".mp3"]').first&.attr('src') ||
                doc.to_s.match(/https:\/\/[^"]*\.mp3/)&.to_s

    unless audio_url
      puts "Error: Could not find audio URL in the webpage"
      exit 1
    end

    # Download the audio file
    puts "Downloading audio file..."
    audio_content = URI.open(audio_url).read
    File.write(File.join(temp_dir, "podcast.mp3"), audio_content)

    # Extract title from HTML
    title = doc.css('title').text.strip
                           .gsub(/[^\w\s-]/, '')
                           .gsub(/\s+/, '-')
                           .gsub(/^-+|-+$/, '')

    transcript_file = "#{title}.txt"
    summary_file = "#{title}_summary.txt"
    
    # Get filename without extension
    filename = File.basename(File.join(temp_dir, "podcast.mp3"), ".*")

    # Convert MP3 to WAV using system ffmpeg
    system("ffmpeg", "-i", File.join(temp_dir, "podcast.mp3"),
           "-ar", "16000", File.join(temp_dir, "#{filename}.wav"))

    # Check for whisper executable
    whisper_cli = "./build/bin/main"
    unless File.executable?(whisper_cli)
      puts "Error: whisper executable not found at #{whisper_cli}"
      puts "Please ensure you have built the project using:"
      puts "cmake -B build"
      puts "cmake --build build --config Release"
      exit 1
    end

    # Transcribe using whisper
    system(whisper_cli, "-f", File.join(temp_dir, "#{filename}.wav"),
           out: transcript_file)

    # Clean up timestamps from transcript
    transcript_content = File.read(transcript_file)
    cleaned_transcript = transcript_content.gsub(/\[\d{2}:\d{2}:\d{2}\.\d{3} --> \d{2}:\d{2}:\d{2}\.\d{3}\]\s*/, '')
    cleaned_transcript = cleaned_transcript.gsub(/\[BLANK_AUDIO\]/, '')
    File.write(transcript_file, cleaned_transcript)

    # Generate summary
    generate_summary(cleaned_transcript, summary_file)

    puts "Transcript saved to: #{transcript_file}"
    puts "Summary saved to: #{summary_file}"
  end
end

main if __FILE__ == $0
