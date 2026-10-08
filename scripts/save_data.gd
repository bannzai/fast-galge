extends Node
## 保存データ (autoload の SaveData)。章の区切りでのオートセーブ (章の ID と好感度) と、到達したエンディングを持つ。
## 保存先は端末内の user:// の JSON 1 ファイル (documents/PROJECT.md「技術・配信」) で、起動時に読み込み、変えるたびに書き出す。
## 読めない・形が違う保存データは壊れたものとして既定値で始め、元のファイルは次に保存する時に BROKEN_SUFFIX を付けて
## 退避してから書く (読み込みではファイルを動かさない。検証 (scripts/dev/) が保存先を変える前に autoload の起動時の
## 読み込みが走るため、読み込みでプレイヤーのファイルを動かすと検証がプレイヤーの保存データを書き換えてしまう)。
## 一部の値だけがおかしい時は、その値だけを既定値にして残りを使う。
## 到達したエンディングの記録はここだけが持つ (GameState は会話の進行だけを持ち、エンディングに着いたらここに記録する)。

## 保存先
const SAVE_PATH: String = "user://save.json"
## 保存データの形式の版。形式を変えたら上げ、parse() で古い版を読み替える
const VERSION: int = 1
## 壊れた保存データを退避する時にファイル名へ足す文字列。保存で上書きして中身を確かめる手がかりを失わないよう、
## 保存の直前に退避する
const BROKEN_SUFFIX: String = ".broken"
## 書き出し途中のファイル名へ足す文字列。書き終えてから保存先へ移し、途中で落ちても保存データを壊さない
const WRITING_SUFFIX: String = ".writing"
## 保存データのキー
const KEY_VERSION: String = "version"
const KEY_CHAPTER: String = "chapter"
const KEY_AFFECTION: String = "affection"
const KEY_REACHED_ENDINGS: String = "reached_endings"
## parse() と default_data() が返す辞書の、壊れていたかの印のキー
const KEY_BROKEN: String = "broken"
## 好感度の形 ({ヒロインの ID: 整数}) の判定 (シナリオの形式と同じ)
const ScenarioScript := preload("res://scripts/scenario.gd")

## 保存先。検証 (scripts/dev/) はプレイヤーの保存データを書き換えないよう load_from() で別の場所に変える
var path: String = SAVE_PATH
## オートセーブした章の区切りの ID (シナリオの chapter の行)。空なら途中の保存は無い
var chapter: String = ""
## オートセーブした時点の、ヒロインの ID ごとの好感度
var affection: Dictionary = {}
## 到達したエンディングの ID (到達した順。重複なし)
var reached_endings: Array[String] = []
## 直近の読み込みで保存データが壊れていて既定値で始めたか。次に保存したら (壊れたファイルを退避してから) 消す
var loaded_broken: bool = false


## 起動時に保存先 (user://) の保存データを読み込む
func _ready() -> void:
	load_from(path)


## at の保存データを読み込む。以降の保存先も at にする。無ければ既定値で始める。壊れていたら既定値で始める
## (ファイルは動かさず、次の save() が退避する)
func load_from(at: String) -> void:
	path = at
	_recover_writing()
	var data: Dictionary = default_data()
	if FileAccess.file_exists(path):
		data = parse(FileAccess.get_file_as_string(path))
	loaded_broken = data[KEY_BROKEN]
	chapter = data[KEY_CHAPTER]
	affection = data[KEY_AFFECTION]
	reached_endings = data[KEY_REACHED_ENDINGS]


## 今の進行と記録を保存先へ書き出す。読み込んだ保存データが壊れていたら、先に path + BROKEN_SUFFIX へ退避する。
## 書き出し途中のファイルは、書き終えたことを確かめてから保存先へ移す (書けなかった時は既存の保存データを残す)。
## 書き出せたら壊れていた知らせを消す
func save() -> Error:
	if loaded_broken and FileAccess.file_exists(path):
		var evacuate: Error = DirAccess.rename_absolute(path, path + BROKEN_SUFFIX)
		if evacuate != OK:
			push_error("壊れた保存データを退避できない: %s (%s)" % [path, error_string(evacuate)])
			return evacuate
	var writing: String = path + WRITING_SUFFIX
	var file: FileAccess = FileAccess.open(writing, FileAccess.WRITE)
	if file == null:
		var open_error: Error = FileAccess.get_open_error()
		push_error("保存データを書き出せない: %s (%s)" % [writing, error_string(open_error)])
		return open_error
	var stored: bool = file.store_string(serialize(chapter, affection, reached_endings))
	var write_error: Error = file.get_error()
	file.close()
	if not stored or write_error != OK:
		DirAccess.remove_absolute(writing)
		push_error("保存データを書き終えられない: %s (%s)" % [writing, error_string(write_error)])
		return write_error if write_error != OK else ERR_FILE_CANT_WRITE
	var status: Error = DirAccess.rename_absolute(writing, path)
	if status != OK:
		push_error("保存データを保存先へ移せない: %s (%s)" % [path, error_string(status)])
		return status
	loaded_broken = false
	return OK


