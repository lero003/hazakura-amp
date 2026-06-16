//
//  AudioProcessingBackend.swift
//  CoreAudioTapPoC
//

import Foundation

struct AudioBackendDiagnostics: Equatable {
    var captureBufferCount: UInt64 = 0
    var renderCallCount: UInt64 = 0
    var lastObservedGain: Float = 0.0
}

protocol AudioProcessingBackend: AnyObject, Sendable {
    var diagnostics: AudioBackendDiagnostics { get }

    func start() async throws
    func stop()
    func setLinearGain(_ linearGain: Float)
}

final class AudioBackendMeter: @unchecked Sendable {
    private let lock = NSLock()
    private var captureBuffers: UInt64 = 0
    private var renderCalls: UInt64 = 0
    private var currentLinearGain: Float = 1.0
    private var currentOutputGain: Float = 0.0

    var linearGain: Float {
        lock.withLock { currentLinearGain }
    }

    var outputGain: Float {
        lock.withLock { currentOutputGain }
    }

    var diagnostics: AudioBackendDiagnostics {
        lock.withLock {
            AudioBackendDiagnostics(
                captureBufferCount: captureBuffers,
                renderCallCount: renderCalls,
                lastObservedGain: currentOutputGain
            )
        }
    }

    func resetCounters() {
        lock.withLock {
            captureBuffers = 0
            renderCalls = 0
        }
    }

    func setLinearGain(_ gain: Float) {
        lock.withLock {
            currentLinearGain = gain
            currentOutputGain = max(0.0, gain)
        }
    }

    func markCaptureBuffer() {
        lock.withLock {
            captureBuffers &+= 1
        }
    }

    func markRenderCall() {
        lock.withLock {
            renderCalls &+= 1
        }
    }
}
