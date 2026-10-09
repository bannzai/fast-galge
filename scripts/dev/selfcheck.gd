extends "res://scripts/dev/headless_check.gd"
## 画面の遷移表、会話エンジンの計算 (表示時間・時間切れ・好感度・分岐・章の区切り・所要時間)、シナリオの形式、本編 (5 つの
## エンディングへの到達・各ルートの所要時間・共通パートの分岐・章の区切りの数)、GameState の会話の進行 (章の区切りでの
## オートセーブと「つづきから」の再開を含む)、背景と立ち絵の決め方と素材、保存データの読み書きと壊れたデータの扱い、
## 全シーンのロード、全素材が
## assets/CREDITS.md に記録されていることの検証 (headless)。
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
## 保存データの autoload のスクリプト
const SAVE_DATA_SCRIPT := preload("res://scripts/save_data.gd")
## 保存・読み込みの検証で書き出す保存データ。プレイヤーの保存データ (user://) を書き換えないよう tmp/ に置く
const SAVE_TEST_PATH: String = "res://tmp/selfcheck-save.json"
## 保存データの解釈の検証で、壊れたデータとして扱う文字列
const BROKEN_SAVE_TEXTS: Array[String] = [
	"", "{", "not json", "[1, 2]", "42", '{"version": 2}', '{"version": "1"}', "{}"
]
## ファイルの読み書きの検証で、壊れた保存データとして書き込む中身 (途中で切れた JSON)
const BROKEN_SAVE_FILE_TEXT: String = '{"version": 1, "chapter": "route_'
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
	[
		GAME_STATE_SCRIPT.Screen.TITLE,
		GAME_STATE_SCRIPT.Command.CONTINUE,
		GAME_STATE_SCRIPT.Screen.PLAYING,
		"タイトルのつづきからで会話中になる",
	],
	[
		GAME_STATE_SCRIPT.Screen.PLAYING,
		GAME_STATE_SCRIPT.Command.CONTINUE,
		GAME_STATE_SCRIPT.Screen.PLAYING,
		"会話中のつづきからでは画面が変わらない",
	],
	[
		GAME_STATE_SCRIPT.Screen.ENDING,
		GAME_STATE_SCRIPT.Command.CONTINUE,
		GAME_STATE_SCRIPT.Screen.ENDING,
		"エンディングのつづきからでは画面が変わらない",
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
	[[{"chapter": ""}, ENDING_LINE], "章の区切りの ID が空"],
	[[{"chapter": "c", "text": "a"}, ENDING_LINE], "章の区切りに本文がある"],
	[[{"chapter": "c"}, {"chapter": "c"}, ENDING_LINE], "章の区切りの ID が重複している"],
]
## 章の区切りの検証に使うシナリオ。選択肢の後に章の区切りがあり、章の区切りの次のメッセージから再開できる
const CHAPTER_LINES: Array = [
	{"text": "ああああああああああ"},
	{
		"choices": [
			{"text": "up", "affection": {"a": 1}},
			{"text": "down", "affection": {"a": -1}},
		],
	},
	{"label": "merge"},
	{"chapter": "second"},
	{"text": "ああああああああああ"},
	{"ending": "end", "name": "end", "summary": "end"},
]
## 本編のルートに入る周で通る章の区切りの数の下限 (ルートの始まり = 共通パートの終わりと、ルートの中間)
const ROUTE_MIN_CHAPTERS: int = 2
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
	_check_chapter()
	_check_scenario_format()
	_check_main_scenario()
	_check_game_state_conversation()
	_check_stage()
	_check_save_parse()
	_check_save_file()
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


## 章の区切りの計算の検証 (CHAPTER_LINES)。止まる行として扱い、所要時間に数えず、ID から位置を引ける
func _check_chapter() -> void:
	_check(ScenarioScript.validate(CHAPTER_LINES).is_empty(), "章の区切りの検証用のシナリオは形式が正しい")
	_check(ScenarioScript.kind(CHAPTER_LINES[3]) == ScenarioScript.CHAPTER, "章の区切り: 行の種類が chapter")
	_check(ScenarioScript.chapter_index(CHAPTER_LINES, "second") == 3, "章の区切り: ID から位置を引ける")
	_check(ScenarioScript.chapter_index(CHAPTER_LINES, "none") == -1, "章の区切り: 無い ID は -1")
	_check(ScenarioScript.chapter_index(CHAPTER_LINES, "merge") == -1, "章の区切り: ラベルの名前とは別")
	_check(ConversationScript.next_stop(CHAPTER_LINES, 2, {}) == 3, "章の区切り: ラベルは飛ばして章の区切りで止まる")
	_check(
		is_equal_approx(ConversationScript.stop_seconds(CHAPTER_LINES[3]), 0.0),
		"章の区切り: 止まる時間は 0"
	)
	var result: Dictionary = ConversationScript.playthrough(
		CHAPTER_LINES, func(_choice: Dictionary) -> int: return 0
	)
	_check(
		is_equal_approx(result["seconds"], 2.8) and result["ending"].get("ending") == "end",
		"章の区切り: 所要時間に数えずエンディングに着く"
	)


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
	_check_route_chapters(lines)
	_check_route_split(ScenarioScript.load_lines([GAME_STATE_SCRIPT.MAIN_SCENARIO_PATHS[0]]))


