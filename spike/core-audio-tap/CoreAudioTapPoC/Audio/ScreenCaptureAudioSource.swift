//
//  ScreenCaptureAudioSource.swift
//  CoreAudioTapPoC
//

import AudioToolbox
import CoreMedia
import Foundation
import ScreenCaptureKit

final class ScreenCaptureAudioSource: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private let ringBuffer: PCMFloatRingBuffer
    private let meter: AudioBackendMeter
    private let diagnosticLog: DiagnosticLogStore
    private let sampleQueue = DispatchQueue(label: "dev.keisetsu.hazakura-volume-booster.poc.screen-audio")
    private var stream: SCStream?
    private var hasReportedUnsupportedFormat = false

    init(
        ringBuffer: PCMFloatRingBuffer,
        meter: AudioBackendMeter,
        diagnosticLog: DiagnosticLogStore
    ) {
        self.ringBuffer = ringBuffer
        self.meter = meter
        self.diagnosticLog = diagnosticLog
    }

    func start() async throws {
        let content = try await SCShareableContent.current
        guard let display = content.displays.first else {
            throw makeError("ScreenCaptureKit could not find a display to capture")
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.width = 2
        configuration.height = 2
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        configuration.showsCursor = false
        configuration.capturesAudio = true
        configuration.excludesCurrentProcessAudio = true
        configuration.sampleRate = 48_000
        configuration.channelCount = 2

        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: sampleQueue)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            stream.startCapture { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }

        self.stream = stream
        record(.info, "ScreenCaptureKit audio capture started")
    }

    func stop() {
        guard let stream else { return }
        self.stream = nil
        stream.stopCapture { [weak self] error in
            if let error {
                self?.record(.warning, "ScreenCaptureKit stop reported: \(error.localizedDescription)")
            }
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, sampleBuffer.isValid else { return }

        let frameCount = CMSampleBufferGetNumSamples(sampleBuffer)
        guard frameCount > 0 else { return }
        guard isFloat32PCM(sampleBuffer) else {
            if !hasReportedUnsupportedFormat {
                hasReportedUnsupportedFormat = true
                record(.warning, "ScreenCaptureKit audio format is not Float32 PCM; buffer ignored")
            }
            return
        }

        var bufferListSize = 0
        var blockBuffer: CMBlockBuffer?
        var status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: &bufferListSize,
            bufferListOut: nil,
            bufferListSize: 0,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &blockBuffer
        )
        guard status == noErr, bufferListSize > 0 else {
            record(.warning, "Could not size ScreenCaptureKit audio buffer list: OSStatus=\(status)")
            return
        }

        let rawBufferList = UnsafeMutableRawPointer.allocate(
            byteCount: bufferListSize,
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { rawBufferList.deallocate() }

        let audioBufferList = rawBufferList.bindMemory(to: AudioBufferList.self, capacity: 1)
        status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: audioBufferList,
            bufferListSize: bufferListSize,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &blockBuffer
        )
        guard status == noErr else {
            record(.warning, "Could not read ScreenCaptureKit audio buffer list: OSStatus=\(status)")
            return
        }

        ringBuffer.write(fromAudioBufferList: audioBufferList, frameCount: frameCount)
        ringBuffer.trimToMostRecentFrames(AudioPipelineTiming.latencyBudgetFrames)
        meter.markCaptureBuffer()
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        record(.error, "ScreenCaptureKit stream stopped: \(error.localizedDescription)")
    }

    private func isFloat32PCM(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard
            let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
            let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)
        else {
            return false
        }

        let description = streamDescription.pointee
        return description.mFormatID == kAudioFormatLinearPCM
            && description.mBitsPerChannel == 32
            && (description.mFormatFlags & kAudioFormatFlagIsFloat) != 0
    }

    private func record(_ level: DiagnosticLogLevel, _ message: String) {
        Task { @MainActor [diagnosticLog] in
            diagnosticLog.record(level, message)
        }
    }

    private func makeError(_ message: String) -> NSError {
        NSError(
            domain: "ScreenCaptureAudioSource",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}
