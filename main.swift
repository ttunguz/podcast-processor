import Foundation
import WhisperKit

@main
struct WhisperKitCLI {
    static func main() async throws {
        // Initialize WhisperKit
        let config = WhisperKit.Config()
        let whisperKit = try await WhisperKit(config: config)
        
        // Get input file path from arguments
        guard CommandLine.arguments.count > 1 else {
            print("Please provide an audio file path")
            exit(1)
        }
        let audioPath = CommandLine.arguments[1]
        
        // Transcribe
        let result = try await whisperKit.transcribe(audioPath)
        print(result.text)
    }
}