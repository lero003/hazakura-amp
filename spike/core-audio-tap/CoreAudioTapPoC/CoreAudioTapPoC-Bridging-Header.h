//
//  CoreAudioTapPoC-Bridging-Header.h
//  CoreAudioTapPoC
//
//  Obj-C++ 側の API を Swift から使えるようにするための bridging header。
//  リアルタイムオーディオ処理は Swift の保証外なので、IO proc は
//  Objective-C++ で書き、ここから Swift に公開する。
//

#ifndef CoreAudioTapPoC_Bridging_Header_h
#define CoreAudioTapPoC_Bridging_Header_h

#import "AudioIOProc.h"

#endif /* CoreAudioTapPoC_Bridging_Header_h */
