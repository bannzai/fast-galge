extends RefCounted
## シナリオの保存形式 (scenario/*.json) の読み込みと検証。シナリオは行 (Dictionary) の配列で、行は次のどれか 1 種類。
## - メッセージ: {"text": 本文, "speaker": 話者 (省くと地の文), "expression": 表情 (省ける)}
## - 選択肢: {"choices": [{"text": 本文, "affection": {ヒロインの ID: 好感度の変化}, "goto": 分岐先のラベル}],
##   "timeout": 時間切れの分岐先のラベル, "speaker": 選ぶ人 (バックログに残す話者。省ける)}
## - ラベル: {"label": 名前}
## - 移動: {"goto": ラベル, "if_affection": {ヒロインの ID: 必要な好感度}} (if_affection は省ける。あれば満たす時だけ移る)
## - エンディング: {"ending": ID, "name": エンディング名, "summary": 一言}
## 選択肢の goto と timeout は省くと次の行へ進む。時間切れで好感度が下がる相手は、その選択肢の affection に名前がある
## ヒロイン全員。移動先は必ず後ろの行にする (会話が必ずエンディングで終わるようにするため)。
## JSON にした理由は documents/adr/0003-scenario-format-json.md

## 行と選択肢のキー
const TEXT: String = "text"
const SPEAKER: String = "speaker"
const EXPRESSION: String = "expression"
const CHOICES: String = "choices"
const AFFECTION: String = "affection"
const GOTO: String = "goto"
const TIMEOUT: String = "timeout"
const LABEL: String = "label"
const IF_AFFECTION: String = "if_affection"
const ENDING: String = "ending"
const NAME: String = "name"
const SUMMARY: String = "summary"
## 行の種類を決めるキーと、その種類の行が持てるキー
const LINE_KEYS: Dictionary = {
	TEXT: [TEXT, SPEAKER, EXPRESSION],
	CHOICES: [CHOICES, TIMEOUT, SPEAKER],
	LABEL: [LABEL],
	GOTO: [GOTO, IF_AFFECTION],
	ENDING: [ENDING, NAME, SUMMARY],
}
## 選択肢が持てるキー
const OPTION_KEYS: Array = [TEXT, AFFECTION, GOTO]
## 1 つの選択肢の行に置ける選択肢の数 (documents/PROJECT.md「基本ルール」の 2〜3 択。画面のボタンと入力も 3 つまで)
const MIN_OPTIONS: int = 2
const MAX_OPTIONS: int = 3


## paths の JSON を順に読み、行を 1 つの配列につなげて返す (ラベルは全ファイルで共通)。
## 読めないファイル・行の配列でないファイルは ERROR を出して飛ばす
static func load_lines(paths: Array[String]) -> Array:
	var lines: Array = []
	for path: String in paths:
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Array:
			lines.append_array(parsed)
		else:
			push_error("シナリオが行の配列ではない: %s" % path)
	return lines


## line の種類 (LINE_KEYS のキー)。どの種類でもない行・複数の種類に当たる行は ""
static func kind(line: Dictionary) -> String:
	var kinds: Array = LINE_KEYS.keys().filter(func(key: String) -> bool: return line.has(key))
	return kinds[0] if kinds.size() == 1 else ""


## label (空でない名前) のラベルの行の位置。無ければ -1
static func label_index(lines: Array, label: String) -> int:
	for index: int in range(lines.size()):
		if lines[index] is Dictionary and str(lines[index].get(LABEL, "")) == label:
			return index
	return -1


## lines の形式の誤りを、何番目の行かを付けた文で返す (空なら誤りなし)
static func validate(lines: Array) -> Array[String]:
	var errors: Array[String] = []
	for index: int in range(lines.size()):
		for error: String in _line_errors(lines, index):
			errors.append("%d 番目の行: %s" % [index + 1, error])
	if lines.is_empty() or not (lines.back() is Dictionary) or not lines.back().has(ENDING):
		errors.append("最後の行がエンディングではない")
	return errors


