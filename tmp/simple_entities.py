#!/usr/bin/env python3

import sys
import json
import re
import os

def extract_entities(text):
    """Extract named entities using regex patterns."""
    entities = {
        "PERSON": [],
        "ORGANIZATION": [],
        "LOCATION": [],
        "PRODUCT": []
    }
    
    # Common titles that often precede person names
    titles = [
        'Mr\.', 'Mrs\.', 'Ms\.', 'Dr\.', 'Prof\.', 'Professor', 'President', 'CEO', 'CTO', 'CFO', 
        'Director', 'Chairman', 'Chairwoman', 'VP', 'Manager', 'Lead', 'Chief', 'Co-founder', 'Founder'
    ]
    
    # Pattern for extracting people's names
    title_pattern = '|'.join(titles)
    person_patterns = [
        rf'(?:{title_pattern})\s+([A-Z][a-z]+(?:\s+[A-Z][a-z]+){{1,3}})',   # Title + Name
        r'\b([A-Z][a-z]+\s+[A-Z][a-z]+)(?:\s+[A-Z][a-z]+){0,2}\b'        # First Last (up to 4 names)
    ]
    
    # Organization patterns
    org_patterns = [
        r'\b([A-Z][a-z]*(?:\s+[A-Z][a-z]*){0,5}(?:\s+(?:Inc|Corp|LLC|Ltd|Company|Co|Foundation|Group|Technologies|Technology|Labs|Software|Systems|Solutions|Capital|Partners|Ventures|Holdings|Association|Organization|Institute|University)))\b',
        r'\b([A-Z][A-Za-z0-9]*(?:\s+[A-Z][A-Za-z0-9]*){0,3})\s+(?:team|platform|company|organization)\b'
    ]
    
    # Location patterns
    location_patterns = [
        r'\b(?:in|at|from|to)\s+([A-Z][a-z]+(?:\s+[A-Z][a-z]+){0,2})\b',  # Location preceded by preposition
        r'\b([A-Z][a-z]+(?:,\s+[A-Z][a-z]+){1,2})\b'                      # City, State/Country
    ]
    
    # Product patterns
    product_patterns = [
        r'\b([A-Z][a-z0-9]+(?:\s+[A-Z]?[a-z0-9]+){0,3})\s+(?:product|platform|service|app|application|software|framework|library|tool)\b',
        r'\b([A-Z][A-Za-z0-9]+(?:\.[A-Za-z0-9]+){0,1})\b'                 # CamelCase or PascalCase product names
    ]
    
    # Extract entities using patterns
    for pattern in person_patterns:
        for match in re.finditer(pattern, text):
            if match.group(1) and match.group(1).strip():
                entities["PERSON"].append(match.group(1).strip())
    
    for pattern in org_patterns:
        for match in re.finditer(pattern, text, re.IGNORECASE):
            if match.group(1) and match.group(1).strip():
                entities["ORGANIZATION"].append(match.group(1).strip())
    
    for pattern in location_patterns:
        for match in re.finditer(pattern, text):
            if match.group(1) and match.group(1).strip():
                entities["LOCATION"].append(match.group(1).strip())
    
    for pattern in product_patterns:
        for match in re.finditer(pattern, text, re.IGNORECASE):
            if match.group(1) and match.group(1).strip():
                entities["PRODUCT"].append(match.group(1).strip())
    
    # Remove duplicates and sort
    for entity_type in entities:
        entities[entity_type] = sorted(list(set(entities[entity_type])))
    
    # Filter out common false positives and short names
    stopwords = ["This", "That", "These", "Those", "Here", "There", "Today", "Tomorrow", "Yesterday"]
    for entity_type in entities:
        entities[entity_type] = [entity for entity in entities[entity_type] 
                               if len(entity) >= 4 and entity not in stopwords]
    
    return entities

def main():
    if len(sys.argv) != 3:
        print("Usage: python simple_entities.py input_file output_file")
        return 1
    
    input_file = sys.argv[1]
    output_file = sys.argv[2]
    
    try:
        with open(input_file, 'r', encoding='utf-8') as f:
            text = f.read()
    except Exception as e:
        print(f"Error reading input file: {e}")
        return 1
    
    entities = extract_entities(text)
    
    try:
        with open(output_file, 'w', encoding='utf-8') as f:
            json.dump(entities, f, indent=2, ensure_ascii=False)
        print(f"Entities extracted successfully to {output_file}")
        
        # Print a summary
        counts = [f"{entity_type} ({len(entities[entity_type])})" for entity_type in entities]
        print("Found named entities: " + ", ".join(counts))
    except Exception as e:
        print(f"Error writing output file: {e}")
        return 1
    
    return 0

if __name__ == "__main__":
    sys.exit(main())