extends "res://scripts/dev/headless_check.gd"
## 画面の遷移表、会話エンジンの計算 (表示時間・時間切れ・好感度・分岐・所要時間)、シナリオの形式、本編 (5 つのエンディングへの
## 到達・各ルートの所要時間・共通パートの分岐)、GameState の会話の進行、全シーンのロード、全素材が assets/CREDITS.md に
## 記録されていることの検証 (headless)。
## 実行方法は AGENTS.md を参照。release ビルドで assert が消えるため、明示的な判定と exit code で結果を返す。

## 起動検証 (main_scene の --quit) ではロードされない遷移先も含めた全シーン
const SCENES: Array[String] = [
	"res://scenes/main.tscn",
]
## 画面と遷移表を持つ autoload のスクリプト
const GAME_STATE_SCRIPT := preload("res://scripts/game_state.gd")
## 背景と立ち絵の素材と、いま出すものの決め方
const StageScript := preload("res://scripts/stage.gd")
## 背景と立ち絵の決め方の検証 (バックログ・期待する背景・期待する立ち絵の行の、バックログの中の位置 (-1 は無し)・説明)
const STAGE_CASES: Array[Array] = [
	[[], "", -1, "何も流れていなければ背景も立ち絵も無い"],
	[
		[{"text": "a", "background": "room"}, {"text": "b", "speaker": "ヒナ", "expression": "smile"}],
		"room",
		1,
		"背景を指定した行の後のヒロインの行で、背景と立ち絵が出る",
	],
	[
		[
			{"text": "a", "background": "room"},
			{"text": "b", "speaker": "ヒナ", "expression": "smile"},
			{"text": "c", "speaker": "ユウ"},
			{"text": "d"},
		],
		"room",
		1,
		"主人公の台詞や地の文の間も、直前のヒロインの立ち絵が残る",
	],
	[
		[
			{"text": "a", "background": "room"},
			{"text": "b", "speaker": "ヒナ", "expression": "smile"},
			{"text": "c", "background": "street"},
		],
		"street",
		-1,
		"場面が変わると立ち絵が消え、新しい背景が出る",
	],
	[
		[
			{"text": "a", "background": "room"},
			{"text": "b", "background": "street", "speaker": "ナギ", "expression": "normal"},
		],
		"street",
		1,
		"背景と表情を両方持つ行は、新しい場面の最初の立ち絵になる",
	],
]
## 素材の検証で、素材が無いことを見つけるシナリオ (誤りを含む行・説明)
const INVALID_STAGE_LINES: Array[Array] = [
	[{"text": "a", "background": "nowhere"}, "素材の無い背景"],
	[{"text": "a", "speaker": "ヒナ", "expression": "crying"}, "素材の無い表情"],
	[{"text": "a", "speaker": "ユウ", "expression": "smile"}, "立ち絵の無い話者の表情"],
]
## 素材の置き場所と、出典・ライセンスの記録
const ASSETS_DIR: String = "res://assets"
const CREDITS_PATH: String = "res://assets/CREDITS.md"
## 素材として記録しないファイル (記録そのものと、Godot が生成するインポート設定)
const CREDITS_EXEMPT_SUFFIXES: Array[String] = ["CREDITS.md", ".import", ".gdignore"]
## シナリオの置き場所
const SCENARIO_DIR: String = "res://scenario"
## 遷移表の検証 (いまの画面・操作・移る先・説明)。会話中の決定で画面が変わらないのは、文字送りを止められない
## というルールの表れ
const TRANSITION_CASES: Array[Array] = [
	[
		GAME_STATE_SCRIPT.Screen.TITLE,
		GAME_STATE_SCRIPT.Command.CONFIRM,
		GAME_STATE_SCRIPT.Screen.PLAYING,
		"タイトルで決定すると会話中になる",
	],
	[
		GAME_STATE_SCRIPT.Screen.TITLE,
		GAME_STATE_SCRIPT.Command.BACKLOG,
		GAME_STATE_SCRIPT.Screen.TITLE,
		"タイトルではバックログを開けない",
	],
	[
		GAME_STATE_SCRIPT.Screen.PLAYING,
		GAME_STATE_SCRIPT.Command.BACKLOG,
		GAME_STATE_SCRIPT.Screen.BACKLOG,
		"会話中にバックログを開ける",
	],
	[
		GAME_STATE_SCRIPT.Screen.PLAYING,
		GAME_STATE_SCRIPT.Command.CONFIRM,
		GAME_STATE_SCRIPT.Screen.PLAYING,
		"会話中の決定では画面が変わらない",
	],
	[
		GAME_STATE_SCRIPT.Screen.BACKLOG,
		GAME_STATE_SCRIPT.Command.BACKLOG,
		GAME_STATE_SCRIPT.Screen.PLAYING,
		"バックログを閉じると会話中に戻る",
	],
	[
		GAME_STATE_SCRIPT.Screen.ENDING,
		GAME_STATE_SCRIPT.Command.CONFIRM,
		GAME_STATE_SCRIPT.Screen.TITLE,
		"エンディングで決定するとタイトルに戻る",
	],
]
## メッセージの表示時間の検証 (本文の文字数・期待する秒数)。10 文字以下は下限、20 文字以上は上限に張り付く
const MESSAGE_SECONDS_CASES: Array[Array] = [
	[0, 0.4],
	[10, 0.4],
	[15, 0.6],
	[20, 0.8],
	[40, 0.8],
]
## 分岐・好感度・時間切れ・所要時間の計算の検証に使う、選択肢 1 つのシナリオ。
## 1 つ目の選択肢 (up) は条件つきの移動を満たして good、2 つ目 (down) と時間切れ (late) は満たさず bad に着く
const BRANCH_LINES: Array = [
	{"text": "ああああああああああ"},
	{
		"choices": [
			{"text": "up", "affection": {"a": 2, "b": 1}, "goto": "up"},
			{"text": "down", "affection": {"a": -2}},
		],
		"timeout": "late",
	},
	{"text": "ああああああああああああああああああああ"},
	{"goto": "merge"},
	{"label": "late"},
	{"text": "ああああああああああ"},
	{"goto": "merge"},
	{"label": "up"},
	{"label": "merge"},
	{"goto": "good", "if_affection": {"a": 2, "b": 1}},
	{"ending": "bad", "name": "bad", "summary": "bad"},
	{"label": "good"},
	{"ending": "good", "name": "good", "summary": "good"},
]
## BRANCH_LINES を通しで進めた結果の検証 (選ぶ番号・期待する所要時間・期待する好感度・期待するエンディング・説明)。
## 所要時間は通ったメッセージの表示時間と選択肢の制限時間の合計
const BRANCH_PLAYTHROUGH_CASES: Array[Array] = [
	[0, 2.4, {"a": 2, "b": 1}, "good", "1 つ目の選択肢"],
	[1, 3.2, {"a": -2}, "bad", "2 つ目の選択肢 (分岐先を省いて次の行へ進む)"],
	[ConversationScript.TIMEOUT, 2.8, {"a": -1, "b": -1}, "bad", "時間切れ"],
]
## 形式の誤りの検証で、シナリオの最後に置くエンディングの行
const ENDING_LINE: Dictionary = {"ending": "end", "name": "end", "summary": "end"}
## 形式の誤りを見つけることの検証 (誤りを含むシナリオ・説明)
const INVALID_SCENARIOS: Array[Array] = [
	[[], "行が無い"],
	[[{"text": "a"}], "最後の行がエンディングではない"],
	[["text", ENDING_LINE], "行が辞書ではない"],
	[[{"text": "a", "label": "x"}, ENDING_LINE], "行の種類が 2 つある"],
	[[{"text": "a", "expresion": "smile"}, ENDING_LINE], "知らないキーがある"],
	[[{"text": ""}, ENDING_LINE], "本文が空"],
	[[{"text": "a", "background": ""}, ENDING_LINE], "背景が空"],
	[[{"goto": "nowhere"}, ENDING_LINE], "移動先のラベルが無い"],
	[[{"label": "back"}, {"text": "a"}, {"goto": "back"}, ENDING_LINE], "移動先が前の行にある"],
	[[{"label": "x"}, {"label": "x"}, ENDING_LINE], "ラベルが重複している"],
	[[{"goto": "end", "if_affection": {"a": 0.5}}, {"label": "end"}, ENDING_LINE], "条件が整数ではない"],
	[
		[{"choices": [{"text": "a", "affection": {"a": 1}}]}, ENDING_LINE],
		"選択肢が 1 つしかない",
	],
	[
		[
			{
				"choices": [
					{"text": "a", "affection": {"a": 1}},
					{"text": "b"},
					{"text": "c"},
					{"text": "d"},
				]
			},
			ENDING_LINE,
		],
		"選択肢が 4 つある",
	],
	[
		[{"choices": [{"text": "a"}, {"text": "b"}]}, ENDING_LINE],
		"時間切れで好感度が下がる相手が決まらない",
	],
	[
		[
			{
				"choices": [{"text": "a", "affection": {"a": 1}}, {"text": "b"}],
				"timeout": "nowhere",
			},
			ENDING_LINE,
		],
		"時間切れの分岐先のラベルが無い",
	],
	[
		[
			{"choices": [{"text": "a", "affection": {"a": 1}, "goto": "end"}, {"text": "b"}]},
			{"label": "end"},
			ENDING_LINE,
		],
		"分岐先を持つ選択肢があるのに時間切れの分岐先が無い",
	],
	[[{"ending": "end"}], "エンディング名と一言が無い"],
]
## 本編のルートに入る周 (共通パート + どちらかのヒロインのルート) の所要時間の範囲 (秒)。共通パート 1 分 + ルート 5 分前後
## (documents/PROJECT.md「登場人物とシナリオの規模」) に対し、4〜7 分に収める
const MAIN_MIN_SECONDS: float = 240.0
const MAIN_MAX_SECONDS: float = 420.0
## 共通 bad に着く周 (共通パート + 共通 bad エンディング) の所要時間の範囲 (秒)。共通パート 1 分前後とエンディングの
## 数行で、ルートに入る周の下限より短く終わる
const COMMON_BAD_MIN_SECONDS: float = 45.0
const COMMON_BAD_MAX_SECONDS: float = 150.0
## ルートに入る周で通る選択肢の数の範囲 (共通パートの 2 箇所 + ルートの 2〜5 箇所)
const MAIN_MIN_CHOICES: int = 4
const MAIN_MAX_CHOICES: int = 7
## ルートに入るのに要るヒロインの好感度 (scenario/common.json の最後の移動の if_affection)。共通パートの選択肢は
## 一方を上げると他方を下げるため、この値を満たすヒロインは相手より厳密に高く、2 人同時には満たさない
const ROUTE_MIN_AFFECTION: int = 1
## 共通パートの分岐の検証で、共通パートの後ろに置くルートと共通 bad の代わりの行 (ラベルは scenario/common.json の
## 移動先と同じ名前)。エンディングの ID (ルートはヒロインの ID、共通 bad は COMMON_BAD) で、どこへ移ったかを見る
const COMMON_BAD: String = "common_bad"
const ROUTE_STUB_LINES: Array = [
	{"label": "route_hina"},
	{"ending": "hina", "name": "hina", "summary": "hina"},
	{"label": "route_nagi"},
	{"ending": "nagi", "name": "nagi", "summary": "nagi"},
	{"label": COMMON_BAD},
	{"ending": COMMON_BAD, "name": COMMON_BAD, "summary": COMMON_BAD},
]


