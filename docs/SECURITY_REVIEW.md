# Security Review

調査日: 2026-08-10

## 今回実施した対策

- Sparkle を 2.9.1 から 2.9.5 へ更新し、既知の脆弱性 CVE-2026-47121 / CVE-2026-47122 を解消
- ATS の全通信許可を削除し、ローカル通信だけを例外化
- 外部画像を HTTPS、画像 MIME、20 MiB 以下、成功レスポンスに制限
- 歌詞検索 URL を `URLComponents` で構築し、JSON と 2 MiB 以下のレスポンスに制限
- カスタム Lottie URL を HTTPS のみに制限し、無効 URL の強制アンラップを削除
- XPC helper の接続を同一ユーザーかつ対象 bundle identifier の署名要件に制限
- Release版XPC helperの接続を対象bundle identifier、Apple署名、同一Team IDの組み合わせに制限（Team ID取得失敗時はfail closed）
- 使用していない incoming network server entitlement を削除
- Shelf の一時ファイルを専用 0700 ディレクトリ配下に限定し、ファイル名を無害化
- 一時ファイル削除時にシンボリックリンク解決後のパス構成要素を検証
- `.webloc` を文字列補間ではなく Property List シリアライザで生成
- ZIP対象名を `./` から始め、先頭ハイフンをコマンドオプションとして解釈させない
- `.env`、秘密鍵、証明書、provisioning profile を Git の除外対象に追加
- 通知 payload の不正な型でクラッシュする force cast を削除
- Clipboard Historyを初期状態OFF・ローカル限定とし、パスワードマネージャー、transient型、秘密鍵、一般的なAPIトークンを除外
- 会議参加リンクをHTTPSかつZoom / Meet / Teams / Webexの完全一致・サブドメインだけに制限
- Objective-C associated-object keyを保持し、解放済みアドレス再利用による衝突を修正

## 実行した検査

- Xcode static analyzer
- SwiftPM の固定バージョン12件をOSV公式APIで照合（該当0件）
- 現在の作業ツリーと Git 履歴の秘密情報パターンスキャン
- plist、asset catalog、コード署名、XPC 埋め込みの検証
- Xcode static analyzer、警告なしのClean Debugビルド、全体最適化Releaseビルド
- 単体テスト4本とUI回帰テスト3本（合計7件）

## 残る注意点

- ローカル Debug ビルドは ad-hoc 署名であり、公配布向けの Developer ID 署名・Notarization ではない。
- HUD 置換用 XPC helper はアクセシビリティ操作のためsandboxを無効にしている。Releaseの接続元検証は強化したが、Debugはad-hoc署名のため同一ユーザー＋bundle identifier検証に限定される。
- WeatherKitは配布用App IDとApple Developer Team側のCapability設定が必要。ローカルDebugはad-hoc署名を成立させるためWeatherKit entitlementを外し、失敗時はUIで安全にエラー表示する。
- MediaRemoteAdapter は非公開システム挙動の変化に影響されやすい。macOS 更新ごとの回帰検証が必要。
- この環境にはSemgrep / Gitleaksがないため、Xcode analyzerと厳格なパターンスキャンで代替した。リリースCIではCodeQL / Semgrep、SBOM、依存更新監視を継続実行することを推奨する。
