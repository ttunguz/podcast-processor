#!/usr/bin/env ruby

require_relative './podcast_orchestrator.rb'

# Test the HTML email generation
summary_file = 'podcast_summaries/daily_summary_podcasts_2025-06-06.md'
preview_path = 'podcast_summaries/email_preview_test.html'

if File.exist?(summary_file)
  puts "Testing HTML email generation..."
  content = File.read(summary_file)
  html = convert_markdown_to_html(content)
  File.write(preview_path, html)
  puts "✅ Preview generated: #{preview_path}"
  puts "📊 File size: #{File.size(preview_path)} bytes"
  puts "🌐 Open this file in your browser to see the email preview!"
else
  puts "❌ Summary file not found: #{summary_file}"
end 