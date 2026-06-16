# Core Audio Tap PoC

> 親: `hazakura-volume-booster/` ルート  
> 関連: [`docs/TECH_SPIKE.md`](../../docs/TECH_SPIKE.md) / [`docs/ARCHITECTURE.md`](../../docs/ARCHITECTURE.md) / [`docs/RISKS.md`](../../docs/RISKS.md) / [`docs/PERMISSIONS.md`](../../docs/PERMISSIONS.md)

Hazakura Boost v0.1 の **実装に着手する前に必ず通す**技術検証（PoC）。  
`docs/TECH_SPIKE.md` の Done 条件を満たさない限り v0.1 には進まない。

## 経緯（なぜこの構成か）

最初の実装は `AVAudioEngine.inputNode` を **tap のみを内包する aggregate device** に切り替える方針だった。結果、起動時に **`kAudioUnitErr_FailedInitialization` (-10875)** で失敗。

その後 `AudioDeviceCreateIOProcID` を試したが IO proc が呼ばれず、`HALOutput AudioUnit` への移行も `CurrentDevice` で失敗した。さらに調査した結果、**aggregate device をシステムの default output として設定しないと IO proc が駆動されない**ことが判明した。

現在の構成は以下の点に準拠する:

- Apple 公式の `Capturing system audio with Core Audio taps` サンプルと同じく **`AudioDeviceCreateIOProcID` で aggregate device に直接 IO proc を登録** し、リアルタイムでゲイン乗算／出力する
- 録音専用なら `kAudioAggregateDeviceSubDeviceListKey: []`（空の sub-device list）でよいが、**ループバック・出力したい場合は default output を sub-device として加える必要がある**
- **ループバックを成立させるため、セットアップ後に aggregate device を default output に設定し、teardown 時に元のデバイスへ復元する**
- IO proc は **リアルタイム安全**（ロック禁止・alloc 禁止）なので、Swift では書けず **Obj-C++ 必須**
- 元音と加工後音の二重再生を防ぐため、tap の `muteBehavior` は `.muted` とする

## このPoCが検証すること

- **macOS 26 上で Core Audio Tap がシステム出力を取り込める**こと
- 取り込んだ PCM を **IO proc 内で線形ゲイン** して、**default output へラウンドトリップ** できること
- **元音と加工後音が二重に鳴らない**こと（エコー防止: `muteBehavior = .muted`）
- 100% / 200% / 400% の差が**聴感で分かる**こと
- 100% 復帰が**1秒以内**に効くこと
- アプリ終了 / 強制終了で **OS 側に tap / aggregate device がゴミとして残らない**こと

## データフロー

```
[他アプリの音声]
   ↓ aggregate device （セットアップ後、これが default output になる）
   ↓ sub-device として含まれる default output device (Hardware)
   ↓ tap (muteBehavior=.muted → 元音は出ない)
   ↓ aggregate device.input
   ↓ IO proc (AudioIOProcImpl, リアルタイム: `sample * _gainLinear`)
   ↓ aggregate device.output
   ↓ sub-device として含まれる default output device (Hardware)
[スピーカー / ヘッドホン]
```

`muteBehavior = .muted` のおかげで、tap 元の音が default output から直接出ない。代わりに **IO proc が必ず同じ音量を出力する責任を持つ**。終了時は aggregate device を破棄する前に、必ず元の default output device に戻す。

## ディレクトリ構成

```
spike/core-audio-tap/
├── README.md                          (このファイル)
├── project.yml                        (xcodegen 用プロジェクト定義)
├── CoreAudioTapPoC.xcodeproj/         (xcodegen で生成)
├── CoreAudioTapPoC/
│   ├── CoreAudioTapPoCApp.swift       (@main, MenuBarExtra)
│   ├── CoreAudioTapPoC-Bridging-Header.h   (Obj-C++ を Swift に公開)
│   ├── ContentView.swift              (SwiftUI: Slider / ON-OFF / Reset / Quit)
│   ├── Audio/
│   │   ├── AudioIOProc.h              (Swift 公開 API、IO proc ハンドル)
│   │   ├── AudioIOProc.mm             (IO proc 本体、リアルタイムゲイン処理)
│   │   ├── SystemTap.swift            (CATapDescription + AggregateDevice + default output 切替)
│   │   ├── PoCAudioEngine.swift       (Swift 側オーケストレータ)
│   │   └── GainProcessor.swift        (linear→dB の数式ヘルパと単体テスト用)
│   └── Resources/
│       ├── Info.plist                 (NSAudioCaptureUsageDescription 入り, LSUIElement=true)
│       └── CoreAudioTapPoC.entitlements (Hardened Runtime ON, Sandbox OFF)
└── CoreAudioTapPoCTests/
    └── GainProcessorTests.swift       (linear→dB 変換の単体テスト)
```

## 前提条件

- macOS 26.0 以降
- Xcode 26 以降
- Homebrew（xcodegen インストール用）

```bash
brew install xcodegen
```

## ビルド・テスト

