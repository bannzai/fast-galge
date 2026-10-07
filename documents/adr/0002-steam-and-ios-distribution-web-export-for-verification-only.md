# 0002. Steam (デスクトップ 3 プラットフォーム) と iOS で配信し、Web エクスポートは検証専用にする

## Status

Accepted。[ADR 0001](0001-godot-gdscript-web-github-pages-no-backend.md) の配信先・計測の決定を置き換える (エンジン・レンダラ・バックエンドを持たない決定は引き継ぐ)

## Context

ADR 0001 は配信先が未決の段階で、agent が「Web エクスポートを GitHub Pages で無料配信し、Cloudflare Web Analytics で計測する」を可逆な既定として置いたもの。関門 1 (構想) で bannzai が「配信先は Steam とモバイルアプリ」「目的は SNS で面白いと思われ、アカウントの力を貯めること」「外部サービスとの新規連携はなし」と返答した ( https://github.com/bannzai/fast-galge/issues/1#issuecomment-6036755110 )。

- Godot 4.7 はデスクトップ 3 プラットフォーム (Windows / macOS / Linux) と iOS / Android にエクスポートできる。iOS のエクスポートは Xcode が要るため macOS のランナーが要る (public リポジトリのため無料)
- 計測元は castle の skill で読めるものに限る (`~/.claude/documents/rules/scaffold-scope-and-product-lessons.md`)。Steam は steam-market-research skill の `fetch-app-details.sh` でレビュー数・同時接続数を、App Store は appstore-research skill でレビュー数・評価を、公開データとして読める。Google Play の公開データを読む skill は無い
- Steamworks のパートナー登録には Steam Direct の登録料 (100 USD) と本人確認・税務情報の登録が要り、外部サービスとの新規連携に当たる

## Decision

- ADR 0001 から引き継ぐ決定 (本 ADR が有効な根拠になる): エンジンは Godot 4.7 stable、言語は GDScript で C# (.NET 版 Godot) は導入しない。レンダラは GL Compatibility (CI の Xvfb + llvmpipe と WebGL2 の両方で描画できる)。Web エクスポートの Thread Support は有効化しない。バックエンド (DB・ストレージ・認証・サーバー) を持たず、セーブデータは端末内のローカル保存 (`user://`) に置く
- 配信先は **Steam (Windows x86_64 / macOS universal / Linux x86_64) と iOS (App Store)** にする。Android は Google Play の公開データを読む手段ができてから足す
- 価格は **Steam・iOS とも無料** (課金・広告なし)。SNS で共有される目的に合わせ、特定商取引法に基づく表記・IAP・EULA の作業を増やさない。有料にする判断が出たら見直す
- **Web エクスポートは配信せず、検証専用に残す**。CI で作って artifact に置き、webtunnel skill で GitHub Actions の runner 上のブラウザから遊ぶ (開発マシンで Godot を動かさないため)。GitHub Pages は紹介ページと法務ドキュメントだけを配信し、Web ビルドを置かない
- **ゲームに計測 SDK を入れない** (Firebase Analytics / Crashlytics / Cloudflare Web Analytics のいずれも)。公開後の判定は Steam と App Store の公開データを castle の skill で読んで行う。GCP の課金・エラーアラート、Crashlytics のアラート転送は引き続き対象外
- Steam への提出 (SteamPipe) と TestFlight への配布は `workflow_dispatch` だけの CD にし、関門 3 (触れる版) で公開に進むと決まるまで動かさない。Steamworks の登録はユーザー作業として「ユーザー作業の一覧」issue に記録し、Steam への提出の起動条件にする
- 操作はキーボードとタップの両方を最初から入れる (iOS のため)
- Steamworks SDK (GodotSteam 等による実績・クラウドセーブ) は入れない。入れる判断が出たら別 ADR で決める
- 法務ドキュメントは Steam (購入の契約相手は Valve) と App Store (配信者は Apple) の両方を扱う記述にし、GitHub Pages のページを App Store の Support URL と privacy URL に使う

## Consequences

- 良い点: 配信先が bannzai の目的 (Steam と App Store で配信した作品としてアカウントの力になる) に合う。計測は公開データで済み、SDK の保守と同意の表示が要らない
- 悪い点: 判定基準の計測はレビュー数・同時接続数という粗い値になる。Steam への提出は Steamworks の登録 (100 USD) を待つ。iOS のビルドは macOS ランナーの時間を使う。Android は当面出さない
- エージェントへの制約: Web ビルドを配信しない (`docs/play/` に置かない)。計測 SDK を追加しない。Steam・TestFlight への配布を既定ブランチへの push で動かさない。Steamworks SDK を追加しない (根拠は本 ADR)
