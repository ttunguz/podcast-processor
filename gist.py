from pynput.keyboard import Key, Listener, Controller
import sounddevice as sd
import numpy as np
from scipy.io.wavfile import write
import subprocess
import os
import re
import datetime

# Set the sample rate to 16 kHz
sample_rate =  16000
recording = False
filename_prefix = "~/Documents/transcripts/"
keyboard = Controller()

def on_press(key):
    global recording_audio
    recording_audio = [] # Reset
    global recording
    if key == Key.alt_l:
        recording = True
        print("Starting recording")

def on_release(key):
    global recording
    if key == Key.alt_l:
        recording = False
        print("Stopped recording")
        sd.wait()

        if recording_audio:
                # create a filename called output & the current date&time to the millisecond 
            now = datetime.datetime.now()
            date_time_str = now.strftime("%Y%m%d-%H%M%S-%f")
            filename = filename_prefix + "output_" + date_time_str + ".wav"
            # Specify the output file path for the processed text
            output_file = filename_prefix + "output_" + date_time_str + ".txt"
            output_file_main = filename_prefix + "output_" + date_time_str 


            # Convert to numpy array and normalize to int16
            recording_np = np.concatenate(recording_audio, axis=0)
            recording_np = np.int16(recording_np * np.iinfo(np.int16).max)

            # Write to wav file
            write(filename, sample_rate, recording_np)

            process_audio(filename, output_file, output_file_main)
        else:
            print("No audio recorded")

def recording_callback(indata, frames, time, status):
    if recording:
        recording_audio.append(indata.copy())

def process_audio(filename, output_file, output_file_main):
    print("Processing audio")
    
    # run the command with the above options and also specify the medium model using this syntax -m FNAME,  --model FNAME       [models/ggml-base.en.bin] model path
#    subprocess.run(["./main", "-otxt", "--output-file", output_file_main, "-m", "models/ggml-small.en-q5_1.bin", filename])
    subprocess.run(["./main", "-otxt", "--output-file", output_file_main, "-m", "models/ggml-small.en-q5_1.bin", "--split-on-word", filename])

    print(output_file)
    # Read the processed text from the file
    if os.path.exists(output_file):
        with open(output_file, 'r') as file:
            print("opening :  " + output_file)
            processed_text = file.read().strip()

        # Remove timestamps from the processed text
        processed_text = re.sub(r'\[\d{2}:\d{2}:\d{2}\.\d{3} --> \d{2}:\d{2}:\d{2}\.\d{3}\]', '', processed_text)

        # remove any text contained within square brackets
        processed_text = re.sub(r'\[.*?\]', '', processed_text)

        # remove any text contained within parentheses
        processed_text = re.sub(r'\(.*?\)', '', processed_text)

        # remove line breaks
        processed_text = processed_text.replace("\n", " ")

        # Type out the processed text
        keyboard.type(processed_text)

        # Clean up by removing the output filename
        # if outpufile exists, remove it 
        if os.path.exists(output_file):
            os.remove(output_file)
        if os.path.exists(output_file_main):
            os.remove(output_file_main)

    # Clean up by removing the recorded audio file
    os.remove(filename)

if __name__ == "__main__":
    recording_audio = []
    with Listener(on_press=on_press, on_release=on_release) as listener:
        with sd.InputStream(samplerate=sample_rate, channels=1, callback=recording_callback):
            listener.join()


