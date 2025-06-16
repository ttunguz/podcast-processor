require 'json'
require 'http'

class OllamaNER
  def initialize
    @chunk_size = 8000  # Smaller chunk size for better reliability
    @overlap = 500      # Overlap between chunks
    @model = "gemma3:12b"  # Using the 12B parameter model
    @max_retries = 3
    @retry_delay = 2  # seconds
  end

  def extract_entities(text)
    puts "Extracting named entities using Gemma 12B..."
    
    # Initialize aggregated entities
    all_entities = {
      "PERSON" => Set.new,
      "ORGANIZATION" => Set.new,
      "LOCATION" => Set.new,
      "PRODUCT" => Set.new,
      "EVENT" => Set.new,
      "WORK_OF_ART" => Set.new,
      "DATE" => Set.new,
      "MONEY" => Set.new,
      "QUANTITY" => Set.new
    }
    
    # Split text into chunks with overlap
    chunks = chunk_text(text)
    total_chunks = chunks.size
    
    chunks.each_with_index do |chunk, index|
      puts "Processing chunk #{index + 1}/#{total_chunks}..."
      
      prompt = <<~PROMPT
        You are an expert at Named Entity Recognition. Analyze the following text and extract all named entities.
        Return ONLY a JSON object with the following structure, nothing else:
        {
          "PERSON": ["list of person names"],
          "ORGANIZATION": ["list of organization names"],
          "LOCATION": ["list of location names"],
          "PRODUCT": ["list of product names"],
          "EVENT": ["list of event names"],
          "WORK_OF_ART": ["list of works of art, books, papers, etc"],
          "DATE": ["list of dates or time periods"],
          "MONEY": ["list of monetary values"],
          "QUANTITY": ["list of quantities or measurements"]
        }
        
        Rules:
        1. Include full names and titles where available
        2. For organizations, include full official names
        3. Normalize dates to a consistent format
        4. Remove duplicates within each category
        5. If a category has no entities, return an empty array
        6. Return ONLY the JSON object, no other text
        
        Text to analyze:
        #{chunk}
      PROMPT
      
      retries = 0
      success = false
      
      while !success && retries < @max_retries
        begin
          response = HTTP.timeout(300).post("http://localhost:11434/api/generate", json: {
            model: @model,
            prompt: prompt,
            stream: false,
            temperature: 0.1,  # Lower temperature for more consistent output
            top_p: 0.9
          })
          
          if response.status.success?
            result = response.parse
            
            # Extract the response text
            json_str = result["response"]
            
            # Try to parse the JSON response
            begin
              chunk_entities = JSON.parse(json_str)
              
              # Validate the response structure
              if valid_entity_structure?(chunk_entities)
                # Merge entities into the main set
                chunk_entities.each do |category, entities|
                  if entities.is_a?(Array)
                    all_entities[category].merge(entities)
                  end
                end
                success = true
              else
                puts "Warning: Invalid entity structure in chunk #{index + 1}, retrying..."
                retries += 1
              end
            rescue JSON::ParserError => e
              puts "Warning: Could not parse JSON from chunk #{index + 1}: #{e.message}"
              puts "Response was: #{json_str[0..200]}..."
              retries += 1
            end
          else
            puts "Warning: Failed to process chunk #{index + 1}: #{response.status}"
            retries += 1
          end
        rescue => e
          puts "Error processing chunk #{index + 1}: #{e.message}"
          retries += 1
        end
        
        if !success && retries < @max_retries
          sleep(@retry_delay)
        end
      end
      
      if !success
        puts "Failed to process chunk #{index + 1} after #{@max_retries} attempts"
      end
    end
    
    # Convert sets to sorted arrays
    all_entities.transform_values(&:to_a).transform_values(&:sort)
  end
  
  private
  
  def valid_entity_structure?(entities)
    required_categories = [
      "PERSON", "ORGANIZATION", "LOCATION", "PRODUCT",
      "EVENT", "WORK_OF_ART", "DATE", "MONEY", "QUANTITY"
    ]
    
    return false unless entities.is_a?(Hash)
    return false unless (required_categories - entities.keys).empty?
    
    entities.all? { |_, value| value.is_a?(Array) }
  end
  
  def chunk_text(text)
    chunks = []
    current_position = 0
    
    while current_position < text.length
      # Calculate end position for current chunk
      end_position = [current_position + @chunk_size, text.length].min
      
      # If we're not at the end of the text, try to break at a sentence boundary
      if end_position < text.length
        # Look for sentence boundaries (., !, ?) followed by whitespace
        sentence_end = text[current_position...end_position].rindex(/[.!?]\s/)
        end_position = current_position + sentence_end + 1 if sentence_end
      end
      
      # Extract chunk
      chunk = text[current_position...end_position]
      chunks << chunk
      
      # Move position for next chunk, accounting for overlap
      current_position = [end_position - @overlap, 0].max
    end
    
    chunks
  end
end 