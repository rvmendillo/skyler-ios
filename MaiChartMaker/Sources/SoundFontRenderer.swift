import Foundation
import AVFoundation

enum SoundFontRendererError: LocalizedError {
    case invalidBank
    case noTracks
    case cannotRender

    var errorDescription: String? {
        switch self {
        case .invalidBank: return "The selected soundfont could not be loaded. Use an SF2 or DLS bank."
        case .noTracks: return "The MIDI file contains no playable tracks."
        case .cannotRender: return "The MIDI sequence could not be rendered to audio."
        }
    }
}

enum SoundFontRenderer {
    static func copyBank(_ source: URL) throws -> URL {
        let access = source.startAccessingSecurityScopedResource()
        defer { if access { source.stopAccessingSecurityScopedResource() } }

        let ext = source.pathExtension.lowercased()
        guard ext == "sf2" || ext == "dls" else {
            throw SoundFontRendererError.invalidBank
        }

        let target = FileManager.default.temporaryDirectory
            .appendingPathComponent("soundfont-\(UUID().uuidString)")
            .appendingPathExtension(ext)
        try? FileManager.default.removeItem(at: target)
        try FileManager.default.copyItem(at: source, to: target)
        return target
    }

    static func renderWAV(
        midiURL: URL,
        bankURL: URL,
        program: Int
    ) async throws -> URL {
        let engine = AVAudioEngine()
        let sampler = AVAudioUnitSampler()
        engine.attach(sampler)
        engine.connect(sampler, to: engine.mainMixerNode, format: nil)

        do {
            try sampler.loadSoundBankInstrument(
                at: bankURL,
                program: UInt8(clamping: program),
                bankMSB: UInt8(kAUSampler_DefaultMelodicBankMSB),
                bankLSB: UInt8(kAUSampler_DefaultBankLSB)
            )
        } catch {
            throw SoundFontRendererError.invalidBank
        }

        let sequencer = AVAudioSequencer(audioEngine: engine)
        try sequencer.load(from: midiURL, options: .smf_ChannelsToTracks)
        guard !sequencer.tracks.isEmpty else { throw SoundFontRendererError.noTracks }

        for track in sequencer.tracks {
            track.destinationAudioUnit = sampler
        }

        let sampleRate = 48_000.0
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 2,
            interleaved: false
        ) else {
            throw SoundFontRendererError.cannotRender
        }

        let maximumFrames: AVAudioFrameCount = 4096
        try engine.enableManualRenderingMode(
            .offline,
            format: format,
            maximumFrameCount: maximumFrames
        )

        engine.prepare()
        try engine.start()

        sequencer.prepareToPlay()
        sequencer.currentPositionInBeats = 0
        try sequencer.start()

        let sequenceLength = max(
            0.1,
            sequencer.tracks.map(\.lengthInSeconds).max() ?? 0.1
        )
        let tailSeconds = 2.0
        let totalFrames = AVAudioFramePosition((sequenceLength + tailSeconds) * sampleRate)

        let wavURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("soundfont-render-\(UUID().uuidString).wav")
        let file = try AVAudioFile(forWriting: wavURL, settings: format.settings)

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: engine.manualRenderingFormat,
            frameCapacity: maximumFrames
        ) else {
            throw SoundFontRendererError.cannotRender
        }

        while engine.manualRenderingSampleTime < totalFrames {
            let remaining = totalFrames - engine.manualRenderingSampleTime
            let frames = AVAudioFrameCount(min(Int64(maximumFrames), remaining))

            let status = try engine.renderOffline(frames, to: buffer)
            switch status {
            case .success:
                try file.write(from: buffer)
            case .cannotDoInCurrentContext:
                continue
            case .insufficientDataFromInputNode:
                continue
            case .error:
                throw SoundFontRendererError.cannotRender
            @unknown default:
                throw SoundFontRendererError.cannotRender
            }
        }

        sequencer.stop()
        engine.stop()
        return wavURL
    }
}
