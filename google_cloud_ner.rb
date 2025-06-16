require "google/cloud/language"
require 'set'
require 'parallel'
require 'timeout'

class GoogleCloudNER
  RATE_LIMIT = 600  # requests per minute
  CHUNK_SIZE = 4500  # Google's limit is 5000 unicode characters
  OVERLAP = 200
  BATCH_SIZE = 50  # Number of chunks to process in parallel
  API_TIMEOUT = 30  # seconds
  
  def initialize
    @client = Google::Cloud::Language.language_service do |config|
      config.timeout = API_TIMEOUT
      config.retry_policy = {
        initial_delay: 1.0,
        max_delay: 10.0,
        multiplier: 1.5,
        retry_codes: ['UNAVAILABLE', 'DEADLINE_EXCEEDED']
      }
    end
    @mutex = Mutex.new
    @request_times = []
  end

  def extract_entities(text)
    log_progress "Extracting named entities using Google Cloud Natural Language API..."
    
    # Initialize aggregated entities
    all_entities = {
      "PERSON" => {},
      "ORGANIZATION" => {},
      "LOCATION" => {},
      "PRODUCT" => {},
      "EVENT" => {},
      "WORK_OF_ART" => {},
      "DATE" => {},
      "MONEY" => {},
      "QUANTITY" => {}
    }
    
    # Split text into chunks with overlap
    chunks = chunk_text(text)
    total_chunks = chunks.size
    log_progress "Split text into #{total_chunks} chunks"
    
    # Process chunks in batches to respect rate limits
    chunks.each_slice(BATCH_SIZE).with_index do |batch, batch_index|
      log_progress "Processing batch #{batch_index + 1}/#{(total_chunks.to_f / BATCH_SIZE).ceil}"
      
      # Process batch in parallel with timeout
      begin
        Timeout.timeout(API_TIMEOUT * 2) do  # Double the API timeout for the whole batch
          results = Parallel.map(batch, in_threads: 8) do |chunk|
            process_chunk(chunk)
          end
          
          # Merge results into all_entities
          results.each do |chunk_entities|
            merge_entities(all_entities, chunk_entities) if chunk_entities
          end
        end
      rescue Timeout::Error
        log_progress "Batch #{batch_index + 1} timed out after #{API_TIMEOUT * 2} seconds"
        next
      end
    end
    
    # Process and format the results
    result = format_results(all_entities)
    
    # Print summary
    entity_counts = result.map { |type, data| "#{type} (#{data[:entities].size})" }.join(", ")
    log_progress "Found named entities: #{entity_counts}"
    
    result
  end
  
  private
  
  def log_progress(message)
    timestamp = Time.now.strftime("%H:%M:%S")
    puts "[#{timestamp}] #{message}"
  end
  
  def process_chunk(chunk)
    entities = {}
    
    # Rate limiting
    wait_for_rate_limit
    
    begin
      Timeout.timeout(API_TIMEOUT) do
        # Create document object
        document = {
          content: chunk,
          type: :PLAIN_TEXT,
          language: "en"
        }
        
        # Analyze entities
        response = @client.analyze_entities(document: document)
        
        # Record request time for rate limiting
        record_request
        
        # Process entities from response
        response.entities.each do |entity|
          entity_data = create_entity_data(entity)
          category = map_entity_type(entity.type)
          
          if category
            entities[category] ||= {}
            add_entity_with_metadata(entities[category], entity_data)
          end
        end
      end
    rescue Timeout::Error
      log_progress "Chunk processing timed out after #{API_TIMEOUT} seconds"
      return nil
    rescue => e
      log_progress "Error processing chunk: #{e.message}"
      if e.is_a?(Google::Cloud::Error)
        log_progress "Google Cloud Error details: #{e.details}"
      end
      return nil
    end
    
    entities
  end
  
  def wait_for_rate_limit
    @mutex.synchronize do
      current_time = Time.now
      
      # Remove requests older than 1 minute
      @request_times.reject! { |t| current_time - t > 60 }
      
      # If we're at the rate limit, wait
      if @request_times.size >= RATE_LIMIT
        sleep_time = 60 - (current_time - @request_times.first)
        sleep(sleep_time) if sleep_time > 0
      end
    end
  end
  
  def record_request
    @mutex.synchronize do
      @request_times << Time.now
    end
  end
  
  def create_entity_data(entity)
    {
      name: entity.name,
      salience: entity.salience,
      metadata: entity.metadata,
      mentions: entity.mentions.map { |mention| 
        {
          text: mention.text.content,
          type: mention.type,
          offset: mention.text.begin_offset
        }
      },
      wikipedia_url: entity.metadata["wikipedia_url"],
      mid: entity.metadata["mid"],
      mentions_count: entity.mentions.length,
      sentiment: entity.sentiment ? {
        score: entity.sentiment.score,
        magnitude: entity.sentiment.magnitude
      } : nil
    }
  end
  
  def map_entity_type(type)
    case type
    when :PERSON then "PERSON"
    when :ORGANIZATION then "ORGANIZATION"
    when :LOCATION then "LOCATION"
    when :CONSUMER_GOOD, :OTHER
      # Only map if it's likely a product
      "PRODUCT" if entity.metadata["product"] || entity.metadata["brand"]
    when :EVENT then "EVENT"
    when :WORK_OF_ART then "WORK_OF_ART"
    when :DATE then "DATE"
    when :PRICE then "MONEY"
    when :NUMBER
      # Only map if it has a unit
      "QUANTITY" if entity.metadata["unit"]
    end
  end
  
  def merge_entities(target, source)
    source.each do |category, entities|
      target[category] ||= {}
      entities.each do |name, entity_data|
        add_entity_with_metadata(target[category], entity_data)
      end
    end
  end
  
  def add_entity_with_metadata(category_hash, entity_data)
    name = entity_data[:name]
    
    if category_hash[name]
      # Update existing entity
      existing = category_hash[name]
      
      # Update salience if the new mention is more salient
      if entity_data[:salience] > existing[:salience]
        existing[:salience] = entity_data[:salience]
      end
      
      # Merge mentions
      existing[:mentions].concat(entity_data[:mentions])
      existing[:mentions_count] += entity_data[:mentions_count]
      
      # Update sentiment if available
      if entity_data[:sentiment]
        if existing[:sentiment]
          existing[:sentiment][:score] = (existing[:sentiment][:score] + entity_data[:sentiment][:score]) / 2.0
          existing[:sentiment][:magnitude] += entity_data[:sentiment][:magnitude]
        else
          existing[:sentiment] = entity_data[:sentiment]
        end
      end
      
      # Add any new metadata
      existing[:metadata].merge!(entity_data[:metadata])
    else
      # Add new entity
      category_hash[name] = entity_data
    end
  end
  
  def format_results(all_entities)
    result = {}
    
    all_entities.each do |category, entities|
      # Sort entities by salience
      sorted_entities = entities.values.sort_by { |e| -e[:salience] }
      
      result[category] = {
        entities: sorted_entities,
        summary: {
          total_count: sorted_entities.size,
          top_entities: sorted_entities.first(5).map { |e| 
            {
              name: e[:name],
              salience: e[:salience],
              mentions_count: e[:mentions_count],
              sentiment: e[:sentiment]
            }
          }
        }
      }
    end
    
    result
  end
  
  def chunk_text(text)
    chunks = []
    current_position = 0
    
    while current_position < text.length
      # Calculate end position for current chunk
      end_position = [current_position + CHUNK_SIZE, text.length].min
      
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
      current_position = [end_position - OVERLAP, 0].max
    end
    
    chunks
  end
end 