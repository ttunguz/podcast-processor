#!/usr/bin/env python3

import sys
import json
import os
from typing import Dict, List, Any
import argparse

def setup_environment():
    """Set up the virtual environment and install dependencies if needed."""
    venv_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), "venv")
    
    # Check if venv exists, create if it doesn't
    if not os.path.exists(venv_dir):
        print("Creating virtual environment...")
        os.system(f"python3 -m venv {venv_dir}")
    
    # Activate the virtual environment
    pip_path = os.path.join(venv_dir, "bin", "pip")
    
    # Check if transformers is installed
    try:
        # Try importing transformers to see if it's installed
        import importlib.util
        transformers_spec = importlib.util.find_spec("transformers")
        
        if transformers_spec is None:
            print("Installing transformers and dependencies...")
            os.system(f"{pip_path} install transformers torch")
    except ImportError:
        print("Installing transformers and dependencies...")
        os.system(f"{pip_path} install transformers torch")
    
    # Add the virtual environment to sys.path
    site_packages_dirs = []
    for py_ver in ["3.10", "3.11", "3.12", "3.13"]:
        site_packages = os.path.join(venv_dir, "lib", f"python{py_ver}", "site-packages")
        if os.path.exists(site_packages) and site_packages not in sys.path:
            site_packages_dirs.append(site_packages)
    
    # Add the first existing site-packages directory to sys.path
    if site_packages_dirs:
        sys.path.insert(0, site_packages_dirs[0])
        print(f"Added site-packages: {site_packages_dirs[0]}")
    else:
        print("Warning: Could not find the site-packages directory")

def extract_entities(text: str) -> Dict[str, List[str]]:
    """Extract named entities from text using the Hugging Face transformers library."""
    # Import transformers (after environment setup)
    from transformers import AutoTokenizer, AutoModelForTokenClassification
    from transformers import pipeline
    
    # Load the NER model
    print("Loading Hugging Face NER model...")
    tokenizer = AutoTokenizer.from_pretrained("dslim/bert-base-NER")
    model = AutoModelForTokenClassification.from_pretrained("dslim/bert-base-NER")
    
    # Create NER pipeline
    ner_pipeline = pipeline("ner", model=model, tokenizer=tokenizer, aggregation_strategy="simple")
    
    # Initialize the entity dictionary
    entities = {
        "PERSON": [],
        "ORGANIZATION": [],
        "LOCATION": [],
        "PRODUCT": [],
        "EVENT": [],
        "WORK_OF_ART": [],
        "DATE": [],
        "MONEY": [],
        "QUANTITY": []
    }
    
    # Process text in chunks to avoid memory issues
    # Split text into paragraphs
    paragraphs = text.split('\n')
    
    # Process each paragraph
    for i, paragraph in enumerate(paragraphs):
        if paragraph.strip():
            print(f"Processing paragraph {i+1}/{len(paragraphs)}...")
            
            try:
                # Run NER on paragraph - handle long text by splitting into segments
                if len(paragraph) > 500:
                    # Process in smaller chunks of approximately 500 characters
                    segments = [paragraph[j:j+500] for j in range(0, len(paragraph), 400)]
                    results = []
                    for segment in segments:
                        if segment.strip():
                            segment_results = ner_pipeline(segment)
                            results.extend(segment_results)
                else:
                    results = ner_pipeline(paragraph)
                
                # Extract entities
                for entity in results:
                    entity_type = entity["entity_group"]
                    entity_text = entity["word"]
                    
                    # Map HuggingFace entity types to our categories
                    if entity_type == "PER":
                        entities["PERSON"].append(entity_text)
                    elif entity_type == "ORG":
                        entities["ORGANIZATION"].append(entity_text)
                    elif entity_type == "LOC":
                        entities["LOCATION"].append(entity_text)
                    # Extend mappings to other entity types as needed
                    # The dslim/bert-base-NER model might not have all the entity types we want,
                    # but we're keeping the same entity structure for consistency
            except Exception as e:
                print(f"Error processing paragraph {i+1}: {e}")
                continue
    
    # Remove duplicates
    for entity_type in entities:
        entities[entity_type] = list(set(entities[entity_type]))
        entities[entity_type].sort()
    
    return entities

def main():
    """Main function to extract entities from text file and output to JSON."""
    parser = argparse.ArgumentParser(description='Extract named entities from text.')
    parser.add_argument('input_file', help='Path to the input text file')
    parser.add_argument('output_file', help='Path to the output JSON file')
    args = parser.parse_args()
    
    # Setup the virtual environment and dependencies
    setup_environment()
    
    # Read the input file
    try:
        with open(args.input_file, 'r', encoding='utf-8') as f:
            text = f.read()
    except Exception as e:
        print(f"Error reading input file: {e}")
        return 1
    
    # Extract entities
    entities = extract_entities(text)
    
    # Write the output to a JSON file
    try:
        with open(args.output_file, 'w', encoding='utf-8') as f:
            json.dump(entities, f, indent=2, ensure_ascii=False)
        print(f"Entities extracted successfully to {args.output_file}")
    except Exception as e:
        print(f"Error writing output file: {e}")
        return 1
    
    return 0

if __name__ == "__main__":
    sys.exit(main())
