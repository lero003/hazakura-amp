import SwiftUI
import AppKit

enum BoostStatusSeverity: Equatable {
    case normal
    case notice
    case warning
    case error
}

struct BoostStatusPresentation: Equatable {
    let headline: String
    let detail: String
    let severity: BoostStatusSeverity
    let showsErrorBanner: Bool
    let chipLabel: String

    static func make(statusText: String, isRunning: Bool, lastError: String?) -> BoostStatusPresentation {
        if isRunning {
            return BoostStatusPresentation(
                headline: "動作中",
                detail: "オーディオはローカルで処理されます。録音・保存・送信は行いません。",
                severity: .normal,
                showsErrorBanner: false,
                chipLabel: "動作中"
            )
        }

        switch statusText {
        case PoCAudioEngineStatus.sleeping.rawValue:
            return BoostStatusPresentation(
                headline: "スリープ中",
                detail: "スリープ準備で出力ゲインを 100% に戻しました。",
                severity: .notice,
                showsErrorBanner: false,
                chipLabel: "スリープ中"
            )
        case PoCAudioEngineStatus.waking.rawValue:
            return BoostStatusPresentation(
                headline: "復帰中",
                detail: "スリープ復帰後にオーディオ経路を再接続しています。",
                severity: .notice,
                showsErrorBanner: false,
                chipLabel: "復帰中"
            )
        case "reconnecting output":
            return BoostStatusPresentation(
                headline: "出力先を再接続中",
                detail: "既定の出力デバイス変更後にオーディオ経路を再構築しています。",
                severity: .notice,
                showsErrorBanner: false,
                chipLabel: "再接続中"
            )
        case PoCAudioEngineStatus.manualStartRequired.rawValue:
            return BoostStatusPresentation(
                headline: "復帰後に開始が必要です",
                detail: "開始を押してオーディオ経路を再接続してください。",
                severity: .notice,
                showsErrorBanner: false,
                chipLabel: "開始が必要"
            )
        case PoCAudioEngineStatus.restartRequired.rawValue:
            return BoostStatusPresentation(
                headline: "再開が必要です",
                detail: "開始を押してオーディオ経路を再構築してください。\(lastError.map { " \($0)" } ?? "")",
                severity: .warning,
                showsErrorBanner: true,
                chipLabel: "再開が必要"
            )
        case PoCAudioEngineStatus.permissionDenied.rawValue:
            return BoostStatusPresentation(
                headline: "システム音声へのアクセスが許可されていません",
                detail: "システム設定 > プライバシーとセキュリティ で Hazakura Amp を許可してから、再度 開始 を押してください。",
                severity: .warning,
                showsErrorBanner: true,
                chipLabel: "権限が必要"
            )
        case PoCAudioEngineStatus.error.rawValue:
            return BoostStatusPresentation(
                headline: "エラーが発生しました",
                detail: "開始を押して再試行してください。繰り返す場合は診断を開いてください。\(lastError.map { " \($0)" } ?? "")",
                severity: .error,
                showsErrorBanner: true,
                chipLabel: "エラー"
            )
        default:
            return BoostStatusPresentation(
                headline: "ブーストを開始してください",
                detail: "システム音をローカル処理します。録音・保存・送信は行いません。",
                severity: .normal,
                showsErrorBanner: false,
                chipLabel: "停止中"
            )
        }
    }
}

struct ContentView: View {
    @ObservedObject private var engine: PoCAudioEngine
    @StateObject private var safariExtensionController = SafariExtensionController()
    @State private var isShowingDevMode = false

    init(engine: PoCAudioEngine) {
        self.engine = engine
    }

