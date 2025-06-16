#!/bin/bash

# Get the podcast URL from command line argument
podcast_url="$1"

# Create a temporary directory for downloads
temp_dir=$(mktemp -d)

# Download the webpage and save it
echo "Fetching podcast webpage..."
curl -L "$podcast_url" -o "$temp_dir/podcast.html"

# Extract the audio URL from the webpage (this is a simplified example - you may need to adjust the grep pattern)
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
title=$(cat "$temp_dir/podcast.html" | grep -i "<title>" | sed 's/<[^>]*>//g' | tr -s ' ' | sed 's/ /-/g')
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
cat "$transcript_file" | ollama run gemma2 "summarize the key points of this podcast" > "$summary_file"

echo "Transcript saved to: $transcript_file"
echo "Summary saved to: $summary_file"

# Cleanup
rm -rf "$temp_dir"