## 全検証を実行し、1 件でも失敗していれば exit code 1、すべて通れば `selfcheck OK` を出して exit code 0 で終わる
func _initialize() -> void:
	_check_transitions()
	_check_message_seconds()
	_check_branch()
	_check_scenario_format()
	_check_main_scenario()
	_check_game_state_conversation()
	_check_stage()
	_check_scenes()
	_check_credits()
	if failed:
		quit(1)
		return
	print("selfcheck OK")
	quit(0)


## 遷移表 (TRANSITION_CASES) と GameState の実体の振る舞いの検証
func _check_transitions() -> void:
	for case: Array in TRANSITION_CASES:
		var actual: GAME_STATE_SCRIPT.Screen = GAME_STATE_SCRIPT.next_screen(case[0], case[1])
		_check(actual == case[2], "遷移: %s" % case[3])
	var game_state: Node = GAME_STATE_SCRIPT.new()
	_check(game_state.screen == GAME_STATE_SCRIPT.Screen.TITLE, "起動時の画面はタイトル")
	_check(game_state.apply(GAME_STATE_SCRIPT.Command.CONFIRM), "apply: 画面が移ると true")
	_check(game_state.is_playing(), "apply の後は会話中")
	_check(not game_state.apply(GAME_STATE_SCRIPT.Command.CONFIRM), "apply: 画面が変わらないと false")
	game_state.free()


