//
//  PoCAudioEngine.swift
//  CoreAudioTapPoC
//
//  SwiftUI から操作されるオーディオエンジンのオーケストレータ。
//
//  データフロー:
//    [他アプリの音声]
//      ↓ Core Audio process tap (muteBehavior=.muted で原音を止める)
//      ↓ ScreenCaptureKit audio
//      ↓ PCM ring buffer
//      ↓ AVAudioSourceNode (gain 適用)
//      ↓ default output device
//    [スピーカー / ヘッドホン]
//
//  状態:
//  - configuredGain: スライダーで設定された値（1.0〜4.0）。ON/OFF に関係なく保持。
//  - isEnabled:      ブースト処理の ON/OFF。OFF 時は effectiveGain = 1.0。
//  - effectiveGain:  backend に渡す目標ゲイン。
//
//  参照: docs/ARCHITECTURE.md / docs/TECH_SPIKE.md
//

import AudioToolbox
import Foundation
import os.log

protocol SystemTapControlling: AnyObject {
    var aggregateDeviceID: AudioObjectID { get }

    func setup() throws
    func teardown()
}

protocol AudioIOProcControlling: AnyObject {
    func start(withDeviceID deviceID: AudioObjectID) -> OSStatus
    func stop()
    func setLinearGain(_ linearGain: Float)
}

enum DiagnosticLogLevel: String, Equatable {
    case info
    case warning
    case error

    var label: String {
        switch self {
        case .info: "Info"
        case .warning: "Warn"
        case .error: "Error"
        }
    }
}

struct DiagnosticLogEntry: Identifiable, Equatable {
    let id = UUID()
    let timestamp: Date
    let level: DiagnosticLogLevel
    let message: String
}

final class DiagnosticLogStore: ObservableObject {
    @Published private(set) var entries: [DiagnosticLogEntry] = []

    private let maxEntries: Int

    init(maxEntries: Int = 80) {
        self.maxEntries = max(1, maxEntries)
    }

    func record(_ level: DiagnosticLogLevel, _ message: String, timestamp: Date = Date()) {
        entries.append(DiagnosticLogEntry(timestamp: timestamp, level: level, message: message))
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
    }

    func clear() {
        entries.removeAll()
    }
}

@MainActor
final class PoCAudioEngine: ObservableObject {

    // MARK: - Published state

    /// スライダー設定値（1.0〜4.0 = 100%〜400%）。ON/OFF に関係なく保持する。
    @Published var configuredGain: Double = 1.0 {
        didSet { applyEffectiveGain() }
    }

    /// ブースト ON/OFF。OFF でも configuredGain は保持し、effectiveGain だけ 1.0 にする。
    @Published var isEnabled: Bool = true {
        didSet { applyEffectiveGain() }
    }

    @Published private(set) var isRunning: Bool = false
    @Published private(set) var lastError: String?
    @Published private(set) var statusText: String = "idle"

    // 診断用: capture/render backend の状態
    @Published private(set) var captureBufferCount: UInt64 = 0
    @Published private(set) var renderCallCount: UInt64 = 0
    @Published private(set) var lastObservedGain: Float = 0.0
    let diagnosticLog: DiagnosticLogStore

    // MARK: - Internals

    private let log = Logger(subsystem: "dev.keisetsu.hazakura-volume-booster.poc", category: "PoCAudioEngine")
    private let audioBackend: any AudioProcessingBackend
    private var diagnosticTimer: Timer?
    private var startTask: Task<Void, Never>?
    private var hasReportedMissingCaptureBuffers = false
    private var hasReportedMissingRenderCalls = false

    init(
        diagnosticLog: DiagnosticLogStore = DiagnosticLogStore(),
        audioBackend: (any AudioProcessingBackend)? = nil
    ) {
        self.diagnosticLog = diagnosticLog
        self.audioBackend = audioBackend ?? BoostAudioPipeline(diagnosticLog: diagnosticLog)
        diagnosticLog.record(.info, "Engine initialized")
    }

    /// 現在の effective gain。UI 表示・IO proc 適用値はこれ。
    var effectiveGain: Double {
        guard isRunning, isEnabled else { return 1.0 }
        return max(1.0, min(4.0, configuredGain))
    }

