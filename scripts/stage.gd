extends RefCounted
## 会話中の画面に出す背景と立ち絵。シナリオのメッセージの行の background・speaker・expression (形式は
## scripts/scenario.gd) と素材のファイル (assets/) を対応させ、バックログからいま出す背景と立ち絵を決める。
## 見た目の方向は documents/DIRECTION.md「デザインの方向」。

## シナリオの保存形式のキー
const ScenarioScript := preload("res://scripts/scenario.gd")
## 立ち絵を持つ話者 (シナリオの speaker) と、そのヒロインの ID (シナリオの affection と素材のファイル名に使う)
const HEROINES: Dictionary = {"ヒナ": "hina", "ナギ": "nagi"}
## 立ち絵の表情 (シナリオの expression)。ヒロインごとにこの全部の素材がある
const EXPRESSIONS: Array[String] = ["normal", "smile", "surprised", "shy", "angry", "sad"]
## 背景 (シナリオの background)。シナリオの場面をこの数にまとめた
const BACKGROUNDS: Array[String] = [
	"room",
	"street",
	"classroom",
	"rooftop",
	"broadcast_room",
	"library",
	"stage",
	"track",
	"beach",
	"shrine",
	"inn_hallway",
	"avenue_night",
	"sakura_tree",
]
## 素材のパス (立ち絵はヒロインの ID と表情、背景は背景の ID を埋める)
const PORTRAIT_PATH: String = "res://assets/portraits/%s_%s.png"
const BACKGROUND_PATH: String = "res://assets/backgrounds/%s.jpg"
const TITLE_PATH: String = "res://assets/title/title.jpg"


## background (BACKGROUNDS の 1 つ) の背景の素材のパス
static func background_path(background: String) -> String:
	return BACKGROUND_PATH % background


## line (表情を持つメッセージの行) の話者と表情の立ち絵の素材のパス
static func portrait_path(line: Dictionary) -> String:
	return PORTRAIT_PATH % [HEROINES[line[ScenarioScript.SPEAKER]], line[ScenarioScript.EXPRESSION]]


## backlog (流れた行の古い順の一覧) で最後に背景を指定した行の背景。どの行も指定していなければ ""
static func shown_background(backlog: Array) -> String:
	for index: int in range(backlog.size() - 1, -1, -1):
		if backlog[index].has(ScenarioScript.BACKGROUND):
			return backlog[index][ScenarioScript.BACKGROUND]
	return ""


## backlog (流れた行の古い順の一覧) のうち、いまの場面 (最後に背景を指定した行から後) で最後に表情を持つ行。
## 主人公の台詞や地の文の間も直前のヒロインの立ち絵を残し、場面が変わったら消すため。無ければ {}
static func shown_portrait(backlog: Array) -> Dictionary:
	for index: int in range(backlog.size() - 1, -1, -1):
		if backlog[index].has(ScenarioScript.EXPRESSION):
			return backlog[index]
		if backlog[index].has(ScenarioScript.BACKGROUND):
			return {}
	return {}


## lines (シナリオの行) の background・expression が素材のある値でない誤りと、表情を持つ行の話者が立ち絵を持つ
## ヒロインでない誤りを、何番目の行かを付けた文で返す (空なら誤りなし)
static func errors(lines: Array) -> Array[String]:
	var found: Array[String] = []
	for index: int in range(lines.size()):
		var line: Dictionary = lines[index]
		if line.has(ScenarioScript.BACKGROUND) and not (line[ScenarioScript.BACKGROUND] in BACKGROUNDS):
			found.append("%d 番目の行: 背景の素材が無い: %s" % [index + 1, line[ScenarioScript.BACKGROUND]])
		if not line.has(ScenarioScript.EXPRESSION):
			continue
		if not (line[ScenarioScript.EXPRESSION] in EXPRESSIONS):
			found.append("%d 番目の行: 表情の素材が無い: %s" % [index + 1, line[ScenarioScript.EXPRESSION]])
		if not HEROINES.has(line.get(ScenarioScript.SPEAKER, "")):
			found.append(
				"%d 番目の行: 立ち絵の無い話者に表情がある: %s" % [index + 1, line.get(ScenarioScript.SPEAKER, "")]
			)
	return found
