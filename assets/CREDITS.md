# 素材の記録

`assets/` に置く素材の出典とライセンス。素材を追加・差し替えたら同じ変更でここに記録する (`make selfcheck` が、`assets/` の全ファイルがこの表に記録されていることを検証する)。記録の項目は `~/.claude/rules/coding-rules-general-assets-license.md` に従う。

## 生成画像 (立ち絵・背景・タイトルの一枚絵・流線)

下の表の「生成」の素材は、2026-10-09 に Codex CLI 0.156.0 の組み込み画像生成 (imagegen skill。ツール `image_gen.imagegen` の画像生成モデルは `gpt-image-2`。出典: https://github.com/openai/codex/blob/rust-v0.156.0/codex-rs/ext/image-generation/src/tool.rs の `const IMAGE_MODEL: &str = "gpt-image-2";`。生成時の codex のログの `model:` 行の `gpt-6-astra` はツールを呼んだ agent のモデル) で agent が生成した。生成は game-art-reference skill の `generate-reference.sh` で行い、画風は `documents/art-direction/` の承認済みの参考画像 (`play-1.png`・`title-1.png`) を添付して揃えた。プロンプトの共通部分は「1990 年代後半の PC ギャルゲー風のフラットな 2D アニメ調 (手描きの線の揺らぎと塗りむらを残したセル調)」と、使わないもの (ツヤのある 3D レンダ、金属やネオンの質感、磨かれすぎた左右対称の顔、パステル背景に太い輪郭線、写実の照明、読める文字やロゴ)。立ち絵は各ヒロインの `normal` を先に生成し、他の表情は `normal` を添付して同じ人物に揃えた。

帰属: OpenAI の利用規約 (https://openai.com/policies/terms-of-use/ 「Ownership of content」) は「As between you and OpenAI, and to the extent permitted by applicable law, you (a) retain your ownership rights in Input and (b) own the Output. We hereby assign to you all our right, title, and interest, if any, in and to Output.」と定める (2026-10-09 に検索結果の引用で確認。ページ本体はボットの確認画面で取得できなかった)。同じ節は「output may not be unique and other users may receive similar output」とも書いており、他の利用者の出力には譲渡が及ばない。クレジット表記の要否は同規約に定めが無い。

| 素材 | 用途 | 作者・入手元 | ライセンス | 改変 |
|---|---|---|---|---|
| `fonts/NotoSansJP-Regular.otf` (Noto Sans JP Regular) | プロジェクトの既定フォント (`project.godot` の `gui/theme/custom_font`)。全画面の日本語と英数字 | Google / Adobe。https://github.com/notofonts/noto-cjk の tag `Sans2.004` の `Sans/SubsetOTF/JP/NotoSansJP-Regular.otf` | SIL Open Font License 1.1 (ライセンス文を同梱する。クレジット表記は不要) | なし |
| `fonts/OFL.txt` | `fonts/NotoSansJP-Regular.otf` のライセンス文 (エクスポートの include filter で配布物に含める) | 同上の tag の `LICENSE` | SIL Open Font License 1.1 | ファイル名を `LICENSE` から変更 |
| `portraits/hina_normal.png` / `portraits/hina_smile.png` / `portraits/hina_surprised.png` / `portraits/hina_shy.png` / `portraits/hina_angry.png` / `portraits/hina_sad.png` | 早瀬ヒナの立ち絵 (表情 6 種。シナリオの `expression`) | Codex の画像生成 (gpt-image-2) で agent が生成。プロンプトの要点: 明るい茶色のくせのある短髪、紺のブレザーとオレンジのリボン、腰から上、背景は透過 | OpenAI の利用規約により出力の権利は利用者に帰属 (クレジット表記は不要) | 1086x1448 から高さ 960 に縮小 |
| `portraits/nagi_normal.png` / `portraits/nagi_smile.png` / `portraits/nagi_surprised.png` / `portraits/nagi_shy.png` / `portraits/nagi_angry.png` / `portraits/nagi_sad.png` | 千早ナギの立ち絵 (表情 6 種) | Codex の画像生成 (gpt-image-2) で agent が生成。プロンプトの要点: 腰まで届く黒のまっすぐな長い髪、紺のブレザーとオレンジのリボン、表情が読みにくい静かな少女、腰から上、背景は透過 | 同上 | 1086x1448 から高さ 960 に縮小 |
| `backgrounds/room.jpg` / `backgrounds/street.jpg` / `backgrounds/classroom.jpg` / `backgrounds/rooftop.jpg` / `backgrounds/broadcast_room.jpg` / `backgrounds/library.jpg` / `backgrounds/stage.jpg` / `backgrounds/track.jpg` / `backgrounds/beach.jpg` / `backgrounds/shrine.jpg` / `backgrounds/inn_hallway.jpg` / `backgrounds/avenue_night.jpg` / `backgrounds/sakura_tree.jpg` | 会話中の背景 (シナリオの `background`。主人公の部屋・通学路・教室・屋上・放送室・図書室・文化祭の舞台・グラウンド・海・神社・旅館の廊下・駅前の並木道・校舎裏の桜) | Codex の画像生成 (gpt-image-2) で agent が生成。プロンプトの要点: 場面の説明、人物と読める文字を描かない | 同上 | 1672x941 の PNG から 1280x720 に縮小し、ガウスぼかし (sigma 1.5) をかけて JPEG にした (立ち絵を背景から浮かせるため) |
| `title/title.jpg` | タイトル画面の一枚絵 | Codex の画像生成 (gpt-image-2) で agent が生成。プロンプトの要点: 夕方の校門、手を振るヒナと残像・流線、静かに立つナギ、下 1/3 はタイトルの空き | 同上 | 1672x941 の PNG から 1600x900 に縮小して JPEG にした |
| `effects/speed_lines.png` | ヒナの立ち絵の後ろに出す流線 | Codex の画像生成 (gpt-image-2) で agent が生成。プロンプトの要点: 左から右へ伸びるオレンジとクリーム色の細い横線、背景は透過 | 同上 | 幅 1280 に縮小 |