    var body: some View {
        // Keep a fixed popover height budget and scroll when diagnostics expand,
        // so primary controls stay reachable instead of being pushed off-screen.
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 14) {
                BoostHeaderView(presentation: statusPresentation)

                StatusMessageView(presentation: statusPresentation)

                if statusPresentation.showsErrorBanner {
                    ErrorBannerView(presentation: statusPresentation)
                }

                BoostControlsSection(
                    configuredGain: $engine.configuredGain,
                    isRunning: engine.isRunning,
                    gainLabel: gainLabel,
                    gainAccessibilityValue: gainAccessibilityValue,
                    isHighBoost: isHighBoost,
                    onSelectPreset: { engine.applyPreset($0) }
                )

                EqualizerSection(equalizer: $engine.equalizer)

                BoostActionBar(
                    isRunning: engine.isRunning,
                    startStopAccessibilityLabel: startStopAccessibilityLabel,
                    onToggle: {
                        if engine.isRunning { engine.stop() } else { engine.start() }
                    },
                    onQuit: {
                        engine.shutdownForAppTermination()
                        NSApplication.shared.terminate(nil)
                    }
                )

                DisclosureGroup(isExpanded: $isShowingDevMode) {
                    DevDiagnosticsView(
                        captureBufferCount: engine.captureBufferCount,
                        renderCallCount: engine.renderCallCount,
                        lastObservedGain: engine.lastObservedGain,
                        availableFrames: engine.availableFrames,
                        underrunCount: engine.underrunCount,
                        droppedFrameCount: engine.droppedFrameCount,
                        latestBufferFrameCount: engine.latestBufferFrameCount,
                        health: engine.backendHealth,
                        isRunning: engine.isRunning,
                        safariExtensionController: safariExtensionController,
                        logStore: engine.diagnosticLog,
                        diagnosticSnapshot: engine.diagnosticSnapshotText()
                    )
                    .padding(.top, 6)
                } label: {
                    Text("診断")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Developer diagnostics")
                        .accessibilityHint("Shows audio pipeline counters and recent diagnostic events.")
                }

                ProductFooterView()
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 380)
        .frame(maxHeight: 560)
    }

    // MARK: - Helpers

    private var statusPresentation: BoostStatusPresentation {
        BoostStatusPresentation.make(
            statusText: engine.statusText,
            isRunning: engine.isRunning,
            lastError: engine.lastError
        )
    }

    private var isHighBoost: Bool {
        engine.configuredGain >= 3.0
    }

    private var gainLabel: String {
        let percent = Int((engine.configuredGain * 100).rounded())
        if engine.configuredGain == 1.0 { return "100%" }
        return "ブースト \(percent)%"
    }

    private var gainAccessibilityValue: String {
        "\(Int((engine.configuredGain * 100).rounded())) percent"
    }

    private var startStopAccessibilityLabel: String {
        engine.isRunning ? "Stop boost processing" : "Start boost processing"
    }
}

// MARK: - Header / Status

private struct BoostHeaderView: View {
    let presentation: BoostStatusPresentation

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Text("Hazakura Amp")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            StatusIndicator(presentation: presentation)
        }
    }
}

private struct StatusMessageView: View {
    let presentation: BoostStatusPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(presentation.headline)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(headlineColor)
            Text(presentation.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var headlineColor: Color {
        switch presentation.severity {
        case .normal:
            return .primary
        case .notice:
            return .secondary
        case .warning:
            return .orange
        case .error:
            return .red
        }
    }
}

/// メニューバーアイコン横の稼働状態インジケータ。
struct StatusIndicator: View {
    let presentation: BoostStatusPresentation

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(dotColor)
                .frame(width: 7, height: 7)
            Text(presentation.chipLabel)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(labelColor)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(chipBackground, in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Status, \(presentation.chipLabel)")
    }

    private var dotColor: Color {
        switch presentation.severity {
        case .normal:
            return presentation.chipLabel == "動作中" ? Color.green : Color.secondary.opacity(0.55)
        case .notice:
            return Color.orange.opacity(0.85)
        case .warning:
            return Color.orange
        case .error:
            return Color.red
        }
    }

    private var labelColor: Color {
        switch presentation.severity {
        case .normal:
            return .secondary
        case .notice:
            return .secondary
        case .warning:
            return .orange
        case .error:
            return .red
        }
    }

    private var chipBackground: Color {
        switch presentation.severity {
        case .normal:
            return Color.secondary.opacity(0.10)
        case .notice:
            return Color.orange.opacity(0.10)
        case .warning:
            return Color.orange.opacity(0.14)
        case .error:
            return Color.red.opacity(0.12)
        }
    }
}

private struct ErrorBannerView: View {
    let presentation: BoostStatusPresentation

