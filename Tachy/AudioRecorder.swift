import Foundation
import AVFoundation

class AudioRecorder: NSObject {
    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var audioFileURL: URL?
    private(set) var isRecording = false

    /// Callback for live audio data (PCM 24kHz mono 16-bit)
    var onAudioData: ((Data) -> Void)?

    /// Callback for audio level (RMS 0.0-1.0)
    var onAudioLevel: ((Float) -> Void)?

    func startRecording(completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            beginRecording(completion: completion)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.beginRecording(completion: completion)
                    } else {
                        completion(false)
                    }
                }
            }
        default:
            completion(false)
        }
    }

    private func beginRecording(completion: @escaping (Bool) -> Void) {
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode

        // Target format: PCM 24kHz mono 16-bit (Realtime API format)
        let targetFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 24000, channels: 1, interleaved: true)!

        // Also prepare a file for batch fallback (m4a for Whisper)
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "voice_dictation_\(UUID().uuidString).m4a"
        audioFileURL = tempDir.appendingPathComponent(fileName)

        do {
            audioFile = try AVAudioFile(forWriting: audioFileURL!, settings: [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 16000,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ])
        } catch {
            print("Failed to create audio file: \(error)")
            completion(false)
            return
        }

        let inputFormat = inputNode.outputFormat(forBus: 0)

        // Converter for live streaming (to 24kHz PCM16)
        let liveConverter = AVAudioConverter(from: inputFormat, to: targetFormat)

        // Converter for file writing (to 16kHz Float32)
        let fileTargetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
        let fileConverter = AVAudioConverter(from: inputFormat, to: fileTargetFormat)

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self = self else { return }

            // Calculate RMS for audio level
            let rms = self.calculateRMS(buffer: buffer)
            DispatchQueue.main.async {
                self.onAudioLevel?(rms)
            }

            // Convert and send for live transcription
            if let converter = liveConverter, let onAudioData = self.onAudioData {
                let frameCount = AVAudioFrameCount(Double(buffer.frameLength) * targetFormat.sampleRate / inputFormat.sampleRate)
                guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCount) else { return }

                var error: NSError?
                var hasData = false
                converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
                    if hasData {
                        outStatus.pointee = .noDataNow
                        return nil
                    }
                    hasData = true
                    outStatus.pointee = .haveData
                    return buffer
                }

                if error == nil, convertedBuffer.frameLength > 0 {
                    let data = Data(bytes: convertedBuffer.int16ChannelData![0],
                                    count: Int(convertedBuffer.frameLength) * 2)
                    onAudioData(data)
                }
            }

            // Write to file for batch fallback
            if let converter = fileConverter, let audioFile = self.audioFile {
                let frameCount = AVAudioFrameCount(Double(buffer.frameLength) * fileTargetFormat.sampleRate / inputFormat.sampleRate)
                guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: fileTargetFormat, frameCapacity: frameCount) else { return }

                var error: NSError?
                var hasData = false
                converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
                    if hasData {
                        outStatus.pointee = .noDataNow
                        return nil
                    }
                    hasData = true
                    outStatus.pointee = .haveData
                    return buffer
                }

                if error == nil, convertedBuffer.frameLength > 0 {
                    try? audioFile.write(from: convertedBuffer)
                }
            }
        }

        do {
            engine.prepare()
            try engine.start()
            audioEngine = engine
            isRecording = true
            completion(true)
        } catch {
            print("Failed to start audio engine: \(error)")
            completion(false)
        }
    }

    func stopRecording(completion: @escaping (URL?) -> Void) {
        guard isRecording else {
            completion(nil)
            return
        }

        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        audioFile = nil
        isRecording = false
        onAudioData = nil
        onAudioLevel = nil
        completion(audioFileURL)
    }

    func cancelRecording() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        audioFile = nil
        isRecording = false
        onAudioData = nil
        onAudioLevel = nil

        // Delete temp file
        if let url = audioFileURL {
            try? FileManager.default.removeItem(at: url)
            audioFileURL = nil
        }
    }

    private func calculateRMS(buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData?[0] else { return 0 }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return 0 }

        var sum: Float = 0
        for i in 0..<frameLength {
            let sample = channelData[i]
            sum += sample * sample
        }
        return sqrt(sum / Float(frameLength))
    }
}
