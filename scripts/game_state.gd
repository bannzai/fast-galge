extends Node
## ゲーム進行の状態 (autoload の GameState)。いま表示している画面 (タイトル・会話中・バックログ・エンディング)、
## 会話の進行 (シナリオの位置・経過時間・好感度・バックログ)、結果画面の値 (所要時間・選んだ選択肢の数・時間切れの回数) を持つ。
## 画面をまたいで参照する値はここに集める (UI ノードに状態を持たせない)。会話のルールの計算は scripts/conversation.gd。
## 章の区切りでのオートセーブと到達したエンディングの記録は SaveData (scripts/save_data.gd) に書く。

## 表示している画面。会話が進むのは PLAYING の間だけで、BACKLOG を開いている間は止まる
enum Screen { TITLE, PLAYING, BACKLOG, ENDING }
## 画面を切り替える操作 (project.godot の入力の confirm / backlog / continue)。CONTINUE はタイトルで保存した章から再開する
enum Command { CONFIRM, BACKLOG, CONTINUE }

## シナリオの保存形式の読み込みとキー
const ScenarioScript := preload("res://scripts/scenario.gd")
## 会話のルールの値と計算
const ConversationScript := preload("res://scripts/conversation.gd")
## 結果 (エンディングに着いた時の値) のキー
const ResultScript := preload("res://scripts/result.gd")
## 画面ごとに受け付ける操作と、その操作で移る画面。ここに無い操作はその画面では何もしない。
## ENDING へは操作ではなく、会話がエンディングの行に着くことで移る。TITLE の CONTINUE は途中の保存がある時だけ移る
const TRANSITIONS: Dictionary = {
	Screen.TITLE: {Command.CONFIRM: Screen.PLAYING, Command.CONTINUE: Screen.PLAYING},
	Screen.PLAYING: {Command.BACKLOG: Screen.BACKLOG},
	Screen.BACKLOG: {Command.BACKLOG: Screen.PLAYING, Command.CONFIRM: Screen.PLAYING},
	Screen.ENDING: {Command.CONFIRM: Screen.TITLE},
}
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
## 今回の会話 (最初から、または「つづきから」の再開から) で進めた時間の合計 (秒)。結果画面の所要時間。advance に渡された
## 時間の合計で、1 フレームの上限 (ConversationScript.MAX_FRAME_SECONDS) で切り詰めた後の値のため、描画が止まった分は
## 実時間より短くなる
var play_seconds: float = 0.0
## 今回の会話で制限時間内に選んだ選択肢の数と、時間切れの回数
var choice_count: int = 0
var timeout_count: int = 0
## オートセーブと到達したエンディングの記録先 (autoload の SaveData)。null なら保存しない。
## 検証 (scripts/dev/selfcheck.gd) は tree に入れない SaveData の実体に差し替える
var save_data: Node = null


## autoload の SaveData を記録先にする (project.godot の autoload の順で、SaveData が先に用意されている)
func _ready() -> void:
	save_data = get_tree().root.get_node_or_null("SaveData")


## current の画面で command を受けた時に移る画面。受け付けない操作なら current のまま。
## 遷移表の検証 (scripts/dev/selfcheck.gd) が autoload の実体なしで呼べるよう static にする
static func next_screen(current: Screen, command: Command) -> Screen:
	var accepted: Dictionary = TRANSITIONS.get(current, {})
	return accepted.get(command, current)


## command を受けて画面を移す。移ったら true。タイトルから会話中に移る時は、CONFIRM なら scenario_paths のシナリオを
## 最初から、CONTINUE なら保存した章の区切りの次から始める (保存が無ければ移らない)。
## 画面と会話の進行を書き換えるため冪等ではない
func apply(command: Command) -> bool:
	var next: Screen = next_screen(screen, command)
	if next == screen:
		return false
	if screen != Screen.TITLE:
		screen = next
	elif command == Command.CONTINUE:
		if not can_continue():
			return false
		_resume()
	else:
		_start()
	return true


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
## する。会話中でなければ何もしない (バックログを開いている間は会話が止まる)。経過時間を積むため冪等ではない
func advance(delta: float) -> void:
	if not is_playing():
		return
	elapsed += delta
	play_seconds += delta
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


## エンディングの画面に出す結果 (エンディング名・所要時間・選んだ選択肢の数・時間切れの回数。キーは scripts/result.gd)
func result() -> Dictionary:
	return {
		ResultScript.ENDING_NAME: current_line().get(ScenarioScript.NAME, ""),
		ResultScript.SECONDS: play_seconds,
		ResultScript.CHOICES: choice_count,
		ResultScript.TIMEOUTS: timeout_count,
	}


## scenario_paths のシナリオを読み、会話の進行と結果を初期値に戻して最初の行から会話中にする
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
	play_seconds = 0.0
	choice_count = 0
	timeout_count = 0
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


## いまの選択肢の行で pick 番目 (ConversationScript.TIMEOUT なら時間切れ) を選び、結果の回数・好感度・バックログに
## 積んで分岐先へ進む
func _pick(pick: int) -> void:
	var choice: Dictionary = current_line()
	var option: Dictionary = ConversationScript.picked_option(choice, pick)
	if pick == ConversationScript.TIMEOUT:
		timeout_count += 1
	else:
		choice_count += 1
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
