extends "res://scripts/dev/headless_check.gd"
## 画面の遷移表、会話エンジンの計算 (表示時間・時間切れ・好感度・分岐・所要時間)、シナリオの形式、GameState の会話の進行と
## 結果の記録、結果の文面と X の投稿画面の URL の形、全シーンのロード、全素材が assets/CREDITS.md に記録されていることの
## 検証 (headless)。
## 実行方法は AGENTS.md を参照。release ビルドで assert が消えるため、明示的な判定と exit code で結果を返す。

## 起動検証 (main_scene の --quit) ではロードされない遷移先も含めた全シーン
const SCENES: Array[String] = [
	"res://scenes/main.tscn",
	"res://scenes/result_card.tscn",
]
## 画面と遷移表を持つ autoload のスクリプト
const GAME_STATE_SCRIPT := preload("res://scripts/game_state.gd")
## 結果の文面と URL の組み立て
const ResultScript := preload("res://scripts/result.gd")
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
## 本編 (共通パート + 1 人目のヒロインのルート) の所要時間の範囲 (秒)。共通パート 1 分 + ルート 5 分前後
## (documents/PROJECT.md「登場人物とシナリオの規模」) に対し、4〜7 分に収める
const MAIN_MIN_SECONDS: float = 240.0
const MAIN_MAX_SECONDS: float = 420.0
## 本編に置く選択肢の数の範囲 (共通パートと 1 人目のヒロインのルートで 3〜5 箇所)
const MAIN_MIN_CHOICES: int = 3
const MAIN_MAX_CHOICES: int = 5
## 本編の good / bad のエンディングの ID
const GOOD_ENDING: String = "hina_good"
const BAD_ENDING: String = "hina_bad"
## 所要時間の表記の検証 (秒・期待する表記)。秒は切り捨て
const FORMAT_SECONDS_CASES: Array[Array] = [
	[0.0, "0分00秒"],
	[59.9, "0分59秒"],
	[302.9, "5分02秒"],
	[3600.0, "60分00秒"],
]
## X の文字数の数え方の検証 (文・期待する文字数)。全角は 2、ASCII は 1、URL は長さによらず 23、改行と空白は 1
const WEIGHTED_LENGTH_CASES: Array[Array] = [
	["abc", 3],
	["あ", 2],
	["https://bannzai.github.io/fast-galge/", 23],
	["あ https://x.com/intent/post\nabc", 2 + 1 + 23 + 1 + 3],
]
## 結果の文面の検証に使う結果 (所要時間 302.9 秒・選択肢 5・時間切れ 0)
const SAMPLE_RESULT: Dictionary = {
	ResultScript.ENDING_NAME: "ふたりの速度",
	ResultScript.SECONDS: 302.9,
	ResultScript.CHOICES: 5,
	ResultScript.TIMEOUTS: 0,
}
## 結果の画像 (scenes/result_card.tscn) のエンディング名の 1 行に収まる文字数の上限 (幅 1080 px・72 px の全角 15 文字)
const MAX_ENDING_NAME_LENGTH: int = 14
## 文面の文字数の上限の検証で、どのエンディングでも超えないことを確かめる時に入れる最大の値
## (本編の所要時間の上限と選択肢の数の上限)
const LONGEST_RESULT_VALUES: Dictionary = {
	ResultScript.SECONDS: MAIN_MAX_SECONDS,
	ResultScript.CHOICES: MAIN_MAX_CHOICES,
	ResultScript.TIMEOUTS: MAIN_MAX_CHOICES,
}


## 全検証を実行し、1 件でも失敗していれば exit code 1、すべて通れば `selfcheck OK` を出して exit code 0 で終わる
func _initialize() -> void:
	_check_transitions()
	_check_message_seconds()
	_check_branch()
	_check_scenario_format()
	_check_main_scenario()
	_check_game_state_conversation()
	_check_result_text()
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


