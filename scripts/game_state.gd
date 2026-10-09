extends Node
## ゲーム進行の状態 (autoload の GameState)。いま表示している画面 (タイトル・会話中・バックログ・エンディング・
## エンディング一覧)、会話の進行 (シナリオの位置・経過時間・好感度・バックログ) と、ゆっくりモードを選んでいるかを持つ。
## 画面をまたいで参照する値はここに集める (UI ノードに状態を持たせない)。会話のルールの計算は scripts/conversation.gd。
## 章の区切りでのオートセーブと到達したエンディングの記録は SaveData (scripts/save_data.gd) に書く。

## 表示している画面。会話が進むのは PLAYING の間だけで、BACKLOG を開いている間は止まる。ENDINGS はタイトルから開く
## エンディング一覧
enum Screen { TITLE, PLAYING, BACKLOG, ENDING, ENDINGS }
## 画面を切り替える操作 (project.godot の入力の confirm / backlog / continue / ending_list)。CONTINUE はタイトルで
## 保存した章から再開する。ENDINGS はタイトルでエンディング一覧を開閉する
enum Command { CONFIRM, BACKLOG, CONTINUE, ENDINGS }

## シナリオの保存形式の読み込みとキー
const ScenarioScript := preload("res://scripts/scenario.gd")
## 会話のルールの値と計算
const ConversationScript := preload("res://scripts/conversation.gd")
## 画面ごとに受け付ける操作と、その操作で移る画面。ここに無い操作はその画面では何もしない。
## ENDING へは操作ではなく、会話がエンディングの行に着くことで移る。TITLE の CONTINUE は途中の保存がある時だけ移る
const TRANSITIONS: Dictionary = {
	Screen.TITLE:
	{
		Command.CONFIRM: Screen.PLAYING,
		Command.CONTINUE: Screen.PLAYING,
		Command.ENDINGS: Screen.ENDINGS,
	},
	Screen.PLAYING: {Command.BACKLOG: Screen.BACKLOG},
	Screen.BACKLOG: {Command.BACKLOG: Screen.PLAYING, Command.CONFIRM: Screen.PLAYING},
	Screen.ENDING: {Command.CONFIRM: Screen.TITLE},
	Screen.ENDINGS: {Command.ENDINGS: Screen.TITLE, Command.CONFIRM: Screen.TITLE},
}
## エンディング一覧で、まだ到達していないエンディングの名前の代わりに出す文字列
const UNKNOWN_ENDING_NAME: String = "???"
## 本編のシナリオ。共通パート、2 人のヒロインのルート、共通の bad エンディングの順につなげて読む (共通パートの最後の
## 移動が好感度で分ける)
const MAIN_SCENARIO_PATHS: Array[String] = [
	"res://scenario/common.json",
	"res://scenario/route_hina.json",
	"res://scenario/route_nagi.json",
	"res://scenario/common_bad.json",
]

## 表示している画面。起動時はタイトル
var screen: Screen = Screen.TITLE
## タイトルから始めるシナリオのファイル。検証 (scripts/dev/) がサンプルシナリオに差し替える
var scenario_paths: Array[String] = MAIN_SCENARIO_PATHS
## 再生しているシナリオの行 (形式は scripts/scenario.gd)。JSON を読んだままの配列のため、要素の型は持たない
var lines: Array = []
## いま表示が止まっている行 (メッセージ・選択肢・エンディング) の、lines の中の位置
var position: int = 0
## position の行で表示が止まってからの経過時間 (秒)
var elapsed: float = 0.0
## ヒロインの ID ごとの好感度
var affection: Dictionary = {}
## 流れたメッセージの行と、選んだ選択肢 (話者と本文を持つ行) の、古い順の一覧
var backlog: Array[Dictionary] = []
## オートセーブと到達したエンディングの記録先 (autoload の SaveData)。null なら保存しない。
## 検証 (scripts/dev/selfcheck.gd) は tree に入れない SaveData の実体に差し替える
var save_data: Node = null
## ゆっくりモード (通常のギャルゲーの速さで、文字送りを手で送り、選択肢に制限時間が無い) で遊ぶか。クリア済みの時だけ
## タイトルで切り替えられる。保存データには書かず、起動するたびに通常の速さから始める
var slow_mode: bool = false