## 本編の各ルート (ROUTE_LABELS) に章の区切りが ROUTE_MIN_CHAPTERS 箇所以上あること。ルートの範囲は、そのルートの
## ラベルから次のルート (または共通 bad) のラベルの前まで
func _check_route_chapters(lines: Array) -> void:
	var starts: Array[int] = []
	for heroine: String in ROUTE_LABELS:
		starts.append(ScenarioScript.label_index(lines, ROUTE_LABELS[heroine]))
	starts.append(ScenarioScript.label_index(lines, COMMON_BAD))
	for route_index: int in range(starts.size() - 1):
		var chapters: int = lines.slice(starts[route_index], starts[route_index + 1]).filter(
			func(line: Dictionary) -> bool: return line.has(ScenarioScript.CHAPTER)
		).size()
		_check(
			chapters >= ROUTE_MIN_CHAPTERS,
			(
				"本編: %s のルートに章の区切りが %d 箇所以上 (%d 箇所)"
				% [ROUTE_LABELS.keys()[route_index], ROUTE_MIN_CHAPTERS, chapters]
			)
		)


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


## GameState の会話の進行の検証 (サンプルシナリオ)。自動送り・バックログの間の停止・選択・時間切れ・章の区切りでの
## オートセーブ・エンディングの記録・やり直した時の初期化・「つづきから」の再開。保存先は tmp/ の検証用のファイル
func _check_game_state_conversation() -> void:
	var path: String = ProjectSettings.globalize_path(SAVE_TEST_PATH)
	_remove_save_files(path)
	var saver: Node = SAVE_DATA_SCRIPT.new()
	saver.load_from(path)
	var game_state: Node = GAME_STATE_SCRIPT.new()
	game_state.save_data = saver
	game_state.scenario_paths = SAMPLE_SCENARIO_PATHS
	_check(
		not game_state.can_continue() and not game_state.apply(GAME_STATE_SCRIPT.Command.CONTINUE),
		"つづきから: 保存が無ければ再開できず、タイトルのまま"
	)
	_check(game_state.screen == GAME_STATE_SCRIPT.Screen.TITLE, "つづきから: 保存が無ければ画面はタイトルのまま")
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
	_check(not saver.has_progress(), "オートセーブ: 章の区切りを通るまでは保存されない")
	var chapter: int = ScenarioScript.chapter_index(game_state.lines, "sample_after")
	_fast_forward(game_state, func() -> bool: return game_state.position > chapter)
	_check(
		saver.chapter == "sample_after" and saver.affection == {"hina": 1},
		"オートセーブ: 章の区切りを通ると章の ID と好感度が保存される"
	)
	_check(
		game_state.position == chapter + 1 and game_state.backlog.back() == game_state.lines[chapter + 1],
		"オートセーブ: 章の区切りの行では止まらず次のメッセージに進む"
	)
	_check(FileAccess.file_exists(path), "オートセーブ: 保存データのファイルが書かれる")
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
		saver.reached_endings == ["sample_good", "sample_bad"] and saver.is_cleared(),
		"進行: 到達したエンディングが到達した順に記録され、クリア済みになる"
	)
	var timed_out: Dictionary = {"hina": ConversationScript.TIMEOUT_AFFECTION}
	_check(
		saver.chapter == "sample_after" and saver.affection == timed_out,
		"オートセーブ: やり直して章の区切りを通ると上書きされる"
	)
	game_state.apply(GAME_STATE_SCRIPT.Command.CONFIRM)
	_check(game_state.can_continue(), "つづきから: 章の区切りの保存があれば再開できる")
	var loader: Node = SAVE_DATA_SCRIPT.new()
	loader.load_from(path)
	game_state.save_data = loader
	_check(game_state.apply(GAME_STATE_SCRIPT.Command.CONTINUE), "つづきから: 読み込み直した保存データから再開できる")
	_check(
		game_state.is_playing() and game_state.position == chapter + 1 and game_state.backlog.size() == 1,
		"つづきから: 保存した章の区切りの次のメッセージから始まる"
	)
	_check(game_state.affection == timed_out, "つづきから: 保存した好感度で再開する")
	_check(loader.chapter == "sample_after", "つづきから: 再開しても章の区切りの保存は消えない")
	_fast_forward(game_state, func() -> bool: return false)
	_check(
		game_state.current_line().get("ending") == "sample_bad",
		"つづきから: 再開した好感度でエンディングに着く"
	)
	game_state.apply(GAME_STATE_SCRIPT.Command.CONFIRM)
	loader.chapter = "unknown_chapter"
	_check(game_state.apply(GAME_STATE_SCRIPT.Command.CONTINUE), "つづきから: 保存した章がシナリオに無くても会話中になる")
	_check(
		game_state.position == 0 and game_state.affection.is_empty(),
		"つづきから: 保存した章がシナリオに無ければ最初から始まる"
	)
	game_state.free()
	saver.free()
	loader.free()
	_remove_save_files(path)


