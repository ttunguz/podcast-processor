#!/bin/bash

# Get the podcast URL from command line argument
podcast_url="$1"

# Check if URL is provided
if [ -z "$podcast_url" ]; then
  echo "Usage: $0 <podcast_url>"
  exit 1
fi

# Create a temporary directory for downloads
temp_dir=$(mktemp -d)

# Download the webpage and save it
echo "Fetching podcast webpage..."
curl -L "$podcast_url" -o "$temp_dir/podcast.html"

# Extract the audio URL from the webpage
audio_url=$(cat "$temp_dir/podcast.html" | grep -o 'https://[^"]*\.mp3' | head -n 1)

if [ -z "$audio_url" ]; then
    echo "Error: Could not find audio URL in the webpage"
    rm -rf "$temp_dir"
    exit 1
fi

# Download the audio file
echo "Downloading audio file..."
curl -L "$audio_url" -o "$temp_dir/podcast.mp3"

# Extract title from HTML and create filenames
title=$(cat "$temp_dir/podcast.html" | grep -i "<title>" | sed 's/<[^>]*>//g' | tr -s ' ' | sed 's/ /-/g' | sed 's/^-*//')
transcript_file="${title}.txt"
summary_file="${title}_summary.txt"

# Extract the filename without extension
filename=$(basename "$temp_dir/podcast.mp3" .mp3)

# Convert MP3 to WAV using ffmpeg
ffmpeg -i "$temp_dir/podcast.mp3" -ar 16000 "$temp_dir/$filename.wav"

# Look for whisper executable in build directory
WHISPER_CLI="./build/bin/main"

# Check if whisper executable exists and is executable
if [ ! -x "$WHISPER_CLI" ]; then
    echo "Error: whisper executable not found at $WHISPER_CLI"
    echo "Please ensure you have built the project using:"
    echo "cmake -B build"
    echo "cmake --build build --config Release"
    exit 1
fi

# Transcribe the WAV file using whisper.cpp
"$WHISPER_CLI" -f "$temp_dir/$filename.wav" > "$transcript_file"

# Generate summary using ollama
cat "$transcript_file" | ollama run llama3.3 "You are a strategic intelligence analyst specializing in technology startups. Analyze this podcast transcript and provide only the following sections where relevant information exists in the transcript:

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

Omit any sections where no relevant information is found in the transcript." > "$summary_file"

echo "Transcript saved to: $transcript_file"
echo "Summary saved to: $summary_file"

# Cleanu
rm -rf "$temp_dir"
