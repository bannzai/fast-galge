extends Control
## 結果の画像 (1200x630。X のタイムラインで読める大きさの文字) を描く専用のシーン。メインシーンの SubViewport の中に置き、
## エンディングの画面に表示するのと PNG に保存するのに同じ描画を使う (見た目は仮の配色。関門 2 のデザインの反映で
## 作り直す)。

## 結果の値と文面の組み立て
const ResultScript := preload("res://scripts/result.gd")

## エンディング名と、結果 (所要時間・選んだ選択肢の数・時間切れの回数) の本文
@onready var ending_name_label: Label = $EndingName
@onready var stats_label: Label = $Stats


## result (GameState.result()) を画像の本文に写す
func show_result(result: Dictionary) -> void:
	ending_name_label.text = result.get(ResultScript.ENDING_NAME, "")
	stats_label.text = ResultScript.stats_text(result)
