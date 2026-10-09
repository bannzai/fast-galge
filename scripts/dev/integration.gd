extends "res://scripts/dev/headless_check.gd"
## キー入力とマウスのクリック (タップの代わり) でメインシーンを動かし、会話の自動送り・選択・時間切れ・バックログの開閉・
## 5 つのエンディングへの到達・章の区切りでのオートセーブとタイトルの「つづきから」での再開・結果の記録 (結果の画像の本文と
## X の投稿画面の URL) と、表示が会話の進行に追従することと、タイトルから開く設定 (音量の変更と保存) とクレジット
## (リンクを開く) と、BGM が会話中とエンディングだけ場面に合わせて鳴ること (タイトル・設定・クレジットでは鳴らない) と
## 文字送り・選択肢の表示・時間切れ・好感度の変化で効果音が鳴ることを検証する (headless)。保存先は tmp/ の検証用の
## ファイルに変える。
## 共有のボタンとクレジットのリンクは、URL を開く関数を記録するものに差し替えてから押す
## (OS.shell_open が runner でブラウザを開こうとして ERROR を出すため)。Makefile が --fixed-fps 60 を付けて
## 起動し、会話の時間を実時間から切り離して 1 フレーム 1/60 秒で進める (本編を実時間で流すと 1 周に約 5 分かかるため)。
## 実行方法は AGENTS.md を参照。失敗したら quit(1) で終わる。

## 画面 (Screen) の定義と本編のシナリオを持つ autoload の GameState のスクリプト
const GameStateScript := preload("res://scripts/game_state.gd")
## 音量のバスと段階を持つ autoload の SaveData のスクリプト
const SaveDataScript := preload("res://scripts/save_data.gd")
## クレジット画面の文とリンクの URL
const CreditsScript := preload("res://scripts/credits.gd")
## クレジット画面のリンクのボタン (メインシーンのノードのパス) と、そのタップで開く URL
const CREDIT_LINKS: Dictionary = {
	"CreditsScreen/TermsButton": CreditsScript.TERMS_URL,
	"CreditsScreen/PrivacyButton": CreditsScript.PRIVACY_URL,
	"CreditsScreen/SupportButton": CreditsScript.SUPPORT_URL,
	"CreditsScreen/MailButton": CreditsScript.MAIL_URL,
}
## 結果のキーと、文面・URL の組み立て
const ResultScript := preload("res://scripts/result.gd")
## 場面ごとの BGM と効果音の素材
const SoundScript := preload("res://scripts/sound.gd")
## 本編の所要時間の実測が見積もりより短くなる分の上限 (秒)。見積もりは選択肢ごとに制限時間いっぱい止まる前提のため、
## キーで即座に選ぶ実測は選択肢 1 つにつき制限時間の分だけ短くなる。長くなる側の許容は 1 フレーム分に余裕を持たせた 1 秒
const MAIN_SECONDS_TOLERANCE: float = 1.0
## 所要時間の下限に持たせる余裕 (秒)。何も選ばない進め方では下限が見積もりそのものになり、1/60 秒ずつ積んだ浮動小数の
## 丸め誤差で数 e-15 秒だけ下回り得るため
const SECONDS_EPSILON: float = 0.001
## 会話が進むのを待つ上限のフレーム数 (60 fps で 10 分)。本編 1 周 (ルートに入る周) の所要時間の上限 7 分より長くして、
## 会話が終わらない不具合の時だけ待ちを打ち切る
const WAIT_FRAME_LIMIT: int = 36000
## バックログを開いている間に会話が止まることを確かめるために待つ時間 (秒)。メッセージの表示時間の上限より長い
const PAUSE_CHECK_TIME: float = 1.0
## 描画が止まっていた後の 1 フレームとしてメインシーンに渡す経過時間 (秒)。上限なしに進めると、サンプルシナリオの
## 選択肢の時間切れまで過ぎる長さ
const LONG_FRAME_TIME: float = 5.0
## ヒロインの ID と、そのルートで最後に通る章の区切りの ID (ルートの中間に置いた章の区切り)
const LAST_CHAPTERS: Dictionary = {"hina": "route_hina_autumn", "nagi": "route_nagi_autumn"}