## 本編の検証。好感度を上げる選択で good、下げる選択・時間切れで bad に着き、どの進め方でも所要時間が範囲に収まり、
## 選択肢の数が範囲に収まること
func _check_main_scenario() -> void:
	var lines: Array = ScenarioScript.load_lines(GAME_STATE_SCRIPT.MAIN_SCENARIO_PATHS)
	var time_out: Callable = func(_choice: Dictionary) -> int: return ConversationScript.TIMEOUT
	var cases: Array[Array] = [
		[_option_by_affection.bind(1), GOOD_ENDING, "好感度を上げる選択"],
		[_option_by_affection.bind(-1), BAD_ENDING, "好感度を下げる選択"],
		[time_out, BAD_ENDING, "時間切れ"],
	]
	for case: Array in cases:
		var result: Dictionary = ConversationScript.playthrough(lines, case[0])
		_check(
			result["ending"].get("ending") == case[1],
			"本編: %s で %s に着く (好感度 %s)" % [case[2], case[1], result["affection"]]
		)
		_check(
			result["seconds"] >= MAIN_MIN_SECONDS and result["seconds"] <= MAIN_MAX_SECONDS,
			(
				"本編: %s の所要時間が %.0f〜%.0f 秒に収まる (%.1f 秒)"
				% [case[2], MAIN_MIN_SECONDS, MAIN_MAX_SECONDS, result["seconds"]]
			)
		)
	var choices: int = lines.filter(
		func(line: Dictionary) -> bool: return line.has(ScenarioScript.CHOICES)
	).size()
	_check(
		choices >= MAIN_MIN_CHOICES and choices <= MAIN_MAX_CHOICES,
		"本編: 選択肢が %d〜%d 箇所 (%d 箇所)" % [MAIN_MIN_CHOICES, MAIN_MAX_CHOICES, choices]
	)
	_check_main_progress(ConversationScript.playthrough(lines, time_out))


