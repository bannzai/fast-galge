# 0001. Godot 4.7 + GDScript の Web エクスポートを GitHub Pages で配信し、バックエンドを持たない

## Status

Accepted

## Context

会話がすごい早さで進むギャルゲーを、1 プレイ 5 分前後の無料ブラウザゲームとして公開する ( https://github.com/bannzai/IdeaMemo/issues/355 、評価と判定は関門 1 の issue https://github.com/bannzai/fast-galge/issues/1 )。企画の段階で「Godot で作る」が決まっている。

- リポジトリは public。GitHub Actions の Linux ランナーを無料で使える
- 開発マシン (macOS) の負荷を下げるため、ビルド・描画付きの検証は GitHub Actions で行いたい。Xvfb 上のソフトウェア GL (Mesa llvmpipe) で描画できるレンダラが必要になる
- オンライン機能 (ランキング・アカウント・課金) は企画に無い
- 公開後の継続・打ち切りは訪問数とエンディング到達率で判定する (documents/DIRECTION.md)。計測元は castle の skill で読めるものに限る

## Decision

- エンジンは Godot 4.7 stable、言語は GDScript にする。C# (.NET 版 Godot) は導入しない (.NET 版は Web エクスポートの準備が増え、ノベルゲームで C# を要する理由がない)
- レンダラは GL Compatibility にする。2D で Forward+ の機能を使わず、CI の Xvfb + llvmpipe と Web (WebGL2) の両方で描画できる
- エクスポート先は Web (シングルスレッド。`variant/thread_support=false`) だけにする。SharedArrayBuffer を使わないため COOP / COEP ヘッダが不要で、GitHub Pages のような静的配信で動く。Thread Support は有効化しない
- 配信先は GitHub Pages。LP と法務ドキュメントは `docs/` に置いてデフォルトブランチの `/docs` から配信し、Web ビルドは関門 3 で公開に進むと決まった後に `docs/play/` へ CD (`workflow_dispatch`) で配置する。それまで Web ビルドは CI の artifact (`fast-galge-web`) に留める
- バックエンド (DB・ストレージ・認証・サーバー) を持たない。セーブデータはブラウザのローカル保存 (`user://`、Web では IndexedDB) に置く。課金・アカウントは無い
- 計測は Cloudflare Web Analytics の JS スニペット (Cloudflare 外のサイト向け) をゲームのページだけに置く。ゲーム内に計測 SDK を入れない。このため GCP の課金・エラーアラート、Crashlytics のアラート転送は対象外にする
- 特定商取引法に基づく表記は用意しない (課金が無いため)。課金を入れる判断をした時に見直す

## Consequences

- 良い点: サーバーの運用費・障害対応が無い。検証は Linux ランナーで完結し、開発マシンで Godot を起動しなくてよい。配信は main へのマージと CD の実行だけで済む
- 悪い点: クラッシュや不具合の報告はユーザーからの連絡 (メール) に頼る。GL Compatibility では Forward+ 専用の描画機能を使えない。シングルスレッドの Web ビルドは重い処理で描画が止まり得るため、会話の演出は軽く保つ
- エージェントへの制約: C# を導入しない。レンダラを GL Compatibility から変えない。Web エクスポートの Thread Support を有効化しない。サーバー・計測 SDK を追加しない (根拠は本 ADR)