    // MARK: - Public API

    func start() {
        startTask?.cancel()
        startTask = Task { [weak self] in
            await self?.startAsync()
        }
    }

    func startAsync() async {
        guard !isRunning else {
            log.warning("start() called while already running")
            diagnosticLog.record(.warning, "Start ignored because engine is already running")
            return
        }
        do {
            statusText = "starting audio pipeline…"
            diagnosticLog.record(.info, "Starting ScreenCaptureKit audio pipeline")
            try await audioBackend.start()

            isRunning = true
            applyEffectiveGain()

            lastError = nil
            statusText = "running"
            hasReportedMissingCaptureBuffers = false
            hasReportedMissingRenderCalls = false
            log.info("PoC engine started")
            diagnosticLog.record(.info, "Engine started")

            startDiagnosticTimer()
        } catch {
            let errMsg = error.localizedDescription
            log.error("start() failed: \(errMsg, privacy: .public)")
            diagnosticLog.record(.error, errMsg)
            lastError = errMsg
            statusText = "error"
            cleanupAfterFailure()
        }
    }

    func stop() {
        guard isRunning else { return }
        log.info("stop() called")
        diagnosticLog.record(.info, "Stopping engine")
        startTask?.cancel()
        startTask = nil
        diagnosticTimer?.invalidate()
        diagnosticTimer = nil

        audioBackend.setLinearGain(1.0)
        audioBackend.stop()

        isRunning = false
        isEnabled = true
        statusText = "stopped"
        captureBufferCount = 0
        renderCallCount = 0
        lastObservedGain = 0.0
        hasReportedMissingCaptureBuffers = false
        hasReportedMissingRenderCalls = false
        diagnosticLog.record(.info, "Engine stopped and gain reset to neutral")
    }

    /// 100%（素通し）に戻す。configuredGain を 1.0 にし、isEnabled を ON に戻す。
    func resetToNeutral() {
        configuredGain = 1.0
        isEnabled = true
        applyEffectiveGain()
        log.info("Reset to 100%")
        diagnosticLog.record(.info, "Reset gain to 100%")
    }

    // MARK: - Internals

    private func applyEffectiveGain() {
        let gain = Float(effectiveGain)
        audioBackend.setLinearGain(gain)
        if isRunning {
            diagnosticLog.record(.info, "Applied effective gain \(String(format: "%.2f", gain))x")
        }
    }

    private func cleanupAfterFailure() {
        diagnosticLog.record(.warning, "Cleaning up after startup failure")
        diagnosticTimer?.invalidate()
        diagnosticTimer = nil
        audioBackend.setLinearGain(1.0)
        audioBackend.stop()
        hasReportedMissingCaptureBuffers = false
        hasReportedMissingRenderCalls = false
        diagnosticLog.record(.info, "Cleanup after failure finished")
    }

    private func startDiagnosticTimer() {
        diagnosticTimer?.invalidate()
        diagnosticTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                let diagnostics = self.audioBackend.diagnostics
                self.captureBufferCount = diagnostics.captureBufferCount
                self.renderCallCount = diagnostics.renderCallCount
                self.lastObservedGain = diagnostics.lastObservedGain
                if self.isRunning && diagnostics.captureBufferCount == 0 && !self.hasReportedMissingCaptureBuffers {
                    self.hasReportedMissingCaptureBuffers = true
                    self.diagnosticLog.record(.warning, "ScreenCaptureKit audio buffers have not arrived yet")
                }
                if self.isRunning && diagnostics.renderCallCount == 0 && !self.hasReportedMissingRenderCalls {
                    self.hasReportedMissingRenderCalls = true
                    self.diagnosticLog.record(.warning, "AVAudioEngine render callback has not been called yet")
                }
            }
        }
    }
}

// AudioIOProc は Objective-C のシングルスレッド利用クラス。PoCAudioEngine 内で
// 単一のバックグラウンドタスクから操作されるため @unchecked Sendable とする。
extension AudioIOProc: AudioIOProcControlling, @unchecked Sendable {}
