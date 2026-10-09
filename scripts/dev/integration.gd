extends "res://scripts/dev/headless_check.gd"
## キー入力とマウスのクリック (タップの代わり) でメインシーンを動かし、会話の自動送り・選択・時間切れ・バックログの開閉・
## 5 つのエンディングへの到達と、表示が会話の進行に追従することを検証する (headless)。Makefile が --fixed-fps 60 を付けて
## 起動し、会話の時間を実時間から切り離して 1 フレーム 1/60 秒で進める (本編を実時間で流すと 1 周に約 5 分かかるため)。
## 実行方法は AGENTS.md を参照。失敗したら quit(1) で終わる。

## 画面 (Screen) の定義と本編のシナリオを持つ autoload の GameState のスクリプト
const GameStateScript := preload("res://scripts/game_state.gd")
## 会話が進むのを待つ上限のフレーム数 (60 fps で 10 分)。本編 1 周 (ルートに入る周) の所要時間の上限 7 分より長くして、
## 会話が終わらない不具合の時だけ待ちを打ち切る
const WAIT_FRAME_LIMIT: int = 36000
## バックログを開いている間に会話が止まることを確かめるために待つ時間 (秒)。メッセージの表示時間の上限より長い
const PAUSE_CHECK_TIME: float = 1.0
## 描画が止まっていた後の 1 フレームとしてメインシーンに渡す経過時間 (秒)。上限なしに進めると、サンプルシナリオの
## 選択肢の時間切れまで過ぎる長さ
const LONG_FRAME_TIME: float = 5.0


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


## メインシーンを置いてサンプルシナリオと本編を入力で進め、最後にシーンを消す
func _run_scenes(game_state: Node) -> void:
	var main: Control = _add_main()
	await process_frame
	game_state.scenario_paths = SAMPLE_SCENARIO_PATHS
	await _check_sample_with_keys(game_state, main)
	await _check_sample_timeout(game_state, main)
	await _check_sample_with_taps(game_state, main)
	game_state.scenario_paths = GameStateScript.MAIN_SCENARIO_PATHS
	for case: Array in MAIN_ENDING_CASES:
		await _check_main_ending(game_state, case)
	main.queue_free()
	await process_frame
	await create_timer(AUDIO_RELEASE_TIME).timeout


## サンプルシナリオをキー入力で進める。文字送りを入力で止められないこと、バックログの開閉、選択肢を選ぶこと、
## エンディングの表示とタイトルへ戻ること
func _check_sample_with_keys(game_state: Node, main: Control) -> void:
	var message_label: Label = main.get_node("ConversationScreen/MessageWindow/Message")
	var speaker_label: Label = main.get_node("ConversationScreen/MessageWindow/Speaker")
	_check(game_state.screen == GameStateScript.Screen.TITLE, "起動直後はタイトル")
	_check(main.get_node("TitleScreen").visible, "タイトルの画面が出ている")
	await _hold_keys([KEY_ENTER], 1)
	_check(game_state.screen == GameStateScript.Screen.PLAYING, "Enter で会話中になる")
	_check(main.get_node("ConversationScreen").visible, "会話中の画面が出ている")
	_check(message_label.text == game_state.lines[0]["text"], "最初のメッセージが表示される")
	main.call("_process", LONG_FRAME_TIME)
	_check(
		(
			game_state.backlog.size() == 1
			and game_state.elapsed <= ConversationScript.MAX_FRAME_SECONDS * 2.0
		),
		"描画が止まっていた後の長い 1 フレームでは、上限までしか会話が進まない"
	)
	await _hold_keys([KEY_ENTER], 1)
	await _hold_keys([KEY_SPACE], 1)
	await _click(main.get_node("ConversationScreen/MessageWindow"))
	_check(
		game_state.is_playing() and game_state.backlog.size() == 1,
		"会話中の Enter・Space・クリックではメッセージが送られない"
	)
	await _wait_until(func() -> bool: return game_state.backlog.size() >= 2)
	_check(message_label.text == game_state.lines[1]["text"], "操作しなくても次のメッセージに進む")
	_check(speaker_label.text == game_state.lines[1]["speaker"], "話者名が表示される")
	await _check_backlog_with_keys(game_state, main)
	await _wait_until(_is_choosing.bind(game_state))
	_check(main.get_node("ConversationScreen/Choices").visible, "選択肢が表示される")
	_check(
		(
			main.get_node("ConversationScreen/Choices/Choice1").text
			== "1. " + game_state.current_line()["choices"][0]["text"]
		),
		"選択肢のボタンに本文が出る"
	)
	_check(
		not main.get_node("ConversationScreen/Choices/Choice3").visible,
		"選択肢に無い番号のボタンは出ない"
	)
	await _hold_keys([CHOICE_KEYS[0]], 1)
	_check(not _is_choosing(game_state), "1 のキーで選択肢を選べる")
	_check(game_state.affection == {"hina": 1}, "選んだ選択肢の好感度が足される")
	await _wait_until(func() -> bool: return not game_state.is_playing())
	_check(game_state.screen == GameStateScript.Screen.ENDING, "会話の終わりでエンディングになる")
	_check(game_state.current_line().get("ending") == "sample_good", "好感度を満たすと good に着く")
	_check(
		main.get_node("EndingScreen/Name").text == game_state.current_line()["name"],
		"エンディング名が表示される"
	)
	_check(game_state.reached_endings == ["sample_good"], "到達したエンディングが記録される")
	await _hold_keys([KEY_ENTER], 1)
	_check(game_state.screen == GameStateScript.Screen.TITLE, "エンディングの Enter でタイトルに戻る")


