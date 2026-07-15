# Hazakura Amp

> Macの小さい音を、メニューバーからすぐ持ち上げる。

**Hazakura Amp**（リポジトリ名: `hazakura-amp`）は、Macのシステム音量をメニューバーから一時的にブーストする常駐型ユーティリティアプリです。YouTubeや配信、講義動画、古い音源など「最大音量でも小さすぎる」コンテンツを、外部スピーカーやモニターの物理ボリュームを触らずに聞こえやすくします。

ドライバ非依存・アプリ別ミキサー非対応・EQ非対応という割り切りで、Mac全体の音を「**少し大きくする**」ことだけに集中します。

## ステータス

**フェーズ: v0.4.0 feature expansion / 手元・知人向け製品品質候補**

- ✅ 企画書 [`hazakura-amp企画書.md`](./hazakura-amp企画書.md)
- ✅ 準備ドキュメント（本リポジトリの `docs/`）
- ✅ **Core Audio Tap + ScreenCaptureKit**（[`spike/core-audio-tap`](./spike/core-audio-tap)）
- ✅ メニューバーUI / プリセット / 3バンドEQ / 0%〜400%スライダー / 折りたたみ診断
- ✅ ゲインランプ・ソフトリミッタ・出力デバイス自動再接続
- ✅ YouTube floating remote（Boost / 速度 / 字幕トグル / Repeat / 終了時100%）
- ✅ 手元環境での音量ブースト確認（0% / 100% / 200% / 400%）
- ✅ dev 配布スクリプト `./scripts/build_dev_distribution.sh`（Apple Development / team preview）
- ✅ Developer ID Release 候補スクリプト（Developer ID プロファイルが必要）
- ⚠️ Notarized DMG・自動アップデートは未整備
- ⚠️ 公証済み一般配布・App Store 提出は未着手

## クイックリンク

| ドキュメント | 内容 |
|---|---|
| [`hazakura-amp企画書.md`](./hazakura-amp企画書.md) | プロダクト企画の一次資料。コンセプト・想定ユーザー・MVP機能・やらないこと |
| [`docs/ARCHITECTURE.md`](./docs/ARCHITECTURE.md) | 技術アーキ・コンポーネント構成・データフロー・技術選定理由 |
| [`docs/ROADMAP.md`](./docs/ROADMAP.md) | v0.1〜v0.4+ のマイルストーンとDoneの定義 |
| [`docs/TECH_SPIKE.md`](./docs/TECH_SPIKE.md) | **Core Audio Tap PoC**。v0.1 着手前に通す技術検証の Done 条件 |
| [`docs/DEVELOPMENT.md`](./docs/DEVELOPMENT.md) | 開発環境・ビルド/テスト手順・コード規約・ブランチ戦略 |
| [`docs/RISKS.md`](./docs/RISKS.md) | 技術リスク・既知の落とし穴・未解決の論点 |
| [`docs/PERMISSIONS.md`](./docs/PERMISSIONS.md) | macOSのAudio/Sandbox/Hardened Runtime/Notarization方針 |
| [`docs/UI_DESIGN.md`](./docs/UI_DESIGN.md) | アイコン・ポップオーバー・状態表現・アクセシビリティ |
| [`spike/core-audio-tap/README.md`](./spike/core-audio-tap/README.md) | 現在動いている v0.2 candidate PoC のビルド・起動手順 |

## 現在の実装

v0.2 candidate は `spike/core-audio-tap/` の PoC 実装を現在の実体として扱います。

- ScreenCaptureKit でシステム音声を取得
- Core Audio process tap を `.muted` で使い、元音の二重再生を抑制
- `PCMFloatRingBuffer` 経由で `AVAudioSourceNode` から加工後音を出力
- ゲインは 0%〜400% を対象とし、100%未満では小さく、100%超では簡易ソフトリミッタで過大なクリッピングを抑制
- Dev モードで capture buffer / render call / output gain / event log を確認可能

これは公証済み配布製品ではなく、手元・知人向けの製品品質候補です。録音・保存・外部送信は行いません。

## ビルド・テスト

