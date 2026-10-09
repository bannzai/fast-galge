extends Control
## メインシーン。GameState の画面に合わせてタイトル・会話・バックログ・エンディング・設定・クレジット・エンディング一覧の
## 表示を切り替え、毎フレーム会話の時間を進める。キー入力とタップ用のボタンを GameState の操作 (設定の音量は SaveData) に
## 写すだけで、会話の進行も音量も持たない (見た目の方向は documents/DIRECTION.md「デザインの方向」、背景と立ち絵の
## 決め方は scripts/stage.gd)。エンディングの画面では結果の画像 (SubViewport に置いた scenes/result_card.tscn の描画)
## を出し、共有のボタンで画像の保存と X の投稿画面を開く操作を行う。場面に合わせて BGM を切り替え、GameState が
## 知らせるきっかけで効果音を鳴らす (場面と BGM・きっかけと効果音の対応は scripts/sound.gd)。

## autoload の GameState のスクリプト。autoload 名の識別子で参照すると、--script で起動する scripts/dev/ の検証が
## autoload の登録前にこのスクリプトをコンパイルして失敗するため、ノードとして取る
const GameStateScript := preload("res://scripts/game_state.gd")
## シナリオの保存形式のキー
const ScenarioScript := preload("res://scripts/scenario.gd")
## 会話のルールの値と計算 (選択肢の制限時間、1 フレームで進める時間)
const ConversationScript := preload("res://scripts/conversation.gd")
## 背景と立ち絵の素材と、いま出すものの決め方
const StageScript := preload("res://scripts/stage.gd")
## 音量のバスと段階 (autoload の SaveData のスクリプト。GameState と同じ理由でノードとして取る)
const SaveDataScript := preload("res://scripts/save_data.gd")
## クレジット画面に出す素材の出典と、開くリンクの URL
const CreditsScript := preload("res://scripts/credits.gd")
## 結果の文面と X の投稿画面の URL の組み立て、結果の画像のファイル名
const ResultScript := preload("res://scripts/result.gd")
## 場面ごとの BGM と効果音の素材
const SoundScript := preload("res://scripts/sound.gd")
## 共有の操作の結果を知らせる文。デスクトップは画像の保存先と文面のコピー、それ以外 (iOS・Web) は画像がアプリの
## 保存領域にあることと写真に残す方法を案内する (プラグインなしの共有シートは無く、写真への保存は別 issue)
const SHARE_SAVED_TEXT: String = "画像を保存しました: %s"
const SHARE_SAVED_IN_APP_TEXT: String = "画像をアプリの保存領域に保存しました (この版では直接は取り出せません)"
const SHARE_SAVE_FAILED_TEXT: String = "画像を保存できませんでした (%s)"
const SHARE_COPIED_TEXT: String = "文面をコピーしました"
const SHARE_PHOTO_HINT_TEXT: String = "写真に残すには この画面のスクリーンショットを撮ってください"
const SHARE_OPENED_TEXT: String = "X の投稿画面を開きました"
const SHARE_OPEN_FAILED_TEXT: String = "X の投稿画面を開けませんでした (%s)"
## アプリの保存領域に置く結果の画像のパス (iOS・Web と、デスクトップでピクチャフォルダに書けない時)
const USER_IMAGE_PATH: String = "user://" + ResultScript.IMAGE_FILE_NAME
## 描画しない起動 (--headless) の DisplayServer の名前。結果の画像の保存は描画の完了を待てないため省く
const HEADLESS_DISPLAY_SERVER: String = "headless"
## 入力のアクションと、GameState に送る操作
const SCREEN_ACTIONS: Dictionary = {
	"confirm": GameStateScript.Command.CONFIRM,
	"backlog": GameStateScript.Command.BACKLOG,
	"continue": GameStateScript.Command.CONTINUE,
	"settings": GameStateScript.Command.SETTINGS,
	"credits": GameStateScript.Command.CREDITS,
	"ending_list": GameStateScript.Command.ENDINGS,
}
## ゆっくりモードを切り替える入力のアクション
const SLOW_MODE_ACTION: String = "slow_mode"
## 選択肢を選ぶ入力のアクション (並び順が選択肢の番号)
const CHOICE_ACTIONS: Array[String] = ["choice_1", "choice_2", "choice_3"]
## エンディングの画面で共有する入力のアクション (キーボードでも共有できるように。project.godot の入力の share)
const SHARE_ACTION: String = "share"

