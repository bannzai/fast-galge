extends "res://scripts/dev/headless_check.gd"
## キー入力 (InputMap を通る InputEventKey) でメインシーンを動かし、タイトル → 会話中 → バックログ → 会話中の
## 画面の遷移と、表示の見出しが画面に追従することを検証する (headless)。会話の中身の検証は土台の issue で足す。
## 実行方法は AGENTS.md を参照。失敗したら quit(1) で終わる。

## 画面 (Screen) の定義を持つ autoload の GameState のスクリプト
const GameStateScript := preload("res://scripts/game_state.gd")


## tree の準備が終わってから _run() を始める (シーンの追加は _initialize() の後でないとできない)
func _initialize() -> void:
	_run.call_deferred()


## 物理フレームを進めながら入力を流すため、同じ実行中に重ねて呼び出さない
func _run() -> void:
	var game_state: Node = root.get_node_or_null("GameState")
	_check(game_state != null, "前提: autoload の GameState が root にある")
	if game_state != null:
		await _run_scenes(game_state)
	if failed:
		quit(1)
		return
	print("integration OK")
	quit(0)


## メインシーンを置いて画面の遷移を入力で確かめ、最後にシーンを消す
func _run_scenes(game_state: Node) -> void:
	var main: Control = _add_main()
	await process_frame
	var title_label: Label = main.get_node("Title")
	_check(game_state.screen == GameStateScript.Screen.TITLE, "起動直後はタイトル")
	_check(title_label.text == "fast-galge", "タイトルの見出し")
	await _hold_keys([KEY_ENTER], 1)
	_check(game_state.screen == GameStateScript.Screen.PLAYING, "Enter で会話中になる")
	_check(title_label.text == "PLAYING", "会話中の見出し")
	await _hold_keys([KEY_ENTER], 1)
	_check(game_state.screen == GameStateScript.Screen.PLAYING, "会話中の Enter では画面が変わらない")
	await _hold_keys([KEY_B], 1)
	_check(game_state.screen == GameStateScript.Screen.BACKLOG, "B でバックログを開く")
	_check(title_label.text == "BACKLOG", "バックログの見出し")
	await _hold_keys([KEY_B], 1)
	_check(game_state.screen == GameStateScript.Screen.PLAYING, "B でバックログを閉じて会話中に戻る")
	main.queue_free()
	await process_frame
	await create_timer(AUDIO_RELEASE_TIME).timeout
