//
//  AudioProcessingBackend.swift
//  CoreAudioTapPoC
//

import Foundation

enum AudioBackendHealthLevel: String, Equatable {
    case ok = "OK"
    case watch = "Watch"
    case warning = "Warning"
}

struct AudioBackendHealthAssessment: Equatable {
    let level: AudioBackendHealthLevel
    let underrunRate: Double
    let summary: String
    let recommendation: String
}

struct AudioBackendDiagnostics: Equatable {
    var captureBufferCount: UInt64 = 0
    var renderCallCount: UInt64 = 0
    var lastObservedGain: Float = 0.0
    var availableFrames: Int = 0
    var underrunCount: UInt64 = 0
    var droppedFrameCount: UInt64 = 0
    var latestBufferFrameCount: Int = 0
}

extension AudioBackendDiagnostics {
    var healthAssessment: AudioBackendHealthAssessment {
        let rate: Double
        if renderCallCount == 0 {
            rate = 0.0
        } else {
            rate = Double(underrunCount) / Double(renderCallCount)
        }
        let percent = String(format: "%.2f%%", rate * 100)

        if droppedFrameCount > 0 {
            return AudioBackendHealthAssessment(
                level: .warning,
                underrunRate: rate,
                summary: "Warning: underruns \(percent), dropped \(droppedFrameCount)",
                recommendation: "Restart boost and check output device changes if audio glitches are audible."
            )
        }

        if renderCallCount == 0 {
            return AudioBackendHealthAssessment(
                level: .watch,
                underrunRate: rate,
                summary: "Watch: waiting for render callbacks",
                recommendation: "Start playback and confirm render callbacks begin."
            )
        }

        if underrunCount == 0 {
            return AudioBackendHealthAssessment(
                level: .ok,
                underrunRate: rate,
                summary: "OK: underruns 0.00%, dropped 0",
                recommendation: "No buffer health issue detected."
            )
        }

        if rate < 0.005 {
            return AudioBackendHealthAssessment(
                level: .watch,
                underrunRate: rate,
                summary: "Watch: underruns \(percent), dropped 0",
                recommendation: "Continue playback; investigate only if pops or dropouts are audible."
            )
        }

        return AudioBackendHealthAssessment(
            level: .warning,
            underrunRate: rate,
            summary: "Warning: underruns \(percent), dropped 0",
            recommendation: "Frequent underruns detected; restart boost or reduce competing audio load."
        )
    }
}

protocol AudioProcessingBackend: AnyObject, Sendable {
    var diagnostics: AudioBackendDiagnostics { get }

    func start() async throws
    func stop()
    /// Target linear gain. Implementations should ramp toward the value when audible.
    func setLinearGain(_ linearGain: Float)
    /// Immediately force gain (used for stop/shutdown safety paths).
    func snapLinearGain(_ linearGain: Float)
    func setEqualizer(_ settings: EqualizerSettings)
}

extension AudioProcessingBackend {
    func snapLinearGain(_ linearGain: Float) {
        setLinearGain(linearGain)
    }

    func setEqualizer(_ settings: EqualizerSettings) {
        // Optional for backends that only process gain.
        _ = settings
    }
}

final class AudioBackendMeter: @unchecked Sendable {
    /// ~50 ms gain ramp at typical render rates, matching docs/RISKS.md guidance.
    static let defaultRampSeconds: Float = 0.05

    private let lock = NSLock()
    private let rampSeconds: Float
    private var captureBuffers: UInt64 = 0
    private var renderCalls: UInt64 = 0
    private var targetLinearGain: Float = 1.0
    private var smoothedOutputGain: Float = 0.0
    private var currentAvailableFrames: Int = 0
    private var underruns: UInt64 = 0
    private var droppedFrames: UInt64 = 0
    private var latestBufferFrames: Int = 0

    init(rampSeconds: Float = AudioBackendMeter.defaultRampSeconds) {
        self.rampSeconds = max(0.001, rampSeconds)
    }

    var linearGain: Float {
        lock.withLock { targetLinearGain }
    }

    var outputGain: Float {
        lock.withLock { smoothedOutputGain }
    }

    var diagnostics: AudioBackendDiagnostics {
        lock.withLock {
            AudioBackendDiagnostics(
                captureBufferCount: captureBuffers,
                renderCallCount: renderCalls,
                lastObservedGain: smoothedOutputGain,
                availableFrames: currentAvailableFrames,
                underrunCount: underruns,
                droppedFrameCount: droppedFrames,
                latestBufferFrameCount: latestBufferFrames
            )
        }
    }

    func resetCounters() {
        lock.withLock {
            captureBuffers = 0
            renderCalls = 0
            currentAvailableFrames = 0
            underruns = 0
            droppedFrames = 0
            latestBufferFrames = 0
        }
    }

    /// Set the target gain; render path ramps toward it.
    func setLinearGain(_ gain: Float) {
        lock.withLock {
            targetLinearGain = max(0.0, gain)
        }
    }

    /// Instantly force gain (stop / permission failure / termination).
    func snapLinearGain(_ gain: Float) {
        lock.withLock {
            let safe = max(0.0, gain)
            targetLinearGain = safe
            smoothedOutputGain = safe
        }
    }

    /// Advance the smoothed gain for the upcoming render quantum and return it.
    func advanceOutputGain(frameCount: Int, sampleRate: Double = 48_000) -> Float {
        lock.withLock {
            let frames = max(0, frameCount)
            guard frames > 0 else { return smoothedOutputGain }

            let rampFrames = max(1.0, Float(sampleRate) * rampSeconds)
            let alpha = min(1.0, Float(frames) / rampFrames)
            smoothedOutputGain += (targetLinearGain - smoothedOutputGain) * alpha

            // Snap residual error so we land exactly on target.
            if abs(targetLinearGain - smoothedOutputGain) < 0.000_1 {
                smoothedOutputGain = targetLinearGain
            }
            return smoothedOutputGain
        }
    }

    func markCaptureBuffer(frameCount: Int, droppedFrames: Int, availableFrames: Int) {
        lock.withLock {
            captureBuffers &+= 1
            latestBufferFrames = max(0, frameCount)
            self.droppedFrames &+= UInt64(max(0, droppedFrames))
            currentAvailableFrames = max(0, availableFrames)
        }
    }

    func markRenderCall(requestedFrames: Int, framesRead: Int, availableFrames: Int) {
        lock.withLock {
            renderCalls &+= 1
            if max(0, framesRead) < max(0, requestedFrames) {
                underruns &+= 1
            }
            currentAvailableFrames = max(0, availableFrames)
        }
    }
}