## 途中の保存 (つづきから再開できる章) があるか
func has_progress() -> bool:
	return not chapter.is_empty()


## クリア済み (エンディングを 1 つ以上見た) か。ゆっくりモードの解放の条件
func is_cleared() -> bool:
	return not reached_endings.is_empty()


## 章の区切り chapter_id に着いた時点の好感度 current_affection をオートセーブする。
## 前の保存は上書きする (途中の保存は最新の 1 つだけ持つ)
func record_chapter(chapter_id: String, current_affection: Dictionary) -> void:
	chapter = chapter_id
	affection = current_affection.duplicate()
	save()


## ending のエンディングに到達したことを記録して保存する。記録済みなら何もしない
func record_ending(ending: String) -> void:
	if reached_endings.has(ending):
		return
	reached_endings.append(ending)
	save()


## 保存データの文字列。値の順序を固定し、同じ内容からは同じ文字列を作る
static func serialize(
	chapter_id: String, affection_by_heroine: Dictionary, endings: Array[String]
) -> String:
	return JSON.stringify(
		{
			KEY_VERSION: VERSION,
			KEY_CHAPTER: chapter_id,
			KEY_AFFECTION: affection_by_heroine,
			KEY_REACHED_ENDINGS: endings,
		},
		"\t",
		true
	)


## 保存データの文字列を解釈した値 (default_data() と同じ形)。JSON として読めない・最上位が辞書でない・版が違う時は
## broken を true にして既定値を返す。値ごとに型がおかしいものはその値だけ既定値にする (文字列でない章は無し、
## {ヒロインの ID: 整数} でない好感度は空、文字列でない・重複したエンディングは捨てる)
static func parse(text: String) -> Dictionary:
	var data: Dictionary = default_data()
	var json: JSON = JSON.new()
	if json.parse(text) != OK or not (json.data is Dictionary):
		data[KEY_BROKEN] = true
		return data
	var root: Dictionary = json.data
	var version: Variant = root.get(KEY_VERSION)
	if not _is_number(version) or version != VERSION:
		data[KEY_BROKEN] = true
		return data
	var chapter_in: Variant = root.get(KEY_CHAPTER)
	if chapter_in is String:
		data[KEY_CHAPTER] = chapter_in
	var affection_in: Variant = root.get(KEY_AFFECTION)
	if ScenarioScript.is_affection(affection_in):
		for heroine: String in affection_in:
			data[KEY_AFFECTION][heroine] = int(affection_in[heroine])
	var endings_in: Variant = root.get(KEY_REACHED_ENDINGS)
	if endings_in is Array:
		var endings: Array[String] = data[KEY_REACHED_ENDINGS]
		for ending: Variant in endings_in:
			if ending is String and not ending.is_empty() and not endings.has(ending):
				endings.append(ending)
	return data


## 保存先が無く、書き出し途中のファイル (path + WRITING_SUFFIX) だけが残っている時、それが読めるなら保存先へ移して使う。
## Windows の DirAccess.rename_absolute は移動先を消してから移すため、その間に落ちると保存先だけが消えて書き終えた
## ファイルが残る。壊れた書きかけは動かさず (既定値で始め、次の保存で上書きされる)
func _recover_writing() -> void:
	var writing: String = path + WRITING_SUFFIX
	if FileAccess.file_exists(path) or not FileAccess.file_exists(writing):
		return
	if parse(FileAccess.get_file_as_string(writing))[KEY_BROKEN]:
		return
	DirAccess.rename_absolute(writing, path)


## 保存データが無い時の値。broken は壊れていたか、chapter はオートセーブした章の ID (空なら無し)、affection は
## ヒロインの ID ごとの好感度、reached_endings は到達したエンディングの ID
static func default_data() -> Dictionary:
	var endings: Array[String] = []
	return {KEY_BROKEN: false, KEY_CHAPTER: "", KEY_AFFECTION: {}, KEY_REACHED_ENDINGS: endings}


## value が数 (JSON の数は float になる) か
static func _is_number(value: Variant) -> bool:
	return value is int or value is float
