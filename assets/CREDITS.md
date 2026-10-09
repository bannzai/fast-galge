# 素材の記録

`assets/` に置く素材の出典とライセンス。素材を追加・差し替えたら同じ変更でここに記録する (`make selfcheck` が、`assets/` の全ファイルがこの表に記録されていることを検証する)。記録の項目は `~/.claude/rules/coding-rules-general-assets-license.md` に従う。

| 素材 | 用途 | 作者・入手元 | ライセンス | 改変 |
|---|---|---|---|---|
| `fonts/NotoSansJP-Regular.otf` (Noto Sans JP Regular) | プロジェクトの既定フォント (`project.godot` の `gui/theme/custom_font`)。全画面の日本語と英数字 | Google / Adobe。https://github.com/notofonts/noto-cjk の tag `Sans2.004` の `Sans/SubsetOTF/JP/NotoSansJP-Regular.otf` | SIL Open Font License 1.1 (ライセンス文を同梱する。クレジット表記は不要) | なし |
| `fonts/OFL.txt` | `fonts/NotoSansJP-Regular.otf` のライセンス文 (エクスポートの include filter で配布物に含める) | 同上の tag の `LICENSE` | SIL Open Font License 1.1 | ファイル名を `LICENSE` から変更 |
| `audio/bgm_common.ogg` | 共通パートの会話中の BGM | 本プロジェクトで自作。`scripts/dev/generate_audio.py` が波形を合成し、ffmpeg (libvorbis) で Ogg Vorbis にエンコードした | 本プロジェクトの一部。外部の素材を含まないため、クレジット表記は不要 | なし |
| `audio/bgm_route.ogg` | ヒロインのルートの会話中の BGM | 同上 | 同上 | なし |
| `audio/bgm_ending.ogg` | エンディングの画面の BGM | 同上 | 同上 | なし |
| `audio/se_message.wav` | 文字送り (メッセージの切り替わり) の効果音 | 本プロジェクトで自作。`scripts/dev/generate_audio.py` が波形を合成した | 同上 | なし |
| `audio/se_choice.wav` | 選択肢の表示の効果音 | 同上 | 同上 | なし |
| `audio/se_timeout.wav` | 時間切れの効果音 | 同上 | 同上 | なし |
| `audio/se_affection.wav` | 好感度の変化の効果音 | 同上 | 同上 | なし |
