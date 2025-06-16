import sounddevice as sd
import numpy as np
import tempfile
import subprocess
import os
from pynput import keyboard

# Configure audio settings
fs = 44100  # Sample rate
channels = 1  # Mono audio

def record_audio():
    """Records audio between two f8 key presses."""
    print("Press f8 to start recording, press f8 again to stop...")
    
    recording_state = {'is_recording': False, 'audio_data': [], 'stream': None}

    def on_press(key):
        try:
            if key == keyboard.Key.f8:
                if not recording_state['is_recording']:
                    # Start recording
                    recording_state['is_recording'] = True
                    recording_state['audio_data'] = []
                    recording_state['stream'] = sd.InputStream(
                        samplerate=fs, 
                        channels=channels,
                        callback=lambda indata, frames, time, status: recording_state['audio_data'].append(indata.copy())
                    )
                    recording_state['stream'].start()
                    print("Recording started...")
                else:
                    # Stop recording
                    if recording_state['stream']:
                        recording_state['stream'].stop()
                        recording_state['stream'].close()
                    return False  # Stop listener
        except Exception as e:
            print(f"Error in keyboard handler: {e}")

    # Create and start the listener
    with keyboard.Listener(on_press=on_press) as listener:
        listener.join()

    if recording_state['audio_data']:
        # Concatenate all audio chunks
        recording = np.concatenate(recording_state['audio_data'])
        
        # Save to temporary file
        with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as temp_audio_file:
            import soundfile as sf
            sf.write(temp_audio_file.name, recording, fs)
            print(f"Recording stopped. Audio saved to: {temp_audio_file.name}")
            return temp_audio_file.name
    
    return None

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
        audio_file = record_audio()  # This now handles both start and stop with f8
        if audio_file:
            transcript = transcribe_audio(audio_file)
            if transcript:
                type_text(transcript)
            os.remove(audio_file)  # Clean up the temporary audio file
