extends RefCounted
## 会話のルール (速さ・時間切れ・好感度・分岐) の値と計算。状態を持たない static な関数だけを置き、会話の進行の
## 状態は GameState (scripts/game_state.gd) が持つ。速さの値はこのスクリプトの定数にだけ置く
## (.claude/rules/conversation-speed-and-scenario-single-source.md)。

## シナリオの保存形式のキー
const ScenarioScript := preload("res://scripts/scenario.gd")
## メッセージの 1 文字あたりの表示時間 (秒)。10 文字で下限、20 文字で上限に届く傾きにして、短い相づちと長い台詞で
## 表示時間に差が出るようにした (documents/PROJECT.md「基本ルール」。CI の録画で見て調整する)
const SECONDS_PER_CHARACTER: float = 0.02
## メッセージの表示時間の下限と上限 (秒)。初期値 0.4〜0.8 秒を bannzai が遊んで「遅い」と返答したため 2 倍速にした
## (documents/DIRECTION.md「決めたこと」の 2026-10-10)
const MIN_MESSAGE_SECONDS: float = 0.2
const MAX_MESSAGE_SECONDS: float = 0.4
## 選択肢の制限時間 (秒)。documents/PROJECT.md「基本ルール」の初期値
const CHOICE_SECONDS: float = 2.0
## 時間切れで選んだ扱いになる選択肢の本文と、その好感度の変化 (documents/PROJECT.md「基本ルール」)
const TIMEOUT_TEXT: String = "……"
const TIMEOUT_AFFECTION: int = -1
## 選択肢の番号の代わりに渡す、時間切れの印 (選択肢の番号は 0 以上のため、重ならない負の値)
const TIMEOUT: int = -1
## 1 フレームで会話に進める時間の上限 (秒)。アプリが裏に回った後や描画が止まった後の最初のフレームは経過時間が
## 数秒以上になり、そのまま進めると読んでいないメッセージが流れて選択肢が時間切れになるため、上限を超えた分は
## 進めない。10 fps 相当で、通常の描画 (30〜60 fps) の 1 フレームは上限に届かない
const MAX_FRAME_SECONDS: float = 0.1
## 会話の速さの倍率。表示時間と制限時間はこの倍率で割る。通常の速さは 1、クリア後に解放する「ゆっくりモード」は
## SLOW_SPEED_RATE で、ゆっくりモードの速さは別の値の組を持たずこの倍率だけで決める
## (.claude/rules/conversation-speed-and-scenario-single-source.md)。
## ゆっくりモードでは表示時間をかけてメッセージの文字を出し、出し切った後はクリックか決定で送る (自動では送らない)。
## SLOW_SPEED_RATE は通常のギャルゲーの文字の速さ (20 文字を 1.6 秒) に合わせた値で、CI の録画で見て調整する
## (通常の速さを 2 倍速にした時に、ゆっくりモードの速さが変わらないよう 0.5 から 0.25 にした)
const NORMAL_SPEED_RATE: float = 1.0
const SLOW_SPEED_RATE: float = 0.25


## 1 フレームの経過時間 delta (秒) のうち、会話に進める時間 (秒)
static func frame_seconds(delta: float) -> float:
	return minf(delta, MAX_FRAME_SECONDS)


## ゆっくりモード (slow) かどうかに応じた会話の速さの倍率
static func speed_rate(slow: bool) -> float:
	return SLOW_SPEED_RATE if slow else NORMAL_SPEED_RATE


## 本文 text のメッセージを、速さの倍率 rate で表示し続ける時間 (秒)
static func message_seconds(text: String, rate: float = NORMAL_SPEED_RATE) -> float:
	return (
		clampf(text.length() * SECONDS_PER_CHARACTER, MIN_MESSAGE_SECONDS, MAX_MESSAGE_SECONDS)
		/ rate
	)


## line (メッセージ・選択肢・章の区切りの行) で、速さの倍率 rate の時に表示が止まる時間 (秒)。メッセージは表示時間、
## 選択肢は制限時間、章の区切りは表示されないため 0 (会話はオートセーブして通り過ぎる)
static func stop_seconds(line: Dictionary, rate: float = NORMAL_SPEED_RATE) -> float:
	if line.has(ScenarioScript.CHOICES):
		return CHOICE_SECONDS / rate
	if line.has(ScenarioScript.CHAPTER):
		return 0.0
	return message_seconds(line.get(ScenarioScript.TEXT, ""), rate)


## 本文 text のメッセージを出し始めてから elapsed 秒の時点で、速さの倍率 rate で出し終えている文字の割合 (0〜1)。
## ゆっくりモードの文字送りに使う
static func revealed_ratio(text: String, elapsed: float, rate: float) -> float:
	return clampf(elapsed / message_seconds(text, rate), 0.0, 1.0)