## autoload の SaveData を記録先にする (project.godot の autoload の順で、SaveData が先に用意されている)
func _ready() -> void:
	save_data = get_tree().root.get_node_or_null("SaveData")


## current の画面で command を受けた時に移る画面。受け付けない操作なら current のまま。
## 遷移表の検証 (scripts/dev/selfcheck.gd) が autoload の実体なしで呼べるよう static にする
static func next_screen(current: Screen, command: Command) -> Screen:
	var accepted: Dictionary = TRANSITIONS.get(current, {})
	return accepted.get(command, current)


## lines のエンディングの名前を並び順に並べ、reached (到達したエンディングの ID) に無いものを UNKNOWN_ENDING_NAME に
## した一覧 (エンディング一覧の表示)
static func ending_names(lines: Array, reached: Array[String]) -> Array[String]:
	var names: Array[String] = []
	for line: Dictionary in lines:
		if line.has(ScenarioScript.ENDING):
			names.append(
				line[ScenarioScript.NAME]
				if reached.has(line[ScenarioScript.ENDING])
				else UNKNOWN_ENDING_NAME
			)
	return names


## command を受けて画面を移す。移ったら true。タイトルから会話中に移る時は、CONFIRM なら scenario_paths のシナリオを
## 最初から、CONTINUE なら保存した章の区切りの次から始める (保存が無ければ移らない)。
## 画面と会話の進行を書き換えるため冪等ではない
func apply(command: Command) -> bool:
	var next: Screen = next_screen(screen, command)
	if next == screen:
		return false
	if screen != Screen.TITLE or next != Screen.PLAYING:
		screen = next
	elif command == Command.CONTINUE:
		if not can_continue():
			return false
		_resume()
	else:
		_start()
	return true


## ゆっくりモードの会話中にメッセージで止まっていれば、文字を出し切る前なら全文を出し、出し切った後なら次の行へ送る。
## 送れた (文字を出し切ったか次の行へ進んだ) ら true。通常の速さでは文字送りを止めも早めもできないため何もしない。
## 経過時間と会話の位置を書き換えるため冪等ではない
func send() -> bool:
	if not is_playing() or not slow_mode or not current_line().has(ScenarioScript.TEXT):
		return false
	var seconds: float = ConversationScript.stop_seconds(current_line(), speed_rate())
	if elapsed < seconds:
		elapsed = seconds
	else:
		elapsed = 0.0
		_enter(position + 1)
	return true


## タイトルでゆっくりモードを選べる (クリア済み = エンディングを 1 つ以上見た) か
func can_select_slow_mode() -> bool:
	return save_data != null and save_data.is_cleared()


## タイトルでゆっくりモードを選べる時、ゆっくりモードと通常の速さを切り替える。切り替えたら true。
## 切り替えるたびに反転するため冪等ではない
func toggle_slow_mode() -> bool:
	if screen != Screen.TITLE or not can_select_slow_mode():
		return false
	slow_mode = not slow_mode
	return true


## いまの会話の速さの倍率
func speed_rate() -> float:
	return ConversationScript.speed_rate(slow_mode)


## いま表示が止まっているメッセージの文字を出し終えている割合 (0〜1)。ゆっくりモードでメッセージを出している途中だけ
## 1 未満になり、通常の速さと選択肢などメッセージでない行では 1
func revealed_ratio() -> float:
	if not slow_mode or not current_line().has(ScenarioScript.TEXT):
		return 1.0
	return ConversationScript.revealed_ratio(
		current_line()[ScenarioScript.TEXT], elapsed, speed_rate()
	)


## エンディング一覧の表示。scenario_paths のシナリオのエンディングを並び順に、到達していないものを
## UNKNOWN_ENDING_NAME にした名前の一覧
func ending_list() -> Array[String]:
	var reached: Array[String] = []
	if save_data != null:
		reached = save_data.reached_endings
	return ending_names(ScenarioScript.load_lines(scenario_paths), reached)


## 会話が進む画面 (会話中) か
func is_playing() -> bool:
	return screen == Screen.PLAYING


## タイトルの「つづきから」で再開できる (章の区切りの保存がある) か
func can_continue() -> bool:
	return save_data != null and save_data.has_progress()


