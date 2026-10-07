extends "res://scripts/dev/game_driver.gd"
## 実際の描画で代表画面を撮影する (headless では描画されないため、Makefile の screenshot target が --headless なしで
## 起動する)。撮影した PNG は tmp/screenshot-<名前>.png に保存し、失敗したら quit(1) で終わる。
## 画面や状態を増やす時は _capture_scenes() だけを差し替える。


## tree の準備が終わってから _run() を始める (シーンの追加は _initialize() の後でないとできない)
func _initialize() -> void:
	_run.call_deferred()


## 物理フレームを進めながら入力を流すため、同じ実行中に重ねて呼び出さない
func _run() -> void:
	if await _capture_scenes():
		await create_timer(AUDIO_RELEASE_TIME).timeout
		quit(0)


## 代表画面を順に撮影する。失敗した撮影は _capture() が quit(1) 済みなので、false を受けたらそのまま抜ける
func _capture_scenes() -> bool:
	var main: Control = _add_main()
	await create_timer(0.3).timeout
	if not await _capture("tmp/screenshot-title.png"):
		return false
	await _hold_keys([KEY_ENTER], 1)
	if not await _capture("tmp/screenshot-playing.png"):
		return false
	await _hold_keys([KEY_B], 1)
	if not await _capture("tmp/screenshot-backlog.png"):
		return false
	main.queue_free()
	await process_frame
	return true


## 描画が反映されるまで 2 フレームと描画の完了 (frame_post_draw) を待ってから viewport を path に PNG で保存する。
## 失敗したら quit(1) する
func _capture(path: String) -> bool:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var status: Error = root.get_viewport().get_texture().get_image().save_png(path)
	if status != OK:
		push_error("スクリーンショット保存失敗: %s (%s)" % [path, error_string(status)])
		quit(1)
		return false
	print("screenshot: " + path)
	return true
