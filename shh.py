import keyboard
import sounddevice as sd
import numpy as np
import tempfile
import subprocess
import os

# Configure audio settings
fs = 44100  # Sample rate
channels = 1  # Mono audio




def record_audio():
    """Records audio while the f8 key is pressed."""

    print("Press and hold the f8 key to record audio...")

    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as temp_audio_file:
        audio_data = np.array([], dtype=np.float32)  # Initialize an empty array

        while keyboard.is_pressed('f8'):
            recording = sd.rec(int(fs * 0.1), samplerate=fs, channels=channels)  # Record in chunks
            sd.wait()
            audio_data = np.append(audio_data, recording[:, 0])  # Append new data

        sd.wait()  # Wait for any remaining audio

        # No need to write audio data manually here, sd.rec() already handles it

        print(f"Audio saved to: {temp_audio_file.name}")
        return temp_audio_file.name

def transcribe_audio(audio_file):
  """Transcribes the audio file using whisper.cpp."""

  whisper_cpp_path = "/Users/tomasztunguz/Documents/coding/whisper.cpp/build/bin/main"  # Path to whisper.cpp executable
  model_path = "/Users/tomasztunguz/Documents/coding/whisper.cpp/models/ggml-base.en.bin"  # Model path
  whisper_command = [
      whisper_cpp_path,
      "-m", model_path,  # Model file
      "-l", "en",       # Language
      "-f", audio_file  # Input file
  ]

  try:
    process = subprocess.run(whisper_command, capture_output=True, text=True)
    process.check_returncode()  # Raise an exception if whisper.cpp fails
    transcript = process.stdout.strip()
    print(f"Transcription: {transcript}")
    return transcript
  except subprocess.CalledProcessError as e:
    print(f"Error transcribing audio: {e}")
    return None

def type_text(text):
  """Types the transcribed text using the keyboard library."""

  keyboard.write(text)

if __name__ == "__main__":
  while True:
    keyboard.wait('f8')  # Wait for the f8 key to be pressed
    audio_file = record_audio()
    if audio_file:
      transcript = transcribe_audio(audio_file)
      if transcript:
        type_text(transcript)
      os.remove(audio_file)  # Clean up the temporary audio file
