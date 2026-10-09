extends Control
## 結果の画像 (1200x630。X のタイムラインで読める大きさの文字) を描く専用のシーン。メインシーンの SubViewport の中に置き、
## エンディングの画面に表示するのと PNG に保存するのに同じ描画を使う。紙のカード・流線・2 人のスタンプは背景の 1 枚の
## 画像 (assets/result/result_card.jpg) に描かれており、文字はその上に重ねる (エンディング名は画像の上部の枠の中)。

## 結果の値と文面の組み立て
const ResultScript := preload("res://scripts/result.gd")

## ゲーム名、エンディング名、結果 (所要時間・選んだ選択肢の数・時間切れの回数) の本文、ハッシュタグと URL
@onready var game_name_label: Label = $GameName
@onready var ending_name_label: Label = $EndingName
@onready var stats_label: Label = $Stats
@onready var footer_label: Label = $Footer


## ゲーム名・ハッシュタグ・URL を scripts/result.gd の定数から出す (投稿の文面と同じ値にする)
func _ready() -> void:
	game_name_label.text = ResultScript.GAME_NAME
	footer_label.text = footer_text()


## 画像の下に出すハッシュタグと URL
static func footer_text() -> String:
	return "%s  %s" % [ResultScript.HASHTAG, ResultScript.URL]


## result (GameState.result()) を画像の本文に写す
func show_result(result: Dictionary) -> void:
	ending_name_label.text = result.get(ResultScript.ENDING_NAME, "")
	stats_label.text = ResultScript.stats_text(result)
