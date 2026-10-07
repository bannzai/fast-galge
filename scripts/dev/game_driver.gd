extends SceneTree
## キー入力 (InputMap を通る InputEventKey) でメインシーンを動かす開発用スクリプト (scripts/dev/ の screenshot.gd と、
## headless_check.gd を継承する selfcheck.gd・integration.gd) が共通で使う、キーの押し方・物理フレームの待ち方・
## メインシーンの置き方。各スクリプトは _initialize() から自分の検証・撮影を始める。

## メインシーン
const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
## 最後のメインシーンを消してから終了するまで待つ時間 (秒)。消したシーンが鳴らしていた音の再生は AudioServer が
## ミキシングを数回進めてから解放するため、headless (1 フレームがほぼ 0 秒で進む) で待たずに終了すると再生が
## リークとして WARNING / ERROR に出る (kageboshi の CI で実測)。ミキシング数回分に余裕を持たせた値
const AUDIO_RELEASE_TIME: float = 0.25


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
