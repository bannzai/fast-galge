extends "res://scripts/dev/game_driver.gd"
## headless で実行する検証 (scripts/dev/selfcheck.gd と scripts/dev/integration.gd) が継承する土台。
## 検証の失敗の記録と、両方の検証が使うシナリオ・選択肢の選び方を持つ (入力の送り方とメインシーンの置き方は
## scripts/dev/game_driver.gd)。

## 会話のルールの値と計算
const ConversationScript := preload("res://scripts/conversation.gd")
## 会話エンジンの検証に使うサンプルシナリオ (10 メッセージと選択肢 1 つ。選んだ好感度で 2 つのエンディングに分かれる)
const SAMPLE_SCENARIO_PATHS: Array[String] = ["res://scenario/sample.json"]

## 検証が 1 件でも失敗したか。true なら exit code 1 で終わる
var failed: bool = false


## cond が false なら label を ERROR として出し、失敗として記録する。
## ERROR の行頭には実行した検証のスクリプトの名前 (selfcheck / integration) を付ける
func _check(cond: bool, label: String) -> void:
	if not cond:
		push_error("%s FAIL: %s" % [get_script().resource_path.get_file().get_basename(), label])
		failed = true


## choice (選択肢の行) の選択肢のうち、好感度の変化の合計が最も大きい (direction = 1) / 最も小さい (direction = -1)
## ものの番号 (0 始まり。同じ合計なら先のもの)
func _option_by_affection(choice: Dictionary, direction: int) -> int:
	var totals: Array[int] = []
	for option: Dictionary in choice[ScenarioScript.CHOICES]:
		var total: int = 0
		for amount: Variant in option.get(ScenarioScript.AFFECTION, {}).values():
			total += int(amount) * direction
		totals.append(total)
	return totals.find(totals.max())
