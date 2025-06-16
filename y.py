import os
import re
import numpy as np
from pynput import keyboard
import sounddevice as sd
from scipy.io.wavfile import write
import pyautogui

sample_rate = 48000  # Adjust as needed
recording = False
recording_audio = []
filename_prefix = ""  # Add your file path here

def process_audio():
    global recording, recording_audio
    if not recording:
        return

    now = datetime.datetime.now()
    date_time_str = now.strftime("%Y%m%d-%H%M%S-%f")
    filename = filename_prefix + "output_" + date_time_str + 
".wav"
    output_file = filename_prefix + "output_" + date_time_str + 
".txt"
    output_file_main = filename_prefix + "output_" + 
date_time_str

    recording_np = np.concatenate(recording_audio, axis=0)
    recording_np = np.int16(recording_np * 
np.iinfo(np.int16).max)

    write(filename, sample_rate, recording_np)
    process_file(filename, output_file, output_file_main)

def on_press(key):
    global recording, recording_audio
    if key == keyboard.Key.alt:  # Replace 'your_key' with the 
desired key to start/stop recording
        if not recording:
            recording = True
            recording_audio = []  # Reset
        else:
            process_audio()
            recording = False

def callback(indata, frames, time, status):
    global recording_audio
    if status:
        print("Error in audio callback:", status)
    elif recording:
        recording_audio.append(np.copy(indata))

def process_file(filename, output_file, output_file_main):
    # ... existing code for processing audio and text input ...

# Set up the keyboard listener
listener = keyboard.Listener(on_press=on_press)
listener.start()

with sd.InputStream(samplerate=sample_rate, channels=1, 
callback=callback):
    while True:
        # The audio processing is done in the background via the 
'callback' function
        pass  # This loop keeps the main thread alive to listen 
for keyboard input
