# AutoShell-execer

macOS の **launchd** を使って、シェルスクリプトを定期実行する GUI アプリ（SwiftUI）。
cron を手で書く代わりに、画面から「いつ・何を実行するか」を設定できる、Lingon ライクなツールです。

## できること

- **ジョブの作成 / 編集 / 削除 / 有効・無効切り替え**
- **スクリプトの指定**
  - インラインで直接コードを書く（インタプリタ選択可: zsh / bash / sh / python3 …）
  - 既存の `.sh` などのファイルを指定する
- **スケジュール設定（2モード）**
  - **launchd かんたんモード**（既定）: 「N分ごと」「毎日 / 毎週 / 毎月の HH:MM」をドロップダウンで
  - **cron モード**: 5フィールドをプルダウン＋プリセットで組み立て。`*/5 * * * *` などを launchd へ自動変換
- **テスト実行**: 保存・登録せずに今のスクリプトをそのまま実行し、下部のターミナル風コンソールに出力をライブ表示
- **今すぐ実行**: 登録済みジョブを launchd 経由で即実行し、ログを表示
- **ログ表示 / 保存**: stdout / stderr をコンソールで確認し、テキストファイルへ保存
- **オプション**: ログイン時に実行 (RunAtLoad)、常駐＆自動再起動 (KeepAlive)

## しくみ（アーキテクチャ）

このアプリ自身が作ったジョブだけを管理します（既存の他の LaunchAgent には触りません）。

```
~/Library/Application Support/AutoShell-execer/
├── jobs/     ← 各ジョブの設定 (JSON)  ＝ アプリの「真実の源」
├── scripts/  ← インラインスクリプトの .sh
└── logs/     ← stdout / stderr ログ
~/Library/LaunchAgents/
└── com.autoshell.<uuid>.plist  ← JSON から生成した launchd 定義
```

- 保存すると JSON から plist を生成し、`launchctl bootstrap gui/$UID` で読み込みます。
- 有効/無効は `launchctl enable/disable` の永続オーバーライド＋ bootstrap/bootout で制御。
- 今すぐ実行は `launchctl kickstart -k`。

### cron → launchd 変換について

launchd の `StartCalendarInterval` は cron ほど表現力がないため、各フィールドを値の集合に展開し、
**ワイルドカードでないフィールドだけの直積**で `StartCalendarInterval` の配列を生成します。

- `*/5 * * * *` → `{Minute:0},{Minute:5},…,{Minute:55}` の 12 個（壁時計の :00, :05… に正しく整列）
- `0 9 * * 1-5` → 平日 9:00 の 5 エントリ
- `* * * * *`（毎分）→ `StartInterval = 60`
- 展開数が多すぎる式（上限超過）はエラーにして「間隔モード」を案内します

> ⚠️ cron の「日」と「曜日」を同時指定したときの OR 挙動は、launchd では AND になります。どちらか片方は `*` を推奨します。

## ビルドと実行

```sh
open AutoShell-execer.xcodeproj   # Xcode で開いて ⌘R
# もしくは
xcodebuild -project AutoShell-execer.xcodeproj -scheme AutoShell-execer -configuration Debug build
```

要件: macOS 26.5+ / Xcode 26.5+。

### App Sandbox について

launchd への書き込みと `launchctl` 制御のため、**App Sandbox はオフ**にしています
（`ENABLE_APP_SANDBOX = NO`）。Mac App Store 配布はできませんが、Developer ID 配布＋公証は可能です。
**Hardened Runtime は有効**のままにしてあります（公証の必須要件）。

## Apple 公証 (notarization) の取り方

サンドボックスのオン/オフは公証とは無関係です。公証に必要なのは次の3つだけ:

1. **Developer ID Application 証明書**（Apple Developer Program、年 $99）
2. **Hardened Runtime 有効**（このプロジェクトは設定済み）
3. **notarytool で申請 → staple**

一番ラクな手順（`notarytool` にキーチェーンプロファイルを一度だけ登録しておく方式）:

```sh
# 0) 一度だけ: App用パスワード(appleid.apple.com で発行)をキーチェーンへ保存
xcrun notarytool store-credentials "AC_NOTARY" \
  --apple-id "あなたのAppleID" \
  --team-id "S8H29X7UP8" \
  --password "xxxx-xxxx-xxxx-xxxx"   # App固有パスワード

# 1) Developer ID でアーカイブ書き出し（Xcode: Product > Archive → Distribute App > Direct Distribution でもOK）
xcodebuild -project AutoShell-execer.xcodeproj -scheme AutoShell-execer \
  -configuration Release -archivePath build/AutoShell.xcarchive archive

xcodebuild -exportArchive -archivePath build/AutoShell.xcarchive \
  -exportPath build/export -exportOptionsPlist ExportOptions.plist

# 2) zip にして公証申請（完了まで待つ）
ditto -c -k --keepParent "build/export/AutoShell-execer.app" "build/AutoShell.zip"
xcrun notarytool submit "build/AutoShell.zip" --keychain-profile "AC_NOTARY" --wait

# 3) チケットをアプリに添付（オフラインでも Gatekeeper が通るように）
xcrun stapler staple "build/export/AutoShell-execer.app"

# 4) 確認
spctl -a -vvv "build/export/AutoShell-execer.app"   # → accepted, source=Notarized Developer ID
```

`ExportOptions.plist` の例（Developer ID 配布）:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>developer-id</string>
  <key>teamID</key><string>S8H29X7UP8</string>
  <key>signingStyle</key><string>automatic</string>
</dict></plist>
```

> 補足: Xcode の **Product > Archive → Distribute App → Direct Distribution** を使うと、署名・公証・staple をGUIで一括実行でき、上記コマンドを打たずに済みます（一番ラク）。

## 既知の制限 / 今後

- cron の `L`（末日）`W` `#` などの拡張記法は未対応
- 「日」と「曜日」同時指定は launchd 仕様で AND
- 他アプリが作った既存 LaunchAgent のインポートは未対応（安全のため自作ジョブのみ管理）
