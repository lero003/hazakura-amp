//
//  BoostAudioPipeline.swift
//  CoreAudioTapPoC
//

import AVFAudio
import Foundation

enum AudioPipelineTiming {
    static let ringBufferCapacityFrames = 16_384
    static let latencyBudgetFrames = 8_192
}

final class BoostAudioPipeline: AudioProcessingBackend, @unchecked Sendable {
    private let ringBuffer = PCMFloatRingBuffer(
        capacityFrames: AudioPipelineTiming.ringBufferCapacityFrames,
        channelCount: 2
    )
    private let meter = AudioBackendMeter()
    private let diagnosticLog: DiagnosticLogStore
    private let systemOutputMuter: any SystemTapControlling
    private let onBackendFailure: (@Sendable (String) -> Void)?
    private let eqLock = NSLock()
    private var equalizerSettings = EqualizerSettings.neutral
    private var engine: AVAudioEngine?
    private var sourceNode: AVAudioSourceNode?
    private var equalizerNode: AVAudioUnitEQ?
    private var captureSource: ScreenCaptureAudioSource?

    var diagnostics: AudioBackendDiagnostics {
        meter.diagnostics
    }

    init(
        diagnosticLog: DiagnosticLogStore,
        systemOutputMuter: (any SystemTapControlling)? = nil,
        onBackendFailure: (@Sendable (String) -> Void)? = nil
    ) {
        self.diagnosticLog = diagnosticLog
        self.systemOutputMuter = systemOutputMuter ?? SystemTap(diagnosticLog: diagnosticLog)
        self.onBackendFailure = onBackendFailure
    }

    func start() async throws {
        stop()
        ringBuffer.clear()
        meter.resetCounters()

        do {
            diagnosticLog.record(.info, "Muting original system output with Core Audio process tap")
            try systemOutputMuter.setup()
        } catch {
            diagnosticLog.record(.error, "Original output mute setup failed: \(error.localizedDescription)")
            throw error
        }

        let audioEngine = AVAudioEngine()
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 2, interleaved: false)!
        let source = AVAudioSourceNode(format: format) { [ringBuffer, meter] isSilence, _, frameCount, outputData in
            let gain = meter.advanceOutputGain(frameCount: Int(frameCount), sampleRate: 48_000)
            let framesRead = ringBuffer.read(
                into: outputData,
                frameCount: Int(frameCount),
                gain: gain
            )
            meter.markRenderCall(
                requestedFrames: Int(frameCount),
                framesRead: framesRead,
                availableFrames: ringBuffer.availableFrames
            )
            isSilence.pointee = ObjCBool(framesRead == 0 || gain == 0.0)
            return noErr
        }

        let eq = makeEqualizerNode()
        let settings = eqLock.withLock { equalizerSettings }
        applyEqualizerSettings(settings, to: eq)

        audioEngine.attach(source)
        audioEngine.attach(eq)
        audioEngine.connect(source, to: eq, format: format)
        audioEngine.connect(eq, to: audioEngine.mainMixerNode, format: format)
        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            systemOutputMuter.teardown()
            throw error
        }

        let capture = ScreenCaptureAudioSource(
            ringBuffer: ringBuffer,
            meter: meter,
            diagnosticLog: diagnosticLog,
            onStoppedWithError: onBackendFailure
        )
        do {
            try await capture.start()
        } catch {
            audioEngine.stop()
            systemOutputMuter.teardown()
            throw error
        }

        engine = audioEngine
        sourceNode = source
        equalizerNode = eq
        captureSource = capture
        diagnosticLog.record(.info, "Original output muted; boosted pipeline is now the audible path")
    }

    func stop() {
        captureSource?.stop()
        captureSource = nil
        engine?.stop()
        engine = nil
        sourceNode = nil
        equalizerNode = nil
        systemOutputMuter.teardown()
        ringBuffer.clear()
        meter.resetCounters()
    }

    func setLinearGain(_ linearGain: Float) {
        meter.setLinearGain(linearGain)
    }

    func snapLinearGain(_ linearGain: Float) {
        meter.snapLinearGain(linearGain)
    }

    func setEqualizer(_ settings: EqualizerSettings) {
        let sanitized = settings.sanitized
        eqLock.withLock {
            equalizerSettings = sanitized
        }
        if let equalizerNode {
            applyEqualizerSettings(sanitized, to: equalizerNode)
        }
    }

    private func makeEqualizerNode() -> AVAudioUnitEQ {
        let eq = AVAudioUnitEQ(numberOfBands: 3)
        eq.globalGain = 0

        // Low shelf ~250 Hz
        eq.bands[0].filterType = .lowShelf
        eq.bands[0].frequency = 250
        eq.bands[0].bandwidth = 1.0
        eq.bands[0].bypass = false

        // Mid peak ~1 kHz
        eq.bands[1].filterType = .parametric
        eq.bands[1].frequency = 1_000
        eq.bands[1].bandwidth = 1.0
        eq.bands[1].bypass = false

        // High shelf ~4 kHz
        eq.bands[2].filterType = .highShelf
        eq.bands[2].frequency = 4_000
        eq.bands[2].bandwidth = 1.0
        eq.bands[2].bypass = false

        return eq
    }

    private func applyEqualizerSettings(_ settings: EqualizerSettings, to eq: AVAudioUnitEQ) {
        eq.bands[0].gain = settings.lowDB
        eq.bands[1].gain = settings.midDB
        eq.bands[2].gain = settings.highDB
    }
}
