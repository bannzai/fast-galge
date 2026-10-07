# fast-galge

会話がすごい早さで進むギャルゲー (Godot 4.7 / Steam と iOS)。仕様・スコープは [documents/PROJECT.md](documents/PROJECT.md) を参照 (SSOT)。判断の根拠 (仮説・判定基準・決めたこと) は [documents/DIRECTION.md](documents/DIRECTION.md)。

## 制約

- C# (.NET 版 Godot) を導入しない。レンダラを GL Compatibility から変えない。Web エクスポートの Thread Support を有効化しない。サーバー・計測 SDK (Firebase / Cloudflare Web Analytics 等) を追加しない。Steamworks SDK を追加しない。根拠: [ADR 0001](documents/adr/0001-godot-gdscript-web-github-pages-no-backend.md)、[ADR 0002](documents/adr/0002-steam-and-ios-distribution-web-export-for-verification-only.md)
- Web ビルドは検証専用で配信しない (GitHub Pages の `docs/play/` に置かない)。関門 3 (触れる版) で公開に進むと決まるまで、Steam (SteamPipe)・TestFlight への配布を既定ブランチへの push で動かさない。ビルドは CI の artifact (`fast-galge-desktop` / `fast-galge-web`) に留める

## 検証方法

ビルド・Godot の起動 (headless を含む)・描画付きの撮影・ブラウザや simulator での動作確認は、開発マシンの負荷を避けるため、このマシンでは実行せず外部マシンに任せる。本リポジトリは public のため GitHub Actions のランナー (Linux。iOS のエクスポートだけ macOS) を使い、ブラウザでの操作を伴う確認は webtunnel skill (runner 上の Chromium を Tailscale 経由で操作する) で Web ビルドを開いて行い、iOS の simulator での確認は simtunnel (ios-simulator skill) で行う。private リポジトリへ変える場合は、描画を伴う動作確認を Devin のセッションで行う (devin-macos-e2e skill)。

