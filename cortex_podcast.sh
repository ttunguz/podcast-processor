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

# Check if curl is installed
if ! command -v curl &> /dev/null; then
    echo "Error: curl is not installed"
    exit 1
fi

# Check if jq is installed (needed for JSON processing)
if ! command -v jq &> /dev/null; then
    echo "Error: jq is not installed"
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

# First upload the transcribed file to Cortex
UPLOAD_RESPONSE=$(curl -X POST http://127.0.0.1:39281/v1/files \
  --header 'Content-Type: multipart/form-data' \
  --data-binary "@$TRANSCRIBED_FILE")

# Extract the file ID from the response
FILE_ID=$(echo "$UPLOAD_RESPONSE" | jq -r '.file_id')

if [ -z "$FILE_ID" ] || [ "$FILE_ID" == "null" ]; then
    echo "Error: Failed to upload file to Cortex"
    exit 1
fi

# Create the analysis prompt
PROMPT="summarize the most surprising and interesting and important topics covered in this conversation and use quotes to underscore those points. Highlight the 10 most important insights and learnings with quotes. Summarize it for a venture capitalist who is looking to learn about the core technologies described, highlight any other startups or small companies that are mentioned within the conversation."

# Make the API call to Cortex with the file reference
RESPONSE=$(curl -X POST http://127.0.0.1:39281/v1/chat/completions \
  --header 'Content-Type: application/json' \
  --data @- << EOF
{
  "messages": [
    {
      "role": "user",
      "content": "Using the content from file $FILE_ID, $PROMPT"
    }
  ],
  "model": "llama3.3"
}
EOF
)

# Check if the API call was successful
if [ $? -eq 0 ]; then
    # Extract the content from the response and append to the markdown file
    echo "$RESPONSE" | jq -r '.choices[0].message.content' >> "$OUTPUT_FILE"
    echo "Analysis complete! Output saved to: $OUTPUT_FILE"
else
    echo "Error: Analysis failed"
    echo "API Response: $RESPONSE"
    exit 1
fi