## tree の準備が終わってから _run() を始める (シーンの追加は _initialize() の後でないとできない)
func _initialize() -> void:
	_run.call_deferred()


## 物理フレームを進めながら入力を流すため、同じ実行中に重ねて呼び出さない
func _run() -> void:
	var game_state: Node = root.get_node_or_null("GameState")
	var save_data: Node = _isolate_save("integration")
	_check(game_state != null, "前提: autoload の GameState が root にある")
	_check(save_data != null, "前提: autoload の SaveData が root にある")
	if game_state != null and save_data != null:
		await _run_scenes(game_state, save_data)
	if failed:
		quit(1)
		return
	print("integration OK")
	quit(0)


## 壊れた保存データで起動しても落ちず既定値に戻ることを確かめてから、メインシーンを置いてサンプルシナリオ・設定と
## クレジット・本編を入力で進め、最後にシーンを消す
func _run_scenes(game_state: Node, save_data: Node) -> void:
	_check_broken_save(save_data)
	var main: Control = _add_main()
	await process_frame
	game_state.scenario_paths = SAMPLE_SCENARIO_PATHS
	await _check_sample_with_keys(game_state, main, save_data)
	await _check_sample_timeout(game_state, main)
	await _check_sample_with_taps(game_state, main)
	await _check_sample_resume(game_state, main, save_data)
	await _check_settings(game_state, main, save_data)
	await _check_credits(game_state, main)
	game_state.scenario_paths = GameStateScript.MAIN_SCENARIO_PATHS
	for case: Array in MAIN_ENDING_CASES:
		await _check_main_ending(game_state, main, case, save_data)
	main.queue_free()
	await process_frame
	await _wait_audio_release_realtime()


## 壊れた保存データ (JSON として読めないファイル) を読み込んでも落ちず、既定値 (途中の保存なし) で始まり、
## 次の保存で元のファイルが退避されること。確かめた後は保存データと退避したファイルを消し、保存データが無い状態に戻す
func _check_broken_save(save_data: Node) -> void:
	var file: FileAccess = FileAccess.open(save_data.path, FileAccess.WRITE)
	file.store_string("{broken")
	file.close()
	save_data.load_from(save_data.path)
	_check(save_data.loaded_broken, "壊れた保存データ: 壊れたと判定する")
	_check(not save_data.has_progress() and not save_data.is_cleared(), "壊れた保存データ: 既定値で始まる")
	_check(
		not FileAccess.file_exists(save_data.path + save_data.BROKEN_SUFFIX),
		"壊れた保存データ: 読み込みでは元のファイルを動かさない"
	)
	_check(
		save_data.save() == OK and FileAccess.file_exists(save_data.path + save_data.BROKEN_SUFFIX),
		"壊れた保存データ: 保存する時に元のファイルを退避する"
	)
	_remove_file(save_data.path)
	_remove_file(save_data.path + save_data.BROKEN_SUFFIX)
	save_data.load_from(save_data.path)


