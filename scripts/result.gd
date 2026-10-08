extends RefCounted
## 結果画面 (エンディングに着いた時の結果) の値と、X に投稿する文面・URL の組み立て。状態を持たない static な関数だけを
## 置き、結果の値 (所要時間・選んだ選択肢の数・時間切れの回数) は GameState (scripts/game_state.gd) が記録する。
## 文面の文字数の上限と URL の形は scripts/dev/selfcheck.gd が検証する。

## 結果 (GameState.result() が返す Dictionary) のキー
const ENDING_NAME: String = "ending_name"
const SECONDS: String = "seconds"
const CHOICES: String = "choices"
const TIMEOUTS: String = "timeouts"
## 結果の画像と文面に入れるゲーム名・ハッシュタグ・URL。URL は紹介ページ (documents/PROJECT.md「技術・配信」)。
## Steam・App Store のストアページができたらそちらに差し替える
const GAME_NAME: String = "fast-galge"
const HASHTAG: String = "#fastgalge"
const URL: String = "https://bannzai.github.io/fast-galge/"
## X の投稿画面を開く Web Intent の URL (text に文面を付ける)。twitter.com/intent/tweet は x.com へ転送される
const INTENT_URL_PREFIX: String = "https://x.com/intent/post?text="
## X の 1 投稿の文字数の上限 (重みつき)。URL は長さによらず URL_WEIGHT、全角の文字 (CJK 等) は 2、
## それ以外 (ASCII・ラテン文字等) は 1 として数える (X の文字数の数え方)
const MAX_WEIGHTED_LENGTH: int = 280
const URL_WEIGHT: int = 23
## 重み 1 で数える文字のコードポイントの範囲 (両端を含む)。範囲の外は重み 2
const SINGLE_WEIGHT_RANGES: Array[Array] = [
	[0x0000, 0x10FF],
	[0x2000, 0x200D],
	[0x2010, 0x201F],
	[0x2032, 0x2037],
]
## 保存する結果の画像のファイル名
const IMAGE_FILE_NAME: String = "fast-galge-result.png"


## seconds (所要時間) を「分秒」の表記にする (秒は切り捨て)
static func format_seconds(seconds: float) -> String:
	var total: int = int(floorf(seconds))
	return "%d分%02d秒" % [total / 60, total % 60]


## result (ENDING_NAME・SECONDS・CHOICES・TIMEOUTS) を 1 行ずつにした、結果の画像に出す本文。
## 無いキーは 0 として出す (シナリオを始める前の空の結果でも本文の形を崩さないため)
static func stats_text(result: Dictionary) -> String:
	return "\n".join(
		PackedStringArray(
			[
				"所要時間 %s" % format_seconds(result.get(SECONDS, 0.0)),
				"選んだ選択肢 %d" % int(result.get(CHOICES, 0)),
				"時間切れ %d" % int(result.get(TIMEOUTS, 0)),
			]
		)
	)


## result を X に投稿する文面 (ゲーム名・エンディング名・結果・ハッシュタグ・URL)
static func share_text(result: Dictionary) -> String:
	return "\n".join(
		PackedStringArray(
			[
				GAME_NAME,
				"エンディング「%s」" % result.get(ENDING_NAME, ""),
				stats_text(result),
				HASHTAG,
				URL,
			]
		)
	)


## text を文面にして X の投稿画面を開く URL。文面は URL に入れられるよう符号化する
static func share_url(text: String) -> String:
	return INTENT_URL_PREFIX + text.uri_encode()


## text の X の数え方での文字数 (URL は URL_WEIGHT、全角の文字は 2、それ以外は 1。改行と空白は 1)。
## URL は改行か空白で区切られた、http:// か https:// で始まる語
static func weighted_length(text: String) -> int:
	var lines: PackedStringArray = text.split("\n")
	var total: int = lines.size() - 1
	for line: String in lines:
		var tokens: PackedStringArray = line.split(" ")
		total += tokens.size() - 1
		for token: String in tokens:
			if token.begins_with("http://") or token.begins_with("https://"):
				total += URL_WEIGHT
				continue
			for index: int in range(token.length()):
				total += 1 if _is_single_weight(token.unicode_at(index)) else 2
	return total


## code (コードポイント) が重み 1 で数える文字か
static func _is_single_weight(code: int) -> bool:
	for range_pair: Array in SINGLE_WEIGHT_RANGES:
		if code >= range_pair[0] and code <= range_pair[1]:
			return true
	return false