## メッセージの表示時間 (MESSAGE_SECONDS_CASES)、選択肢の行で止まる時間、1 フレームで進める時間の検証
func _check_message_seconds() -> void:
	for case: Array in MESSAGE_SECONDS_CASES:
		_check(
			is_equal_approx(ConversationScript.message_seconds("あ".repeat(case[0])), case[1]),
			"表示時間: %d 文字は %.1f 秒" % case
		)
	_check(
		is_equal_approx(
			ConversationScript.stop_seconds(BRANCH_LINES[1]), ConversationScript.CHOICE_SECONDS
		),
		"選択肢の行は制限時間だけ止まる"
	)
	_check(
		is_equal_approx(ConversationScript.frame_seconds(1.0 / 60.0), 1.0 / 60.0),
		"1 フレームの時間: 通常の描画の経過時間はそのまま進める"
	)
	_check(
		is_equal_approx(
			ConversationScript.frame_seconds(5.0), ConversationScript.MAX_FRAME_SECONDS
		),
		"1 フレームの時間: 描画が止まっていた後の長い経過時間は上限までしか進めない"
	)


## 分岐・時間切れ・好感度・所要時間の計算の検証 (BRANCH_LINES)
func _check_branch() -> void:
	var choice: Dictionary = BRANCH_LINES[1]
	_check(ScenarioScript.validate(BRANCH_LINES).is_empty(), "分岐の検証用のシナリオは形式が正しい")
	_check(ConversationScript.next_stop(BRANCH_LINES, 0, {}) == 0, "分岐: メッセージの行で止まる")
	_check(ConversationScript.next_stop(BRANCH_LINES, 3, {}) == 10, "分岐: 条件を満たさない移動は辿らない")
	_check(
		ConversationScript.next_stop(BRANCH_LINES, 3, {"a": 2, "b": 1}) == 12,
		"分岐: 条件を満たす移動を辿る"
	)
	_check(
		ConversationScript.next_stop(BRANCH_LINES, 3, {"a": 5, "b": 0}) == 10,
		"分岐: 条件のヒロインが 1 人でも足りなければ辿らない"
	)
	_check(
		ConversationScript.option_from(BRANCH_LINES, 1, choice["choices"][0]) == 7,
		"分岐: 選択肢の分岐先のラベルへ進む"
	)
	_check(
		ConversationScript.option_from(BRANCH_LINES, 1, choice["choices"][1]) == 2,
		"分岐: 分岐先を省いた選択肢は次の行へ進む"
	)
	var timeout: Dictionary = ConversationScript.picked_option(choice, ConversationScript.TIMEOUT)
	_check(timeout["text"] == ConversationScript.TIMEOUT_TEXT, "時間切れ: 「……」を選んだ扱いになる")
	_check(
		timeout["affection"] == {"a": -1, "b": -1},
		"時間切れ: 選択肢に名前があるヒロイン全員の好感度が 1 下がる"
	)
	_check(
		ConversationScript.option_from(BRANCH_LINES, 1, timeout) == 4,
		"時間切れ: 時間切れの分岐先のラベルへ進む"
	)
	var before: Dictionary = {"a": 1}
	_check(
		ConversationScript.affection_after(before, {"a": 2, "b": -1}) == {"a": 3, "b": -1},
		"好感度: ヒロインごとに変化を足す"
	)
	_check(before == {"a": 1}, "好感度: 元の好感度を書き換えない")
	for case: Array in BRANCH_PLAYTHROUGH_CASES:
		var pick: Callable = func(_choice: Dictionary) -> int: return case[0]
		var result: Dictionary = ConversationScript.playthrough(BRANCH_LINES, pick)
		_check(is_equal_approx(result["seconds"], case[1]), "所要時間: %s" % case[4])
		_check(result["affection"] == case[2], "通しの好感度: %s" % case[4])
		_check(result["ending"].get("ending") == case[3], "通しのエンディング: %s" % case[4])