## サンプルシナリオをキー入力で進める。文字送りを入力で止められないこと、バックログの開閉、選択肢を選ぶこと、
## エンディングの表示とタイトルへ戻ること
func _check_sample_with_keys(game_state: Node, main: Control, save_data: Node) -> void:
	var message_label: Label = main.get_node("ConversationScreen/MessageWindow/Message")
	var speaker_label: Label = main.get_node("ConversationScreen/MessageWindow/Speaker")
	var continue_button: Button = main.get_node("TitleScreen/ContinueButton")
	_check(game_state.screen == GameStateScript.Screen.TITLE, "起動直後はタイトル")
	_check(main.get_node("TitleScreen").visible, "タイトルの画面が出ている")
	_check(not continue_button.visible, "保存が無い間はつづきからのボタンが出ない")
	_check_bgm(main, null, "BGM: タイトルでは鳴らない")
	await _hold_keys([KEY_C], 1)
	_check(game_state.screen == GameStateScript.Screen.TITLE, "保存が無い間は C を押してもタイトルのまま")
	await _hold_keys([KEY_ENTER], 1)
	_check(game_state.screen == GameStateScript.Screen.PLAYING, "Enter で会話中になる")
	_check(main.get_node("ConversationScreen").visible, "会話中の画面が出ている")
	_check(message_label.text == game_state.lines[0]["text"], "最初のメッセージが表示される")
	_check_bgm(main, SoundScript.BGM_COMMON, "BGM: 会話を始めると共通パートの BGM が鳴る")
	_check_effect(main, "message_entered", "効果音: 最初のメッセージで文字送りの効果音が鳴る")
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
	_check_effect(main, "choice_entered", "効果音: 選択肢が表示されると選択肢の効果音が鳴る")
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
	_check_effect(main, "affection_changed", "効果音: 好感度が変わる選択肢を選ぶと好感度の効果音が鳴る")
	_check(not save_data.has_progress(), "章の区切りを通るまではオートセーブされない")
	await _wait_until(func() -> bool: return save_data.has_progress())
	_check(
		save_data.chapter == "sample_after" and save_data.affection == {"hina": 1},
		"章の区切りを通ると章の ID と好感度がオートセーブされる"
	)
	_check(FileAccess.file_exists(save_data.path), "オートセーブの保存データがファイルに書かれる")
	await _wait_until(func() -> bool: return not game_state.is_playing())
	_check(game_state.screen == GameStateScript.Screen.ENDING, "会話の終わりでエンディングになる")
	_check(game_state.current_line().get("ending") == "sample_good", "好感度を満たすと good に着く")
	_check(
		main.get_node("EndingScreen/Name").text == game_state.current_line()["name"],
		"エンディング名が表示される"
	)
	_check(save_data.reached_endings == ["sample_good"], "到達したエンディングが記録される")
	_check_bgm(main, SoundScript.BGM_ENDING, "BGM: エンディングではエンディングの BGM に切り替わる")
	_check_result(game_state, main, 1, 0)
	await _check_share(game_state, main)
	_check_bgm(main, null, "BGM: エンディングからタイトルに戻ると止まる")
	_check(
		not main.get_node("EndingScreen/ResultImage").is_visible_in_tree(),
		"結果: タイトルでは結果の画像が出ない"
	)
	_check(main.get_node("EndingScreen/ShareStatus").text.is_empty(), "画面が移ると共有の結果の表示は空")
	await process_frame
	_check(continue_button.visible, "保存があるとタイトルにつづきからのボタンが出る")


