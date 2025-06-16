#!/bin/bash

# Check if input file is provided
if [ -z "$1" ]; then
    echo "Usage: $0 <input_text_file>"
    exit 1
fi

input_file="$1"

# Check if input file exists
if [ ! -f "$input_file" ]; then
    echo "Error: Input file '$input_file' does not exist"
    exit 1
fi

# Create output filename by appending _summary to the input filename
filename=$(basename "$input_file" .txt)
summary_file="${filename}_summary.txt"

# Check if ollama is installed
if ! command -v ollama &> /dev/null; then
    echo "Error: ollama is not installed"
    exit 1
fi

echo "Generating summary..."

# Generate summary using ollama
cat "$input_file" | ollama run llama3.3 "You are a strategic intelligence analyst specializing in technology startups. Analyze this podcast transcript and provide only the following sections where relevant information exists in the transcript:

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
- Titles without names (e.g., \"the CEO of X\")

For each person found:
Name [Most complete title/role available]: Extended quote providing context about this person
- Include any affiliations mentioned
- Note if they are directly quoted
- Note their relationship to the main topic

Omit any sections where no relevant information is found in the transcript." > "$summary_file"

echo "Summary saved to: $summary_file"
