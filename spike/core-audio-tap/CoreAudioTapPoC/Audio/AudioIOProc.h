//
//  AudioIOProc.h
//  CoreAudioTapPoC
//
//  Core Audio の IO proc (C 関数) を Swift から使えるようにラップする
//  Objective-C クラス。Apple 公式の "Capturing system audio with Core
//  Audio taps" サンプルと同じパターン:
//    - AudioDeviceCreateIOProcID で aggregate device に IO proc を登録
//    - IO proc 内で tap からの PCM を受け取り、ゲインを乗算して出力へ書き戻す
//  Swift はリアルタイム安全性を保証できないため、IO proc 自体はこの
//  Objective-C 実装の中に閉じる。
//

#import <Foundation/Foundation.h>
#import <CoreAudio/CoreAudio.h>

NS_ASSUME_NONNULL_BEGIN

/// Swift から操作する IO proc のハンドル。
/// IO proc の本体は内部の C 関数 (AudioIOProcImpl) として持つ。
///
/// `_gainLinear` は `volatile float`:
/// - `volatile` によって Swift 側 (メインスレッド) の write が IO proc (リアルタイム
///   スレッド) から register cache 抜きで読み出される
/// - 4byte aligned float の load/store は x86/ARM で hardware レベル atomic
/// - PoC の用途（線形ゲイン、数百ms 以内の反映遅延が許容範囲）には十分
///   本番で厳密な ordering が必要になったら OSAtomic や C++ `<atomic>` に切替。
@interface AudioIOProc : NSObject {
@public
    volatile float _gainLinear;
}

/// 初期化のみ。実際のセットアップは -startWithDeviceID: で行う。
- (instancetype)init NS_DESIGNATED_INITIALIZER;

/// aggregate device に IO proc を登録して start。
/// @param deviceID tap を内包する aggregate device の AudioObjectID
/// @return noErr なら成功、それ以外は OSStatus
- (OSStatus)startWithDeviceID:(AudioObjectID)deviceID;

/// IO proc を stop して device から切り離す。
- (void)stop;

/// 0.0 ... 4.0 の linear gain を即時反映（リアルタイム安全）。
/// 別スレッドから呼ばれても OK。
- (void)setLinearGain:(float)linearGain;

/// 現在設定されている linear gain を取得（デバッグ用）。
- (float)linearGain;

/// IO proc が呼ばれた回数（デバッグ用）。リアルタイムコンテキストでも
/// メインスレッドから atomic load して読むだけなら安全。
+ (uint64_t)ioProcCallCount;

/// 最後に IO proc が読んだ gain 値（デバッグ用）。
+ (float)lastObservedGain;

@end

NS_ASSUME_NONNULL_END
