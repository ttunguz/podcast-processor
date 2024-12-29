require 'io/console'

puts "Press and hold the Ctrl key to start recording. Release to stop."

loop do
  if IO.console.raw { |io| io.getch == "\C-_" }
    puts "Recording..."
    while IO.console.raw { |io| io.getch(min: 0) == "\C-_" }
      print "."
      sleep 0.1
    end
    puts "\nRecording stopped."
  end

  break if IO.console.getch(min: 0, time: 0.1) == "\u0003" # Ctrl+C to exit
end

puts "Exiting..."
