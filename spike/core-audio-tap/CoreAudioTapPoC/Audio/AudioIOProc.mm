//
//  AudioIOProc.mm
//  CoreAudioTapPoC
//
//  IO proc の実装。Apple 公式の AudioRecorder.mm パターンを踏襲。
//
//  - 内部に `volatile float _gainLinear` を保持（リアルタイム安全）
//  - IO proc 内ではメモリアロック・alloc・objc_msgsend を呼ばない
//  - 入力 PCM (Float32) に gain を乗算して出力バッファへ memcpy する最小実装
//
//  参照:
//  - https://developer.apple.com/documentation/CoreAudio/capturing-system-audio-with-core-audio-taps
//  - /tmp/csa/AudioTapSample/AudioRecorder.mm
//

#import "AudioIOProc.h"

#import <algorithm>
#import <atomic>
#import <cstring>

// IO proc の診断用カウンタと gain 履歴。
// リアルタイムコンテキストからは atomic fetch_add / store のみ（ロックなし）。
// メインスレッドからは +ioProcCallCount / +lastObservedGain でロードする。
static std::atomic<uint64_t> g_ioProcCallCount{0};
static std::atomic<float> g_lastObservedGain{0.0f};

@interface AudioIOProc () {
    AudioObjectID _deviceID;
    AudioDeviceIOProcID _IOProcID;
    BOOL _running;
}
@end

@implementation AudioIOProc

- (instancetype)init {
    self = [super init];
    if (self == nil) {
        return nil;
    }
    _deviceID = kAudioObjectUnknown;
    _IOProcID = nullptr;
    self->_gainLinear = 1.0f;
    _running = NO;
    return self;
}

- (void)dealloc {
    [self stop];
}

- (OSStatus)startWithDeviceID:(AudioObjectID)deviceID {
    if (_running) {
        // 既に走っている。同じ device なら何もしない。
        if (_deviceID == deviceID) {
            return noErr;
        }
        // 別の device に切り替えたい場合は一旦止める
        [self stop];
    }

    if (deviceID == kAudioObjectUnknown) {
        return paramErr;
    }

    // IO proc を登録。self を client data として渡すことで、
    // IO proc 内で _gainLinear を読める。
    AudioDeviceIOProcID ioProcID = nullptr;
    OSStatus status = AudioDeviceCreateIOProcID(
        deviceID,
        AudioIOProcImpl,
        (__bridge void *)self,
        &ioProcID
    );
    if (status != noErr) {
        return status;
    }

    // IO 開始
    status = AudioDeviceStart(deviceID, ioProcID);
    if (status != noErr) {
        // 失敗したら登録を巻き戻す
        AudioDeviceDestroyIOProcID(deviceID, ioProcID);
        return status;
    }

    _deviceID = deviceID;
    _IOProcID = ioProcID;
    _running = YES;
    return noErr;
}

- (void)stop {
    if (!_running) {
        return;
    }
    AudioDeviceStop(_deviceID, _IOProcID);
    AudioDeviceDestroyIOProcID(_deviceID, _IOProcID);
    _IOProcID = nullptr;
    _deviceID = kAudioObjectUnknown;
    _running = NO;
}

- (void)setLinearGain:(float)linearGain {
    // クランプして volatile に保存
    float clamped = linearGain;
    if (clamped < 0.0f) clamped = 0.0f;
    if (clamped > 4.0f) clamped = 4.0f;
    self->_gainLinear = clamped;
}

- (float)linearGain {
    return self->_gainLinear;
}

+ (uint64_t)ioProcCallCount {
    return g_ioProcCallCount.load(std::memory_order_relaxed);
}

+ (float)lastObservedGain {
    return g_lastObservedGain.load(std::memory_order_relaxed);
}

/// Core Audio から呼ばれる IO proc。リアルタイムコンテキスト。
/// - メモリアロック禁止
/// - Objective-C / Swift ランタイム呼び出し禁止
/// - volatile float の読み出しは hardware レベルで atomic
static OSStatus AudioIOProcImpl(
    AudioObjectID /* inDevice */,
    const AudioTimeStamp * /* inNow */,
    const AudioBufferList * inInputData,
    const AudioTimeStamp * /* inInputTime */,
    AudioBufferList * outOutputData,
    const AudioTimeStamp * /* inOutputTime */,
    void * inClientData
) {
    AudioIOProc *self = (__bridge AudioIOProc *)inClientData;
    if (self == nil) {
        return noErr;
    }

    // 診断用: 呼ばれた回数と gain 値を atomic に記録
    g_ioProcCallCount.fetch_add(1, std::memory_order_relaxed);

    if (inInputData == nullptr || outOutputData == nullptr) {
        return noErr;
    }

    // リアルタイムコンテキストで volatile 読み出し（register cache 抜き、hardware atomic）
    const float gain = self->_gainLinear;
    g_lastObservedGain.store(gain, std::memory_order_relaxed);

    const UInt32 inputBufferCount = inInputData->mNumberBuffers;
    const UInt32 outputBufferCount = outOutputData->mNumberBuffers;
    const UInt32 bufferCount = std::min(inputBufferCount, outputBufferCount);

    for (UInt32 i = 0; i < bufferCount; i++) {
        const AudioBuffer &inBuf = inInputData->mBuffers[i];
        AudioBuffer &outBuf = outOutputData->mBuffers[i];

        if (inBuf.mData == nullptr || outBuf.mData == nullptr) {
            continue;
        }
        if (inBuf.mNumberChannels == 0 || outBuf.mNumberChannels == 0) {
            continue;
        }

        const UInt32 inBytes = inBuf.mDataByteSize;
        const UInt32 outBytes = outBuf.mDataByteSize;
        const UInt32 copyBytes = std::min(inBytes, outBytes);
        const UInt32 sampleCount = copyBytes / sizeof(Float32);

        if (gain == 1.0f) {
            // 100% (素通し) は memcpy の方が速い
            std::memcpy(outBuf.mData, inBuf.mData, copyBytes);
        } else {
            const Float32 * __restrict__ in = static_cast<const Float32 *>(inBuf.mData);
            Float32 * __restrict__ out = static_cast<Float32 *>(outBuf.mData);
            for (UInt32 j = 0; j < sampleCount; j++) {
                out[j] = in[j] * gain;
            }
        }
    }

    return noErr;
}

@end