## 本編を GameState で操作せずに最後まで進めた時の所要時間・好感度・エンディングが、expected (同じ進め方の
## playthrough の結果) と一致すること。所要時間の見積もりが実際の会話の進み方とずれていないことを確かめる
func _check_main_progress(expected: Dictionary) -> void:
	var game_state: Node = GAME_STATE_SCRIPT.new()
	game_state.apply(GAME_STATE_SCRIPT.Command.CONFIRM)
	var stepped: float = 0.0
	while game_state.is_playing():
		game_state.advance(FAST_FORWARD_STEP)
		stepped += FAST_FORWARD_STEP
	_check(
		absf(stepped - expected["seconds"]) <= FAST_FORWARD_STEP + 0.001,
		(
			"本編: GameState で進めた所要時間が見積もりと一致する (%.2f 秒 / 見積もり %.2f 秒)"
			% [stepped, expected["seconds"]]
		)
	)
	_check(game_state.affection == expected["affection"], "本編: GameState で進めた好感度が見積もりと一致する")
	_check(
		game_state.current_line() == expected["ending"],
		"本編: GameState で進めたエンディングが見積もりと一致する"
	)
	_check(
		is_equal_approx(game_state.play_seconds, stepped),
		"本編: 結果の所要時間が会話中に進めた時間と一致する (%.2f 秒)" % game_state.play_seconds
	)
	game_state.free()


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
		game_state.choice_count == 1 and game_state.timeout_count == 0,
		"結果: 制限時間内に選ぶと選んだ選択肢の数が増え、時間切れの回数は増えない"
	)
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
	var result: Dictionary = game_state.result()
	_check(
		(
			result[ResultScript.ENDING_NAME] == game_state.current_line()["name"]
			and result[ResultScript.CHOICES] == 1
			and result[ResultScript.TIMEOUTS] == 0
			and result[ResultScript.SECONDS] > 0.0
		),
		"結果: エンディングに着くとエンディング名・所要時間・選んだ選択肢の数・時間切れの回数が揃う (%s)" % result
	)
	game_state.apply(GAME_STATE_SCRIPT.Command.CONFIRM)
	game_state.apply(GAME_STATE_SCRIPT.Command.CONFIRM)
	_check(
		game_state.affection.is_empty() and game_state.backlog.size() == 1,
		"進行: やり直すと好感度とバックログが初期値に戻る"
	)
	_check(
		(
			game_state.choice_count == 0
			and game_state.timeout_count == 0
			and is_zero_approx(game_state.play_seconds)
		),
		"結果: やり直すと所要時間・選んだ選択肢の数・時間切れの回数が初期値に戻る"
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
		game_state.choice_count == 0 and game_state.timeout_count == 1,
		"結果: 時間切れは時間切れの回数に数え、選んだ選択肢の数には数えない"
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


## 結果の文面と X の投稿画面の URL の検証。所要時間の表記、X の文字数の数え方、文面にエンディング名・結果・ハッシュタグ・
## URL が入ること、サンプルと本編のどのエンディングでも文字数の上限に収まること、URL の形 (投稿画面の URL で始まり、
## 符号化した文面を戻すと元の文面になり、符号化されていない空白・改行・# を含まない)
func _check_result_text() -> void:
	for case: Array in FORMAT_SECONDS_CASES:
		_check(ResultScript.format_seconds(case[0]) == case[1], "所要時間の表記: %.1f 秒は %s" % case)
	for case: Array in WEIGHTED_LENGTH_CASES:
		_check(
			ResultScript.weighted_length(case[0]) == case[1],
			"X の文字数: %s は %d" % [case[0].replace("\n", "\\n"), case[1]]
		)
	var text: String = ResultScript.share_text(SAMPLE_RESULT)
	for expected: String in [
		ResultScript.GAME_NAME,
		SAMPLE_RESULT[ResultScript.ENDING_NAME],
		"5分02秒",
		"選んだ選択肢 5",
		"時間切れ 0",
		ResultScript.HASHTAG,
		ResultScript.URL,
	]:
		_check(text.contains(expected), "文面: %s が入る" % expected)
	for ending: Dictionary in _ending_lines():
		_check(
			ending[ScenarioScript.NAME].length() <= MAX_ENDING_NAME_LENGTH,
			(
				"エンディング名の長さ: %s が結果の画像の 1 行に収まる %d 文字以内 (%d 文字)"
				% [ending[ScenarioScript.ENDING], MAX_ENDING_NAME_LENGTH, ending[ScenarioScript.NAME].length()]
			)
		)
		var longest: Dictionary = LONGEST_RESULT_VALUES.duplicate()
		longest[ResultScript.ENDING_NAME] = ending[ScenarioScript.NAME]
		var length: int = ResultScript.weighted_length(ResultScript.share_text(longest))
		_check(
			length <= ResultScript.MAX_WEIGHTED_LENGTH,
			(
				"文面の文字数: %s が上限 %d に収まる (%d)"
				% [ending[ScenarioScript.ENDING], ResultScript.MAX_WEIGHTED_LENGTH, length]
			)
		)
	var url: String = ResultScript.share_url(text)
	_check(url.begins_with(ResultScript.INTENT_URL_PREFIX), "URL: X の投稿画面の URL で始まる")
	var encoded: String = url.trim_prefix(ResultScript.INTENT_URL_PREFIX)
	_check(encoded.uri_decode() == text, "URL: 符号化した文面を戻すと元の文面になる")
	_check(
		not encoded.contains(" ") and not encoded.contains("\n") and not encoded.contains("#"),
		"URL: 符号化されていない空白・改行・# を含まない"
	)


## サンプルと本編のシナリオのエンディングの行
func _ending_lines() -> Array:
	var lines: Array = ScenarioScript.load_lines(SAMPLE_SCENARIO_PATHS)
	lines.append_array(ScenarioScript.load_lines(GAME_STATE_SCRIPT.MAIN_SCENARIO_PATHS))
	return lines.filter(func(line: Dictionary) -> bool: return line.has(ScenarioScript.ENDING))


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