    var body: some View {
        Label {
            Text(presentation.detail)
                .font(.caption)
                .foregroundStyle(textColor)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: presentation.severity == .error ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(textColor)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(backgroundColor, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Warning, \(presentation.detail)")
    }

    private var textColor: Color {
        presentation.severity == .error ? .red : .orange
    }

    private var backgroundColor: Color {
        presentation.severity == .error
            ? Color.red.opacity(0.10)
            : Color.orange.opacity(0.10)
    }
}

// MARK: - Controls / Actions

private struct BoostControlsSection: View {
    @Binding var configuredGain: Double
    let isRunning: Bool
    let gainLabel: String
    let gainAccessibilityValue: String
    let isHighBoost: Bool
    let onSelectPreset: (BoostPreset) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("ブースト")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(gainLabel)
                    .font(.body)
                    .fontWeight(.medium)
                    .monospacedDigit()
                    .foregroundStyle(isHighBoost ? Color.orange : Color.primary)
                    .frame(minWidth: 100, alignment: .trailing)
            }

            Slider(value: $configuredGain, in: 0.0...4.0, step: 0.01) {
                Text("ブーストゲイン")
            } minimumValueLabel: {
                Text("0%").font(.caption2).foregroundStyle(.secondary)
            } maximumValueLabel: {
                Text("400%").font(.caption2).foregroundStyle(.secondary)
            }
            .disabled(!isRunning)
            .accessibilityLabel("Boost level")
            .accessibilityValue(gainAccessibilityValue)
            .accessibilityHint("Adjusts the local system audio boost level.")

            HStack(spacing: 6) {
                ForEach(BoostPreset.allCases) { preset in
                    let isActive = BoostPreset.matching(gain: configuredGain) == preset
                    Button {
                        onSelectPreset(preset)
                    } label: {
                        VStack(spacing: 1) {
                            Text(preset.title)
                                .font(.caption2)
                                .fontWeight(.semibold)
                            Text(preset.percentLabel)
                                .font(.caption2)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.bordered)
                    .tint(isActive ? Color.accentColor : Color.secondary)
                    .controlSize(.small)
                    .accessibilityLabel("Boost preset \(preset.title), \(preset.percentLabel)")
                }
            }

            if isHighBoost {
                Text("300% 以上では音源によって割れやすくなります。")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct EqualizerSection: View {
    @Binding var equalizer: EqualizerSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("音質")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("リセット") {
                    equalizer = .neutral
                }
                .controlSize(.mini)
                .disabled(equalizer == .neutral)
                .accessibilityLabel("Reset equalizer")
            }

            eqSlider(title: "低域", value: lowBinding)
            eqSlider(title: "中域", value: midBinding)
            eqSlider(title: "高域", value: highBinding)

            Text("簡易3バンドEQ（±6 dB）。ノイズ除去などの高度な処理は行いません。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var lowBinding: Binding<Double> {
        Binding(
            get: { Double(equalizer.lowDB) },
            set: { equalizer.lowDB = Float($0) }
        )
    }

    private var midBinding: Binding<Double> {
        Binding(
            get: { Double(equalizer.midDB) },
            set: { equalizer.midDB = Float($0) }
        )
    }

    private var highBinding: Binding<Double> {
        Binding(
            get: { Double(equalizer.highDB) },
            set: { equalizer.highDB = Float($0) }
        )
    }

    private func eqSlider(title: String, value: Binding<Double>) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.caption)
                .frame(width: 28, alignment: .leading)
            Slider(value: value, in: -6...6, step: 0.5)
                .controlSize(.small)
                .accessibilityLabel("\(title) equalizer band")
                .accessibilityValue("\(Int(value.wrappedValue.rounded())) decibels")
            Text(String(format: "%+.1f", value.wrappedValue))
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .trailing)
        }
    }
}

private struct BoostActionBar: View {
    let isRunning: Bool
    let startStopAccessibilityLabel: String
    let onToggle: () -> Void
    let onQuit: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            // Start is prominent accent. Stop is bordered (not secondary-tinted
            // prominent), so the label stays readable in light and dark mode.
            Group {
                if isRunning {
                    Button("停止", action: onToggle)
                        .buttonStyle(.bordered)
                } else {
                    Button("開始", action: onToggle)
                        .buttonStyle(.borderedProminent)
                        .tint(Color.accentColor)
                }
            }
            .keyboardShortcut(.defaultAction)
            .controlSize(.large)
            .accessibilityLabel(startStopAccessibilityLabel)
            .accessibilityHint("Starts or stops the audio processing path.")

