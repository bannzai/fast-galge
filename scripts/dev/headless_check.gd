extends "res://scripts/dev/game_driver.gd"
## headless で実行する検証 (scripts/dev/selfcheck.gd と scripts/dev/integration.gd) が継承する土台。
## 検証の失敗の記録と、両方の検証が使うシナリオ・選択肢の選び方を持つ (入力の送り方とメインシーンの置き方は
## scripts/dev/game_driver.gd)。

## 会話のルールの値と計算
const ConversationScript := preload("res://scripts/conversation.gd")
## 会話エンジンの検証に使うサンプルシナリオ (10 メッセージと選択肢 1 つ。選んだ好感度で 2 つのエンディングに分かれる)
const SAMPLE_SCENARIO_PATHS: Array[String] = ["res://scenario/sample.json"]
## 本編のヒロインの ID と、そのルートの先頭のラベル (scenario/common.json の最後の移動の先)
const ROUTE_LABELS: Dictionary = {"hina": "route_hina", "nagi": "route_nagi"}
## 本編の 5 つのエンディングへの進め方 (エンディングの ID・ヒロインの ID・ルートでの選び方の向き)。ルートの 4 つは
## 共通パートでそのヒロインへ向かう選択をしてから、ルートで好感度を上げる (1) / 下げる (-1) 選択をする。共通 bad は
## 何も選ばない (全部時間切れ) 進め方で、ヒロインの ID を空にして表す
const MAIN_ENDING_CASES: Array[Array] = [
	["hina_good", "hina", 1],
	["hina_bad", "hina", -1],
	["nagi_good", "nagi", 1],
	["nagi_bad", "nagi", -1],
	["common_bad", "", 0],
]

## 検証が 1 件でも失敗したか。true なら exit code 1 で終わる
var failed: bool = false


## cond が false なら label を ERROR として出し、失敗として記録する。
## ERROR の行頭には実行した検証のスクリプトの名前 (selfcheck / integration) を付ける
func _check(cond: bool, label: String) -> void:
	if not cond:
		push_error("%s FAIL: %s" % [get_script().resource_path.get_file().get_basename(), label])
		failed = true


## choice (選択肢の行) の選択肢のうち、heroine の好感度の変化が最も大きい (direction = 1) / 最も小さい (direction = -1)
## ものの番号 (0 始まり。同じ変化なら先のもの。名前の無い選択肢の変化は 0)
func _option_for(choice: Dictionary, heroine: String, direction: int) -> int:
	var changes: Array[int] = []
	for option: Dictionary in choice[ScenarioScript.CHOICES]:
		changes.append(int(option.get(ScenarioScript.AFFECTION, {}).get(heroine, 0)) * direction)
	return changes.find(changes.max())


## MAIN_ENDING_CASES の case (ヒロインの ID と向き) で、lines の index 番目の選択肢の行で選ぶ番号。共通パート (ヒロインの
## ルートのラベルより前) ではそのヒロインの好感度が最も上がる選択肢、ルートでは向きに従った選択肢。共通 bad の
## 進め方 (ヒロインの ID が空) は時間切れ
func _pick_for_case(case: Array, lines: Array, index: int) -> int:
	if case[1].is_empty():
		return ConversationScript.TIMEOUT
	var in_route: bool = index >= ScenarioScript.label_index(lines, ROUTE_LABELS[case[1]])
	return _option_for(lines[index], case[1], case[2] if in_route else 1)