## シナリオの形式の検証。scenario/ の全ファイルが検証の対象 (サンプルか本編) に入っていて形式が正しいことと、
## 形式の誤り (INVALID_SCENARIOS) を見つけること
func _check_scenario_format() -> void:
	for file: String in DirAccess.get_files_at(SCENARIO_DIR):
		var path: String = SCENARIO_DIR + "/" + file
		_check(
			path in SAMPLE_SCENARIO_PATHS or path in GAME_STATE_SCRIPT.MAIN_SCENARIO_PATHS,
			"シナリオの形式: %s がサンプルか本編に入っている" % path
		)
	_check_scenario_valid(SAMPLE_SCENARIO_PATHS)
	_check_scenario_valid(GAME_STATE_SCRIPT.MAIN_SCENARIO_PATHS)
	for case: Array in INVALID_SCENARIOS:
		_check(not ScenarioScript.validate(case[0]).is_empty(), "形式の誤りを見つける: %s" % case[1])


## paths のファイルをつなげたシナリオの形式が正しい
func _check_scenario_valid(paths: Array[String]) -> void:
	var errors: Array[String] = ScenarioScript.validate(ScenarioScript.load_lines(paths))
	_check(errors.is_empty(), "シナリオの形式: %s %s" % [paths, errors])


## 本編の検証。MAIN_ENDING_CASES の 5 つの進め方がそれぞれのエンディングに着き、ルートに入る周は所要時間と通る選択肢の
## 数が範囲に収まり、共通 bad に着く周は短い範囲に収まること。共通パートの分岐の検証は _check_route_split
func _check_main_scenario() -> void:
	var lines: Array = ScenarioScript.load_lines(GAME_STATE_SCRIPT.MAIN_SCENARIO_PATHS)
	for case: Array in MAIN_ENDING_CASES:
		var picked: Array[int] = []
		var pick: Callable = func(choice: Dictionary) -> int:
			picked.append(_pick_for_case(case, lines, lines.find(choice)))
			return picked.back()
		var result: Dictionary = ConversationScript.playthrough(lines, pick)
		_check(
			result["ending"].get(ScenarioScript.ENDING) == case[0],
			"本編: %s への進め方で着く (好感度 %s)" % [case[0], result["affection"]]
		)
		var min_seconds: float = MAIN_MIN_SECONDS if case[0] != COMMON_BAD else COMMON_BAD_MIN_SECONDS
		var max_seconds: float = MAIN_MAX_SECONDS if case[0] != COMMON_BAD else COMMON_BAD_MAX_SECONDS
		_check(
			result["seconds"] >= min_seconds and result["seconds"] <= max_seconds,
			(
				"本編: %s の所要時間が %.0f〜%.0f 秒に収まる (%.1f 秒)"
				% [case[0], min_seconds, max_seconds, result["seconds"]]
			)
		)
		if case[0] != COMMON_BAD:
			_check(
				picked.size() >= MAIN_MIN_CHOICES and picked.size() <= MAIN_MAX_CHOICES,
				(
					"本編: %s で通る選択肢が %d〜%d 箇所 (%d 箇所)"
					% [case[0], MAIN_MIN_CHOICES, MAIN_MAX_CHOICES, picked.size()]
				)
			)
		_check_main_progress(
			case,
			lines,
			result,
			picked.filter(func(pick: int) -> bool: return pick != ConversationScript.TIMEOUT).size()
		)
	_check_route_split(ScenarioScript.load_lines([GAME_STATE_SCRIPT.MAIN_SCENARIO_PATHS[0]]))