## 共有のボタンの流れ。X の投稿画面を開く関数とクリップボードに書く関数を記録するものに差し替え (runner でブラウザを
## 開かないため)、保存フォルダを返す関数は空を返すものに差し替え (headless では保存できないため OS に聞かない)、
## ボタンのタップと S キーで結果の文面の URL を開き、デスクトップでは文面をコピーし、結果の表示が出て、
## ボタンが押せる状態に戻ること。保存を待つ間にエンディングの画面を離れると投稿画面を開かず表示もしないこと。
## 画像の保存は headless では行えない (ERR_UNAVAILABLE) ため、保存の失敗の表示が出る。保存の待ち (数フレーム) は
## ボタンが押せる状態に戻るまで待って確かめる。最後はタイトルに戻る
func _check_share(game_state: Node, main: Control) -> void:
	var opened: Array[String] = []
	var copied: Array[String] = []
	main.url_opener = func(url: String) -> Error:
		opened.append(url)
		return OK
	main.clipboard_writer = func(text: String) -> void: copied.append(text)
	main.pictures_dir_provider = func() -> String: return ""
	var share_button: Button = main.get_node("EndingScreen/ShareButton")
	var status_label: Label = main.get_node("EndingScreen/ShareStatus")
	var expected_url: String = main.share_url()
	var expected_text: String = ResultScript.share_text(game_state.result())
	await _click(share_button)
	await _wait_until(func() -> bool: return not share_button.disabled)
	_check(opened == [expected_url], "共有: ボタンのタップで結果の文面の URL を開く (%s)" % [opened])
	if OS.has_feature("pc"):
		_check(copied == [expected_text], "共有: デスクトップでは文面をクリップボードに書く")
		_check(status_label.text.contains(main.SHARE_COPIED_TEXT), "共有: コピーしたことを表示する")
	else:
		_check(copied.is_empty(), "共有: デスクトップ以外ではクリップボードに書かない")
		_check(status_label.text.contains(main.SHARE_PHOTO_HINT_TEXT), "共有: 写真に残す方法を案内する")
	_check(not share_button.disabled, "共有: 保存を待った後にボタンが押せる状態に戻る")
	_check(status_label.text.contains(main.SHARE_OPENED_TEXT), "共有: 投稿画面を開いたことを表示する")
	_check(
		status_label.text.contains(main.SHARE_SAVE_FAILED_TEXT % error_string(ERR_UNAVAILABLE)),
		"共有: headless では画像を保存できないことを表示する"
	)
	opened.clear()
	await _hold_keys([KEY_S], 1)
	await _wait_until(func() -> bool: return not share_button.disabled)
	_check(opened == [expected_url], "共有: S キーでも結果の文面の URL を開く (%s)" % [opened])
	opened.clear()
	main.call("_share")
	_check(share_button.disabled, "共有: 保存を待つ間はボタンを押せない")
	main.call("_apply", GameStateScript.Command.CONFIRM)
	_check(game_state.screen == GameStateScript.Screen.TITLE, "エンディングの決定でタイトルに戻る")
	await _wait_until(func() -> bool: return not share_button.disabled)
	_check(
		opened.is_empty() and status_label.text.is_empty() and not share_button.disabled,
		"共有: 待つ間にエンディングの画面を離れたら投稿画面を開かず表示もしない"
	)


## エンディングの画面の結果 (game_state.result()) が、選んだ選択肢の数 choices・時間切れの回数 timeouts と、着いた
## エンディング名・正の所要時間を持ち、結果の画像の本文と X の投稿画面の URL がその結果から組み立てられていること
func _check_result(game_state: Node, main: Control, choices: int, timeouts: int) -> void:
	var result: Dictionary = game_state.result()
	_check(
		(
			result[ResultScript.ENDING_NAME] == game_state.current_line()["name"]
			and result[ResultScript.SECONDS] > 0.0
			and result[ResultScript.CHOICES] == choices
			and result[ResultScript.TIMEOUTS] == timeouts
		),
		"結果: エンディング名・所要時間・選んだ選択肢 %d・時間切れ %d が記録される (%s)" % [choices, timeouts, result]
	)
	_check(
		main.get_node("EndingScreen/ResultImage").is_visible_in_tree(),
		"結果: 結果の画像がエンディングの画面に出る"
	)
	_check(
		(
			main.get_node("EndingScreen/ResultViewport/ResultCard/EndingName").text
			== result[ResultScript.ENDING_NAME]
		),
		"結果: 結果の画像にエンディング名が入る"
	)
	_check(
		(
			main.get_node("EndingScreen/ResultViewport/ResultCard/Stats").text
			== ResultScript.stats_text(result)
		),
		"結果: 結果の画像に所要時間・選んだ選択肢の数・時間切れの回数が入る"
	)
	var card: Control = main.get_node("EndingScreen/ResultViewport/ResultCard")
	_check(
		(
			card.get_node("GameName").text == ResultScript.GAME_NAME
			and card.get_node("Footer").text == card.footer_text()
			and card.get_node("Footer").text.contains(ResultScript.HASHTAG)
			and card.get_node("Footer").text.contains(ResultScript.URL)
		),
		"結果: 結果の画像のゲーム名・ハッシュタグ・URL が文面と同じ定数から出る"
	)
	_check(
		main.share_url() == ResultScript.share_url(ResultScript.share_text(result)),
		"結果: 共有のボタンが開く URL が結果の文面から組み立てられる"
	)


