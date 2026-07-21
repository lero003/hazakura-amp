# 開発ガイド

> 関連: [ARCHITECTURE](./ARCHITECTURE.md) / [ROADMAP](./ROADMAP.md) / [PERMISSIONS](./PERMISSIONS.md) / [RISKS](./RISKS.md)

Hazakura Ampの開発に参加する人（自分自身も含む）とAIエージェントが、**最短で開発環境を整え、ビルドし、テストし、リリース前段まで進められる**ようにするためのドキュメントです。

## 必要な環境

| 項目 | 要件 | 備考 |
|---|---|---|
| macOS | **26.0以降** | 企画書§対応OSに準拠。これ未満は対象外 |
| Xcode | **26以降** | Swift 6.0のツールチェーン含む |
| Swift | 6.0以降 | strict concurrencyを基本ON |
| コマンドラインツール | `xcode-select --install` | `xcodebuild`, `swift`, `swift package` 等 |
| Git | 最新版推奨 | `git config init.defaultBranch main` 推奨 |

> Xcode 26 / macOS 26 はプレビュー/ベータ時点の表記です。安定版がリリースされたタイミングでバージョンを具体化します。

### 任意で使いたいもの

- `xcbeautify` … `xcodebuild` の出力を読みやすく整形
- `xcodeproj` (Ruby gem) … `.pbxproj` をスクリプトから編集したい場合
- `swift-format` … コード整形。プロジェクトに `.swift-format` を置く
- `swiftlint` … 追加Lint。**初期は必須としない**
- `Instruments` … Audio処理のデバッグ・リーク検出
- `Console.app` … `os_log` / `OSLog` のストリーム確認

## セットアップ

```bash
# 1. リポジトリを取得
git clone https://github.com/lero003/hazakura-amp.git
cd hazakura-amp

# 2. 念のため .gitignore / ディレクトリ構成を確認
ls -la
ls -la docs/

# 3. Xcodeでプロジェクトを開く
#    （本体昇格時に hazakura-amp.xcodeproj を作成する）
open hazakura-amp.xcodeproj
```

`.gitignore` の推奨内容（プロジェクト作成時に配置）:

```gitignore
# macOS
.DS_Store

# Xcode
build/
DerivedData/
*.xcodeproj/xcuserdata/
*.xcworkspace/xcuserdata/
*.xcuserstate
xcuserdata/

# Swift Package Manager
.swiftpm/
.build/
Package.resolved

# Misc
*.swp
.vscode/
.idea/
```

## ビルド

Xcodeプロジェクトを生成した後の想定手順。

```bash
# コマンドラインからクリーンビルド
xcodebuild \
  -project hazakura-amp.xcodeproj \
  -scheme hazakura-amp \
  -configuration Debug \
  -destination 'platform=macOS' \
  clean build
```

成果物の場所（Debug）:

```
~/Library/Developer/Xcode/DerivedData/hazakura-amp-*/Build/Products/Debug/Hazakura Amp.app
```

## テスト

```bash
# ユニットテスト
xcodebuild \
  -project hazakura-amp.xcodeproj \
  -scheme hazakura-amp \
  -destination 'platform=macOS' \
  test
```

### テスト方針（v0.1）

- **ロジック層（`BoostController`）**: ほぼ全パスをユニットテストでカバー
  - boostPercent の範囲クランプ（0.0〜4.0）
  - Sliderで100%へ戻す状態遷移
  - Stopで値を保持しつつ出力がニュートラルへ戻る
  - `shutdown()` 呼び出しで内部状態が「ニュートラル」へ戻る
- **Audio Engine層**: 実機動作は手動 / Instruments、コード上は型と状態遷移をテスト
  - 実PCMを流しての自動テストは macOS のAudio APIとCIの両面で難しいため、**v0.1では回帰テストに含めない**
  - 代わりに `AudioEngineProtocol` を導入してテスト時はスタブに差し替え