```bash
cd spike/core-audio-tap

# プロジェクト生成（project.yml から）
xcodegen generate

# クリーンビルド
xcodebuild \
  -project CoreAudioTapPoC.xcodeproj \
  -scheme CoreAudioTapPoC \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath build \
  clean build

# ユニットテスト
xcodebuild \
  -project CoreAudioTapPoC.xcodeproj \
  -scheme CoreAudioTapPoC \
  -destination 'platform=macOS' \
  -derivedDataPath build \
  test
```

## 起動手順

```bash
open build/Build/Products/Debug/CoreAudioTapPoC.app
```

初回起動時に **`NSAudioCaptureUsageDescription` の OS ダイアログ**が出るので「許可」する。  
以降はメニューバーにアイコンが表示されるので、クリックしてポップオーバーを開き、「開始」を押すと aggregate device 上で IO proc がラウンドトリップを駆動する。

## 検証チェックリスト

`docs/TECH_SPIKE.md` の Done 条件と対応する手動チェック:

```
[ ] YouTube 音声を取得できた（Start 直後から聴こえる）
[ ] 100%（素通し）で原音と同等に聴こえる
[ ] 200% / 400% で音量が明確に上がる
[ ] 元音と加工後音が二重に鳴らない（.muted が効いている）
[ ] 100% 復帰できる
[ ] アプリ終了で通常出力に戻る（Stop 後に Default 出力になる）
[ ] スリープ前にゲインが 1.0 へ戻る（手動テストは省略可）
[ ] スリープから復帰して保存値へ復元する（手動テストは省略可）
[ ] 強制終了後に OS 側に tap/routing が残らない
[ ] 権限拒否でクラッシュしない（Setting > Privacy で拒否して再起動）
[ ] マイク権限ダイアログが出ない
[ ] レイテンシが 200ms 未満の体感
```

### 強制終了の検証手順

```bash
# アプリ稼働中に Activity Monitor を開いて CoreAudioTapPoC を強制終了
# その直後に、tap / aggregate device が残っていないか確認:
system_profiler SPAudioDataType | grep -i 'hbb-poc'

# 何も出なければ OK（OS 側が完全解放している）
# もし出てきたら、Tech Spike 撤退ラインに到達。v0.1 延期。
```

## 状態確認（ログ）

`Console.app` で以下をフィルタすると便利:

- subsystem: `dev.keisetsu.hazakura-volume-booster.poc`
- category: `SystemTap` / `PoCAudioEngine`

## 撤退ライン

`docs/TECH_SPIKE.md §撤退ライン` と一致:

- 「出力をタップして戻す」ラウンドトリップが成立しない（IO proc 登録が失敗する等）
- 200ms を超える体感遅延が避けられない
- 強制終了で OS 側に tap/routing が残る
- エコー（原音と加工後音の二重再生）が避けられない

**いずれか1つでも成立しなければ v0.1 の実装には進まない**。  
縮退案（自プロセス音声のみ）は技術デモ扱いとし、MVP としては採用しない。

## ファイル対応

| ファイル | 役割 | 対応する設計ドキュメント |
|---|---|---|
| `AudioIOProc.h` / `.mm` | リアルタイム IO proc、線形ゲイン乗算（現在の active 実装） | [ARCHITECTURE §3 Audio Engine層](../../docs/ARCHITECTURE.md) / [RISKS §3 レイテンシ](../../docs/RISKS.md) / [RISKS §5 終了時の音量リーク](../../docs/RISKS.md) |
| `SystemTap.swift` | CATapDescription + AggregateDevice + default output 切替復元 | [ARCHITECTURE §3](../../docs/ARCHITECTURE.md) / [RISKS §1 Core Audio Tap の実現性](../../docs/RISKS.md) |
| `PoCAudioEngine.swift` | Swift 側オーケストレータ、UI バインド、ON/OFF 状態管理 | [ARCHITECTURE §データフロー](../../docs/ARCHITECTURE.md) |
| `GainProcessor.swift` | linear→dB の数式ヘルパ（IO proc は直接 linear を使うので runtime では未使用） | [ARCHITECTURE §3 ゲインの実装方式](../../docs/ARCHITECTURE.md) |
| `Info.plist` | NSAudioCaptureUsageDescription、LSUIElement | [PERMISSIONS §Info.plist](../../docs/PERMISSIONS.md) |
| `*.entitlements` | Hardened Runtime、App Sandbox OFF | [PERMISSIONS §Entitlements](../../docs/PERMISSIONS.md) |
| `CoreAudioTapPoC-Bridging-Header.h` | Obj-C++ (AudioIOProc.h) を Swift に公開 | — |
| `CoreAudioTapPoCApp.swift` | `MenuBarExtra` 常駐エントリポイント | [ARCHITECTURE §1 UI Layer](../../docs/ARCHITECTURE.md) |

## 次のステップ

PoC の Done 条件をすべて満たしたら:

1. `docs/TECH_SPIKE.md` の PoC チェックリストを埋める
2. この `spike/core-audio-tap/` の実装を `hazakura-volume-booster/` ルート直下の Xcode プロジェクト（v0.1 本体）へ移植する
3. v0.1 本体プロジェクトを `xcodegen` ベースで再構築する
4. v0.1 の DoD（[ROADMAP §v0.1 MVP](../../docs/ROADMAP.md#v01-mvp)）を順番に潰していく