## 起動検証 (make check) が確認する起動の印
const BOOT_MESSAGE: String = "fast-galge boot"

## URL を開く関数 (共有の X の投稿画面と、クレジット画面のリンク)、文面をクリップボードに書く関数、デスクトップで
## 画像を保存するフォルダを返す関数。既定は OS と DisplayServer のもので、検証 (scripts/dev/integration.gd・
## screenshot.gd) が、runner でブラウザを開かず・開発者のフォルダに書かずに共有とリンクの流れを通すために差し替える
var url_opener: Callable = Callable(OS, "shell_open")
var clipboard_writer: Callable = Callable(DisplayServer, "clipboard_set")
var pictures_dir_provider: Callable = func() -> String:
	return OS.get_system_dir(OS.SYSTEM_DIR_PICTURES)

## タイトルの画面、一枚絵、会話を最初から始めるボタン、保存した章から再開するボタン (途中の保存がある間だけ出す)、
## エンディング一覧を開くボタン、ゆっくりモードを切り替えるボタン (クリア済みの間だけ出す)
@onready var title_screen: Control = $TitleScreen
@onready var title_art: TextureRect = $TitleScreen/TitleArt
@onready var start_button: Button = $TitleScreen/StartButton
@onready var continue_button: Button = $TitleScreen/ContinueButton
@onready var endings_button: Button = $TitleScreen/EndingsButton
@onready var slow_mode_button: Button = $TitleScreen/SlowModeButton
## 会話中の画面と、ゆっくりモードでメッセージを送るタップを受ける、画面全体の透明なボタン
## (立ち絵とメッセージウィンドウより手前、ログと選択肢のボタンより奥に置く。ホバー・押下の見た目も描かないよう
## self_modulate の不透明度を 0 にしている)
@onready var conversation_screen: Control = $ConversationScreen
@onready var send_area: Button = $ConversationScreen/SendArea
## いまの場面の背景、立ち絵、立ち絵の後ろの流線 (立ち絵が流線を出すヒロインの間だけ出す)
@onready var scene_background: TextureRect = $ConversationScreen/SceneBackground
@onready var portrait: TextureRect = $ConversationScreen/Portrait
@onready var speed_lines: TextureRect = $ConversationScreen/SpeedLines
## メッセージウィンドウの名札 (話者がいる間だけ出す)、話者名、本文
@onready var name_tag: Control = $ConversationScreen/MessageWindow/NameTag
@onready var speaker_label: Label = $ConversationScreen/MessageWindow/Speaker
@onready var message_label: Label = $ConversationScreen/MessageWindow/Message
## バックログを開くボタン
@onready var backlog_button: Button = $ConversationScreen/BacklogButton
## 選択肢の表示 (選択肢の行で止まっている間だけ出す)、残り時間のバー、選択肢のボタン (並び順が選択肢の番号)
@onready var choice_panel: Control = $ConversationScreen/Choices
@onready var time_bar: ProgressBar = $ConversationScreen/Choices/TimeBar
@onready var choice_buttons: Array[Button] = [
	$ConversationScreen/Choices/Choice1 as Button,
	$ConversationScreen/Choices/Choice2 as Button,
	$ConversationScreen/Choices/Choice3 as Button,
]
## バックログの画面、一覧のスクロール、一覧の本文、閉じるボタン
@onready var backlog_screen: Control = $BacklogScreen
@onready var backlog_scroll: ScrollContainer = $BacklogScreen/Scroll
@onready var backlog_label: Label = $BacklogScreen/Scroll/Entries
@onready var close_button: Button = $BacklogScreen/CloseButton
## エンディングの画面、エンディング名、一言、タイトルへ戻るボタン
@onready var ending_screen: Control = $EndingScreen
@onready var ending_name_label: Label = $EndingScreen/Name
@onready var ending_summary_label: Label = $EndingScreen/Summary
@onready var title_button: Button = $EndingScreen/TitleButton
## 設定の画面と、バスの名前 (SaveDataScript.VOLUME_BUSES) ごとの音量の行 (下げるボタン Down・段階のバー Level・
## 上げるボタン Up を持つ。ノード名がバスの名前) を並べる親
@onready var settings_screen: Control = $SettingsScreen
@onready var volume_rows: Control = $SettingsScreen/Volumes
## クレジットの画面と、素材の出典の一覧
@onready var credits_screen: Control = $CreditsScreen
@onready var credits_label: Label = $CreditsScreen/Scroll/Entries
## 結果の画像を描く SubViewport とその中の結果のシーン、画像を画面に出す TextureRect、共有のボタン、共有の操作の結果
@onready var result_viewport: SubViewport = $EndingScreen/ResultViewport
@onready var result_card: Control = $EndingScreen/ResultViewport/ResultCard
@onready var result_image: TextureRect = $EndingScreen/ResultImage
@onready var share_button: Button = $EndingScreen/ShareButton
@onready var share_status_label: Label = $EndingScreen/ShareStatus
## エンディング一覧の画面、見たエンディングの数、一覧の本文、閉じるボタン
@onready var endings_screen: Control = $EndingsScreen
@onready var endings_count_label: Label = $EndingsScreen/Count
@onready var endings_label: Label = $EndingsScreen/Entries
@onready var endings_close_button: Button = $EndingsScreen/CloseButton
## 場面ごとの BGM を鳴らすノード (BGM バス)。効果音のノード (SE バス) は同じ Audio の下の、GameState の signal と
## 同じ名前のノード
@onready var bgm_player: AudioStreamPlayer = $Audio/Bgm