- **UI層**: 手動の受け入れチェック（[ROADMAP §v0.1 受入チェックリスト](./ROADMAP.md#v01-受入チェックリスト)）をDoDとする
  - ViewInspector等は使わず、必要ならSnapshot Testもv0.1では後回し

## コード規約

- **Swift API Design Guidelines** に準拠
  - 名前で意図を読み取れるようにする
  - 型名は `UpperCamelCase`、メソッド/プロパティは `lowerCamelCase`
- **Concurrency**: Swift 6の strict concurrency を基本ON
  - `BoostController` は `@MainActor`
  - Audio Engineは専用 actor か dispatch queue に隔離
  - 状態共有は `Sendable` を意識
- **エラーハンドリング**: `throws` を活用。`fatalError` は原則禁止（起動時の前提違反時のみ限定的に許可）
- **ロギング**: `os.Logger` / `OSLog` を使う。v0.2 PoC のサブシステムは `dev.hazakura-amp` を維持し、Bundle Identifier 変更時に再評価する
- **マジックナンバー禁止**: ゲイン範囲や刻みは `BoostRange` のような型に集約
- **SwiftLint / swift-format**: 初期は導入せず、CIが安定してから `.swift-format` を設置

## ブランチ戦略

- **`main`**: 常にビルドが通る・タグ済みの状態のみ
- **フィーチャーブランチ**: `feature/<name>`（例: `feature/menu-bar-extra`）
- **バグ修正**: `fix/<name>`（例: `fix/shutdown-gain-leak`）
- **ドキュメントのみ**: `docs/<name>`（コードを含まない変更）

マージ条件:
1. ローカルでクリーンビルドが成功する
2. ユニットテストが全て成功する
3. 関連ドキュメントが更新されている
4. 差分が小さい（1PRでレビュー可能）

## コミットメッセージ

Conventional Commits をベースに簡略化:

```
feat(ui): add BoostSliderView
fix(audio): reset gain to 1.0 on shutdown
docs(roadmap): add v0.1 acceptance checklist
chore: add .gitignore
```

- 1コミット1意図を意識
- 日本語/英語どちらでもよいが、**同じPR内では揃える**

## 配布zipの作成（`build_dist.sh`）

入口は `spike/core-audio-tap/scripts/build_dist.sh` のみ。証明書・配布用 profile の有無確認から、Developer ID zip、公証までを同じコマンドで扱う。

必要なもの（`release` / `notarized`）:

- Developer ID Application 証明書
- `dev.hazakura-amp` / `dev.hazakura-amp.safari-extension` の **Developer ID 配布用 provisioning profile**（`ProvisionsAllDevices`、App Group `group.dev.hazakura-amp`）
- profile 名は `project.yml` の `PROVISIONING_PROFILE_SPECIFIER` と一致（既定: `Hazakura Amp dev` / `Hazakura Amp safari-extension dev`）

```bash
cd spike/core-audio-tap

# 証明書・プロファイルの事前確認
./scripts/build_dist.sh check

# 他マシン向け Developer ID zip（デフォルト）
./scripts/build_dist.sh
# → dist/HazakuraAmp-v<ver>-developer-id.zip
# → dist/HazakuraAmp-v<ver>-developer-id.SHA256SUMS
# → dist/HazakuraAmp-v<ver>-developer-id-INSTALL.txt

# 公証 + staple まで一発（任意の Mac でダブルクリック起動）
./scripts/build_dist.sh notarized
# → dist/HazakuraAmp-v<ver>-notarized.zip

# 登録 Mac 向け team preview（Devices 登録が必要）
./scripts/build_dist.sh dev
```

公証の認証情報（優先順）:

1. 環境変数 `HAZAKURA_NOTARY_*`
2. Keychain profile（`HAZAKURA_NOTARY_KEYCHAIN_PROFILE` / `notarytool store-credentials`）
3. ローカル `.env.notary`（gitignored。例: `scripts/env.notary.example`）
4. App Store Connect API key
5. 対話入力（TTY があるときのみ）

```bash
export HAZAKURA_NOTARY_APPLE_ID='you@example.com'
export HAZAKURA_NOTARY_TEAM_ID='8BNUB2R9C8'
export HAZAKURA_NOTARY_PASSWORD='xxxx-xxxx-xxxx-xxxx'
./scripts/build_dist.sh notarized

# または
cp scripts/env.notary.example .env.notary   # 編集してから
./scripts/build_dist.sh notarized
```

App-Specific Password は https://appleid.apple.com → Sign-In and Security → App-Specific Passwords で生成する。

> GitHub 経由で Safari 拡張が動かない場合、多くは **未公証** が原因。TestFlight ではなく Developer ID + notarize が正しい直配布経路。

> 旧スクリプト名 `build_release_candidate.sh` / `build_dev_distribution.sh` は `build_dist.sh` への互換ラッパー。
> `notarize_and_staple.sh` は公証本体で、`build_dist.sh notarized` から呼び出される。
> 詳細は [PERMISSIONS §配布経路](./PERMISSIONS.md) を参照。

## デバッグTips

- **音が出ない/ブーストが効かない**:
  1. `BoostController` のログで `applyGain` が呼ばれているか確認
  2. 権限ダイアログが許可済みか `System Settings > Privacy & Security` で確認
  3. Audio MIDI 設定アプリで出力デバイスがミュートになっていないか確認
- **メニューバーにアイコンが出ない**:
  1. `MenuBarExtra` のスタイルが `.window` か `.menu` かを確認
  2. `LSUIElement` が `true` になっているか（Info.plist）
- **スリープ後に音量が暴れる**:
  - `NSWorkspace.willSleepNotification` で `resetTo100()` を呼んでいるか確認
  - `didWakeNotification` で復元しているか確認

## 関連ドキュメント

- [ARCHITECTURE.md](./ARCHITECTURE.md) … アーキ・コンポーネント・不変条件
- [ROADMAP.md](./ROADMAP.md) … バージョンごとのDoD
- [RISKS.md](./RISKS.md) … 技術リスクと既知の落とし穴
- [PERMISSIONS.md](./PERMISSIONS.md) … 権限・配布
- [UI_DESIGN.md](./UI_DESIGN.md) … UI/UX設計