## choice (選択肢の行) で pick 番目 (0 始まり) を選んだ時に適用する選択肢。pick が TIMEOUT なら時間切れの扱いで、
## 本文は TIMEOUT_TEXT、好感度は choice の affection に名前があるヒロイン全員が TIMEOUT_AFFECTION、分岐先は
## choice の timeout
static func picked_option(choice: Dictionary, pick: int) -> Dictionary:
	if pick != TIMEOUT:
		return choice[ScenarioScript.CHOICES][pick]
	var affection: Dictionary = {}
	for option: Dictionary in choice[ScenarioScript.CHOICES]:
		for heroine: String in option.get(ScenarioScript.AFFECTION, {}):
			affection[heroine] = TIMEOUT_AFFECTION
	return {
		ScenarioScript.TEXT: TIMEOUT_TEXT,
		ScenarioScript.AFFECTION: affection,
		ScenarioScript.GOTO: choice.get(ScenarioScript.TIMEOUT, ""),
	}


## affection (ヒロインの ID ごとの好感度) に changes (ID ごとの変化) を足した好感度。affection は書き換えない
static func affection_after(affection: Dictionary, changes: Dictionary) -> Dictionary:
	var result: Dictionary = affection.duplicate()
	for heroine: String in changes:
		result[heroine] = int(result.get(heroine, 0)) + int(changes[heroine])
	return result


## changes (ヒロインの ID ごとの好感度の変化) で、いずれかのヒロインの好感度が変わるか (0 だけなら変わらない)
static func changes_affection(changes: Dictionary) -> bool:
	return changes.values().any(func(amount: Variant) -> bool: return int(amount) != 0)


## affection が required (ヒロインの ID ごとの必要な好感度) をすべて満たすか
static func meets(affection: Dictionary, required: Dictionary) -> bool:
	for heroine: String in required:
		if int(affection.get(heroine, 0)) < int(required[heroine]):
			return false
	return true


## lines を from 番目の行から進めて、次に止まる行 (メッセージ・選択肢・章の区切り・エンディング) の位置。ラベルは飛ばし、
## 移動は affection が条件を満たせば辿る。止まる行が無ければ lines.size()。
## 移動先が後ろの行に無い (形式の誤り) 時は次の行へ進める (前の行へ戻して終わらなくなるのを防ぐ)
static func next_stop(lines: Array, from: int, affection: Dictionary) -> int:
	var index: int = from
	while index < lines.size():
		var line: Dictionary = lines[index]
		if line.has(ScenarioScript.GOTO):
			index = (
				_target_index(lines, index, line[ScenarioScript.GOTO])
				if meets(affection, line.get(ScenarioScript.IF_AFFECTION, {}))
				else index + 1
			)
		elif line.has(ScenarioScript.LABEL):
			index += 1
		else:
			break
	return index


## lines の choice_index 番目の選択肢の行で option を選んだ後に進める行の位置 (next_stop の from に渡す)
static func option_from(lines: Array, choice_index: int, option: Dictionary) -> int:
	return _target_index(lines, choice_index, option.get(ScenarioScript.GOTO, ""))


## lines を最初から最後まで、選択肢ごとに pick_for.call(選択肢の行) の番号 (TIMEOUT なら時間切れ) を選んで進めた結果。
## "seconds" は所要時間 (通ったメッセージの表示時間の合計 + 通った選択肢の数 × 制限時間)、"affection" は最後の
## 好感度、"ending" は着いたエンディングの行 (着かなければ {})
static func playthrough(lines: Array, pick_for: Callable) -> Dictionary:
	var seconds: float = 0.0
	var affection: Dictionary = {}
	var index: int = next_stop(lines, 0, affection)
	while index < lines.size() and not lines[index].has(ScenarioScript.ENDING):
		var line: Dictionary = lines[index]
		var from: int = index + 1
		if line.has(ScenarioScript.CHOICES):
			var option: Dictionary = picked_option(line, pick_for.call(line))
			affection = affection_after(affection, option.get(ScenarioScript.AFFECTION, {}))
			from = option_from(lines, index, option)
		seconds += stop_seconds(line)
		index = next_stop(lines, from, affection)
	return {
		"seconds": seconds,
		"affection": affection,
		"ending": lines[index] if index < lines.size() else {},
	}


## lines の index 番目の行から label へ移る先の位置。label が空・無い・後ろの行に無い時は次の行
static func _target_index(lines: Array, index: int, label: String) -> int:
	if label.is_empty():
		return index + 1
	return maxi(ScenarioScript.label_index(lines, label), index + 1)