## 起動の印を出し、場面で変わらない絵を置き、効果音を GameState の signal につなぎ、タップ用のボタンを GameState の
## 操作・音量の変更・URL を開く処理につなぎ、クレジットの一覧を読み、GameState の画面に合わせた表示にする
func _ready() -> void:
	print(BOOT_MESSAGE)
	title_art.texture = load(StageScript.TITLE_PATH)
	speed_lines.texture = load(StageScript.SPEED_LINES_PATH)
	bgm_player.volume_db = SoundScript.BGM_VOLUME_DB
	var game_state: Node = _game_state()
	for event: String in SoundScript.EFFECTS:
		var effect_player: AudioStreamPlayer = $Audio.get_node(event)
		effect_player.stream = SoundScript.EFFECTS[event]
		effect_player.volume_db = SoundScript.EFFECT_VOLUME_DB
		if game_state != null:
			game_state.connect(event, effect_player.play)
	start_button.pressed.connect(_apply.bind(GameStateScript.Command.CONFIRM))
	continue_button.pressed.connect(_apply.bind(GameStateScript.Command.CONTINUE))
	endings_button.pressed.connect(_apply.bind(GameStateScript.Command.ENDINGS))
	slow_mode_button.pressed.connect(_toggle_slow_mode)
	send_area.pressed.connect(_apply.bind(GameStateScript.Command.CONFIRM))
	backlog_button.pressed.connect(_apply.bind(GameStateScript.Command.BACKLOG))
	close_button.pressed.connect(_apply.bind(GameStateScript.Command.BACKLOG))
	title_button.pressed.connect(_apply.bind(GameStateScript.Command.CONFIRM))
	endings_close_button.pressed.connect(_apply.bind(GameStateScript.Command.ENDINGS))
	share_button.pressed.connect(_share)
	for option_index: int in range(choice_buttons.size()):
		choice_buttons[option_index].pressed.connect(_choose.bind(option_index))
	$TitleScreen/SettingsButton.pressed.connect(_apply.bind(GameStateScript.Command.SETTINGS))
	$SettingsScreen/CloseButton.pressed.connect(_apply.bind(GameStateScript.Command.SETTINGS))
	for bus: String in SaveDataScript.VOLUME_BUSES:
		var row: Control = volume_rows.get_node(bus)
		row.get_node("Down").pressed.connect(_change_volume.bind(bus, -1))
		row.get_node("Up").pressed.connect(_change_volume.bind(bus, 1))
		row.get_node("Level").max_value = SaveDataScript.MAX_VOLUME
	$TitleScreen/CreditsButton.pressed.connect(_apply.bind(GameStateScript.Command.CREDITS))
	$CreditsScreen/CloseButton.pressed.connect(_apply.bind(GameStateScript.Command.CREDITS))
	$CreditsScreen/TermsButton.pressed.connect(_open.bind(CreditsScript.TERMS_URL))
	$CreditsScreen/PrivacyButton.pressed.connect(_open.bind(CreditsScript.PRIVACY_URL))
	$CreditsScreen/SupportButton.pressed.connect(_open.bind(CreditsScript.SUPPORT_URL))
	$CreditsScreen/MailButton.pressed.connect(_open.bind(CreditsScript.MAIL_URL))
	credits_label.text = CreditsScript.load_text()
	result_image.texture = result_viewport.get_texture()
	_refresh()