## 保存データの文字列の解釈。壊れたデータ (JSON でない・形が違う・版が違う) と、一部の値だけがおかしいデータ
func _check_save_parse() -> void:
	for broken_text: String in BROKEN_SAVE_TEXTS:
		var broken: Dictionary = SAVE_DATA_SCRIPT.parse(broken_text)
		_check(broken["broken"], "保存データ: %s は壊れたデータとして扱う" % broken_text)
		_check(
			(
				broken["chapter"] == ""
				and broken["affection"].is_empty()
				and broken["reached_endings"].is_empty()
			),
			"保存データ: 壊れたデータ %s は既定値にする" % broken_text
		)
	var empty: Dictionary = SAVE_DATA_SCRIPT.parse('{"version": 1}')
	_check(
		not empty["broken"] and empty["chapter"] == "" and empty["reached_endings"].is_empty(),
		"保存データ: 版だけのデータは壊れていない既定値"
	)
	var endings: Array[String] = ["hina_good"]
	var text: String = SAVE_DATA_SCRIPT.serialize("route_hina_autumn", {"hina": 2}, endings)
	var loaded: Dictionary = SAVE_DATA_SCRIPT.parse(text)
	_check(not loaded["broken"], "保存データ: 書き出したデータを読める")
	_check(loaded["chapter"] == "route_hina_autumn", "保存データ: 章の区切りを読み戻せる")
	_check(loaded["affection"] == {"hina": 2}, "保存データ: 好感度を整数で読み戻せる")
	_check(loaded["reached_endings"] == endings, "保存データ: 到達したエンディングを読み戻せる")
	var rewritten: String = SAVE_DATA_SCRIPT.serialize(
		loaded["chapter"], loaded["affection"], loaded["reached_endings"]
	)
	_check(rewritten == text, "保存データ: 読み戻した値から同じ文字列を書き出す")
	var partial: Dictionary = SAVE_DATA_SCRIPT.parse(
		JSON.stringify(
			{
				"version": 1,
				"chapter": 3,
				"affection": {"hina": 1.5},
				"reached_endings": ["hina_bad", 1, "hina_bad", "", null],
			}
		)
	)
	_check(not partial["broken"], "保存データ: 一部の値だけがおかしいデータは壊れたデータとしない")
	_check(partial["chapter"] == "", "保存データ: 文字列でない章の区切りは無し")
	_check(partial["affection"].is_empty(), "保存データ: 整数でない好感度は空")
	_check(
		partial["reached_endings"] == ["hina_bad"],
		"保存データ: 文字列でない・空・重複したエンディングは捨てる"
	)