## 本編を GameState で case の進め方 (選択肢が出たらすぐ選ぶ) で最後まで進めた時の所要時間・好感度・エンディングが、
## expected (同じ進め方の playthrough の結果) と一致すること。playthrough は選択肢ごとに制限時間を丸ごと数え、GameState は
## 選んだ時点で次へ進むため、所要時間は選んだ (時間切れでない) 選択肢の数 (choices) × 制限時間を引いて比べる。
## 所要時間の見積もりが実際の会話の進み方とずれていないことを確かめる
func _check_main_progress(case: Array, lines: Array, expected: Dictionary, choices: int) -> void:
	var game_state: Node = GAME_STATE_SCRIPT.new()
	game_state.apply(GAME_STATE_SCRIPT.Command.CONFIRM)
	var stepped: float = 0.0
	while game_state.is_playing():
		var pick: int = (
			_pick_for_case(case, lines, game_state.position)
			if _is_choosing(game_state)
			else ConversationScript.TIMEOUT
		)
		if pick != ConversationScript.TIMEOUT:
			game_state.choose(pick)
		else:
			game_state.advance(FAST_FORWARD_STEP)
			stepped += FAST_FORWARD_STEP
	var expected_seconds: float = expected["seconds"] - choices * ConversationScript.CHOICE_SECONDS
	_check(
		absf(stepped - expected_seconds) <= FAST_FORWARD_STEP * (choices + 1) + 0.001,
		(
			"本編: %s を GameState で進めた所要時間が見積もりと一致する (%.2f 秒 / 見積もり %.2f 秒)"
			% [case[0], stepped, expected_seconds]
		)
	)
	_check(
		game_state.affection == expected["affection"],
		"本編: %s を GameState で進めた好感度が見積もりと一致する" % case[0]
	)
	_check(
		game_state.current_line() == expected["ending"],
		"本編: %s を GameState で進めたエンディングが見積もりと一致する" % case[0]
	)
	game_state.free()


