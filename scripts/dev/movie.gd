extends "res://scripts/dev/game_driver.gd"
## 起動の録画 (Makefile の movie target) で、タイトルから本編を始めて、文字送りが操作なしで進む様子を映すための操作。
## 録画の長さは Makefile の --quit-after が決める。鳴っている BGM・効果音の再生を残したまま --quit-after で終わると
## 終了時に再生がリークとして WARNING / ERROR に出るため、--quit-after の少し前にメインシーンの音を止め、AudioServer が
## 再生を解放するのを待ってから、このスクリプトが終了する。

## タイトルを映しておく時間 (秒)。起動直後の描画崩れ・真っ黒を、録画の冒頭で見分けられる長さ
const TITLE_SHOW_TIME: float = 1.0
## Godot の起動引数のうち、録画するフレーム数を渡す引数 (値は Makefile の movie target の MOVIE_FRAMES)
const QUIT_AFTER_ARG: String = "--quit-after"
## Godot の起動引数のうち、録画のフレームの速さを渡す引数。音を止めてから終了するまでのフレーム数を決める
const FIXED_FPS_ARG: String = "--fixed-fps"


## tree の準備が終わってから _run() を始める (シーンの追加は _initialize() の後でないとできない)
func _initialize() -> void:
	_run.call_deferred()


## 物理フレームを進めながら入力を流すため、同じ実行中に重ねて呼び出さない
func _run() -> void:
	_isolate_save("movie")
	var main: Control = _add_main()
	await create_timer(TITLE_SHOW_TIME).timeout
	await _hold_keys([KEY_ENTER], 1)
	var quit_after: int = _cmdline_int(QUIT_AFTER_ARG)
	var fixed_fps: int = _cmdline_int(FIXED_FPS_ARG)
	if quit_after < 0 or fixed_fps < 0:
		return
	var release_frames: int = ceili(AUDIO_RELEASE_TIME * fixed_fps) + 1
	while Engine.get_process_frames() < quit_after - release_frames:
		await process_frame
	_silence(main)
	await create_timer(AUDIO_RELEASE_TIME).timeout
	quit(0)


## Godot の起動引数の name に渡した整数。無ければ -1 (このスクリプトからは終了しない)
func _cmdline_int(name: String) -> int:
	var args: PackedStringArray = OS.get_cmdline_args()
	var index: int = args.find(name)
	if index < 0 or index + 1 >= args.size():
		return -1
	return args[index + 1].to_int()


## main の処理を止めて (BGM を鳴らし直さず、会話も進めない。画面は止めた時のまま描かれる)、鳴っている BGM と効果音を
## 止める
func _silence(main: Control) -> void:
	main.process_mode = Node.PROCESS_MODE_DISABLED
	for player: Node in main.get_node("Audio").get_children():
		(player as AudioStreamPlayer).stop()
