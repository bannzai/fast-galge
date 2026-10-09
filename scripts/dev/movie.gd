extends "res://scripts/dev/game_driver.gd"
## 起動の録画 (Makefile の movie target) で、タイトルから本編を始めて、文字送りが操作なしで進む様子を映すための操作。
## 鳴っている BGM・効果音の再生を残したまま終わると終了時に再生がリークとして WARNING / ERROR に出るため、録画する
## フレーム数の少し前にメインシーンの処理と音を止め、AudioServer が再生を解放するのを待ってから、このスクリプトが
## 終了する。録画するフレーム数と録画のフレームの速さは、Makefile が -- の後の引数 (MOVIE_FRAMES_ARG・MOVIE_FPS_ARG)
## で渡す。

## タイトルを映しておく時間 (秒)。起動直後の描画崩れ・真っ黒を、録画の冒頭で見分けられる長さ
const TITLE_SHOW_TIME: float = 1.0
## -- の後の引数のうち、録画するフレーム数を渡す引数の頭 (値は Makefile の MOVIE_FRAMES)
const MOVIE_FRAMES_ARG: String = "--movie-frames="
## -- の後の引数のうち、録画のフレームの速さを渡す引数の頭 (値は Makefile の MOVIE_FPS)。音を止めてから終了するまでの
## フレーム数を決める
const MOVIE_FPS_ARG: String = "--movie-fps="
## 音を止めた時に出す印 (録画のログで、このスクリプトが終了したことを確かめる)
const SILENCED_MESSAGE: String = "movie: BGM と効果音を止めて終了する (フレーム %d)"


## tree の準備が終わってから _run() を始める (シーンの追加は _initialize() の後でないとできない)
func _initialize() -> void:
	_run.call_deferred()


## 物理フレームを進めながら入力を流すため、同じ実行中に重ねて呼び出さない
func _run() -> void:
	_isolate_save("movie")
	var main: Control = _add_main()
	await create_timer(TITLE_SHOW_TIME).timeout
	await _hold_keys([KEY_ENTER], 1)
	var movie_frames: int = _user_arg_int(MOVIE_FRAMES_ARG)
	var movie_fps: int = _user_arg_int(MOVIE_FPS_ARG)
	if movie_frames < 0 or movie_fps < 0:
		push_error("movie: 録画するフレーム数と速さの引数が無い (%s)" % [OS.get_cmdline_user_args()])
		quit(1)
		return
	var release_frames: int = ceili(AUDIO_RELEASE_TIME * movie_fps) + 1
	while Engine.get_process_frames() < movie_frames - release_frames:
		await process_frame
	_silence(main)
	print(SILENCED_MESSAGE % Engine.get_process_frames())
	await create_timer(AUDIO_RELEASE_TIME).timeout
	quit(0)


## -- の後の引数のうち prefix で始まるものの値 (整数)。無ければ -1
func _user_arg_int(prefix: String) -> int:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with(prefix):
			return arg.trim_prefix(prefix).to_int()
	return -1


## main の処理を止めて (BGM を鳴らし直さず、会話も進めない。画面は止めた時のまま描かれる)、鳴っている BGM と効果音を
## 止める
func _silence(main: Control) -> void:
	main.process_mode = Node.PROCESS_MODE_DISABLED
	for player: Node in main.get_node("Audio").get_children():
		(player as AudioStreamPlayer).stop()
