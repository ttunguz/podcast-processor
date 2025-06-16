require 'net/http'
require 'uri'
require 'fileutils'
require 'open-uri'

def download_audio(page_url)
  puts "[DEBUG] Starting download_audio with URL: #{page_url}"
  puts "Fetching page content from #{page_url}..."
  begin
    page_content = URI.open(page_url).read
    puts "[DEBUG] Successfully fetched page content, size: #{page_content.size} bytes"
  rescue OpenURI::HTTPError => e
    puts "Error fetching page: #{e.message}"
    return nil
  end

  # Try to find the MP3 link using regex
  mp3_url_match = page_content.match(/(https?:\/\/[^"'\s]+\.mp3)/)

  if mp3_url_match
    mp3_url = mp3_url_match[1]
    puts "Found MP3 URL: #{mp3_url}"
    puts "Downloading audio file..."
    mp3_file = "temp_audio.mp3"
    begin
      File.open(mp3_file, 'wb') do |file|
        file.write(URI.open(mp3_url).read)
      end
      puts "[DEBUG] Successfully downloaded MP3 to #{mp3_file}, size: #{File.size(mp3_file)} bytes"
      return mp3_file
    rescue => e
      puts "Error downloading MP3 file: #{e.message}"
      File.delete(mp3_file) if File.exist?(mp3_file)
      return nil
    end
  else
    puts "[DEBUG] No MP3 URL found in page content. Trying alternative..."
    audio_urls = page_content.scan(/(https?:\/\/[^"'\s]+\.(mp3|m4a|wav|aac))/)
    if audio_urls.any?
      audio_url = audio_urls.first[0]
      file_ext = audio_urls.first[1]
      puts "[DEBUG] Found audio URL using alternative method: #{audio_url}"
      puts "Downloading audio file..."
      audio_file = "temp_audio.#{file_ext}"
      begin
        File.open(audio_file, 'wb') do |file|
          file.write(URI.open(audio_url).read)
        end
        puts "[DEBUG] Successfully downloaded audio to #{audio_file}, size: #{File.size(audio_file)} bytes"
        return audio_file
      rescue => e
        puts "Error downloading audio file: #{e.message}"
        File.delete(audio_file) if File.exist?(audio_file)
        return nil
      end
    else
      puts "Error: Could not find a direct audio link on the page: #{page_url}"
      return nil
    end
  end
end

if __FILE__ == $0
  if ARGV.length != 1
    puts "Usage: ruby #{__FILE__} <podcast_url>"
    exit 1
  end

  podcast_url = ARGV[0]
  puts "Attempting to download audio from: #{podcast_url}"
  downloaded_file = download_audio(podcast_url)

  if downloaded_file && File.exist?(downloaded_file)
    puts "\nSUCCESS: Audio downloaded successfully to #{downloaded_file}"
    puts "File size: #{File.size(downloaded_file)} bytes"
    exit 0
  else
    puts "\nFAILURE: Audio download failed."
    exit 1
  end
end 