## ファイルへの保存と読み込み、壊れたファイルの退避。tree に入れない SaveData のインスタンスで行う
func _check_save_file() -> void:
	var path: String = ProjectSettings.globalize_path(SAVE_TEST_PATH)
	var broken_path: String = path + SAVE_DATA_SCRIPT.BROKEN_SUFFIX
	_remove_save_files(path)
	var saver: Node = SAVE_DATA_SCRIPT.new()
	saver.load_from(path)
	_check(not saver.loaded_broken, "保存: 保存データが無ければ壊れていない扱いで始める")
	_check(not saver.has_progress() and not saver.is_cleared(), "保存: 保存データが無ければ途中の保存もクリアも無い")
	saver.record_chapter("route_hina_spring", {"hina": 1})
	_check(FileAccess.file_exists(path), "保存: 章の区切りを記録すると保存データを書き出す")
	saver.record_chapter("route_hina_autumn", {"hina": 2})
	saver.record_ending("hina_good")
	saver.record_ending("hina_good")
	var endings: Array[String] = ["hina_good"]
	_check(saver.reached_endings == endings, "保存: 同じエンディングを 2 度記録しても 1 つ")
	var written: String = FileAccess.get_file_as_string(path)
	_check(saver.save() == OK, "保存: もう一度保存できる")
	_check(FileAccess.get_file_as_string(path) == written, "保存: 同じ内容なら同じファイルになる")
	saver.free()

	var loader: Node = SAVE_DATA_SCRIPT.new()
	loader.load_from(path)
	_check(not loader.loaded_broken, "読み込み: 書き出した保存データは壊れていない")
	_check(loader.chapter == "route_hina_autumn", "読み込み: 最後に記録した章の区切りを読み戻す")
	_check(loader.affection == {"hina": 2}, "読み込み: 好感度を読み戻す")
	_check(loader.reached_endings == endings and loader.is_cleared(), "読み込み: 到達したエンディングを読み戻す")

	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(BROKEN_SAVE_FILE_TEXT)
	file.close()
	loader.load_from(path)
	_check(loader.loaded_broken, "壊れた保存データ: 読めないファイルを壊れたと判定する")
	_check(
		not loader.has_progress() and loader.affection.is_empty() and not loader.is_cleared(),
		"壊れた保存データ: 既定値で始める"
	)
	_check(
		FileAccess.file_exists(path) and not FileAccess.file_exists(broken_path),
		"壊れた保存データ: 読み込みでは元のファイルを動かさない"
	)
	loader.load_from(path)
	_check(loader.loaded_broken, "壊れた保存データ: 読み込み直しても壊れた判定のまま (読み込みは冪等)")
	_check(loader.save() == OK and not loader.loaded_broken, "壊れた保存データ: 保存し直すと知らせを消す")
	_check(
		FileAccess.get_file_as_string(broken_path) == BROKEN_SAVE_FILE_TEXT,
		"壊れた保存データ: 保存する時に元のファイルを退避し、中身をそのまま残す"
	)
	loader.load_from(path)
	_check(
		not loader.loaded_broken and not loader.has_progress() and not loader.is_cleared(),
		"壊れた保存データ: 保存し直した後の読み込みは既定値で壊れていない"
	)

	var writing_path: String = path + SAVE_DATA_SCRIPT.WRITING_SUFFIX
	_remove_file(path)
	var writing: FileAccess = FileAccess.open(writing_path, FileAccess.WRITE)
	writing.store_string(SAVE_DATA_SCRIPT.serialize("route_hina_spring", {"hina": 1}, endings))
	writing.close()
	loader.load_from(path)
	_check(
		loader.chapter == "route_hina_spring" and loader.reached_endings == endings,
		"書きかけの保存データ: 保存先が無く書き終えたファイルだけが残っていれば、それを読む"
	)
	_check(
		not FileAccess.file_exists(path) and FileAccess.file_exists(writing_path),
		"書きかけの保存データ: 読み込みでは書きかけを動かさない"
	)
	_check(
		loader.save() == OK and FileAccess.file_exists(path) and not FileAccess.file_exists(writing_path),
		"書きかけの保存データ: 次の保存で保存先へ書き直す"
	)
	_remove_file(path)
	writing = FileAccess.open(writing_path, FileAccess.WRITE)
	writing.store_string(BROKEN_SAVE_FILE_TEXT)
	writing.close()
	loader.load_from(path)
	_check(
		not loader.loaded_broken and not loader.has_progress() and FileAccess.file_exists(writing_path),
		"書きかけの保存データ: 壊れた書きかけは動かさず既定値で始める"
	)
	loader.free()
	_remove_save_files(path)


## path の保存データと、退避したファイル・書き出し途中のファイルを消す (前の実行が途中で止まっていても、保存データが
## 無い状態から検証を始めるため)
func _remove_save_files(path: String) -> void:
	_remove_file(path)
	_remove_file(path + SAVE_DATA_SCRIPT.BROKEN_SUFFIX)
	_remove_file(path + SAVE_DATA_SCRIPT.WRITING_SUFFIX)


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
		_check_chapter_backgrounds(lines)
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
	var used: Array = main_lines.map(
		func(line: Dictionary) -> String: return line.get(ScenarioScript.BACKGROUND, "")
	)
	for background: String in StageScript.BACKGROUNDS:
		_check(background in used, "素材: 背景 %s を本編で使っている" % background)


## lines (シナリオの行) の章の区切りごとに、その後の最初のメッセージの行が背景を指定していること。「つづきから」で
## 再開した直後のバックログはその 1 行だけで、背景が無いと背景が決まらないため
func _check_chapter_backgrounds(lines: Array) -> void:
	for index: int in range(lines.size()):
		if not lines[index].has(ScenarioScript.CHAPTER):
			continue
		var message: int = index + 1
		while message < lines.size() and not lines[message].has(ScenarioScript.TEXT):
			message += 1
		_check(
			message < lines.size() and lines[message].has(ScenarioScript.BACKGROUND),
			"素材: 章の区切り %s の後の最初のメッセージが背景を指定している" % lines[index][ScenarioScript.CHAPTER]
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
