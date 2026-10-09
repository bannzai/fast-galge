extends Control
## メインシーン。GameState の画面に合わせてタイトル・会話・バックログ・エンディングの表示を切り替え、毎フレーム
## 会話の時間を進める。キー入力とタップ用のボタンを GameState の操作に写すだけで、会話の進行は持たない
## (見た目は仮の色面。関門 2 のデザインの反映で作り直す)。エンディングの画面では結果の画像 (SubViewport に置いた
## scenes/result_card.tscn の描画) を出し、共有のボタンで画像の保存と X の投稿画面を開く操作を行う。

## autoload の GameState のスクリプト。autoload 名の識別子で参照すると、--script で起動する scripts/dev/ の検証が
## autoload の登録前にこのスクリプトをコンパイルして失敗するため、ノードとして取る
const GameStateScript := preload("res://scripts/game_state.gd")
## シナリオの保存形式のキー
const ScenarioScript := preload("res://scripts/scenario.gd")
## 会話のルールの値と計算 (選択肢の制限時間、1 フレームで進める時間)
const ConversationScript := preload("res://scripts/conversation.gd")
## 結果の文面と X の投稿画面の URL の組み立て、結果の画像のファイル名
const ResultScript := preload("res://scripts/result.gd")
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
}
## 選択肢を選ぶ入力のアクション (並び順が選択肢の番号)
const CHOICE_ACTIONS: Array[String] = ["choice_1", "choice_2", "choice_3"]
## エンディングの画面で共有する入力のアクション (キーボードでも共有できるように。project.godot の入力の share)
const SHARE_ACTION: String = "share"

## 起動検証 (make check) が確認する起動の印
const BOOT_MESSAGE: String = "fast-galge boot"

## 共有で X の投稿画面の URL を開く関数、文面をクリップボードに書く関数、デスクトップで画像を保存するフォルダを返す
## 関数。既定は OS と DisplayServer のもので、検証 (scripts/dev/integration.gd・screenshot.gd) が、runner でブラウザを
## 開かず・開発者のフォルダに書かずに共有の流れを通すために差し替える
var url_opener: Callable = Callable(OS, "shell_open")
var clipboard_writer: Callable = Callable(DisplayServer, "clipboard_set")
var pictures_dir_provider: Callable = func() -> String:
	return OS.get_system_dir(OS.SYSTEM_DIR_PICTURES)

## タイトルの画面、会話を最初から始めるボタン、保存した章から再開するボタン (途中の保存がある間だけ出す)
@onready var title_screen: Control = $TitleScreen
@onready var start_button: Button = $TitleScreen/StartButton
@onready var continue_button: Button = $TitleScreen/ContinueButton
## 会話中の画面
@onready var conversation_screen: Control = $ConversationScreen
## 立ち絵の代わりの色面と、表情の名前を出すラベル (表情を持つメッセージの間だけ出す)
@onready var portrait: ColorRect = $ConversationScreen/Portrait
@onready var expression_label: Label = $ConversationScreen/Portrait/Expression
## メッセージウィンドウの話者名と本文
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
## 結果の画像を描く SubViewport とその中の結果のシーン、画像を画面に出す TextureRect、共有のボタン、共有の操作の結果
@onready var result_viewport: SubViewport = $EndingScreen/ResultViewport
@onready var result_card: Control = $EndingScreen/ResultViewport/ResultCard
@onready var result_image: TextureRect = $EndingScreen/ResultImage
@onready var share_button: Button = $EndingScreen/ShareButton
@onready var share_status_label: Label = $EndingScreen/ShareStatus


## 起動の印を出し、タップ用のボタンを GameState の操作につなぎ、GameState の画面に合わせた表示にする
func _ready() -> void:
	print(BOOT_MESSAGE)
	start_button.pressed.connect(_apply.bind(GameStateScript.Command.CONFIRM))
	continue_button.pressed.connect(_apply.bind(GameStateScript.Command.CONTINUE))
	backlog_button.pressed.connect(_apply.bind(GameStateScript.Command.BACKLOG))
	close_button.pressed.connect(_apply.bind(GameStateScript.Command.BACKLOG))
	title_button.pressed.connect(_apply.bind(GameStateScript.Command.CONFIRM))
	share_button.pressed.connect(_share)
	for option_index: int in range(choice_buttons.size()):
		choice_buttons[option_index].pressed.connect(_choose.bind(option_index))
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


## command を GameState に送り、画面が移ったら表示を更新する。バックログを開いた時は一覧を最新の行まで送る。
## 画面が移ったら前の共有の操作の結果は消す
func _apply(command: GameStateScript.Command) -> void:
	var game_state: Node = _game_state()
	if game_state == null or not game_state.apply(command):
		return
	share_status_label.text = ""
	_refresh()
	if game_state.screen == GameStateScript.Screen.BACKLOG:
		_scroll_backlog_to_end()


## option_index 番目 (0 始まり) の選択肢を選び、表示を更新する
func _choose(option_index: int) -> void:
	var game_state: Node = _game_state()
	if game_state != null and game_state.choose(option_index):
		_refresh()


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
	if title_screen.visible:
		continue_button.visible = game_state != null and game_state.can_continue()
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
## メッセージか、直前に選んだ選択肢) を出し、選択肢で止まっている間は選択肢と残り時間を出す
func _refresh_conversation(game_state: Node) -> void:
	var backlog: Array = game_state.backlog
	var shown: Dictionary = backlog.back() if not backlog.is_empty() else {}
	speaker_label.text = shown.get(ScenarioScript.SPEAKER, "")
	message_label.text = shown.get(ScenarioScript.TEXT, "")
	portrait.visible = shown.has(ScenarioScript.EXPRESSION)
	expression_label.text = shown.get(ScenarioScript.EXPRESSION, "")
	var options: Array = game_state.current_line().get(ScenarioScript.CHOICES, [])
	choice_panel.visible = not options.is_empty()
	time_bar.value = 1.0 - game_state.elapsed / ConversationScript.CHOICE_SECONDS
	for option_index: int in range(choice_buttons.size()):
		choice_buttons[option_index].visible = option_index < options.size()
		if option_index < options.size():
			choice_buttons[option_index].text = (
				"%d. %s" % [option_index + 1, options[option_index][ScenarioScript.TEXT]]
			)


## バックログの 1 行 (entry) を一覧に出す文にする。話者がいれば「」で囲み、地の文はそのまま出す
func _backlog_text(entry: Dictionary) -> String:
	var speaker: String = entry.get(ScenarioScript.SPEAKER, "")
	if speaker.is_empty():
		return entry[ScenarioScript.TEXT]
	return "%s「%s」" % [speaker, entry[ScenarioScript.TEXT]]


## バックログの一覧を最新の行 (末尾) まで送る。一覧の高さは本文を入れた後のレイアウトで決まるため、
## レイアウトが済むまで 2 フレーム待つ
func _scroll_backlog_to_end() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	backlog_scroll.scroll_vertical = int(backlog_scroll.get_v_scroll_bar().max_value)
