extends "res://scripts/dev/game_driver.gd"
## 実際の描画で代表画面を撮影する (headless では描画されないため、Makefile の screenshot target が --headless なしで
## 起動する)。撮影した PNG は tmp/screenshot-<名前>.png に保存し、失敗したら quit(1) で終わる。
## 画面や状態を増やす時は _capture_scenes() だけを差し替える。

## 画面を出してから撮影するまで待つ時間 (秒)。起動直後の最初の描画と、バックログの一覧を末尾まで送るレイアウト
## (メインシーンが 2 フレーム待ってから送る) が済むのに十分な長さ
const SETTLE_TIME: float = 0.3


## tree の準備が終わってから _run() を始める (シーンの追加は _initialize() の後でないとできない)
func _initialize() -> void:
	_run.call_deferred()


## 物理フレームを進めながら入力を流すため、同じ実行中に重ねて呼び出さない
func _run() -> void:
	if await _capture_scenes():
		await create_timer(AUDIO_RELEASE_TIME).timeout
		quit(0)


## 代表画面を、本編を早送りしながら順に撮影する。最後はエンディングからタイトルへ戻り、章の区切りを通った後の
## タイトル (「つづきから」が出ている) を撮る。
## 失敗した撮影は _capture() が quit(1) 済みなので、false を受けたらそのまま抜ける
func _capture_scenes() -> bool:
	var game_state: Node = root.get_node("GameState")
	_isolate_save("screenshot")
	var main: Control = _add_main()
	await create_timer(SETTLE_TIME).timeout
	if not await _capture("tmp/screenshot-title.png"):
		return false
	await _hold_keys([KEY_ENTER], 1)
	_fast_forward(
		game_state,
		func() -> bool: return game_state.backlog.back().has(ScenarioScript.EXPRESSION)
	)
	if not await _capture("tmp/screenshot-playing.png"):
		return false
	_fast_forward(game_state, _is_choosing.bind(game_state))
	if not await _capture_choice(game_state):
		return false
	await _hold_keys([KEY_B], 1)
	await create_timer(SETTLE_TIME).timeout
	if not await _capture("tmp/screenshot-backlog.png"):
		return false
	await _hold_keys([KEY_B], 1)
	if not await _capture_ending_and_title(game_state):
		return false
	main.queue_free()
	await process_frame
	return true


## 本編の残りを 1 つ目の選択肢で早送りしてエンディングを撮り、タイトルへ戻って「つづきから」が出たタイトルを撮る
func _capture_ending_and_title(game_state: Node) -> bool:
	while game_state.is_playing():
		_fast_forward(game_state, _is_choosing.bind(game_state))
		game_state.choose(0)
	if not await _capture("tmp/screenshot-ending.png"):
		return false
	await _hold_keys([KEY_ENTER], 1)
	return await _capture("tmp/screenshot-title-continue.png")


## 選択肢で止まっている画面を撮影する。撮影は実時間で進むため、描画を待つ間に制限時間が切れていたら (撮れたのが
## 選択肢の画面でなくなるため) 失敗として quit(1) する
func _capture_choice(game_state: Node) -> bool:
	if not await _capture("tmp/screenshot-choice.png"):
		return false
	if not _is_choosing(game_state):
		push_error("選択肢の撮影の前に制限時間が切れた")
		quit(1)
		return false
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