## いま表示が止まっている行。シナリオを始めていない時と、行が尽きた時は {}
func current_line() -> Dictionary:
	return lines[position] if position < lines.size() else {}


## 会話中なら delta 秒だけ時間を進め、表示時間を過ぎたメッセージは次の行へ送り、制限時間を過ぎた選択肢は時間切れに
## する。ゆっくりモードでは送りも時間切れもせず、経過時間を止まっている行の表示時間までで止める (文字を出し切るだけ)。
## 会話中でなければ何もしない (バックログを開いている間は会話が止まる)。経過時間を積むため冪等ではない
func advance(delta: float) -> void:
	if not is_playing():
		return
	if slow_mode:
		elapsed = minf(
			elapsed + delta, ConversationScript.stop_seconds(current_line(), speed_rate())
		)
		return
	elapsed += delta
	while is_playing() and elapsed >= ConversationScript.stop_seconds(current_line()):
		elapsed -= ConversationScript.stop_seconds(current_line())
		if current_line().has(ScenarioScript.CHOICES):
			_pick(ConversationScript.TIMEOUT)
		else:
			_enter(position + 1)


## 会話中に選択肢が出ていれば option_index 番目 (0 始まり) を選ぶ。選べたら true。
## 選んだ結果を好感度とバックログに積むため冪等ではない
func choose(option_index: int) -> bool:
	var options: Array = current_line().get(ScenarioScript.CHOICES, [])
	if not is_playing() or option_index < 0 or option_index >= options.size():
		return false
	elapsed = 0.0
	_pick(option_index)
	return true


## scenario_paths のシナリオを読み、会話の進行を初期値に戻して最初の行から会話中にする
func _start() -> void:
	lines = ScenarioScript.load_lines(scenario_paths)
	_begin({}, 0)


## scenario_paths のシナリオを読み、保存した章の区切りの次の行から、保存した好感度で会話中にする。
## 保存した章がシナリオに無い (シナリオが変わった) 時は最初から始める
func _resume() -> void:
	lines = ScenarioScript.load_lines(scenario_paths)
	var chapter: int = ScenarioScript.chapter_index(lines, save_data.chapter)
	if chapter < 0:
		_begin({}, 0)
	else:
		_begin(save_data.affection, chapter + 1)


## 読み込み済みの lines で、好感度を initial_affection、バックログを空にして from 番目の行から会話中にする
func _begin(initial_affection: Dictionary, from: int) -> void:
	affection = initial_affection.duplicate()
	backlog = []
	elapsed = 0.0
	screen = Screen.PLAYING
	_enter(from)


## from 番目の行から進めて、次に止まる行に着く。章の区切りならオートセーブしてその次へ進み、メッセージならバックログに
## 積み、エンディング (または行が尽きた) ならエンディングの画面に移る
func _enter(from: int) -> void:
	position = ConversationScript.next_stop(lines, from, affection)
	if current_line().has(ScenarioScript.CHAPTER):
		if save_data != null:
			save_data.record_chapter(current_line()[ScenarioScript.CHAPTER], affection)
		_enter(position + 1)
	elif current_line().has(ScenarioScript.TEXT):
		backlog.append(current_line())
	elif not current_line().has(ScenarioScript.CHOICES):
		_finish()


## いまの選択肢の行で pick 番目 (ConversationScript.TIMEOUT なら時間切れ) を選び、好感度とバックログに積んで
## 分岐先へ進む
func _pick(pick: int) -> void:
	var choice: Dictionary = current_line()
	var option: Dictionary = ConversationScript.picked_option(choice, pick)
	affection = ConversationScript.affection_after(
		affection, option.get(ScenarioScript.AFFECTION, {})
	)
	backlog.append(
		{
			ScenarioScript.SPEAKER: choice.get(ScenarioScript.SPEAKER, ""),
			ScenarioScript.TEXT: option[ScenarioScript.TEXT],
		}
	)
	_enter(ConversationScript.option_from(lines, position, option))


## エンディングの画面に移り、着いたエンディングを到達の記録に足す
func _finish() -> void:
	screen = Screen.ENDING
	var ending: String = current_line().get(ScenarioScript.ENDING, "")
	if save_data != null and not ending.is_empty():
		save_data.record_ending(ending)