## 共通パート (common_lines) の分岐の検証。選択肢の選び方 (時間切れを含む) の全組み合わせで、共通パートの最後の移動が
## 「好感度が相手より厳密に高く ROUTE_MIN_AFFECTION 以上のヒロインのルート、いなければ共通 bad」に着くこと
## (documents/PROJECT.md「基本ルール」のルートの分かれ方)
func _check_route_split(common_lines: Array) -> void:
	var lines: Array = common_lines + ROUTE_STUB_LINES
	var choices: Array = lines.filter(
		func(line: Dictionary) -> bool: return line.has(ScenarioScript.CHOICES)
	)
	for picks: Array in _pick_combinations(choices):
		var picked: Array[int] = []
		var pick: Callable = func(_choice: Dictionary) -> int:
			picked.append(picks[picked.size()])
			return picked.back()
		var result: Dictionary = ConversationScript.playthrough(lines, pick)
		_check(
			result["ending"].get(ScenarioScript.ENDING) == _route_for(result["affection"]),
			(
				"共通パートの分岐: 選び方 %s (好感度 %s) で %s に移る (実際は %s)"
				% [picks, result["affection"], _route_for(result["affection"]), result["ending"]]
			)
		)


## affection (ヒロインの ID ごとの好感度) で入るルートのヒロインの ID。相手より厳密に高く ROUTE_MIN_AFFECTION 以上の
## ヒロインがいなければ COMMON_BAD
func _route_for(affection: Dictionary) -> String:
	var route: String = COMMON_BAD
	var highest: int = ROUTE_MIN_AFFECTION - 1
	for heroine: String in ROUTE_LABELS:
		var value: int = int(affection.get(heroine, 0))
		if value > highest:
			route = heroine
			highest = value
		elif value == highest:
			route = COMMON_BAD
	return route