## lines の index 番目の行の形式の誤り
static func _line_errors(lines: Array, index: int) -> Array[String]:
	if not (lines[index] is Dictionary):
		return ["行が辞書ではない"]
	var line: Dictionary = lines[index]
	var line_kind: String = kind(line)
	if line_kind.is_empty():
		return ["行の種類が 1 つに決まらない: %s" % [line.keys()]]
	var errors: Array[String] = _unknown_key_errors(line, LINE_KEYS[line_kind])
	match line_kind:
		TEXT:
			errors.append_array(_text_errors(line, [TEXT], [SPEAKER, EXPRESSION]))
		CHOICES:
			errors.append_array(_text_errors(line, [], [SPEAKER]))
			errors.append_array(_choice_errors(lines, index))
		LABEL:
			errors.append_array(_text_errors(line, [LABEL], []))
			if label_index(lines, str(line[LABEL])) != index:
				errors.append("label が重複している: %s" % [line[LABEL]])
		GOTO:
			errors.append_array(_target_errors(lines, index, line[GOTO]))
			if not _is_affection(line.get(IF_AFFECTION, {})):
				errors.append("if_affection が {ヒロインの ID: 整数} ではない")
		ENDING:
			errors.append_array(_text_errors(line, [ENDING, NAME, SUMMARY], []))
	return errors


## lines の index 番目の選択肢の行の、選択肢と時間切れの分岐先の誤り
static func _choice_errors(lines: Array, index: int) -> Array[String]:
	var line: Dictionary = lines[index]
	var options: Variant = line[CHOICES]
	if not (options is Array) or options.size() < MIN_OPTIONS or options.size() > MAX_OPTIONS:
		return ["choices が %d〜%d 個の配列ではない" % [MIN_OPTIONS, MAX_OPTIONS]]
	var errors: Array[String] = []
	var heroines: Dictionary = {}
	for option: Variant in options:
		if not (option is Dictionary):
			errors.append("選択肢が辞書ではない")
			continue
		errors.append_array(_unknown_key_errors(option, OPTION_KEYS))
		errors.append_array(_text_errors(option, [TEXT], []))
		if option.has(GOTO):
			errors.append_array(_target_errors(lines, index, option[GOTO]))
		if _is_affection(option.get(AFFECTION, {})):
			heroines.merge(option.get(AFFECTION, {}))
		else:
			errors.append("選択肢の affection が {ヒロインの ID: 整数} ではない")
	if heroines.is_empty():
		errors.append("どの選択肢にも affection が無く、時間切れで好感度が下がる相手が決まらない")
	if line.has(TIMEOUT):
		errors.append_array(_target_errors(lines, index, line[TIMEOUT]))
	return errors


## values の required のキーが空でない文字列でない誤りと、optional のキーが (あるのに) 空でない文字列でない誤り
static func _text_errors(values: Dictionary, required: Array, optional: Array) -> Array[String]:
	var errors: Array[String] = []
	for key: String in required + optional:
		if (key in required or values.has(key)) and not _is_text(values.get(key)):
			errors.append("%s が空でない文字列ではない" % key)
	return errors


## values に allowed に無いキーがある誤り (キーの打ち間違いを見つける)
static func _unknown_key_errors(values: Dictionary, allowed: Array) -> Array[String]:
	var errors: Array[String] = []
	for key: Variant in values:
		if not (key in allowed):
			errors.append("知らないキー: %s" % [key])
	return errors


## lines の index 番目の行から label へ移る時の誤り (ラベルが無い・後ろの行にない)
static func _target_errors(lines: Array, index: int, label: Variant) -> Array[String]:
	if not _is_text(label):
		return ["移動先のラベルが空でない文字列ではない"]
	var target: int = label_index(lines, label)
	if target < 0:
		return ["移動先のラベルが無い: %s" % label]
	if target <= index:
		return ["移動先のラベルが後ろの行にない: %s" % label]
	return []


## value が空でない文字列か
static func _is_text(value: Variant) -> bool:
	return value is String and not value.is_empty()


## value が {ヒロインの ID (空でない文字列): 整数} の辞書か (JSON の数は float で読まれるため、小数部が無いことを見る)
static func _is_affection(value: Variant) -> bool:
	if not (value is Dictionary):
		return false
	for heroine: Variant in value:
		var amount: Variant = value[heroine]
		if not _is_text(heroine) or not (amount is float or amount is int) or amount != floorf(amount):
			return false
	return true
