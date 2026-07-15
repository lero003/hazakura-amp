//
//  GainProcessor.swift
//  CoreAudioTapPoC
//
//  Core Audio / ScreenCaptureKit で共有するゲイン・リミッタ・EQ 設定のヘルパ。
//  ARCHITECTURE.md §3 のドキュメント整合性のため、linear→dB の関係を
//  テストで保証する。
//
//  参照: docs/ARCHITECTURE.md §3 ゲインの実装方式 / docs/RISKS.md §3
//

import Foundation

struct EqualizerSettings: Equatable, Codable {
    /// Low shelf gain in dB. Range: -6...+6
    var lowDB: Float
    /// Mid peak gain in dB. Range: -6...+6
    var midDB: Float
    /// High shelf gain in dB. Range: -6...+6
    var highDB: Float

    static let neutral = EqualizerSettings(lowDB: 0, midDB: 0, highDB: 0)

    static func clampBand(_ value: Float) -> Float {
        guard value.isFinite else { return 0 }
        return min(6, max(-6, value))
    }

    var sanitized: EqualizerSettings {
        EqualizerSettings(
            lowDB: Self.clampBand(lowDB),
            midDB: Self.clampBand(midDB),
            highDB: Self.clampBand(highDB)
        )
    }
}

enum BoostPreset: String, CaseIterable, Identifiable {
    case normal
    case video
    case lecture
    case max

    var id: String { rawValue }

    var title: String {
        switch self {
        case .normal: "標準"
        case .video: "動画"
        case .lecture: "講義"
        case .max: "最大"
        }
    }

    /// Linear gain 0.0...4.0
    var linearGain: Double {
        switch self {
        case .normal: 1.0
        case .video: 1.6
        case .lecture: 2.2
        case .max: 3.0
        }
    }

    var percentLabel: String {
        "\(Int((linearGain * 100).rounded()))%"
    }

    static func matching(gain: Double, tolerance: Double = 0.02) -> BoostPreset? {
        allCases.first { abs($0.linearGain - gain) <= tolerance }
    }
}

enum GainProcessor {
    /// Soft-limiter knee as a fraction of full scale. Below this, gain is linear.
    private static let limiterKnee: Float = 0.82
    /// Leave a tiny headroom so hardware DACs rarely hard-clip after EQ.
    private static let outputCeiling: Float = 0.98
    /// Approximate attack of the soft knee region (dimensionless).
    private static let kneeSoftness: Float = 1.35

    /// 0.0 ... 4.0 の linear gain を dB 値に変換する。
    /// - 1.0 → 0 dB（ニュートラル）
    /// - 2.0 → +6.02 dB
    /// - 4.0 → +12.04 dB
    /// - 0.000001 → -120 dB（log10(0) 回避のフロア）
    static func dB(forLinear linear: Double) -> Double {
        let safe = max(linear, 0.000_001)
        return 20.0 * log10(safe)
    }

    static func applyLimitedGain(to sample: Float, gain: Float) -> Float {
        softLimit(sample * max(0.0, gain))
    }

    /// Improved soft limiter: linear below the knee, then a smooth asymptotic curve
    /// toward `outputCeiling` instead of a hard clip at 1.0.
    static func softLimit(_ sample: Float) -> Float {
        let magnitude = abs(sample)
        guard magnitude > limiterKnee else { return sample }

        let headroom = max(0.000_1, outputCeiling - limiterKnee)
        let excess = magnitude - limiterKnee
        // Smooth compression of excess energy; keeps loud peaks audible without hard edges.
        let limitedMagnitude = limiterKnee + headroom * tanh(excess / (headroom * kneeSoftness))
        return copysign(min(limitedMagnitude, outputCeiling), sample)
    }
}
