extends "res://scripts/dev/headless_check.gd"
## 画面の遷移表、全シーンのロード、全素材が assets/CREDITS.md に記録されていることの検証 (headless)。
## 会話エンジンの計算 (表示時間・制限時間・好感度) は土台の issue で足す。
## 実行方法は AGENTS.md を参照。release ビルドで assert が消えるため、明示的な判定と exit code で結果を返す。

## 起動検証 (main_scene の --quit) ではロードされない遷移先も含めた全シーン
const SCENES: Array[String] = [
	"res://scenes/main.tscn",
]
## 画面と遷移表を持つ autoload のスクリプト
const GAME_STATE_SCRIPT := preload("res://scripts/game_state.gd")
## 素材の置き場所と、出典・ライセンスの記録
const ASSETS_DIR: String = "res://assets"
const CREDITS_PATH: String = "res://assets/CREDITS.md"
## 素材として記録しないファイル (記録そのものと、Godot が生成するインポート設定)
const CREDITS_EXEMPT_SUFFIXES: Array[String] = ["CREDITS.md", ".import", ".gdignore"]
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


## 全検証を実行し、1 件でも失敗していれば exit code 1、すべて通れば `selfcheck OK` を出して exit code 0 で終わる
func _initialize() -> void:
	_check_transitions()
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
	game_state.finish()
	_check(game_state.screen == GAME_STATE_SCRIPT.Screen.ENDING, "finish でエンディングになる")
	game_state.free()


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