## choices (選択肢の行の配列) を順に選ぶ番号の全組み合わせ (各行は 0〜選択肢の数 - 1 と時間切れ)
func _pick_combinations(choices: Array) -> Array:
	var combinations: Array = [[]]
	for choice: Dictionary in choices:
		var picks: Array = range(choice[ScenarioScript.CHOICES].size()) + [ConversationScript.TIMEOUT]
		var extended: Array = []
		for combination: Array in combinations:
			for pick: int in picks:
				extended.append(combination + [pick])
		combinations = extended
	return combinations


## GameState の会話の進行の検証 (サンプルシナリオ)。自動送り・バックログの間の停止・選択・時間切れ・エンディングの記録・
## やり直した時の初期化
func _check_game_state_conversation() -> void:
	var game_state: Node = GAME_STATE_SCRIPT.new()
	game_state.scenario_paths = SAMPLE_SCENARIO_PATHS
	game_state.apply(GAME_STATE_SCRIPT.Command.CONFIRM)
	_check(
		game_state.position == 0 and game_state.backlog.size() == 1,
		"進行: 始めると最初のメッセージで止まり、バックログに積まれる"
	)
	game_state.advance(ConversationScript.MIN_MESSAGE_SECONDS / 2.0)
	_check(game_state.backlog.size() == 1, "進行: 表示時間が過ぎるまでは次へ進まない")
	game_state.apply(GAME_STATE_SCRIPT.Command.BACKLOG)
	game_state.advance(60.0)
	_check(game_state.backlog.size() == 1, "進行: バックログを開いている間は会話が止まる")
	game_state.apply(GAME_STATE_SCRIPT.Command.BACKLOG)
	_fast_forward(game_state, _is_choosing.bind(game_state))
	_check(game_state.backlog.size() == 4, "進行: 選択肢までのメッセージが自動で流れてバックログに積まれる")
	_check(not game_state.choose(2), "進行: 無い番号の選択肢は選べない")
	_check(
		not game_state.choose(-1) and _is_choosing(game_state) and game_state.affection.is_empty(),
		"進行: 負の番号では選べず、時間切れの扱いにもならない"
	)
	_check(game_state.choose(0), "進行: 選択肢を選べる")
	_check(game_state.affection == {"hina": 1}, "進行: 選んだ選択肢の好感度が足される")
	_check(
		game_state.backlog[4]["text"] == game_state.lines[4]["choices"][0]["text"],
		"進行: 選んだ選択肢がバックログに積まれる"
	)
	_fast_forward(game_state, func() -> bool: return false)
	_check(
		(
			game_state.screen == GAME_STATE_SCRIPT.Screen.ENDING
			and game_state.current_line().get("ending") == "sample_good"
		),
		"進行: 好感度を満たすと good のエンディングに着く"
	)
	game_state.apply(GAME_STATE_SCRIPT.Command.CONFIRM)
	game_state.apply(GAME_STATE_SCRIPT.Command.CONFIRM)
	_check(
		game_state.affection.is_empty() and game_state.backlog.size() == 1,
		"進行: やり直すと好感度とバックログが初期値に戻る"
	)
	game_state.advance(60.0)
	_check(
		(
			game_state.screen == GAME_STATE_SCRIPT.Screen.ENDING
			and game_state.current_line().get("ending") == "sample_bad"
		),
		"進行: 操作しないと時間切れを経て bad のエンディングに着く"
	)
	_check(
		game_state.affection == {"hina": ConversationScript.TIMEOUT_AFFECTION},
		"進行: 時間切れで好感度が下がる"
	)
	_check(
		game_state.backlog.any(
			func(entry: Dictionary) -> bool: return entry["text"] == ConversationScript.TIMEOUT_TEXT
		),
		"進行: 時間切れの「……」がバックログに積まれる"
	)
	_check(
		game_state.reached_endings == ["sample_good", "sample_bad"],
		"進行: 到達したエンディングが到達した順に記録される"
	)
	game_state.free()


