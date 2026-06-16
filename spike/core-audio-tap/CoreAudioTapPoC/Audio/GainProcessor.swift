//
//  GainProcessor.swift
//  CoreAudioTapPoC
//
//  Core Audio / ScreenCaptureKit PoC で共有するゲイン処理の小さなヘルパ。
//  ARCHITECTURE.md §3 のドキュメント整合性のため、linear→dB の関係を
//  テストで保証する。
//
//  参照: docs/ARCHITECTURE.md §3 ゲインの実装方式 / docs/RISKS.md §3
//

import Foundation

enum GainProcessor {
    private static let limiterKnee: Float = 0.9

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

    private static func softLimit(_ sample: Float) -> Float {
        let magnitude = abs(sample)
        guard magnitude > limiterKnee else { return sample }

        let headroom = 1.0 - limiterKnee
        let excess = magnitude - limiterKnee
        let limitedMagnitude = limiterKnee + headroom * (1.0 - exp(-excess / headroom))
        return copysign(min(limitedMagnitude, 1.0), sample)
    }
}
