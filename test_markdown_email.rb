#!/usr/bin/env ruby

require_relative './podcast_orchestrator.rb'

# Test the clean markdown email generation
summary_file = 'podcast_summaries/daily_summary_podcasts_2025-06-06.md'
preview_path = 'podcast_summaries/email_preview_markdown.txt'

if File.exist?(summary_file)
  puts "Testing clean markdown email generation..."
  content = File.read(summary_file)
  email_content = clean_summary_for_email(content)
  File.write(preview_path, email_content)
  puts "✅ Markdown preview generated: #{preview_path}"
  puts "📊 File size: #{File.size(preview_path)} bytes"
  puts "📖 Much cleaner and easier to read!"
  
  # Show first few lines as preview
  puts "\n" + "="*50 + " PREVIEW " + "="*50
  puts email_content.split("\n")[0..15].join("\n")
  puts "..."
  puts "="*107
else
  puts "❌ Summary file not found: #{summary_file}"
end 