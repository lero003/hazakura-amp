# Hazakura Boost

> Macの小さい音を、メニューバーからすぐ持ち上げる。

**Hazakura Boost**（リポジトリ名: `hazakura-volume-booster`）は、Macのシステム音量をメニューバーから一時的にブーストする常駐型ユーティリティアプリです。YouTubeや配信、講義動画、古い音源など「最大音量でも小さすぎる」コンテンツを、外部スピーカーやモニターの物理ボリュームを触らずに聞こえやすくします。

ドライバ非依存・アプリ別ミキサー非対応・EQ非対応という割り切りで、Mac全体の音を「**少し大きくする**」ことだけに集中します。

## ステータス

**フェーズ: 開発準備中（v0.1着手前）**

- ✅ 企画書 [`hazakura-volume-booster企画書.md`](./hazakura-volume-booster企画書.md)
- ✅ 準備ドキュメント（本リポジトリの `docs/`）
- ⏳ **Core Audio Tap PoC**（[`docs/TECH_SPIKE.md`](./docs/TECH_SPIKE.md)）
- ❌ v0.1 MVP 実装
- ❌ 配布（v0.1時点では未定）

## クイックリンク

| ドキュメント | 内容 |
|---|---|
| [`hazakura-volume-booster企画書.md`](./hazakura-volume-booster企画書.md) | プロダクト企画の一次資料。コンセプト・想定ユーザー・MVP機能・やらないこと |
| [`docs/ARCHITECTURE.md`](./docs/ARCHITECTURE.md) | 技術アーキ・コンポーネント構成・データフロー・技術選定理由 |
| [`docs/ROADMAP.md`](./docs/ROADMAP.md) | v0.1〜v0.4+ のマイルストーンとDoneの定義 |
| [`docs/TECH_SPIKE.md`](./docs/TECH_SPIKE.md) | **Core Audio Tap PoC**。v0.1 着手前に通す技術検証の Done 条件 |
| [`docs/DEVELOPMENT.md`](./docs/DEVELOPMENT.md) | 開発環境・ビルド/テスト手順・コード規約・ブランチ戦略 |
| [`docs/RISKS.md`](./docs/RISKS.md) | 技術リスク・既知の落とし穴・未解決の論点 |
| [`docs/PERMISSIONS.md`](./docs/PERMISSIONS.md) | macOSのAudio/Sandbox/Hardened Runtime/Notarization方針 |
| [`docs/UI_DESIGN.md`](./docs/UI_DESIGN.md) | アイコン・ポップオーバー・状態表現・アクセシビリティ |

## 企画書の要点（要約）

- **対応OS**: macOS 26以降（古いmacOSは対象外。仮想オーディオデバイス等の複雑化を回避するため）
- **配布形態**: ドライバ不要。アプリ単体で動くことを優先
- **MVPスコープ**:
  1. メニューバー常駐（`MenuBarExtra`）
  2. ブーストスライダー 0%〜400%
  3. 100%に戻すボタン
  4. ブーストON/OFF
  5. 状態表示（%）
  6. 終了時の安全処理
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
| **Hazakura Boost** | プロダクト名・UI表示・App Store表記・README・リリースノート |
| **hazakura-volume-booster** | リポジトリ名・Xcodeプロジェクト名・Bundle Identifierの一部候補 |

リポジトリ名から変更する予定が現時点で無いため、**両者は同じものを指す**として扱います。

## 次のアクション

1. Xcodeプロジェクトを `hazakura-volume-booster.xcodeproj` として作成し、`docs/DEVELOPMENT.md` に沿った構成で初期化する
2. `docs/ARCHITECTURE.md` のデータフローを実コードに落とす
3. v0.1 MVP のDoDを [`docs/ROADMAP.md`](./docs/ROADMAP.md) で確認し、順に検証

## ライセンス

未定。v0.1リリース前に決定する。