## 会話中に B でバックログを開閉する。開いている間は会話が止まり、流れたメッセージが一覧に載り、閉じると続きから
## 再開すること。メッセージが切り替わった直後 (表示時間の残りが十分ある時) に呼ぶ
func _check_backlog_with_keys(game_state: Node, main: Control) -> void:
	await _hold_keys([KEY_B], 1)
	_check(game_state.screen == GameStateScript.Screen.BACKLOG, "B でバックログを開く")
	_check(main.get_node("BacklogScreen").visible, "バックログの画面が出ている")
	_check_bgm(main, SoundScript.BGM_COMMON, "BGM: バックログを開いても会話中の BGM が続く")
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
	_check_effect(main, "timed_out", "効果音: 時間切れで時間切れの効果音が鳴る")
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
	_check_result(game_state, main, 0, 1)
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
	_check_result(game_state, main, 1, 0)
	await _click(main.get_node("EndingScreen/TitleButton"))
	_check(game_state.screen == GameStateScript.Screen.TITLE, "タイトルへのボタンのタップでタイトルに戻る")


## タイトルの「つづきから」で、保存した章の区切りの次から保存した好感度で再開する。アプリを起動し直した時と同じく
## 保存データをファイルから読み込み直してから、ボタンのタップと C のキーの両方で再開する。
## 直前のタップの検証が 2 つ目の選択肢 (好感度 -1) で章の区切りを通っているため、再開すると bad に着く
func _check_sample_resume(game_state: Node, main: Control, save_data: Node) -> void:
	var message_label: Label = main.get_node("ConversationScreen/MessageWindow/Message")
	save_data.load_from(save_data.path)
	_check(
		not save_data.loaded_broken and save_data.chapter == "sample_after",
		"つづきから: ファイルから読み込み直した保存データに章の区切りがある"
	)
	_check(save_data.affection == {"hina": -1}, "つづきから: ファイルから読み込み直した保存データに好感度がある")
	await _click(main.get_node("TitleScreen/ContinueButton"))
	_check(game_state.screen == GameStateScript.Screen.PLAYING, "つづきからのボタンのタップで会話中になる")
	var chapter: int = ScenarioScript.chapter_index(game_state.lines, "sample_after")
	_check(
		game_state.position == chapter + 1 and game_state.backlog.size() == 1,
		"つづきから: 保存した章の区切りの次のメッセージから始まる"
	)
	_check(message_label.text == game_state.lines[chapter + 1]["text"], "つづきから: 再開したメッセージが表示される")
	_check(game_state.affection == {"hina": -1}, "つづきから: 保存した好感度で再開する")
	await _wait_until(func() -> bool: return not game_state.is_playing())
	_check(game_state.current_line().get("ending") == "sample_bad", "つづきから: 再開した好感度でエンディングに着く")
	await _hold_keys([KEY_ENTER], 1)
	await _hold_keys([KEY_C], 1)
	_check(
		game_state.screen == GameStateScript.Screen.PLAYING and game_state.position == chapter + 1,
		"つづきから: C のキーでも保存した章の区切りの次から再開する"
	)
	await _wait_until(func() -> bool: return not game_state.is_playing())
	await _hold_keys([KEY_ENTER], 1)
	_check(game_state.screen == GameStateScript.Screen.TITLE, "つづきから: 再開した会話の終わりからタイトルに戻る")


