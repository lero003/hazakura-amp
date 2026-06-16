# UI/UX デザイン

> 関連: [企画書 §初期UI案 / §状態表示](../hazakura-volume-booster企画書.md) / [ARCHITECTURE §UI Layer](./ARCHITECTURE.md) / [PERMISSIONS §アプリ内文言](./PERMISSIONS.md)

Hazakura Boost の UI は、**「ステータスメニューの右に 1 つだけ存在し、迷わず 1 つの操作で完結する」**ことを最優先する。Apple の `MenuBarExtra` ガイドラインと人間工学に準拠しつつ、**ブースト状態が一目でわかる**ことに振り切る。

## デザイン原則

1. **1タップで結果が出る**。ポップオーバーを開いて、Sliderを動かして、音が聞こえる。この往復は 1 秒以内。
2. **状態は「見える化」する**。いま 100% か 180% か OFF か、メニューバーのアイコンとラベルで常に示す。
3. **誤爆しない**。400% まで上げられる以上、操作の取り消し（100% ボタン）は最短経路で提供する。
4. **アクセシビリティを後付けにしない**。キーボード操作、VoiceOver、コントラストを v0.1 から担保。
5. **「多機能アプリ」っぽく見せない**。メニュー項目を増やしすぎない。常駐型ユーティリティの静けさを保つ。

---

## 全体構成

```
┌─────────────────────────────────────────────────────────────┐
│  ステータスバー（右上の常駐アイコン群）                        │
│  …  Wi-Fi  Bluetooth  Battery  [☀ Hazakura Boost]  Time     │
└─────────────────────────────────────────────────────────────┘
                          │ click
                          ▼
                  ┌──────────────────────┐
                  │   Popover (240pt幅)  │
                  │                      │
                  │  Hazakura Boost      │ ← ヘッダ
                  │  ─────────────       │
                  │  Boost               │
                  │  [─────●──────] 180% │ ← Slider + 値
                  │                      │
                  │  [ 100%に戻す ]      │ ← Reset
                  │                      │
                  │  [● ON  ○ OFF]      │ ← Toggle
                  │                      │
                  │  [ 終了 ]            │ ← Quit
                  └──────────────────────┘
```

---

## 1. メニューバーアイコン

### 形状

- ベース: **SF Symbols の `speaker.wave.2.fill`** 系のボリューム系アイコン
- v0.1 は SF Symbols で凌ぐ。独自アセットは v0.2 以降で検討
- テンプレ: 黒／白／アクセント の 3 系統を `Assets.xcassets` に登録

### 状態別表示

| 状態 | アイコン | ラベル（任意） | 意図 |
|---|---|---|---|
| 起動直後・100% | `speaker.wave.2` (塗りなし) | 非表示 / 「Hazakura」 | ニュートラル、控えめ |
| 101%〜200% | `speaker.wave.2.fill` | 「Boost 180%」 | 控えめにブースト中だと一目でわかる |
| 201%〜400% | `speaker.wave.3.fill` (強) | 「Boost 300%」等 | 強ブースト中だと一目でわかる |
| OFF (paused) | `speaker.slash` (or 薄いグレー) | 「OFF」 | 一目で「効いてない」とわかる |

> **状態ラベルの表示は v0.1 では任意**。v0.2 で「メニューバーに%表示」を正式対応する。詳細: [ROADMAP §v0.2](./ROADMAP.md)。

### サイズ

- ステータスバーは macOS 標準で 22pt 程度。SF Symbols は `.large` か `.regular` を使い、Weight は `.regular` 推奨
- アイコンとラベルを併記する場合の余白は 4pt

### ライト/ダーク対応

- `Assets.xcassets` の **Any Appearance / Dark Appearance** で塗りを提供
- アクセントカラーは**赤**を避け、**青 or グレー**に留める。「警告」と「情報」の混同を避けるため

---

## 2. ポップオーバー

### サイズ

