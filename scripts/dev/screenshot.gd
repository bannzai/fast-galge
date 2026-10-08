extends "res://scripts/dev/game_driver.gd"
## 実際の描画で代表画面を撮影する (headless では描画されないため、Makefile の screenshot target が --headless なしで
## 起動する)。撮影した PNG は tmp/screenshot-<名前>.png に保存し、失敗したら quit(1) で終わる。結果の画像 (エンディングの
## 画面が共有で保存する PNG) はメインシーンの保存の処理で tmp/screenshot-result.png に書く。
## 画面や状態を増やす時は _capture_scenes() だけを差し替える。

## 画面を出してから撮影するまで待つ時間 (秒)。起動直後の最初の描画と、バックログの一覧を末尾まで送るレイアウト
## (メインシーンが 2 フレーム待ってから送る) が済むのに十分な長さ
const SETTLE_TIME: float = 0.3
## 結果の画像 (共有で保存する PNG) の保存先
const RESULT_IMAGE_PATH: String = "tmp/screenshot-result.png"
## 結果の画像が単色でないことを見る時に色を取る格子の分割数 (縦横)。帯・文字・背景のどれかに当たる細かさ
const SAMPLE_GRID: int = 20


## tree の準備が終わってから _run() を始める (シーンの追加は _initialize() の後でないとできない)
func _initialize() -> void:
	_run.call_deferred()


## 物理フレームを進めながら入力を流すため、同じ実行中に重ねて呼び出さない
func _run() -> void:
	if await _capture_scenes():
		await create_timer(AUDIO_RELEASE_TIME).timeout
		quit(0)


## 代表画面を、本編を早送りしながら順に撮影する。
## 失敗した撮影は _capture() が quit(1) 済みなので、false を受けたらそのまま抜ける
func _capture_scenes() -> bool:
	var game_state: Node = root.get_node("GameState")
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
	while game_state.is_playing():
		_fast_forward(game_state, _is_choosing.bind(game_state))
		game_state.choose(0)
	if not await _capture_ending(main):
		return false
	main.queue_free()
	await process_frame
	return true


## エンディングの画面を撮影し、結果の画像を共有で保存するのと同じ処理 (メインシーンの save_result_image) で保存して、
## 保存した PNG が結果の画像を描く SubViewport と同じ大きさで、単色 (描画されていない) でないことを確かめる。
## 失敗したら quit(1) する
func _capture_ending(main: Control) -> bool:
	if not await _capture("tmp/screenshot-ending.png"):
		return false
	var status: Error = await main.save_result_image(RESULT_IMAGE_PATH)
	if status != OK:
		push_error("結果の画像の保存失敗: %s (%s)" % [RESULT_IMAGE_PATH, error_string(status)])
		quit(1)
		return false
	var expected_size: Vector2i = main.get_node("EndingScreen/ResultViewport").size
	var saved: Image = Image.load_from_file(RESULT_IMAGE_PATH)
	if saved == null or saved.get_size() != expected_size:
		push_error("結果の画像の大きさが %s ではない: %s" % [expected_size, RESULT_IMAGE_PATH])
		quit(1)
		return false
	if _sampled_colors(saved).size() < 2:
		push_error("結果の画像が単色で、描画されていない: %s" % RESULT_IMAGE_PATH)
		quit(1)
		return false
	print("screenshot: " + RESULT_IMAGE_PATH)
	return true


## image を縦横 SAMPLE_GRID 分割した格子の点の色の集合 (単色かどうかの判定用)
func _sampled_colors(image: Image) -> Dictionary:
	var colors: Dictionary = {}
	for row: int in range(SAMPLE_GRID):
		for column: int in range(SAMPLE_GRID):
			var x: int = floori(image.get_width() * column / float(SAMPLE_GRID))
			var y: int = floori(image.get_height() * row / float(SAMPLE_GRID))
			colors[image.get_pixel(x, y).to_html()] = true
	return colors


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
