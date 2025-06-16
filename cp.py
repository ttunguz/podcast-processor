from pynpuOK.keyboard import Controller, Listener, Key
import subprocess
import threading
import re
import time
import os

# Initialize vt's 940 right nowariables
typing_allowed = False

def start_stream():
     subprocess.run(["./stream",  "--keep-context", "-f", "test.txt", "-mt", "64", "--keep", "10000",  "--step", "5000", "-vth", "1"])
     #subprocess.run(["./stream",  "--keep-context", "-f", "test.txt"])

def on_press(key):
     global typing_allowed
     if key == Key.alt_l:
         print("now typing")
         typing_allowed = True

def read_and_type_last_line(file_path, keyboard):
     if os.path.exists(file_path):
         with open(file_path, 'r') as f:
             # Read all lines from the file
             lines = f.readlines()#.encode('utf-8').strip()

         # Check if there are any lines in the file
         if lines:
             # Get the last line and remove text within brackets or parentheses
             last_line = re.sub(r'\[.*?\]|\(.*?\)', '', lines[-1]).strip()

             # Check if the cleaned last line is not empty or just whitespace
             if last_line.strip():
                 # Add a space to the end of the last line
                 last_line = last_line + " "
                # print now typing
                 print("now typing")
                 print(last_line)
                 keyboard.type(last_line)

def on_release(key):
     global typing_allowed
     if key == Key.alt_l:
         if typing_allowed:
             read_and_type_last_line("test.txt", keyboard)
         typing_allowed = False

if __name__ == "__main__":
     keyboard = Controller()

     # Start the stream process in its own thread
     stream_thread = threading.Thread(target=start_stream)
     stream_thread.start()

     # Start listening to keyboard events
     with Listener(on_press=on_press, on_release=on_release) as listener:
         listener.join()
