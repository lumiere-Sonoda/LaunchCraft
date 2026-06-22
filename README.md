<div align="center">

# AutoShell

**macOS 向け launchd GUI スケジューラー**  
*A native SwiftUI GUI for macOS launchd — schedule shell scripts without touching a plist.*

![macOS](https://img.shields.io/badge/macOS-26.5%2B-blue?logo=apple)
![Swift](https://img.shields.io/badge/Swift-5.0-orange?logo=swift)
![License](https://img.shields.io/badge/license-MIT-green)

</div>

---

> cron を手で書いたり、plist の書き方を調べたりするのが面倒な人へ。  
> **AutoShell** は launchd の GUI フロントエンドです。Lingon に近い使い心地を、無料・オープンソースで。

---

## スクリーンショット

| ジョブ一覧 | スケジュール設定 | ログビューア |
|---|---|---|
| ![list](docs/screenshots/list.png) | ![editor](docs/screenshots/editor.png) | ![log](docs/screenshots/log.png) |

> スクリーンショットは近日追加予定です。[Releases](../../releases) からビルド済みアプリをダウンロードしてお試しください。

---

## 機能

### スケジュール設定
- **launchd かんたんモード** — ドロップダウンで「N 分ごと」「毎日 / 毎週 / 毎月 HH:MM」を設定
- **cron モード** — `*/5 * * * *` などを入力すると launchd の `StartCalendarInterval` へ自動変換
- **次回実行時刻の表示** — 一覧に「次回: 21:00」「あと 5 分」をリアルタイム表示

### スクリプト
- **インラインエディタ** — アプリ内に直接コードを書ける（zsh / bash / sh / python3 / ruby / perl）
- **ファイル指定** — 既存の `.sh` などを選択して実行
- 環境変数・作業ディレクトリ・引数の設定

### 実行・確認
- **テスト実行** — 保存せずに今のスクリプトをライブ実行し、下部コンソールに出力
- **今すぐ実行** — 登録済みジョブを `launchctl kickstart` で即実行
- **専用ログビューア** — stdout / stderr をタブ切り替えで閲覧。行番号・ファイルサイズ表示、2 秒ポーリング自動更新、ログ消去
- **plist プレビュー** — 生成される launchd 定義 XML をその場で確認

### その他
- KeepAlive・RunAtLoad オプション
- 有効 / 無効の即時切り替え
- アプリ削除時にジョブ・ログを一括クリーンアップ

---

## しくみ

```
~/Library/Application Support/AutoShell-execer/
├── jobs/     ← ジョブ設定 JSON（アプリの真実の源）
├── scripts/  ← インラインスクリプトの .sh
└── logs/     ← stdout / stderr ログ
~/Library/LaunchAgents/
└── com.autoshell.<uuid>.plist  ← JSON から生成した launchd 定義
```

**このアプリ自身が作ったジョブだけを管理します。** 既存の LaunchAgent には一切触れません。

- 保存すると plist を生成し `launchctl bootstrap gui/$UID` で登録
- 有効/無効は `launchctl enable/disable` + bootstrap/bootout で永続制御
- 今すぐ実行は `launchctl kickstart -k`

### cron → launchd 変換

launchd の `StartCalendarInterval` は cron より表現力が低いため、**ワイルドカードでないフィールドの直積**で展開します。

| cron 式 | 変換結果 |
|---|---|
| `*/5 * * * *` | `{Minute:0}, {Minute:5}, … {Minute:55}` × 12 エントリ |
| `0 9 * * 1-5` | 平日 9:00 × 5 エントリ |
| `* * * * *` | `StartInterval = 60`（毎分） |

> ⚠️ cron の「日」と「曜日」同時指定は launchd では OR でなく AND になります。

---

## ビルドと実行

```sh
git clone https://github.com/YOUR_NAME/AutoShell-execer.git
open AutoShell-execer/AutoShell-execer.xcodeproj
# Xcode で ⌘R
```

**要件:** macOS 26.5+ / Xcode 26.5+

### App Sandbox

launchd 制御のため **Sandbox はオフ** です（Mac App Store 配布不可）。  
Hardened Runtime は有効なので Developer ID 配布 + 公証は可能です。

<details>
<summary>公証の手順（Developer ID 配布）</summary>

```sh
# 1) App固有パスワードをキーチェーンへ登録（初回のみ）
xcrun notarytool store-credentials "AC_NOTARY" \
  --apple-id "your@appleid.com" --team-id "XXXXXXXXXX" \
  --password "xxxx-xxxx-xxxx-xxxx"

# 2) アーカイブ → zip
xcodebuild -project AutoShell-execer.xcodeproj -scheme AutoShell-execer \
  -configuration Release -archivePath build/AutoShell.xcarchive archive
xcodebuild -exportArchive -archivePath build/AutoShell.xcarchive \
  -exportPath build/export -exportOptionsPlist ExportOptions.plist
ditto -c -k --keepParent "build/export/AutoShell-execer.app" "build/AutoShell.zip"

# 3) 公証申請 → staple
xcrun notarytool submit "build/AutoShell.zip" --keychain-profile "AC_NOTARY" --wait
xcrun stapler staple "build/export/AutoShell-execer.app"
```

`ExportOptions.plist` の例:
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

- cron 拡張記法 (`L`, `W`, `#`) は未対応
- 「日」と「曜日」同時指定は AND
- 他アプリが作った既存 LaunchAgent のインポートは非対応

---

## ライセンス

MIT — 詳細は [LICENSE](LICENSE) を参照してください。
