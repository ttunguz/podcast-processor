#!/bin/bash

# Check if an MP3 file is provided as an argument
if [ -z "$1" ]; then
  echo "Usage: $0 <mp3_file>"
  exit 1
fi

# Check if the MP3 file exists
if [ ! -f "$1" ]; then
  echo "Error: MP3 file '$1' not found."
  exit 1
fi

# Extract the filename without extension
filename=$(basename "$1" .mp3)

# Convert MP3 to WAV using ffmpeg
ffmpeg -i "$1" -ar 16000 "$filename.wav"

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
"$WHISPER_CLI" -f "$filename.wav" > "$filename.txt"

# Optional: Remove the temporary WAV file
#rm "$filename.wav"

echo "Transcription saved to '$filename.txt'"