- **幅 240pt**、高さは内容可変（最小 200pt、最大 360pt 程度）
- `MenuBarExtra` 標準のウィンドウスタイルに準拠（角丸 12pt、影は system 任せ）
- 角丸・影・背景は自前で実装しない（SwiftUI の `.popover` / `MenuBarExtra` のデフォルトを尊重）

### レイアウト（v0.1 確定版）

```
┌────────────────────────────┐
│ Hazakura Boost             │ ← Header（SF Pro 13pt Semibold）
│                            │
│ Boost                      │ ← Section title（11pt）
│ ┌──────────────────────┐ 0%│
│ │  ●─────────────       │  │ ← Slider
│ └──────────────────────┘ 400%│
│            Boost 180%      │ ← 状態ラベル（12pt、右寄せ）
│                            │
│ [    Reset to 100%    ]     │ ← Button（実装値: 英語）
│                            │
│ [● ON]   ON / OFF         │ ← Toggle
│                            │
│                            │
│  [      Quit      ]        │ ← Secondary button（下端）
└────────────────────────────┘
```

> 図中の「Boost 180%」「Reset to 100%」「Quit」等が **実装上の正**。日本語表記は v0.1 では使わない（設計メモは §8 ローカライズ参照）。

余白:
- 左右パディング: 16pt
- 要素間: 12pt
- セクション区切り: 罫線を使わず、空白でリズムを作る

### タイポグラフィ

- システムフォント（San Francisco）を使用
- ヘッダ: `.headline`
- セクションタイトル: `.caption` (または `.subheadline`)
- 値ラベル: `.body` `.monospacedDigit()` を適用して数字がブレない
- ボタン: システム標準の `.bordered` / `.borderedProminent`

### カラー

- システム標準の `Color.accentColor` を尊重
- カスタムカラーは追加しない（Apple HIG に従う）
- ダークモード: 自動追従

### アニメーション

- ポップオーバーの開閉はシステム標準に任せる（追加で書かない）
- Slider の値変化時に **過剰なアニメーションは入れない**（カクつき防止）
- 100% に戻すボタン押下時: 値のラベルが `180%` → `100%` へ一瞬で切り替わる（補間しない）

---

## 3. Slider の細部

### 範囲

- `0%` 〜 `400%`、ステップ `1%`
- 内部表現は `Double` で `0.0` 〜 `4.0`
- 端点は目盛りを表示

### 値ラベル

- Slider の右に現在値（`Boost 180%`）を表示
- 100% のときは `100%`（"Boost" プレフィックスなし）
- OFF 状態のときは `Boost (paused)`

### アクセシビリティ

- `accessibilityLabel`: "Boost level"
- `accessibilityValue`: "180 percent" / "100 percent" / "Paused"
- `accessibilityAdjustableAction`: 上/下スワイプで ±1% 刻み

---

## 4. ボタンとトグル

### 「100%に戻す」ボタン

- `.bordered` スタイル
- 押下で**スライダー値も100%へ同期**（スライダーのつまみも動く）
- **現在の値に関係なく常に有効**
- アクセシビリティラベル: "Reset boost to 100 percent"

### ON / OFF トグル

- macOS 標準の `Toggle`
- ラベル: "Boost" （視認性のため短い）
- OFF にすると内部的にゲインが 1.0 に戻るが、**スライダーの内部値は保持**
- アクセシビリティラベル: "Boost on or off"

### 「終了」ボタン

- ポップオーバーの下端に控えめに配置
- `.borderless` または secondary スタイル
- `⌘Q` も有効（メニューコマンド経由）

---

## 5. 状態とエッジケース

### 権限未付与

- macOS 26 で Core Audio Tap に必要な `NSAudioCaptureUsageDescription` ダイアログが初回起動時に出る
- 拒否された場合:
  - ポップオーバーにバナー表示: `System audio access is not allowed.`
  - スライダー/トグルは**操作不可**（disabled）
  - メニューに "Open System Settings" を追加（v0.2）

### Audio Engine 起動失敗

- ポップオーバー上部に赤系のバナー: 「⚠️ オーディオ処理を開始できません」
- 終了以外の操作を無効化
- v0.2 で自動再起動 / 設定画面リンクを追加