```bash
cd spike/core-audio-tap

xcodebuild \
  -project CoreAudioTapPoC.xcodeproj \
  -scheme CoreAudioTapPoC \
  -destination 'platform=macOS' \
  -derivedDataPath build \
  test

xcodebuild \
  -project CoreAudioTapPoC.xcodeproj \
  -scheme CoreAudioTapPoC \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath build \
  build

# 知人・登録 Mac 向け dev zip（推奨の暫定配布）
./scripts/build_dev_distribution.sh

# Developer ID Release 候補（Developer ID 用 provisioning profile が必要）
./scripts/build_release_candidate.sh
```

起動:

```bash
open "spike/core-audio-tap/build/Build/Products/Debug/Hazakura Amp.app"
```

### dev 版の配布

```bash
cd spike/core-audio-tap
./scripts/build_dev_distribution.sh
# → dist/HazakuraAmp-v0.4.0-dev.zip
# → dist/HazakuraAmp-v0.4.0-dev.SHA256SUMS
```

- **署名**: Apple Development + team provisioning profile（App Group 付き）
- **対象**: Developer ポータルに登録された Mac / チーム内テスター
- **公証なし**。Gatekeeper は初回「右クリック → 開く」が必要な場合あり
- 一般公開に近い配布は、App Group 付き **Developer ID プロファイル** を用意したうえで `build_release_candidate.sh` → `notarytool` / staple

詳細: [`spike/core-audio-tap/RELEASE_NOTES_v0.4.0.md`](./spike/core-audio-tap/RELEASE_NOTES_v0.4.0.md)

普段の開発確認は `Debug` / Apple Development 署名を使います。公証と staple は外部配布直前の別工程です。

## 企画書の要点（要約）

- **対応OS**: macOS 26以降（古いmacOSは対象外。仮想オーディオデバイス等の複雑化を回避するため）
- **配布形態**: ドライバ不要。アプリ単体で動くことを優先
- **MVPスコープ**:
  1. メニューバー常駐
  2. ブーストスライダー 0%〜400%
  3. 開始/停止
  4. 状態表示（%）
  5. 終了時の安全処理
- **やらないこと**: アプリ別ミキサー / タブ別音量 / EQ / ノイズ除去 / 録音 / 配信ミキサー / 複数出力先 / 古いmacOS対応 / 高度な音割れ防止
- **コア体験**: 外部スピーカーのつまみを触らず、メニューバーだけで音を持ち上げる

## ポジショニング（差別化）

`Background Music` や `SoundSource` のような多機能な音声制御アプリとは異なる、**「全体ブースト専用」**の小さなMacユーティリティとして位置づけます。

- アプリ別ミキサーではなく、全体ブーストに集中
- メニューバーだけで完結
- ドライバ不要の軽量設計
- 外部スピーカー利用者に刺さる

## 名称の使い分け

| 名称 | 用途 |
|---|---|
| **Hazakura Amp** | プロダクト名・UI表示・App Store表記・README・リリースノート |
| **hazakura-amp** | GitHubリポジトリ名 |
| **CoreAudioTapPoC** | v0.2 PoC のターゲット名・スキーム名・内部ソースフォルダ名。広いリネームを避けるため現時点では維持 |
| **dev.hazakura-amp** | Bundle Identifier・権限表示・ログ識別子 |

GitHub リポジトリ名、プロダクト名、Bundle Identifier、ログ/tap識別子は `Hazakura Amp` / `hazakura-amp` に合わせる。`CoreAudioTapPoC` は v0.2 PoC の内部ターゲット名・スキーム名・ソースフォルダ名としてだけ残す。

## 次のアクション

1. `spike/core-audio-tap/` の PoC を v0.1 本体プロジェクトへ昇格するか判断する
2. 強制終了・スリープ復帰・出力デバイス変更時の安全性を追加検証する
3. Developer ID署名 / Notarized DMG / Privacy Manifest を配布前に整備する
4. README と `docs/` の計画文書を、PoC結果に合わせて順次更新する

## ライセンス

Hazakura Amp はプロプライエタリソフトウェアです。詳細は [`LICENSE`](./LICENSE) を参照してください。