## タイトルから設定を O のキーとボタンのタップで開閉し、音量の － / ＋ のタップで BGM と効果音の音量を変えると、
## 段階のバー・保存データ・バスの音量が揃って変わり、保存データをファイルから読み込み直しても (再起動の代わり) 保たれる
## こと。タイトルで呼ぶ
func _check_settings(game_state: Node, main: Control, save_data: Node) -> void:
	var rows: Control = main.get_node("SettingsScreen/Volumes")
	await _hold_keys([KEY_O], 1)
	_check(game_state.screen == GameStateScript.Screen.SETTINGS, "設定: O で設定を開く")
	_check(main.get_node("SettingsScreen").visible, "設定: 設定の画面が出ている")
	_check(not game_state.is_playing(), "設定: 設定を開いても会話は始まらない")
	_check_bgm(main, null, "BGM: 設定では鳴らない")
	for bus: String in SaveDataScript.VOLUME_BUSES:
		_check(
			rows.get_node(bus).get_node("Level").value == save_data.volumes[bus],
			"設定: %s の段階のバーが保存データの音量を出す" % bus
		)
	var bgm_before: int = save_data.volumes["BGM"]
	for _i: int in range(SaveDataScript.MAX_VOLUME - bgm_before + 1):
		await _click(rows.get_node("BGM/Up"))
	_check(save_data.volumes["BGM"] == SaveDataScript.MAX_VOLUME, "設定: BGM の ＋ のタップで最大まで上がって止まる")
	var se_before: int = save_data.volumes["SE"]
	await _click(rows.get_node("SE/Down"))
	await _click(rows.get_node("SE/Down"))
	_check(save_data.volumes["SE"] == se_before - 2, "設定: 効果音の － のタップで 1 段ずつ下がる")
	for bus: String in SaveDataScript.VOLUME_BUSES:
		_check_volume_shown(main, save_data, bus)
	await _hold_keys([KEY_O], 1)
	_check(game_state.screen == GameStateScript.Screen.TITLE, "設定: O で閉じてタイトルに戻る")
	await _click(main.get_node("TitleScreen/SettingsButton"))
	_check(game_state.screen == GameStateScript.Screen.SETTINGS, "設定: 設定のボタンのタップで開く")
	await _click(main.get_node("SettingsScreen/CloseButton"))
	_check(game_state.screen == GameStateScript.Screen.TITLE, "設定: とじるボタンのタップでタイトルに戻る")
	var changed: Dictionary = save_data.volumes.duplicate()
	save_data.load_from(save_data.path)
	_check(save_data.volumes == changed, "設定: 保存データを読み込み直しても変えた音量が保たれる")
	await _click(main.get_node("TitleScreen/SettingsButton"))
	for bus: String in SaveDataScript.VOLUME_BUSES:
		_check_volume_shown(main, save_data, bus)
	await _hold_keys([KEY_ENTER], 1)
	_check(game_state.screen == GameStateScript.Screen.TITLE, "設定: Enter で閉じてタイトルに戻る")


## bus のバスの音量が、設定の画面の段階のバーとバスの音量 (dB) に出ている
func _check_volume_shown(main: Control, save_data: Node, bus: String) -> void:
	var level: int = save_data.volumes[bus]
	var bar: ProgressBar = main.get_node("SettingsScreen/Volumes/%s/Level" % bus)
	var index: int = AudioServer.get_bus_index(bus)
	_check(bar.value == level, "設定: %s の段階のバーが音量 %d を出す" % [bus, level])
	_check(
		(
			index >= 0
			and is_equal_approx(AudioServer.get_bus_volume_db(index), SaveDataScript.volume_db(level))
		),
		"設定: %s のバスの音量が段階 %d の大きさ" % [bus, level]
	)