## 会話の時間を 1 フレームぶん進め、表示を更新する (文字送りはここでだけ進み、入力では進まない)
func _process(delta: float) -> void:
	var game_state: Node = _game_state()
	if game_state != null:
		game_state.advance(ConversationScript.frame_seconds(delta))
	_refresh()


## 入力のアクションを GameState の操作に写す。共有のアクションはエンディングの画面でだけ共有のボタンと同じ操作をする
func _unhandled_input(event: InputEvent) -> void:
	for action: String in SCREEN_ACTIONS:
		if event.is_action_pressed(action):
			_apply(SCREEN_ACTIONS[action])
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed(SLOW_MODE_ACTION):
		_toggle_slow_mode()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(SHARE_ACTION) and ending_screen.visible:
		_share()
		get_viewport().set_input_as_handled()
		return
	for option_index: int in range(CHOICE_ACTIONS.size()):
		if event.is_action_pressed(CHOICE_ACTIONS[option_index]):
			_choose(option_index)
			get_viewport().set_input_as_handled()
			return


## autoload の GameState。登録されていない起動 (シーン単体の読み込み) では null
func _game_state() -> Node:
	return get_tree().root.get_node_or_null("GameState")


## command を GameState に送り、画面が移ったら表示を更新する。バックログを開いた時は一覧を最新の行まで送り、
## エンディング一覧を開いた時は一覧を作る。画面が移ったら前の共有の操作の結果は消す。会話中の決定 (画面は移らない) は
## ゆっくりモードのメッセージ送りにする
func _apply(command: GameStateScript.Command) -> void:
	var game_state: Node = _game_state()
	if game_state == null:
		return
	if not game_state.apply(command):
		if command == GameStateScript.Command.CONFIRM and game_state.send():
			_refresh()
		return
	share_status_label.text = ""
	if game_state.screen == GameStateScript.Screen.ENDINGS:
		_fill_endings(game_state.ending_list())
	_refresh()
	if game_state.screen == GameStateScript.Screen.BACKLOG:
		_scroll_backlog_to_end()


## タイトルでゆっくりモードを切り替え、表示を更新する
func _toggle_slow_mode() -> void:
	var game_state: Node = _game_state()
	if game_state != null and game_state.toggle_slow_mode():
		_refresh()


## option_index 番目 (0 始まり) の選択肢を選び、表示を更新する
func _choose(option_index: int) -> void:
	var game_state: Node = _game_state()
	if game_state != null and game_state.choose(option_index):
		_refresh()


## autoload の SaveData。登録されていない起動 (シーン単体の読み込み) では null
func _save_data() -> Node:
	return get_tree().root.get_node_or_null("SaveData")


## bus のバスの音量を step 段だけ変えて (SaveData が保存とバスへの反映をする)、表示を更新する
func _change_volume(bus: String, step: int) -> void:
	var save_data: Node = _save_data()
	if save_data == null:
		return
	save_data.set_volume(bus, save_data.volumes[bus] + step)
	_refresh()


## url を url_opener で開く。開けなかった時はエラーを出す
func _open(url: String) -> void:
	var status: Error = url_opener.call(url)
	if status != OK:
		push_error("URL を開けない: %s (%s)" % [url, error_string(status)])


## GameState の画面に合わせて、画面ごとの表示を切り替えて中身を更新する
func _refresh() -> void:
	var game_state: Node = _game_state()
	var screen: GameStateScript.Screen = (
		game_state.screen if game_state != null else GameStateScript.Screen.TITLE
	)
	title_screen.visible = screen == GameStateScript.Screen.TITLE
	conversation_screen.visible = screen == GameStateScript.Screen.PLAYING
	backlog_screen.visible = screen == GameStateScript.Screen.BACKLOG
	ending_screen.visible = screen == GameStateScript.Screen.ENDING
	settings_screen.visible = screen == GameStateScript.Screen.SETTINGS
	credits_screen.visible = screen == GameStateScript.Screen.CREDITS
	endings_screen.visible = screen == GameStateScript.Screen.ENDINGS
	_refresh_bgm(
		SoundScript.bgm_for(screen, game_state.scenario_path() if game_state != null else "")
	)
	if settings_screen.visible:
		_refresh_volumes()
	if title_screen.visible:
		continue_button.visible = game_state != null and game_state.can_continue()
		slow_mode_button.visible = game_state != null and game_state.can_select_slow_mode()
		if slow_mode_button.visible:
			slow_mode_button.text = (
				"ゆっくりモード %s [Y]" % ("ON" if game_state.slow_mode else "OFF")
			)
	if conversation_screen.visible:
		_refresh_conversation(game_state)
	if backlog_screen.visible:
		backlog_label.text = "\n".join(PackedStringArray(game_state.backlog.map(_backlog_text)))
	if ending_screen.visible:
		ending_name_label.text = game_state.current_line().get(ScenarioScript.NAME, "")
		ending_summary_label.text = game_state.current_line().get(ScenarioScript.SUMMARY, "")
		result_card.show_result(game_state.result())


