# LaunchCraft

> macOS の launchd を GUI で操作する SwiftUI アプリ。  
> cron や plist を手で書かずに、シェルスクリプトの定期実行を設定できます。

![macOS](https://img.shields.io/badge/macOS-26.5%2B-blue?logo=apple)
![Swift](https://img.shields.io/badge/Swift-5.0-orange?logo=swift)
![License](https://img.shields.io/badge/license-MIT-green)

---

## こんな人に

- `crontab -e` でいつも書き方を調べてしまう
- Lingon を使っていたが有料になって困っている
- launchd の plist を手で書くのが面倒
- バックグラウンドで動くスクリプトを手軽に管理したい

---

## 画面構成

```
┌─────────────────────────────────────────────────────────┐
│  LaunchCraft                        + ↺ ⌨  …           │
├──────────────────┬──────────────────────────────────────┤
│  ジョブ (3)      │  Git pull                            │
│                  │                                      │
│  ● Git pull      │  基本                                │
│    毎日 09:00    │    名前 ─────────────────────────    │
│    次回: 09:00   │    有効にする  ✓                     │
│                  │    ラベル  com.launchcraft.xxxxxx     │
│  ● ログ整理      │    最終実行  06/22 09:00  ✓ 成功     │
│    30分ごと      │                                      │
│    次回: あと    │  スクリプト                          │
│      12分        │    インライン │ ファイルを指定        │
│                  │    ┌────────────────────────────┐   │
│  ○ バックアップ  │    │ #!/bin/zsh                 │   │
│    毎週日 03:00  │    │ git -C ~/project pull      │   │
│    無効          │    └────────────────────────────┘   │
│                  │                                      │
│  + ジョブを追加  │  スケジュール  launchd / cron        │
│                  │                                      │
│                  │  [ テスト実行 ] [ 今すぐ実行 ]       │
│                  │  [ ログを見る ] [  保存して登録 ▶ ]  │
├──────────────────┴──────────────────────────────────────┤
│ ⌨  テスト実行: Git pull                                 │
│  $ /bin/zsh /tmp/launchcraft-test-xxxx.sh               │
│  Already up to date.                                    │
│  ― 終了コード 0 ―                                       │
└─────────────────────────────────────────────────────────┘
```

---

## 機能

### スケジュール設定（2 モード）

**launchd かんたんモード**（デフォルト）  
ドロップダウンを選ぶだけで設定完了。

| 設定例 | 動作 |
|---|---|
| 一定間隔 → 30 分 | `StartInterval = 1800` |
| 毎日 → 09:00 | `StartCalendarInterval = {Hour=9, Minute=0}` |
| 毎週 → 月・水・金 09:00 | 3 エントリの配列 |
| 毎月 → 1 日 03:00 | `{Day=1, Hour=3, Minute=0}` |

**cron モード**  
慣れた書き方でそのまま入力できます。内部で launchd へ自動変換。

```
*/5 * * * *   →  {Minute:0}, {Minute:5}, …, {Minute:55}  × 12 エントリ
0 9 * * 1-5   →  平日 9:00 × 5 エントリ
* * * * *     →  StartInterval = 60（毎分）
```

### スクリプト
- **インラインエディタ** ── アプリ内に直接コードを書ける
- **ファイル指定** ── 既存の `.sh` を選択して実行
- インタプリタ選択（zsh / bash / python3 / ruby / perl …）
- 環境変数・作業ディレクトリ・引数の設定
- PATH は `/opt/homebrew/bin` を含む形で自動補完

### 実行・ログ確認
- **テスト実行** ── 保存せず今のスクリプトをライブ実行し、下部コンソールに出力
- **今すぐ実行** ── `launchctl kickstart` で登録済みジョブを即実行
- **ログビューア** ── stdout / stderr タブ切り替え、行番号・ファイルサイズ表示、2 秒ポーリング自動更新、ログ消去
- **実行履歴** ── 最終実行日時と終了コード（成功 / 失敗）をエディタに表示
- **次回実行時刻** ── 一覧に「次回: 09:00」「あと 12 分」をリアルタイム表示
- **plist プレビュー** ── 生成される launchd 定義 XML をその場で確認

### ジョブ管理
- **Import / Export** ── ジョブ設定を JSON で書き出し・読み込み（機種移行・バックアップ）
- 有効 / 無効の即時切り替え
- RunAtLoad・KeepAlive オプション
- 削除時にジョブ・ログを一括クリーンアップ

---

## しくみ

このアプリ自身が作ったジョブだけを管理します。  
既存の LaunchAgent には一切触れません。

```
~/Library/Application Support/LaunchCraft/
├── jobs/     ← ジョブ設定 JSON（アプリの真実の源）
├── scripts/  ← インラインスクリプトの .sh
└── logs/     ← stdout / stderr ログ

~/Library/LaunchAgents/
└── com.launchcraft.<uuid>.plist  ← JSON から生成した launchd 定義
```

| 操作 | launchctl コマンド |
|---|---|
| 保存して登録 | `bootstrap gui/$UID <plist>` |
| 有効 / 無効 | `enable / disable gui/$UID/<label>` |
| 今すぐ実行 | `kickstart -k gui/$UID/<label>` |
| 削除 | `bootout gui/$UID/<label>` |

---

## ビルドと実行

```sh
git clone https://github.com/YOUR_NAME/LaunchCraft.git
open LaunchCraft/AutoShell-execer.xcodeproj
# Xcode で ⌘R
```

**要件:** macOS 26.5+ / Xcode 26.5+

> **App Sandbox はオフ**です（launchd 制御に必要）。  
> Hardened Runtime は有効なので Developer ID 配布 + 公証は可能です。

<details>
<summary>公証の手順（クリックで展開）</summary>

```sh
# 1) App 固有パスワードをキーチェーンへ登録（初回のみ）
xcrun notarytool store-credentials "AC_NOTARY" \
  --apple-id "your@appleid.com" --team-id "XXXXXXXXXX" \
  --password "xxxx-xxxx-xxxx-xxxx"

# 2) アーカイブ → export → zip
xcodebuild -project AutoShell-execer.xcodeproj -scheme AutoShell-execer \
  -configuration Release -archivePath build/LaunchCraft.xcarchive archive
xcodebuild -exportArchive -archivePath build/LaunchCraft.xcarchive \
  -exportPath build/export -exportOptionsPlist ExportOptions.plist
ditto -c -k --keepParent "build/export/AutoShell-execer.app" "build/LaunchCraft.zip"

# 3) 公証申請 → staple
xcrun notarytool submit "build/LaunchCraft.zip" --keychain-profile "AC_NOTARY" --wait
xcrun stapler staple "build/export/AutoShell-execer.app"
```

`ExportOptions.plist`:
```xml
<plist version="1.0"><dict>
  <key>method</key><string>developer-id</string>
  <key>teamID</key><string>XXXXXXXXXX</string>
  <key>signingStyle</key><string>automatic</string>
</dict></plist>
```
</details>

---

## 既知の制限

- cron 拡張記法（`L` `W` `#`）は未対応
- 「日」と「曜日」同時指定は launchd 仕様で OR → AND になる
- 他アプリが作った既存 LaunchAgent のインポートは非対応（安全のため自作ジョブのみ管理）

---

## ライセンス

MIT
