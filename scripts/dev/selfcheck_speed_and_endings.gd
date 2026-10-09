extends "res://scripts/dev/selfcheck_menu.gd"
## selfcheck (scripts/dev/selfcheck.gd) の検証のうち、エンディング一覧の画面の遷移、会話の速さの倍率、ゆっくりモードの
## 解放の条件と手で送る進行、エンディング一覧の名前の検証。selfcheck.gd がこのスクリプトを継承して _check_speed_and_endings() を呼ぶ
## (selfcheck.gd を gdlint の 1 ファイルの行数の上限に収めるため分けた。GameState と SaveData のスクリプトの定数は
## 継承元の scripts/dev/selfcheck_menu.gd のもの)。

## エンディング一覧の画面の遷移表の検証 (いまの画面・操作・移る先・説明)
const ENDINGS_TRANSITION_CASES: Array[Array] = [
	[
		GAME_STATE_SCRIPT.Screen.TITLE,
		GAME_STATE_SCRIPT.Command.ENDINGS,
		GAME_STATE_SCRIPT.Screen.ENDINGS,
		"タイトルでエンディング一覧を開ける",
	],
	[
		GAME_STATE_SCRIPT.Screen.ENDINGS,
		GAME_STATE_SCRIPT.Command.ENDINGS,
		GAME_STATE_SCRIPT.Screen.TITLE,
		"エンディング一覧をもう一度押すとタイトルに戻る",
	],
	[
		GAME_STATE_SCRIPT.Screen.ENDINGS,
		GAME_STATE_SCRIPT.Command.CONFIRM,
		GAME_STATE_SCRIPT.Screen.TITLE,
		"エンディング一覧で決定するとタイトルに戻る",
	],
	[
		GAME_STATE_SCRIPT.Screen.ENDINGS,
		GAME_STATE_SCRIPT.Command.CONTINUE,
		GAME_STATE_SCRIPT.Screen.ENDINGS,
		"エンディング一覧のつづきからでは画面が変わらない",
	],
	[
		GAME_STATE_SCRIPT.Screen.PLAYING,
		GAME_STATE_SCRIPT.Command.ENDINGS,
		GAME_STATE_SCRIPT.Screen.PLAYING,
		"会話中にエンディング一覧は開けない",
	],
]
## ゆっくりモードの文字送りの検証 (経過時間をゆっくりモードの表示時間で割った割合・期待する出し終えた割合)
const REVEALED_RATIO_CASES: Array[Array] = [
	[0.0, 0.0],
	[0.5, 0.5],
	[1.0, 1.0],
	[3.0, 1.0],
]
## 倍率の検証で表示時間を比べる本文の文字数 (下限に張り付く・下限と上限の間・上限に張り付く)
const MESSAGE_LENGTHS: Array[int] = [10, 15, 40]
## 倍率の検証で止まる時間を比べる選択肢の行
const CHOICE_LINE: Dictionary = {
	"choices": [{"text": "a", "affection": {"a": 1}}, {"text": "b", "affection": {"a": -1}}],
}


## このスクリプトの検証 (エンディング一覧の画面の遷移・速さの倍率・ゆっくりモード・一覧の名前) を実行する
func _check_speed_and_endings() -> void:
	_check_endings_transitions()
	_check_speed_rate()
	_check_slow_mode_unlock()
	_check_slow_mode_conversation()
	_check_ending_names()


## エンディング一覧の画面の遷移表 (ENDINGS_TRANSITION_CASES) と、GameState の実体で一覧を開閉しても会話が始まらないこと
func _check_endings_transitions() -> void:
	for case: Array in ENDINGS_TRANSITION_CASES:
		var actual: GAME_STATE_SCRIPT.Screen = GAME_STATE_SCRIPT.next_screen(case[0], case[1])
		_check(actual == case[2], "遷移: %s" % case[3])
	var listing: Node = GAME_STATE_SCRIPT.new()
	_check(listing.apply(GAME_STATE_SCRIPT.Command.ENDINGS), "apply: タイトルでエンディング一覧を開ける")
	_check(listing.screen == GAME_STATE_SCRIPT.Screen.ENDINGS, "apply: エンディング一覧の画面に移る")
	listing.apply(GAME_STATE_SCRIPT.Command.CONFIRM)
	_check(listing.screen == GAME_STATE_SCRIPT.Screen.TITLE, "apply: 一覧で決定するとタイトルに戻る")
	_check(listing.lines.is_empty(), "apply: エンディング一覧の開閉では会話が始まらない")
	listing.free()


## 会話の速さの倍率の計算。ゆっくりモードは通常と同じ計算に倍率を渡し、表示時間と制限時間を倍率で割る
func _check_speed_rate() -> void:
	var slow: float = ConversationScript.SLOW_SPEED_RATE
	_check(ConversationScript.speed_rate(false) == 1.0, "倍率: 通常の速さは 1")
	_check(ConversationScript.speed_rate(true) == slow, "倍率: ゆっくりモードの倍率")
	_check(slow > 0.0 and slow < 1.0, "倍率: ゆっくりモードは通常より遅い")
	for characters: int in MESSAGE_LENGTHS:
		var text_of_length: String = "あ".repeat(characters)
		var seconds: float = ConversationScript.message_seconds(text_of_length, slow)
		var normal: float = ConversationScript.message_seconds(text_of_length)
		_check(is_equal_approx(seconds, normal / slow), "倍率: %d 文字の表示時間を倍率で割る" % characters)
	var choice_seconds: float = ConversationScript.stop_seconds(CHOICE_LINE, slow)
	var limit: float = ConversationScript.CHOICE_SECONDS / slow
	_check(is_equal_approx(choice_seconds, limit), "倍率: 選択肢の制限時間も倍率で割る")
	var text: String = "あ".repeat(15)
	for case: Array in REVEALED_RATIO_CASES:
		var elapsed: float = case[0] * ConversationScript.message_seconds(text, slow)
		var ratio: float = ConversationScript.revealed_ratio(text, elapsed, slow)
		_check(is_equal_approx(ratio, case[1]), "文字送り: 表示時間の %.1f 倍で %.1f まで出す" % case)