## いまの結果を文面にして X の投稿画面を開く URL (共有のボタンが開く URL。検証が形を確かめるため副作用なし)
func share_url() -> String:
	var game_state: Node = _game_state()
	var result: Dictionary = game_state.result() if game_state != null else {}
	return ResultScript.share_url(ResultScript.share_text(result))


## 結果の画像 (SubViewport の描画) を path に PNG で保存する。描画が反映されるまで 1 フレームと描画の完了を待つ。
## headless (描画なし) では描画の完了が来ないため、1 フレーム待った後に ERR_UNAVAILABLE を返す。
## 同じ path には同じ画像を上書きするため冪等
func save_result_image(path: String) -> Error:
	await get_tree().process_frame
	if DisplayServer.get_name() == HEADLESS_DISPLAY_SERVER:
		return ERR_UNAVAILABLE
	await RenderingServer.frame_post_draw
	var image: Image = result_viewport.get_texture().get_image()
	if image == null or image.is_empty():
		return ERR_UNAVAILABLE
	return image.save_png(path)


## 共有のボタンの操作。結果の画像を保存し (デスクトップはピクチャフォルダ。書けない時は user://)、デスクトップでは
## 文面をクリップボードにコピーし、X の投稿画面を開く。保存とコピーの結果は投稿画面を開く前に表示に出す
## (iOS は X に切り替わるため、戻る前に読めるように)。保存を待つ間はボタンを押せなくし、待つ間にエンディングの画面を
## 離れたら投稿画面を開かず表示もしない。保存先・投稿画面の表示・クリップボードを書き換えるため冪等ではない
func _share() -> void:
	var game_state: Node = _game_state()
	if game_state == null or share_button.disabled:
		return
	share_button.disabled = true
	var text: String = ResultScript.share_text(game_state.result())
	var on_desktop: bool = OS.has_feature("pc")
	var image_path: String = _pictures_image_path() if on_desktop else USER_IMAGE_PATH
	var saved: Error = await save_result_image(image_path)
	if saved != OK and image_path != USER_IMAGE_PATH:
		image_path = USER_IMAGE_PATH
		saved = await save_result_image(image_path)
	share_button.disabled = false
	if game_state.screen != GameStateScript.Screen.ENDING:
		return
	var messages: PackedStringArray = []
	if saved == OK and on_desktop:
		messages.append(SHARE_SAVED_TEXT % ProjectSettings.globalize_path(image_path))
	elif saved == OK:
		messages.append(SHARE_SAVED_IN_APP_TEXT)
	else:
		messages.append(SHARE_SAVE_FAILED_TEXT % error_string(saved))
	if on_desktop:
		clipboard_writer.call(text)
		messages.append(SHARE_COPIED_TEXT)
	else:
		messages.append(SHARE_PHOTO_HINT_TEXT)
	share_status_label.text = "\n".join(messages)
	var opened: Error = url_opener.call(ResultScript.share_url(text))
	if opened == OK:
		messages.append(SHARE_OPENED_TEXT)
	else:
		messages.append(SHARE_OPEN_FAILED_TEXT % error_string(opened))
	share_status_label.text = "\n".join(messages)


## デスクトップで結果の画像を保存するパス (pictures_dir_provider が返すユーザーのピクチャフォルダ)。フォルダが取れない時
## (空、Linux で xdg-user-dir が失敗した時の "."、存在しないフォルダ) は user:// にして、書けないパスへの保存で
## ERROR を出さない
func _pictures_image_path() -> String:
	var pictures_dir: String = pictures_dir_provider.call()
	if (
		pictures_dir.is_empty()
		or pictures_dir == "."
		or not DirAccess.dir_exists_absolute(pictures_dir)
	):
		return USER_IMAGE_PATH
	return pictures_dir.path_join(ResultScript.IMAGE_FILE_NAME)