## タイトルからクレジットを K のキーとボタンのタップで開閉し、素材の出典の一覧が出ていて、リンクのボタン
## (CREDIT_LINKS) のタップでそれぞれの URL を開こうとすること。URL はブラウザで開かず、メインシーンの url_opener を
## 差し替えて記録する。タイトルで呼ぶ
func _check_credits(game_state: Node, main: Control) -> void:
	var opened: Array = []
	main.url_opener = func(url: String) -> Error:
		opened.append(url)
		return OK
	await _hold_keys([KEY_K], 1)
	_check(game_state.screen == GameStateScript.Screen.CREDITS, "クレジット: K でクレジットを開く")
	_check(main.get_node("CreditsScreen").visible, "クレジット: クレジットの画面が出ている")
	_check_bgm(main, null, "BGM: クレジットでは鳴らない")
	_check(
		main.get_node("CreditsScreen/Scroll/Entries").text == CreditsScript.load_text(),
		"クレジット: 素材の記録から作った一覧が出ている"
	)
	for button: String in CREDIT_LINKS:
		await _click(main.get_node(button))
	_check(
		opened == CREDIT_LINKS.values(),
		"クレジット: リンクのタップで利用規約・プライバシーポリシー・サポートページ・メールを開く (%s)" % [opened]
	)
	_check(game_state.screen == GameStateScript.Screen.CREDITS, "クレジット: リンクをタップしても画面はクレジットのまま")
	await _hold_keys([KEY_K], 1)
	_check(game_state.screen == GameStateScript.Screen.TITLE, "クレジット: K で閉じてタイトルに戻る")
	await _click(main.get_node("TitleScreen/CreditsButton"))
	_check(game_state.screen == GameStateScript.Screen.CREDITS, "クレジット: クレジットのボタンのタップで開く")
	await _click(main.get_node("CreditsScreen/CloseButton"))
	_check(game_state.screen == GameStateScript.Screen.TITLE, "クレジット: とじるボタンのタップでタイトルに戻る")


