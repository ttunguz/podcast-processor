package main

import (
	"fmt"
	"log"
	"os"

	"github.com/eiannone/keyboard"
	"github.com/go-audio/audio"
	"github.com/go-audio/wav"
	"github.com/gordonklaus/portaudio"
)

const (
	sampleRate = 44100
	channels   = 2
	bufferSize = 1024
)

func main() {
	if err := portaudio.Initialize(); err != nil {
		log.Fatal(err)
	}
	defer portaudio.Terminate()

	buffer := make([]float32, bufferSize)
	stream, err := portaudio.OpenDefaultStream(channels, 0, float64(sampleRate), len(buffer), buffer)
	if err != nil {
		log.Fatal(err)
	}
	defer stream.Close()

	if err := stream.Start(); err != nil {
		log.Fatal(err)
	}
	defer stream.Stop()

	fmt.Println("Press and hold the right Alt key to start recording. Release to stop.")

	if err := keyboard.Open(); err != nil {
		log.Fatal(err)
	}
	defer keyboard.Close()

	var recording bool
	var recordedData []float32

	for {
		_, key, err := keyboard.GetKey()
		if err != nil {
			log.Fatal(err)
		}

		if key == keyboard.KeyAltGr {
			if !recording {
				fmt.Println("Recording started...")
				recording = true
				recordedData = []float32{}
			} else {
				fmt.Println("Recording stopped.")
				recording = false
				saveWAV(recordedData)
			}
		}

		if recording {
			err := stream.Read()
			if err != nil {
				log.Fatal(err)
			}
			recordedData = append(recordedData, buffer...)
		}

		if key == keyboard.KeyEsc {
			fmt.Println("Exiting...")
			break
		}
	}
}

func saveWAV(buffer []float32) {
	tmpFile, err := os.CreateTemp("", "recording-*.wav")
	if err != nil {
		log.Fatal(err)
	}
	defer tmpFile.Close()

	enc := wav.NewEncoder(tmpFile, sampleRate, 32, channels, 1)
	defer enc.Close()

	audioBuf := &audio.Float32Buffer{
		Format: &audio.Format{
			NumChannels: channels,
			SampleRate:  sampleRate,
		},
		Data: buffer,
	}

	if err := enc.Write(audioBuf); err != nil {
		log.Fatal(err)
	}

	fmt.Printf("Recording saved to: %s\n", tmpFile.Name())
}
