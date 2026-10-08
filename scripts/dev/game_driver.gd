extends SceneTree
## キー入力とマウスのクリック (InputMap・GUI を通る入力イベント) でメインシーンを動かす開発用スクリプト (scripts/dev/ の
## screenshot.gd・movie.gd と、headless_check.gd を継承する selfcheck.gd・integration.gd) が共通で使う、入力の送り方・
## フレームの待ち方・会話の早送り・メインシーンの置き方。各スクリプトは _initialize() から自分の検証・撮影を始める。

## メインシーン
const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
## シナリオの保存形式のキー
const ScenarioScript := preload("res://scripts/scenario.gd")
## 選択肢を選ぶキー (並び順が選択肢の番号。project.godot の入力の choice_1〜choice_3)
const CHOICE_KEYS: Array[Key] = [KEY_1, KEY_2, KEY_3]
## 早送り (_fast_forward) で 1 回に進める時間 (秒)。メッセージの表示時間の下限と選択肢の制限時間より十分短くして、
## 止まる条件を確かめる前に行を通り過ぎないようにする
const FAST_FORWARD_STEP: float = 0.05
## 最後のメインシーンを消してから終了するまで待つ時間 (秒)。消したシーンが鳴らしていた音の再生は AudioServer が
## ミキシングを数回進めてから解放するため、headless (1 フレームがほぼ 0 秒で進む) で待たずに終了すると再生が
## リークとして WARNING / ERROR に出る (kageboshi の CI で実測)。ミキシング数回分に余裕を持たせた値
const AUDIO_RELEASE_TIME: float = 0.25


## autoload の SaveData の保存先を res://tmp/<name>-save.json に変えて読み込み直し、SaveData を返す (検証・撮影が
## プレイヤーの保存データ user:// を書き換えないため)。前の実行が残した保存データと退避したファイルは先に消す。
## SaveData が無ければ null
func _isolate_save(name: String) -> Node:
	var save_data: Node = root.get_node_or_null("SaveData")
	if save_data == null:
		return null
	var path: String = ProjectSettings.globalize_path("res://tmp/%s-save.json" % name)
	_remove_file(path)
	_remove_file(path + save_data.BROKEN_SUFFIX)
	_remove_file(path + save_data.WRITING_SUFFIX)
	save_data.load_from(path)
	return save_data


## path のファイルがあれば消す
func _remove_file(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


## メインシーンを置き、画面の遷移で読み込み直せるよう current_scene にして返す
func _add_main() -> Control:
	var main: Control = MAIN_SCENE.instantiate()
	root.add_child(main)
	current_scene = main
	return main


## physical_keycodes (Key の配列) のキーを押す (pressed = true) / 離す (false)
func _press_keys(physical_keycodes: Array, pressed: bool) -> void:
	for keycode: Key in physical_keycodes:
		Input.parse_input_event(_key_event(keycode, pressed))


## physics_frames 物理フレームだけ待つ
func _wait_physics_frames(physics_frames: int) -> void:
	for _i: int in range(physics_frames):
		await physics_frame


## physical_keycodes (Key の配列) のキーを同時に押し、physics_frames 物理フレームの間押し続けてから離す
func _hold_keys(physical_keycodes: Array, physics_frames: int) -> void:
	_press_keys(physical_keycodes, true)
	await _wait_physics_frames(physics_frames)
	_press_keys(physical_keycodes, false)
	await physics_frame


## physical_keycode のキーを押した (pressed = true) / 離した (false) 入力イベント
func _key_event(physical_keycode: Key, pressed: bool) -> InputEventKey:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = physical_keycode
	event.keycode = physical_keycode
	event.pressed = pressed
	return event


## control の中心をマウスの左ボタンで押して離す (タップの代わり。タッチはマウスの入力として届く)
func _click(control: Control) -> void:
	var point: Vector2 = root.get_final_transform() * control.get_global_rect().get_center()
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	Input.parse_input_event(motion)
	await process_frame
	for pressed: bool in [true, false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		Input.parse_input_event(event)
		await process_frame
	await process_frame


## game_state の会話が選択肢で止まっているか
func _is_choosing(game_state: Node) -> bool:
	return game_state.is_playing() and game_state.current_line().has(ScenarioScript.CHOICES)


## game_state の会話を、until.call() が true になるかエンディングに着くまで、フレームを待たずに時間だけ進める
func _fast_forward(game_state: Node, until: Callable) -> void:
	while game_state.is_playing() and not until.call():
		game_state.advance(FAST_FORWARD_STEP)
