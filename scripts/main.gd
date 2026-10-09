extends Control
## メインシーン。GameState の画面に合わせてタイトル・会話・バックログ・エンディング・設定・クレジットの表示を
## 切り替え、毎フレーム会話の時間を進める。キー入力とタップ用のボタンを GameState の操作 (設定の音量は SaveData) に
## 写すだけで、会話の進行も音量も持たない (見た目は仮の色面。関門 2 のデザインの反映で作り直す)。

## autoload の GameState のスクリプト。autoload 名の識別子で参照すると、--script で起動する scripts/dev/ の検証が
## autoload の登録前にこのスクリプトをコンパイルして失敗するため、ノードとして取る
const GameStateScript := preload("res://scripts/game_state.gd")
## シナリオの保存形式のキー
const ScenarioScript := preload("res://scripts/scenario.gd")
## 会話のルールの値と計算 (選択肢の制限時間、1 フレームで進める時間)
const ConversationScript := preload("res://scripts/conversation.gd")
## 音量のバスと段階 (autoload の SaveData のスクリプト。GameState と同じ理由でノードとして取る)
const SaveDataScript := preload("res://scripts/save_data.gd")
## クレジット画面に出す素材の出典と、開くリンクの URL
const CreditsScript := preload("res://scripts/credits.gd")
## 入力のアクションと、GameState に送る操作
const SCREEN_ACTIONS: Dictionary = {
	"confirm": GameStateScript.Command.CONFIRM,
	"backlog": GameStateScript.Command.BACKLOG,
	"continue": GameStateScript.Command.CONTINUE,
	"settings": GameStateScript.Command.SETTINGS,
	"credits": GameStateScript.Command.CREDITS,
}
## 選択肢を選ぶ入力のアクション (並び順が選択肢の番号)
const CHOICE_ACTIONS: Array[String] = ["choice_1", "choice_2", "choice_3"]

## 起動検証 (make check) が確認する起動の印
const BOOT_MESSAGE: String = "fast-galge boot"

## URL を開く処理 (引数は URL、戻り値は Error)。検証 (scripts/dev/integration.gd) がブラウザを開かずに、開こうとした
## URL を記録する処理に差し替える
var open_url: Callable = Callable(OS, "shell_open")

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
## 設定の画面と、バスの名前 (SaveDataScript.VOLUME_BUSES) ごとの音量の行 (下げるボタン Down・段階のバー Level・
## 上げるボタン Up を持つ。ノード名がバスの名前) を並べる親
@onready var settings_screen: Control = $SettingsScreen
@onready var volume_rows: Control = $SettingsScreen/Volumes
## クレジットの画面と、素材の出典の一覧
@onready var credits_screen: Control = $CreditsScreen
@onready var credits_label: Label = $CreditsScreen/Scroll/Entries


## 起動の印を出し、タップ用のボタンを GameState の操作・音量の変更・URL を開く処理につなぎ、クレジットの一覧を読み、
## GameState の画面に合わせた表示にする
func _ready() -> void:
	print(BOOT_MESSAGE)
	start_button.pressed.connect(_apply.bind(GameStateScript.Command.CONFIRM))
	continue_button.pressed.connect(_apply.bind(GameStateScript.Command.CONTINUE))
	backlog_button.pressed.connect(_apply.bind(GameStateScript.Command.BACKLOG))
	close_button.pressed.connect(_apply.bind(GameStateScript.Command.BACKLOG))
	title_button.pressed.connect(_apply.bind(GameStateScript.Command.CONFIRM))
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
	_refresh()


## 会話の時間を 1 フレームぶん進め、表示を更新する (文字送りはここでだけ進み、入力では進まない)
func _process(delta: float) -> void:
	var game_state: Node = _game_state()
	if game_state != null:
		game_state.advance(ConversationScript.frame_seconds(delta))
	_refresh()


## 入力のアクションを GameState の操作に写す
func _unhandled_input(event: InputEvent) -> void:
	for action: String in SCREEN_ACTIONS:
		if event.is_action_pressed(action):
			_apply(SCREEN_ACTIONS[action])
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


## command を GameState に送り、画面が移ったら表示を更新する。バックログを開いた時は一覧を最新の行まで送る
func _apply(command: GameStateScript.Command) -> void:
	var game_state: Node = _game_state()
	if game_state == null or not game_state.apply(command):
		return
	_refresh()
	if game_state.screen == GameStateScript.Screen.BACKLOG:
		_scroll_backlog_to_end()


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


## url を open_url で開く。開けなかった時はエラーを出す
func _open(url: String) -> void:
	var status: Error = open_url.call(url)
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
	if settings_screen.visible:
		_refresh_volumes()
	if title_screen.visible:
		continue_button.visible = game_state != null and game_state.can_continue()
	if conversation_screen.visible:
		_refresh_conversation(game_state)
	if backlog_screen.visible:
		backlog_label.text = "\n".join(PackedStringArray(game_state.backlog.map(_backlog_text)))
	if ending_screen.visible:
		ending_name_label.text = game_state.current_line().get(ScenarioScript.NAME, "")
		ending_summary_label.text = game_state.current_line().get(ScenarioScript.SUMMARY, "")


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


## バックログの一覧を最新の行 (末尾) まで送る。一覧の高さは本文を入れた後のレイアウトで決まるため、
## レイアウトが済むまで 2 フレーム待つ
func _scroll_backlog_to_end() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	backlog_scroll.scroll_vertical = int(backlog_scroll.get_v_scroll_bar().max_value)
