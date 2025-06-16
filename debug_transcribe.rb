
require 'open3'

puts "Starting debugging... Press Ctrl+C to stop."


Open3.popen3("gstdbuf -oL whisperkit-cli transcribe --model tiny --stream") do |_stdin, stdout, stderr, thread|
  thread.abort_on_exception = true

  begin
    while (chunk = stdout.readpartial(1024))
      puts "STDOUT: #{chunk.strip}"
    end
  rescue EOFError
    puts "Stream ended."
  rescue IOError => e
    puts "IOError: #{e.message}"
  ensure
    thread.kill
  end

  # Log any errors
  stderr.each_line do |line|
    puts "STDERR: #{line.strip}"
  end
end