- このマシンで実行してよいのは `make lint` (gdlint) だけ。ユーザーが明示的に頼んだ時と、人が遊んで確かめる `make run` はこの限りでない
- 変更は push して PR を開き、CI の結果で成否を判断する。`gh pr checks <PR 番号> --watch` で完了を待ち、失敗したら `gh run view <run ID> --log-failed` と artifact `fast-galge-check-logs` の `tmp/*.log` を読む
- 見た目の確認は artifact `fast-galge-screenshot-and-movie` を `gh run download <run ID> -n fast-galge-screenshot-and-movie -D tmp/artifact` で取得し、PNG と、mp4 の末尾のフレーム (`ffmpeg -sseof -1 -i tmp/artifact/movie.mp4 -frames:v 1 tmp/artifact/movie-last.png`) を目視してから完了報告する
- ブラウザでの動作確認 (Web ビルドを実際に開いて操作する) は webtunnel skill (`~/.claude/skills/webtunnel/SKILL.md`) で行う。`WEBTUNNEL_REPO=bannzai/fast-galge` で `up <session> --software-webgl --wait` を実行すると、runner が `.github/workflows/browser-session.yml` の手順で Web エクスポートを作って配信し、`scripts/godot-web.sh --session <session>` でクリック・キー入力・撮影ができる。Secrets (`TS_OIDC_CLIENT_ID` / `TS_OIDC_AUDIENCE`) の登録が前提 (未登録なら「ユーザー作業の一覧」issue の項目)
- Web ビルドをローカルで開く時は artifact `fast-galge-web` を `gh run download <run ID> -n fast-galge-web -D tmp/artifact-web` で取得し (artifact 名を 1 つ指定した時は指定したディレクトリの直下に展開される)、`python3 -m http.server 8000 --directory tmp/artifact-web` で配信してブラウザで開く (Web ビルドは file:// の直開きでは動かない。ローカルのブラウザは runner の代わりにならないため、人が遊ぶ時だけ)
- 人がデスクトップ版を遊ぶ時は artifact `fast-galge-desktop` を取得し、macOS なら `macos/fast-galge.zip` を展開してアプリを開く (未署名のため Gatekeeper の警告が出る)

各 target の内容と成功条件 (CI が実行する。`GODOT` 未指定時の既定は macOS の `/Applications/Godot.app/Contents/MacOS/Godot`、CI では Linux バイナリを渡す):

| 目的 | コマンド | 成功条件 |
|---|---|---|
| lint | `make lint` (`gdlint scripts/`) | exit 0 |
| アセットインポート (初回・素材追加後) | `make import` | exit 0 (ログは `tmp/import.log`) |
| 起動検証 (メインシーン・スクリプトのロード) | `make check` | exit 0 かつ `tmp/check.log` に `fast-galge boot` が出力され、WARNING / ERROR 行がない |
| ロジック検証 (画面の遷移表、全シーンのロード、全素材が `assets/CREDITS.md` に記録されていること) | `make selfcheck` | exit 0 かつ `tmp/selfcheck.log` に `selfcheck OK` が出力され、WARNING / ERROR 行がない |
| 入力統合テスト (キー入力でタイトル → 会話中 → バックログ → 会話中の遷移と見出しの追従) | `make integration` | exit 0 かつ `tmp/integration.log` に `integration OK` が出力され、WARNING / ERROR 行がない |
| headless 検証の一括実行 (lint → check → selfcheck → integration) | `make test` (引数なしの `make` = `verify` も同じ) | exit 0 |
| スクリーンショット (タイトル・会話中・バックログ。headless の検証では見た目の崩れを検出できない) | `make screenshot` | exit 0 かつ `tmp/screenshot-*.png` が生成される |
| 起動の録画 (操作なしの起動〜タイトルの表示。起動直後の描画崩れ・真っ黒を検出する) | `make movie` | exit 0 かつ `tmp/movie.mp4` が生成され、末尾のフレームの輝度平均が基準以上 (ffmpeg が必要) |
| ゲームをエディタなしで起動 (人が遊んで確かめる。アセットのインポートを含む) | `make run` | ウィンドウが開きタイトル画面が表示される |
| デスクトップエクスポート (Steam に提出する 3 プラットフォーム) | `make build-macos` / `make build-windows` / `make build-linux` / `make build-all` | exit 0 で `build/<platform>/` に成果物が生成され、`tmp/build-<platform>.log` に WARNING / ERROR 行がない |
| Web エクスポート (検証専用。webtunnel で開く) | `make build-web` | exit 0 で `build/web/` に `index.html` / `index.wasm` / `index.pck` が生成され、`tmp/build-web.log` に WARNING / ERROR 行がない |

- 画面や状態を追加したら `scripts/dev/screenshot.gd` の `_capture_scenes()` に撮影を足し、入力で変わる振る舞いは `scripts/dev/integration.gd` に検証を足す。純粋な計算は `scripts/dev/selfcheck.gd` に検証を足す
- Godot の起動にはすべて `--log-file` を付ける (Makefile の `ENGINE_LOG`)。付けないと Godot が `user://` にログを書こうとし、書き込みを拒否するサンドボックスでは起動に失敗する
- ログは `tmp/*.log` に保存し、target の標準出力と `--log-file` の Godot 自身のログ (`tmp/<target>.godot.log`) の両方の全文を WARNING / ERROR 検査する (`tail` で切り詰めて判定しない。Makefile の `check_clean_log`)
- エクスポートには Godot 4.7 の各プラットフォームの export template (デスクトップ 3 つと Web 用の `web_nothreads_release.zip`) が要る。CI は `.github/actions/setup-godot` が tpz から必要なテンプレートだけを取り出してキャッシュする
- スクリプト・シーンを足した時に Godot が生成する `.uid` はコミット対象 (`~/.claude/rules/coding-rules-godot-gdscript-and-project-layout.md`)。このマシンでは生成できないため、CI の artifact `fast-galge-uid` を `gh run download <run ID> -n fast-galge-uid -D .` で取り込んでコミットする

## 規約

- コーディング規約は `~/.claude/rules/` の Godot・素材ライセンスの規約と、[.claude/rules/](.claude/rules/) のプロジェクト固有の規約に従う

<!-- ai-review-config begin -->
<!--
このブロックは自動生成です。直接編集せず、テンプレートを更新してから再生成してください。
内容は AI コードレビュー時の挙動指示であり、コードベース自体への規約ではありません。
-->

## レビュー時の応答スタイル

- 応答は日本語で行う

## レビュー範囲外

以下は自動レビューで指摘しない (別の検出経路があるため):

- コンパイルエラー・型エラー (ローカル/CI のビルドで検出される)
- Lint/フォーマット違反 (リンター・フォーマッターで検出される)
<!-- ai-review-config end -->
