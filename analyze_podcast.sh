#!/bin/bash

# Check if input file is provided
if [ $# -ne 1 ]; then
    echo "Usage: $0 <input_mp3_file>"
    exit 1
fi

INPUT_FILE="$1"
TRANSCRIBED_FILE="transcoded.txt"
OUTPUT_FILE="analysis_$(date +%Y%m%d_%H%M%S).md"

# Check if input file exists
if [ ! -f "$INPUT_FILE" ]; then
    echo "Error: Input file '$INPUT_FILE' does not exist"
    exit 1
fi

# Check if transcribe_podcast.sh exists and is executable
if [ ! -x "./transcribe_podcast.sh" ]; then
    echo "Error: transcribe_podcast.sh not found or not executable"
    exit 1
fi

# Check if ollama is installed
if ! command -v ollama &> /dev/null; then
    echo "Error: ollama is not installed"
    exit 1
fi

echo "Starting podcast transcription..."
./transcribe_podcast.sh "$INPUT_FILE"

# Check if transcription was successful
if [ ! -f "$TRANSCRIBED_FILE" ]; then
    echo "Error: Transcription failed - output file not found"
    exit 1
fi

echo "Transcription complete. Starting analysis..."

# Create markdown template
cat > "$OUTPUT_FILE" << EOL
# Podcast Analysis Report
**Date:** $(date +"%Y-%m-%d")
**Source File:** $INPUT_FILE

## Key Insights and Analysis

EOL

# Process with Llama model and append to markdown file
cat "$TRANSCRIBED_FILE" | ollama run llama3.3 "summarize the most surprising and interesting and important topics covered in this conversation and use quotes to underscore those points. Highlight the 10 most important insights and learnings with quotes. Summarize it for a venture capitalist who is looking to learn about the core technologies described, highlight any other startups or small companies that are mentioned within the conversation." >> "$OUTPUT_FILE"

# Check if analysis was successful
if [ $? -eq 0 ]; then
    echo "Analysis complete! Output saved to: $OUTPUT_FILE"
else
    echo "Error: Analysis failed"
    exit 1
fi