            Spacer(minLength: 8)

            Button("終了", action: onQuit)
                .buttonStyle(.bordered)
                .controlSize(.large)
                .accessibilityLabel("Quit Hazakura Amp")
                .accessibilityHint("Stops audio processing safely, then quits the app.")
        }
    }
}

private struct ProductFooterView: View {
    var body: some View {
        HStack {
            Text("ローカル処理のみ · 録音なし")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Spacer()
            Text(versionLabel)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
        .padding(.top, 2)
    }

    private var versionLabel: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "—"
        return "v\(version)"
    }
}

// MARK: - Diagnostics

/// audio pipeline の診断情報。動作確認用。
struct DiagnosticsView: View {
    let captureBufferCount: UInt64
    let renderCallCount: UInt64
    let lastObservedGain: Float
    let availableFrames: Int
    let underrunCount: UInt64
    let droppedFrameCount: UInt64
    let latestBufferFrameCount: Int
    let health: AudioBackendHealthAssessment
    let isRunning: Bool

    var body: some View {
        GroupBox("診断メトリクス") {
            VStack(alignment: .leading, spacing: 4) {
                metricRow(title: "キャプチャバッファ", value: "\(captureBufferCount)", emphasize: isRunning && captureBufferCount > 0)
                metricRow(title: "レンダー呼び出し", value: "\(renderCallCount)", emphasize: isRunning && renderCallCount > 0)
                metricRow(title: "出力ゲイン", value: String(format: "%.2f×", lastObservedGain))
                metricRow(title: "利用可能フレーム", value: "\(availableFrames)")
                metricRow(
                    title: "アンダーラン",
                    value: "\(underrunCount)",
                    color: underrunCount == 0 ? Color.secondary : Color.orange
                )
                metricRow(
                    title: "ドロップフレーム",
                    value: "\(droppedFrameCount)",
                    color: droppedFrameCount == 0 ? Color.secondary : Color.orange
                )
                metricRow(title: "最新バッファ", value: "\(latestBufferFrameCount)")
                HStack {
                    Text("ヘルス:")
                    Spacer()
                    Text(healthLabel)
                        .monospacedDigit()
                        .foregroundStyle(healthColor)
                }
                if isRunning && captureBufferCount == 0 {
                    Label("ScreenCaptureKit の音声バッファがまだ届いていません", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                if isRunning && renderCallCount == 0 {
                    Label("AVAudioEngine のレンダー呼び出しがまだ発生していません", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .font(.caption)
        }
    }

    private func metricRow(title: String, value: String, emphasize: Bool = false, color: Color? = nil) -> some View {
        HStack {
            Text("\(title):")
            Spacer()
            Text(value)
                .monospacedDigit()
                .foregroundStyle(color ?? (emphasize ? Color.primary : Color.secondary))
        }
    }

    private var healthLabel: String {
        switch health.level {
        case .ok:
            return "OK"
        case .watch:
            return String(format: "注意 %.2f%%", health.underrunRate * 100)
        case .warning:
            return String(format: "警告 %.2f%%", health.underrunRate * 100)
        }
    }

    private var healthColor: Color {
        switch health.level {
        case .ok:
            return .green
        case .watch:
            return .orange
        case .warning:
            return .red
        }
    }
}

/// Dev モード用の診断情報。失敗した audio 境界をアプリ内で確認する。
struct DevDiagnosticsView: View {
    let captureBufferCount: UInt64
    let renderCallCount: UInt64
    let lastObservedGain: Float
    let availableFrames: Int
    let underrunCount: UInt64
    let droppedFrameCount: UInt64
    let latestBufferFrameCount: Int
    let health: AudioBackendHealthAssessment
    let isRunning: Bool
    @ObservedObject var safariExtensionController: SafariExtensionController
    @ObservedObject var logStore: DiagnosticLogStore
    let diagnosticSnapshot: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SetupChecklistView(
                isRunning: isRunning,
                captureBufferCount: captureBufferCount,
                safariExtensionEnabled: safariExtensionController.isEnabled
            )

            DiagnosticsView(
                captureBufferCount: captureBufferCount,
                renderCallCount: renderCallCount,
                lastObservedGain: lastObservedGain,
                availableFrames: availableFrames,
                underrunCount: underrunCount,
                droppedFrameCount: droppedFrameCount,
                latestBufferFrameCount: latestBufferFrameCount,
                health: health,
                isRunning: isRunning
            )

            SafariExtensionDiagnosticsView(controller: safariExtensionController)

            HStack {
                Text("イベントログ")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("コピー") {
                    copyDiagnostics(diagnosticSnapshot)
                }
                .controlSize(.small)
                Button("クリア") {
                    logStore.clear()
                }
                .controlSize(.small)
                .disabled(logStore.entries.isEmpty)
            }

            if logStore.entries.isEmpty {
                Text("診断イベントはまだありません")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                // Use the outer popover ScrollView only — nested ScrollViews fight
                // trackpad gestures when diagnostics expand.
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(logStore.entries.reversed())) { entry in
                        DiagnosticLogRow(entry: entry)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            }
        }
    }

    private func copyDiagnostics(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

private struct SetupChecklistView: View {
    let isRunning: Bool
    let captureBufferCount: UInt64
    let safariExtensionEnabled: Bool?

    var body: some View {
        GroupBox("初回セットアップ") {
            VStack(alignment: .leading, spacing: 4) {
                row(
                    title: "本体",
                    value: isRunning ? "OK" : "開始待ち",
                    color: isRunning ? .green : .secondary
                )
                row(
                    title: "Safari 拡張",
                    value: safariExtensionLabel,
                    color: safariExtensionColor
                )
                row(
                    title: "音声取得",
                    value: audioCaptureLabel,
                    color: audioCaptureColor
                )
            }
            .font(.caption)
        }
    }

    private func row(title: String, value: String, color: Color) -> some View {
        HStack {
            Text("\(title):")
            Spacer()
            Text(value)
                .fontWeight(.semibold)
                .foregroundStyle(color)
        }
    }

    private var safariExtensionLabel: String {
        switch safariExtensionEnabled {
        case .some(true):
            return "OK"
        case .some(false):
            return "無効"
        case .none:
            return "未確認"
        }
    }

    private var safariExtensionColor: Color {
        switch safariExtensionEnabled {
        case .some(true):
            return .green
        case .some(false):
            return .orange
        case .none:
            return .secondary
        }
    }

    private var audioCaptureLabel: String {
        if isRunning && captureBufferCount > 0 {
            return "OK"
        }
        return isRunning ? "待機中" : "開始後に確認"
    }

    private var audioCaptureColor: Color {
        if isRunning && captureBufferCount > 0 {
            return .green
        }
        return isRunning ? .orange : .secondary
    }
}

private struct SafariExtensionDiagnosticsView: View {
    @ObservedObject var controller: SafariExtensionController

    var body: some View {
        GroupBox("Safari 拡張") {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("状態:")
                    Spacer()
                    Text(controller.statusText)
                        .fontWeight(.semibold)
                        .foregroundStyle(statusColor)
                }
                Text(controller.detailText)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let lastError = controller.lastError {
                    Text(lastError)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                HStack {
                    Button("状態を確認") {
                        controller.refreshState()
                    }
                    .controlSize(.small)
                    Button("拡張設定を開く") {
                        controller.openPreferences()
                    }
                    .controlSize(.small)
                }
            }
            .font(.caption)
        }
        .onAppear {
            controller.refreshState()
        }
    }

    private var statusColor: Color {
        switch controller.isEnabled {
        case .some(true):
            return .green
        case .some(false):
            return .orange
        case .none:
            return .secondary
        }
    }
}

private struct DiagnosticLogRow: View {
    let entry: DiagnosticLogEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(entry.timestamp, style: .time)
                    .monospacedDigit()
                Text(entry.level.label)
                    .foregroundStyle(levelColor)
                    .fontWeight(.semibold)
                Spacer()
            }
            Text(entry.message)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.caption2)
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
    }

    private var levelColor: Color {
        switch entry.level {
        case .info: .secondary
        case .warning: .orange
        case .error: .red
        }
    }
}

#if !DISABLE_SWIFTUI_PREVIEWS
#Preview {
    ContentView(engine: PoCAudioEngine())
}
#endif