## 背景と立ち絵の検証。バックログからの決め方 (STAGE_CASES)、本編とサンプルの background・expression・話者に素材が
## あること、素材の無い値を見つけること (INVALID_STAGE_LINES)、全素材のファイルがあること、本編が背景で始まり
## 全背景を使うこと
func _check_stage() -> void:
	for case: Array in STAGE_CASES:
		var backlog: Array = case[0]
		_check(StageScript.shown_background(backlog) == case[1], "背景: %s" % case[3])
		var expected_portrait: Dictionary = {} if case[2] < 0 else backlog[case[2]]
		_check(StageScript.shown_portrait(backlog) == expected_portrait, "立ち絵: %s" % case[3])
	var main_lines: Array = ScenarioScript.load_lines(GAME_STATE_SCRIPT.MAIN_SCENARIO_PATHS)
	for lines: Array in [main_lines, ScenarioScript.load_lines(SAMPLE_SCENARIO_PATHS)]:
		var errors: Array[String] = StageScript.errors(lines)
		_check(errors.is_empty(), "素材: シナリオの背景・表情・話者に素材がある %s" % [errors])
	for case: Array in INVALID_STAGE_LINES:
		_check(not StageScript.errors([case[0]]).is_empty(), "素材: %sを見つける" % case[1])
	var paths: Array[String] = [StageScript.TITLE_PATH, StageScript.SPEED_LINES_PATH]
	for background: String in StageScript.BACKGROUNDS:
		paths.append(StageScript.background_path(background))
	for speaker: String in StageScript.HEROINES:
		for expression: String in StageScript.EXPRESSIONS:
			paths.append(
				StageScript.portrait_path(
					{ScenarioScript.SPEAKER: speaker, ScenarioScript.EXPRESSION: expression}
				)
			)
	for path: String in paths:
		_check(ResourceLoader.exists(path), "素材: %s がある" % path)
	_check(
		main_lines[0].has(ScenarioScript.BACKGROUND), "素材: 本編の最初の行が背景を指定している"
	)
	for background: String in StageScript.BACKGROUNDS:
		_check(
			main_lines.any(
				func(line: Dictionary) -> bool:
					return line.get(ScenarioScript.BACKGROUND, "") == background
			),
			"素材: 背景 %s を本編で使っている" % background
		)


## 全シーンがロードできる
func _check_scenes() -> void:
	for path: String in SCENES:
		var scene: PackedScene = load(path)
		_check(scene != null and scene.can_instantiate(), "シーンのロード: %s" % path)


## assets/ の全ファイルが CREDITS.md に記録されている
func _check_credits() -> void:
	var credits_file: FileAccess = FileAccess.open(CREDITS_PATH, FileAccess.READ)
	_check(credits_file != null, "CREDITS.md が開ける: %s" % CREDITS_PATH)
	if credits_file == null:
		return
	var credits: String = credits_file.get_as_text()
	credits_file.close()
	for asset: String in _asset_files(ASSETS_DIR):
		var relative: String = asset.trim_prefix(ASSETS_DIR + "/")
		_check(credits.contains("`%s`" % relative), "素材の記録: %s が CREDITS.md にある" % relative)


## dir 配下の素材ファイル (記録の対象外を除く) を再帰的に集める
func _asset_files(dir_path: String) -> Array[String]:
	var files: Array[String] = []
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return files
	dir.list_dir_begin()
	var name: String = dir.get_next()
	while name != "":
		var path: String = dir_path + "/" + name
		if dir.current_is_dir():
			files.append_array(_asset_files(path))
		elif not _is_credits_exempt(name):
			files.append(path)
		name = dir.get_next()
	dir.list_dir_end()
	return files


## 素材として記録しないファイルか
func _is_credits_exempt(name: String) -> bool:
	for suffix: String in CREDITS_EXEMPT_SUFFIXES:
		if name.ends_with(suffix):
			return true
	return false