## ゆっくりモードの解放の条件。クリア済み (到達したエンディングがある) の時だけ、タイトルで切り替えられる
func _check_slow_mode_unlock() -> void:
	var game_state: Node = GAME_STATE_SCRIPT.new()
	var label: String = "ゆっくりモード: "
	_check(not game_state.can_select_slow_mode(), label + "保存データが無ければ選べない")
	var saver: Node = SAVE_DATA_SCRIPT.new()
	game_state.save_data = saver
	_check(not game_state.toggle_slow_mode(), label + "エンディングを見ていなければ選べない")
	_check(not game_state.slow_mode, label + "選べない間は通常の速さのまま")
	saver.reached_endings.append("sample_bad")
	_check(game_state.can_select_slow_mode(), label + "エンディングを 1 つ見ると選べる")
	_check(game_state.toggle_slow_mode() and game_state.slow_mode, label + "タイトルで切り替えられる")
	_check(game_state.toggle_slow_mode() and not game_state.slow_mode, label + "もう一度で通常に戻る")
	game_state.scenario_paths = SAMPLE_SCENARIO_PATHS
	game_state.apply(GAME_STATE_SCRIPT.Command.CONFIRM)
	_check(not game_state.toggle_slow_mode(), label + "会話中は切り替えられない")
	game_state.free()
	saver.free()


## ゆっくりモードの会話の進行 (サンプルシナリオ)。時間が経っても自動では送らず、文字を出し切るだけ。決定 (send) で
## 出し切る前は全文を出し、出し切った後は次の行へ送る。選択肢は時間切れにならない。通常の速さでは send しても送れない
func _check_slow_mode_conversation() -> void:
	var label: String = "ゆっくりモード: "
	var game_state: Node = GAME_STATE_SCRIPT.new()
	game_state.scenario_paths = SAMPLE_SCENARIO_PATHS
	game_state.apply(GAME_STATE_SCRIPT.Command.CONFIRM)
	_check(not game_state.send(), "通常の速さ: 決定してもメッセージは送れない")
	_check(game_state.revealed_ratio() == 1.0, "通常の速さ: メッセージは最初から全文を出す")
	game_state.free()
	game_state = GAME_STATE_SCRIPT.new()
	game_state.scenario_paths = SAMPLE_SCENARIO_PATHS
	game_state.slow_mode = true
	game_state.apply(GAME_STATE_SCRIPT.Command.CONFIRM)
	_check(game_state.revealed_ratio() == 0.0, label + "メッセージの文字は始めは出ていない")
	game_state.advance(60.0)
	_check(game_state.position == 0, label + "時間が経ってもメッセージは自動で送られない")
	_check(game_state.revealed_ratio() == 1.0, label + "表示時間が経つと文字を出し切る")
	_check(game_state.send() and game_state.position == 1, label + "出し切った後の決定で次へ送る")
	_check(game_state.revealed_ratio() == 0.0, label + "送った次のメッセージは出し始めから")
	_check(game_state.send() and game_state.position == 1, label + "出し切る前の決定では送らない")
	_check(game_state.revealed_ratio() == 1.0, label + "出し切る前の決定で全文を出す")
	while not _is_choosing(game_state):
		game_state.send()
	game_state.advance(60.0)
	_check(game_state.affection.is_empty(), label + "選択肢は時間が経っても時間切れにならない")
	_check(not game_state.send(), label + "選択肢で止まっている間は決定で送れない")
	_check(game_state.choose(0), label + "選択肢を選べる")
	while game_state.is_playing():
		game_state.send()
	_check(game_state.current_line().get("ending") == "sample_good", label + "送り続けると着く")
	game_state.free()


## エンディング一覧の名前。シナリオのエンディングを並び順に並べ、到達していないものは名前を隠す
func _check_ending_names() -> void:
	var sample: Array = ScenarioScript.load_lines(SAMPLE_SCENARIO_PATHS)
	var main_lines: Array = ScenarioScript.load_lines(GAME_STATE_SCRIPT.MAIN_SCENARIO_PATHS)
	var unknown: String = GAME_STATE_SCRIPT.UNKNOWN_ENDING_NAME
	var none: Array[String] = []
	var good: Array[String] = ["sample_good"]
	var all_main: Array[String] = []
	for case: Array in MAIN_ENDING_CASES:
		all_main.append(case[0])
	var names: Array[String] = GAME_STATE_SCRIPT.ending_names(main_lines, all_main)
	var label: String = "エンディング一覧: "
	_check(GAME_STATE_SCRIPT.ending_names(sample, none) == [unknown, unknown], label + "未到達は隠す")
	var with_good: Array[String] = GAME_STATE_SCRIPT.ending_names(sample, good)
	_check(with_good == [unknown, "ふたりの帰り道"], label + "到達したものだけ名前を出す")
	_check(names.size() == all_main.size() and not names.has(unknown), label + "本編は全部出る %s" % [names])
	var game_state: Node = GAME_STATE_SCRIPT.new()
	var hidden: Array[String] = GAME_STATE_SCRIPT.ending_names(main_lines, none)
	_check(game_state.ending_list() == hidden, label + "保存データが無ければ本編を全部隠す")
	game_state.free()