## 会話中に B でバックログを開閉する。開いている間は会話が止まり、流れたメッセージが一覧に載り、閉じると続きから
## 再開すること。メッセージが切り替わった直後 (表示時間の残りが十分ある時) に呼ぶ
func _check_backlog_with_keys(game_state: Node, main: Control) -> void:
	await _hold_keys([KEY_B], 1)
	_check(game_state.screen == GameStateScript.Screen.BACKLOG, "B でバックログを開く")
	_check(main.get_node("BacklogScreen").visible, "バックログの画面が出ている")
	var position: int = game_state.position
	var elapsed: float = game_state.elapsed
	await create_timer(PAUSE_CHECK_TIME).timeout
	_check(
		game_state.position == position and is_equal_approx(game_state.elapsed, elapsed),
		"バックログを開いている間は会話が止まる"
	)
	_check(
		main.get_node("BacklogScreen/Scroll/Entries").text.contains(game_state.lines[0]["text"]),
		"バックログに流れたメッセージが載る"
	)
	await _hold_keys([KEY_B], 1)
	_check(game_state.screen == GameStateScript.Screen.PLAYING, "B でバックログを閉じて会話中に戻る")
	_check(game_state.position == position, "バックログを閉じると続きから再開する")


## サンプルシナリオを操作せずに流す。残り時間のバーが減り、制限時間を過ぎると「……」を選んだ扱いで好感度が下がること
func _check_sample_timeout(game_state: Node, main: Control) -> void:
	var time_bar: ProgressBar = main.get_node("ConversationScreen/Choices/TimeBar")
	await _hold_keys([KEY_ENTER], 1)
	_check(
		game_state.affection.is_empty() and game_state.backlog.size() == 1,
		"やり直すと好感度とバックログが初期値に戻る"
	)
	await _wait_until(_is_choosing.bind(game_state))
	await process_frame
	var value_at_start: float = time_bar.value
	await create_timer(ConversationScript.CHOICE_SECONDS / 2.0).timeout
	_check(_is_choosing(game_state), "制限時間の途中では選択肢が出たまま")
	_check(time_bar.value < value_at_start, "残り時間のバーが減る")
	await _wait_until(func() -> bool: return not _is_choosing(game_state))
	_check(
		game_state.affection == {"hina": ConversationScript.TIMEOUT_AFFECTION},
		"時間切れで好感度が下がる"
	)
	_check(
		game_state.backlog.any(
			func(entry: Dictionary) -> bool: return entry["text"] == ConversationScript.TIMEOUT_TEXT
		),
		"時間切れの「……」がバックログに積まれる"
	)
	await _wait_until(func() -> bool: return not game_state.is_playing())
	_check(game_state.current_line().get("ending") == "sample_bad", "好感度が足りないと bad に着く")
	await _hold_keys([KEY_ENTER], 1)


