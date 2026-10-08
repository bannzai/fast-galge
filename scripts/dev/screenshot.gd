extends "res://scripts/dev/game_driver.gd"
## 実際の描画で代表画面を撮影する (headless では描画されないため、Makefile の screenshot target が --headless なしで
## 起動する)。撮影した PNG は tmp/screenshot-<名前>.png に保存し、失敗したら quit(1) で終わる。結果の画像 (エンディングの
## 画面が共有で保存する PNG) はメインシーンの保存の処理で tmp/screenshot-result.png に書く。
## 画面や状態を増やす時は _capture_scenes() だけを差し替える。

## 画面を出してから撮影するまで待つ時間 (秒)。起動直後の最初の描画と、バックログの一覧を末尾まで送るレイアウト
## (メインシーンが 2 フレーム待ってから送る) が済むのに十分な長さ
const SETTLE_TIME: float = 0.3
## 結果の画像のファイル名 (共有の操作の保存先の照合に使う)
const ResultScript := preload("res://scripts/result.gd")
## 結果の画像 (共有で保存する PNG) の保存先
const RESULT_IMAGE_PATH: String = "tmp/screenshot-result.png"
## 結果の画像で文字が描かれていることを確かめる Label (scenes/result_card.tscn のノード名) と、
## その範囲で背景と違う色の画素が最低いくつあれば文字が描かれているとみなすか (1 文字で数百画素になる)
const RESULT_TEXT_LABELS: Array[String] = ["EndingName", "Stats", "Footer"]
const MIN_TEXT_PIXELS: int = 200
## 背景と同じ色とみなす各成分の差の上限 (8 bit の量子化で 1/255 ずれるのを吸収する)
const COLOR_TOLERANCE: float = 2.0 / 255.0
## 共有の操作の保存を待つ上限のフレーム数 (描画の完了を 2 回待つ数フレームに十分な余裕)
const SHARE_WAIT_FRAME_LIMIT: int = 300
## 共有の操作の検証で画像を保存するフォルダ (開発者のピクチャフォルダに書かないよう、ログと同じ tmp/ に向ける)
const SHARE_SAVE_DIR: String = "res://tmp"


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


## 描画付きの起動で共有のボタンの操作 (_share) を通し、画像が保存先 (ピクチャフォルダの代わりに tmp/) に保存されて
## 保存先の表示が出ることを確かめる (headless の integration では保存が失敗する経路しか通らないため)。X の投稿画面を
## 開く関数とクリップボードに書く関数は記録するものに差し替える (runner でブラウザを開かないため)。失敗したら quit(1) する
func _check_share_saves(main: Control) -> bool:
	var opened: Array[String] = []
	main.url_opener = func(url: String) -> Error:
		opened.append(url)
		return OK
	main.clipboard_writer = func(_text: String) -> void: pass
	var save_dir: String = ProjectSettings.globalize_path(SHARE_SAVE_DIR)
	main.pictures_dir_provider = func() -> String: return save_dir
	var share_button: Button = main.get_node("EndingScreen/ShareButton")
	main.call("_share")
	var frames: int = 0
	while share_button.disabled and frames < SHARE_WAIT_FRAME_LIMIT:
		await process_frame
		frames += 1
	var status: String = main.get_node("EndingScreen/ShareStatus").text
	var expected_path: String = save_dir.path_join(ResultScript.IMAGE_FILE_NAME)
	var expected_line: String = main.SHARE_SAVED_TEXT % expected_path
	if (
		opened.size() != 1
		or status.split("\n")[0] != expected_line
		or not FileAccess.file_exists(expected_path)
	):
		push_error("共有の操作で画像の保存と投稿画面の URL が揃わない: %s / %s" % [opened, status])
		quit(1)
		return false
	print("share: " + expected_line)
	return true


## エンディングの画面を撮影し、結果の画像を共有で保存するのと同じ処理 (メインシーンの save_result_image) で保存して、
## 保存した PNG が結果の画像を描く SubViewport と同じ大きさで、エンディング名・結果・ハッシュタグと URL の各 Label の
## 範囲に文字が描かれている (背景と違う色の画素がある) ことを確かめ、最後に共有の操作の保存を通す。失敗したら quit(1) する
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
	var card: Control = main.get_node("EndingScreen/ResultViewport/ResultCard")
	var background: Color = card.get_node("Background").color
	for label_name: String in RESULT_TEXT_LABELS:
		var drawn: int = _pixels_differing(saved, card.get_node(label_name).get_rect(), background)
		if drawn < MIN_TEXT_PIXELS:
			push_error("結果の画像の %s に文字が描かれていない (%d 画素): %s" % [label_name, drawn, RESULT_IMAGE_PATH])
			quit(1)
			return false
	print("screenshot: " + RESULT_IMAGE_PATH)
	return await _check_share_saves(main)


## image の rect の範囲で、background と違う色の画素の数 (文字が描かれているかの判定用)。PNG は 8 bit に量子化されて
## いるため、各成分の差が COLOR_TOLERANCE 以下なら同じ色とみなす
func _pixels_differing(image: Image, rect: Rect2, background: Color) -> int:
	var count: int = 0
	var area: Rect2i = Rect2i(rect).intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	for y: int in range(area.position.y, area.end.y):
		for x: int in range(area.position.x, area.end.x):
			var pixel: Color = image.get_pixel(x, y)
			if (
				absf(pixel.r - background.r) > COLOR_TOLERANCE
				or absf(pixel.g - background.g) > COLOR_TOLERANCE
				or absf(pixel.b - background.b) > COLOR_TOLERANCE
			):
				count += 1
	return count


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
