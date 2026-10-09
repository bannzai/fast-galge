extends RefCounted
## 背景と立ち絵 (scripts/stage.gd) の検証。scripts/dev/selfcheck.gd が呼び、失敗の説明を受け取って記録する
## (selfcheck.gd が gdlint の 1 ファイルの行数の上限を超えないよう分けた)。

## シナリオの保存形式の読み込みとキー
const ScenarioScript := preload("res://scripts/scenario.gd")
## 背景と立ち絵の素材と、いま出すものの決め方
const StageScript := preload("res://scripts/stage.gd")
## 会話のルールの計算 (次に表示が止まる行)
const ConversationScript := preload("res://scripts/conversation.gd")
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


## 背景と立ち絵の検証の失敗の説明 (空なら全部通った)。バックログからの決め方 (STAGE_CASES)、本編 (main_paths) と
## サンプル (sample_paths) の background・expression・話者に素材があり、章の区切りの後の最初のメッセージが背景を
## 指定していること、素材の無い値を見つけること (INVALID_STAGE_LINES)、全素材のファイルがあること、本編が背景で始まり
## 全背景を使うこと
static func failures(main_paths: Array[String], sample_paths: Array[String]) -> Array[String]:
	var found: Array[String] = []
	for case: Array in STAGE_CASES:
		var backlog: Array = case[0]
		if StageScript.shown_background(backlog) != case[1]:
			found.append("背景: %s" % case[3])
		var expected_portrait: Dictionary = {} if case[2] < 0 else backlog[case[2]]
		if StageScript.shown_portrait(backlog) != expected_portrait:
			found.append("立ち絵: %s" % case[3])
	var main_lines: Array = ScenarioScript.load_lines(main_paths)
	for lines: Array in [main_lines, ScenarioScript.load_lines(sample_paths)]:
		var errors: Array[String] = StageScript.errors(lines)
		if not errors.is_empty():
			found.append("素材: シナリオの背景・表情・話者に素材がある %s" % [errors])
		found.append_array(_chapter_background_failures(lines))
	for case: Array in INVALID_STAGE_LINES:
		if StageScript.errors([case[0]]).is_empty():
			found.append("素材: %sを見つける" % case[1])
	for path: String in _asset_paths():
		if not ResourceLoader.exists(path):
			found.append("素材: %s がある" % path)
	if not main_lines[0].has(ScenarioScript.BACKGROUND):
		found.append("素材: 本編の最初の行が背景を指定している")
	var used: Array = main_lines.map(
		func(line: Dictionary) -> String: return line.get(ScenarioScript.BACKGROUND, "")
	)
	for background: String in StageScript.BACKGROUNDS:
		if not (background in used):
			found.append("素材: 背景 %s を本編で使っている" % background)
	return found


## 背景と立ち絵の全素材のパス (タイトルの一枚絵・流線・全背景・全ヒロインの全表情)
static func _asset_paths() -> Array[String]:
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
	return paths


## lines (シナリオの行) の章の区切りのうち、そこから再開して最初に表示が止まる行が、背景を指定したメッセージの行で
## ないものの失敗の説明。「つづきから」で再開した直後のバックログはその 1 行だけで、背景が無いと背景が決まらないため
## (選択肢・エンディングの行は背景を持てないので、それで止まるのも失敗にする)
static func _chapter_background_failures(lines: Array) -> Array[String]:
	var found: Array[String] = []
	for index: int in range(lines.size()):
		if not lines[index].has(ScenarioScript.CHAPTER):
			continue
		var stop: int = ConversationScript.next_stop(lines, index + 1, {})
		if stop >= lines.size() or not lines[stop].has(ScenarioScript.BACKGROUND):
			found.append(
				(
					"素材: 章の区切り %s の後の最初のメッセージが背景を指定している"
					% lines[index][ScenarioScript.CHAPTER]
				)
			)
	return found