## 会話中の画面を game_state の会話の進行に合わせる。メッセージウィンドウにはバックログの最新の行 (いま流れている
## メッセージか、直前に選んだ選択肢) を、ゆっくりモードでは出し終えた文字まで出し、背景と立ち絵はバックログから決め、
## 選択肢で止まっている間は選択肢と残り時間 (ゆっくりモードでは制限時間が無いため出さない) を出す
func _refresh_conversation(game_state: Node) -> void:
	var backlog: Array = game_state.backlog
	var shown: Dictionary = backlog.back() if not backlog.is_empty() else {}
	speaker_label.text = shown.get(ScenarioScript.SPEAKER, "")
	name_tag.visible = not speaker_label.text.is_empty()
	message_label.text = shown.get(ScenarioScript.TEXT, "")
	message_label.visible_ratio = game_state.revealed_ratio()
	var background: String = StageScript.shown_background(backlog)
	_show_texture(
		scene_background, "" if background.is_empty() else StageScript.background_path(background)
	)
	var portrait_line: Dictionary = StageScript.shown_portrait(backlog)
	_show_texture(
		portrait, "" if portrait_line.is_empty() else StageScript.portrait_path(portrait_line)
	)
	speed_lines.visible = (
		not portrait_line.is_empty() and StageScript.has_speed_lines(portrait_line)
	)
	var options: Array = game_state.current_line().get(ScenarioScript.CHOICES, [])
	choice_panel.visible = not options.is_empty()
	time_bar.visible = not game_state.slow_mode
	time_bar.value = 1.0 - game_state.elapsed / ConversationScript.CHOICE_SECONDS
	for option_index: int in range(choice_buttons.size()):
		choice_buttons[option_index].visible = option_index < options.size()
		if option_index < options.size():
			choice_buttons[option_index].text = (
				"%d. %s" % [option_index + 1, options[option_index][ScenarioScript.TEXT]]
			)


## BGM を bgm (null なら止める) にする。毎フレーム呼ぶため、曲が変わった時だけ最初から鳴らし直し、同じ曲は途切れさせない
func _refresh_bgm(bgm: AudioStream) -> void:
	if bgm == null:
		if bgm_player.playing:
			bgm_player.stop()
		return
	if bgm_player.stream != bgm or not bgm_player.playing:
		bgm_player.stream = bgm
		bgm_player.play()


## texture_rect に path の素材を出し、path が空なら隠す。冪等で、毎フレーム呼んでも同じ素材を読み込み直さない
func _show_texture(texture_rect: TextureRect, path: String) -> void:
	texture_rect.visible = not path.is_empty()
	if texture_rect.visible and (
		texture_rect.texture == null or texture_rect.texture.resource_path != path
	):
		texture_rect.texture = load(path)


## 設定の画面の音量の行を、SaveData が持つバスごとの音量の段階に合わせる
func _refresh_volumes() -> void:
	var save_data: Node = _save_data()
	if save_data == null:
		return
	for bus: String in SaveDataScript.VOLUME_BUSES:
		volume_rows.get_node(bus).get_node("Level").value = save_data.volumes[bus]


## バックログの 1 行 (entry) を一覧に出す文にする。話者がいれば「」で囲み、地の文はそのまま出す
func _backlog_text(entry: Dictionary) -> String:
	var speaker: String = entry.get(ScenarioScript.SPEAKER, "")
	if speaker.is_empty():
		return entry[ScenarioScript.TEXT]
	return "%s「%s」" % [speaker, entry[ScenarioScript.TEXT]]


## エンディング一覧の画面に、names (エンディングの名前の一覧。未到達は GameState の UNKNOWN_ENDING_NAME) を番号付きで
## 並べ、見たエンディングの数を出す
func _fill_endings(names: Array[String]) -> void:
	var entries: PackedStringArray = PackedStringArray()
	for index: int in range(names.size()):
		entries.append("%d. %s" % [index + 1, names[index]])
	endings_label.text = "\n".join(entries)
	var reached: int = names.size() - names.count(GameStateScript.UNKNOWN_ENDING_NAME)
	endings_count_label.text = "見たエンディング %d / %d" % [reached, names.size()]


## バックログの一覧を最新の行 (末尾) まで送る。一覧の高さは本文を入れた後のレイアウトで決まるため、
## レイアウトが済むまで 2 フレーム待つ
func _scroll_backlog_to_end() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	backlog_scroll.scroll_vertical = int(backlog_scroll.get_v_scroll_bar().max_value)