## 本編を最初から最後まで、case (MAIN_ENDING_CASES の 1 つ) の進め方で選択肢をキーで選んで (共通 bad の進め方では
## 何も押さずに時間切れで) 進め、case のエンディングに着くこと。ルートに入る周は、そのルートの最後の章の区切り
## (LAST_CHAPTERS) とその時点の好感度が保存されていること。共通 bad の周は章の区切りを通らないため、保存が変わらないこと
## (章の区切りの数はシナリオの形式として selfcheck が数える)。結果に通った選択肢がキーで選んだ数と時間切れの回数として
## 記録され、所要時間が見積もりの範囲に収まること。鳴る BGM が、ルートに入る周は共通パート → ルート → エンディング、
## 共通 bad の周は共通パート → エンディングの順に切り替わること
func _check_main_ending(game_state: Node, main: Control, case: Array, save_data: Node) -> void:
	var expected: String = case[0]
	var chapter_before: String = save_data.chapter
	var bgm_player: AudioStreamPlayer = main.get_node("Audio/Bgm")
	var heard: Array = []
	await _hold_keys([KEY_ENTER], 1)
	_record_bgm(bgm_player, heard)
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
		_record_bgm(bgm_player, heard)
		frames += 1
	await process_frame
	_record_bgm(bgm_player, heard)
	var expected_bgms: Array = (
		[SoundScript.BGM_COMMON, SoundScript.BGM_ENDING]
		if case[1].is_empty()
		else [SoundScript.BGM_COMMON, SoundScript.BGM_ROUTE, SoundScript.BGM_ENDING]
	)
	_check(
		heard == expected_bgms,
		(
			"本編の BGM: %s までの BGM が場面に合わせて切り替わる (%s)"
			% [expected, heard.map(func(bgm: AudioStream) -> String: return bgm.resource_path)]
		)
	)
	_check(
		(
			game_state.screen == GameStateScript.Screen.ENDING
			and game_state.current_line().get("ending") == expected
		),
		"本編: %s への進め方で着く (好感度 %s)" % [expected, game_state.affection]
	)
	_check(save_data.reached_endings.has(expected), "本編: %s が到達の記録に入る" % expected)
	var lines: Array = game_state.lines
	_check_last_chapter_saved(case, lines, save_data, chapter_before)
	var picked: Array[int] = []
	var estimated: Dictionary = ConversationScript.playthrough(
		lines,
		func(choice: Dictionary) -> int:
			picked.append(_pick_for_case(case, lines, lines.find(choice)))
			return picked.back()
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
	var chosen: int = picked.filter(
		func(pick: int) -> bool: return pick != ConversationScript.TIMEOUT
	).size()
	_check_result(game_state, main, chosen, picked.size() - chosen)
	var play_seconds: float = game_state.play_seconds
	_check(
		(
			play_seconds
			>= estimated["seconds"] - chosen * ConversationScript.CHOICE_SECONDS - SECONDS_EPSILON
			and play_seconds <= estimated["seconds"] + MAIN_SECONDS_TOLERANCE
		),
		(
			"本編: %s の結果の所要時間が見積もりの範囲に収まる (%.1f 秒 / 見積もり %.1f 秒)"
			% [expected, play_seconds, estimated["seconds"]]
		)
	)
	await _hold_keys([KEY_ENTER], 1)
	_check(game_state.screen == GameStateScript.Screen.TITLE, "本編: エンディングからタイトルに戻る")


## case の進め方で lines を最後まで進めた後の保存データ (save_data) の検証。ルートに入る周は、そのルートの最後の
## 章の区切り (LAST_CHAPTERS) と、そこまで同じ進め方で進めた時点の好感度が保存されている。共通 bad の周は章の区切りを
## 通らないため、周の前の章 (chapter_before) のまま
func _check_last_chapter_saved(
	case: Array, lines: Array, save_data: Node, chapter_before: String
) -> void:
	var expected: String = case[0]
	if case[1].is_empty():
		_check(
			save_data.chapter == chapter_before,
			"本編: %s では章の区切りを通らず、保存は変わらない (%s)" % [expected, save_data.chapter]
		)
		return
	var last_chapter: String = LAST_CHAPTERS[case[1]]
	var until_chapter: Array = lines.slice(0, ScenarioScript.chapter_index(lines, last_chapter) + 1)
	var at_chapter: Dictionary = ConversationScript.playthrough(
		until_chapter,
		func(choice: Dictionary) -> int:
			return _pick_for_case(case, until_chapter, until_chapter.find(choice))
	)
	_check(
		save_data.chapter == last_chapter and save_data.affection == at_chapter["affection"],
		(
			"本編: %s の最後の章の区切りと、その時点の好感度が保存されている (%s %s)"
			% [expected, save_data.chapter, save_data.affection]
		)
	)


## bgm_player が鳴らしている BGM が heard (鳴った BGM の順の一覧) の最後と違えば heard に足す。鳴っていなければ何もしない
func _record_bgm(bgm_player: AudioStreamPlayer, heard: Array) -> void:
	if bgm_player.playing and (heard.is_empty() or heard.back() != bgm_player.stream):
		heard.append(bgm_player.stream)


## main の BGM のノードが、BGM のバスで bgm を鳴らしている (bgm が null なら鳴っていない) こと
func _check_bgm(main: Control, bgm: AudioStream, label: String) -> void:
	var bgm_player: AudioStreamPlayer = main.get_node("Audio/Bgm")
	if bgm == null:
		_check(not bgm_player.playing, label)
		return
	_check(
		(
			bgm_player.playing
			and bgm_player.stream == bgm
			and bgm_player.bus == &"BGM"
			and is_equal_approx(bgm_player.volume_db, SoundScript.BGM_VOLUME_DB)
		),
		"%s (%s)" % [label, bgm_player.stream.resource_path if bgm_player.stream != null else "なし"]
	)


## main の event (GameState の signal の名前) の効果音のノードが、効果音のバスでその効果音を鳴らしていること
func _check_effect(main: Control, event: String, label: String) -> void:
	var effect_player: AudioStreamPlayer = main.get_node("Audio/" + event)
	_check(
		(
			effect_player.playing
			and effect_player.stream == SoundScript.EFFECTS[event]
			and effect_player.bus == &"SE"
			and is_equal_approx(effect_player.volume_db, SoundScript.EFFECT_VOLUME_DB)
		),
		label
	)


## until.call() が true になるまでフレームを待つ (WAIT_FRAME_LIMIT フレームで打ち切る)
func _wait_until(until: Callable) -> void:
	var frames: int = 0
	while not until.call() and frames < WAIT_FRAME_LIMIT:
		await process_frame
		frames += 1