### スリープ/復帰

- スリープ前に **自動で 100% へ戻す**（既定動作）
- 復帰時に**保存されたスライダー値へ戻す**（既定動作）
- ポップオーバーが開いている場合は特に変化なし（再描画のみ）

### 二重起動

- 既存プロセスが前面に出る
- 2 つ目のプロセスは即時終了し、ログを残す
- ユーザ視点では「アイコンをクリックしても何も起こらない（ように見えない）」

---

## 6. キーボード操作

| キー | 動作 |
|---|---|
| `Tab` | Slider → 100%ボタン → トグル → 終了 の順でフォーカス移動 |
| `Shift+Tab` | 逆順 |
| `Space` / `Enter` | フォーカス中のボタン/Toggleを発火 |
| `←` / `→` | フォーカス中のSliderを ±1% 動かす（SwiftUI既定） |
| `0` キー | 100% ボタン押下と同等（v0.2 で検討） |
| `Esc` | ポップオーバーを閉じる |
| `⌘Q` | アプリ終了 |

> ホットキー（グローバル）は v0.2 以降のスコープ。詳細: [ROADMAP §v0.2](./ROADMAP.md)。

---

## 7. VoiceOver

- ヘッダ: "Hazakura Boost, menu bar utility"
- Slider: "Boost level, 180 percent, adjustable"
- 100%ボタン: "Reset boost to 100 percent, button"
- トグル: "Boost, on, switch"
- 終了: "Quit Hazakura Boost, button"
- エラーバナー: "Warning, system audio access is not allowed"

rotor で見出し/ボタン/スライダーに飛べるようにする（SwiftUI 既定で概ね動くが、見出しを `AccessibilityHeading` で明示）。

---

## 8. ローカライズ（v0.1）

- v0.1 の **実装UI文字列は英語を正**とする。`Info.plist` の `NSAudioCaptureUsageDescription` 等も英語
- 文字列は `Localizable.strings` / SwiftUI の `Text("...")` ではなく `String(localized:)` 系に逃がして**i18n前提で記述**（コードに直書きしない）
- このドキュメント内の日本語UIテキストは **設計説明用の補足** に留め、**実装上の正本は英語** として扱う
  - ポップオーバーヘッダ: "Hazakura Boost"
  - ボタンの実装値:
    - リセット: `Reset to 100%`（設計メモ: 日本語UI案 = 「100%に戻す」）
    - 終了: `Quit`（設計メモ: 日本語UI案 = 「終了」）
  - エラーバナー: `System audio access is not allowed.`（設計メモ: 日本語UI案 = 「⚠️ システム音声へのアクセスが許可されていません」）
  - 起動時バナー: `Hazakura Boost will process system audio locally to apply a volume boost. Audio is not recorded, stored, or transmitted.`
- v0.2 以降で日本語ローカライズを追加（まずは英/日の2言語）

---

## 9. やってはいけないこと

- ❌ **Dockに出す**（`LSUIElement = true` を崩さない）
- ❌ **独自の角丸・影・グラデーション**（HIG逸脱）
- ❌ **スライダーのつまみを巨大化**（macOS標準に合わせる）
- ❌ **状態をアイコン1個の色だけで表現**（色覚多様性に配慮し、形 or ラベルでも示す）
- ❌ **音声変化時に過度なハプティクス演出**（Macには存在しないが、過剰なアニメーションを指す）
- ❌ **「アプリ別ミキサー」「EQ」の UI 断片を追加**（プロダクトの立ち位置を曖昧にする）

---

## 10. 関連ドキュメント

- [ARCHITECTURE §UI Layer](./ARCHITECTURE.md) … コンポーネント・データフロー
- [ROADMAP §v0.1](./ROADMAP.md) … v0.1 のDoDと受入チェックリスト
- [PERMISSIONS §アプリ内文言](./PERMISSIONS.md) … ポップオーバー内に表示する文言
- [RISKS §アイコン視認性](./RISKS.md) … 状態別アイコンの必要性