## サンプルシナリオをタップ (マウスのクリック) だけで最後まで進める。始めるボタン、バックログを開くボタンと閉じる
## ボタン、選択肢のボタン、タイトルへ戻るボタン
func _check_sample_with_taps(game_state: Node, main: Control) -> void:
	await _click(main.get_node("TitleScreen/StartButton"))
	_check(game_state.screen == GameStateScript.Screen.PLAYING, "始めるボタンのタップで会話中になる")
	await _click(main.get_node("ConversationScreen/BacklogButton"))
	_check(game_state.screen == GameStateScript.Screen.BACKLOG, "ログのボタンのタップでバックログを開く")
	await _click(main.get_node("BacklogScreen/CloseButton"))
	_check(game_state.screen == GameStateScript.Screen.PLAYING, "とじるボタンのタップで会話中に戻る")
	await _wait_until(_is_choosing.bind(game_state))
	await process_frame
	var tapped_text: String = game_state.current_line()["choices"][1]["text"]
	await _click(main.get_node("ConversationScreen/Choices/Choice2"))
	_check(not _is_choosing(game_state), "選択肢のボタンのタップで選べる")
	_check(
		game_state.backlog.any(func(entry: Dictionary) -> bool: return entry["text"] == tapped_text),
		"タップした選択肢がバックログに積まれる"
	)
	_check(game_state.affection == {"hina": -1}, "タップした選択肢の好感度が足される")
	await _wait_until(func() -> bool: return not game_state.is_playing())
	_check(game_state.current_line().get("ending") == "sample_bad", "タップだけでエンディングに着く")
	await _click(main.get_node("EndingScreen/TitleButton"))
	_check(game_state.screen == GameStateScript.Screen.TITLE, "タイトルへのボタンのタップでタイトルに戻る")


## 本編を最初から最後まで、case (MAIN_ENDING_CASES の 1 つ) の進め方で選択肢をキーで選んで (共通 bad の進め方では
## 何も押さずに時間切れで) 進め、case のエンディングに着くこと
func _check_main_ending(game_state: Node, case: Array) -> void:
	var expected: String = case[0]
	await _hold_keys([KEY_ENTER], 1)
	var frames: int = 0
	while game_state.is_playing() and frames < WAIT_FRAME_LIMIT:
		var pick: int = (
			_pick_for_case(case, game_state.lines, game_state.position)
			if _is_choosing(game_state)
			else ConversationScript.TIMEOUT
		)
		if pick != ConversationScript.TIMEOUT:
			await _hold_keys([CHOICE_KEYS[pick]], 1)
		else:
			await process_frame
		frames += 1
	_check(
		(
			game_state.screen == GameStateScript.Screen.ENDING
			and game_state.current_line().get("ending") == expected
		),
		"本編: %s への進め方で着く (好感度 %s)" % [expected, game_state.affection]
	)
	_check(game_state.reached_endings.has(expected), "本編: %s が到達の記録に入る" % expected)
	var lines: Array = game_state.lines
	var estimated: Dictionary = ConversationScript.playthrough(
		lines, func(choice: Dictionary) -> int: return _pick_for_case(case, lines, lines.find(choice))
	)
	_check(
		game_state.affection == estimated["affection"],
		"本編: %s の好感度が見積もりと一致する" % expected
	)
	var timed_out: bool = game_state.backlog.any(
		func(entry: Dictionary) -> bool: return entry["text"] == ConversationScript.TIMEOUT_TEXT
	)
	_check(
		timed_out == case[1].is_empty(),
		(
			"本編: %s は%s進んでいる"
			% [expected, "何も選ばず時間切れで" if case[1].is_empty() else "時間切れではなくキーで選んで"]
		)
	)
	await _hold_keys([KEY_ENTER], 1)
	_check(game_state.screen == GameStateScript.Screen.TITLE, "本編: エンディングからタイトルに戻る")


## until.call() が true になるまでフレームを待つ (WAIT_FRAME_LIMIT フレームで打ち切る)
func _wait_until(until: Callable) -> void:
	var frames: int = 0
	while not until.call() and frames < WAIT_FRAME_LIMIT:
		await process_frame
		frames += 1
