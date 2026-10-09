extends Control
## メインシーン。GameState の画面に合わせてタイトル・会話・バックログ・エンディングの表示を切り替え、毎フレーム
## 会話の時間を進める。キー入力とタップ用のボタンを GameState の操作に写すだけで、会話の進行は持たない
## (見た目の方向は documents/DIRECTION.md「デザインの方向」、背景と立ち絵の決め方は scripts/stage.gd)。

## autoload の GameState のスクリプト。autoload 名の識別子で参照すると、--script で起動する scripts/dev/ の検証が
## autoload の登録前にこのスクリプトをコンパイルして失敗するため、ノードとして取る
const GameStateScript := preload("res://scripts/game_state.gd")
## シナリオの保存形式のキー
const ScenarioScript := preload("res://scripts/scenario.gd")
## 会話のルールの値と計算 (選択肢の制限時間、1 フレームで進める時間)
const ConversationScript := preload("res://scripts/conversation.gd")
## 背景と立ち絵の素材と、いま出すものの決め方
const StageScript := preload("res://scripts/stage.gd")
## 入力のアクションと、GameState に送る操作
const SCREEN_ACTIONS: Dictionary = {
	"confirm": GameStateScript.Command.CONFIRM,
	"backlog": GameStateScript.Command.BACKLOG,
}
## 選択肢を選ぶ入力のアクション (並び順が選択肢の番号)
const CHOICE_ACTIONS: Array[String] = ["choice_1", "choice_2", "choice_3"]

## 起動検証 (make check) が確認する起動の印
const BOOT_MESSAGE: String = "fast-galge boot"

## タイトルの画面、一枚絵、会話を始めるボタン
@onready var title_screen: Control = $TitleScreen
@onready var title_art: TextureRect = $TitleScreen/TitleArt
@onready var start_button: Button = $TitleScreen/StartButton
## 会話中の画面
@onready var conversation_screen: Control = $ConversationScreen
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


## 起動の印を出し、場面で変わらない絵を置き、タップ用のボタンを GameState の操作につなぎ、GameState の画面に合わせた
## 表示にする
func _ready() -> void:
	print(BOOT_MESSAGE)
	title_art.texture = load(StageScript.TITLE_PATH)
	speed_lines.texture = load(StageScript.SPEED_LINES_PATH)
	start_button.pressed.connect(_apply.bind(GameStateScript.Command.CONFIRM))
	backlog_button.pressed.connect(_apply.bind(GameStateScript.Command.BACKLOG))
	close_button.pressed.connect(_apply.bind(GameStateScript.Command.BACKLOG))
	title_button.pressed.connect(_apply.bind(GameStateScript.Command.CONFIRM))
	for option_index: int in range(choice_buttons.size()):
		choice_buttons[option_index].pressed.connect(_choose.bind(option_index))
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
	if conversation_screen.visible:
		_refresh_conversation(game_state)
	if backlog_screen.visible:
		backlog_label.text = "\n".join(PackedStringArray(game_state.backlog.map(_backlog_text)))
	if ending_screen.visible:
		ending_name_label.text = game_state.current_line().get(ScenarioScript.NAME, "")
		ending_summary_label.text = game_state.current_line().get(ScenarioScript.SUMMARY, "")


## 会話中の画面を game_state の会話の進行に合わせる。メッセージウィンドウにはバックログの最新の行 (いま流れている
## メッセージか、直前に選んだ選択肢) を出し、背景と立ち絵はバックログから決め、選択肢で止まっている間は選択肢と
## 残り時間を出す
func _refresh_conversation(game_state: Node) -> void:
	var backlog: Array = game_state.backlog
	var shown: Dictionary = backlog.back() if not backlog.is_empty() else {}
	speaker_label.text = shown.get(ScenarioScript.SPEAKER, "")
	name_tag.visible = not speaker_label.text.is_empty()
	message_label.text = shown.get(ScenarioScript.TEXT, "")
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
	time_bar.value = 1.0 - game_state.elapsed / ConversationScript.CHOICE_SECONDS
	for option_index: int in range(choice_buttons.size()):
		choice_buttons[option_index].visible = option_index < options.size()
		if option_index < options.size():
			choice_buttons[option_index].text = (
				"%d. %s" % [option_index + 1, options[option_index][ScenarioScript.TEXT]]
			)


## texture_rect に path の素材を出し、path が空なら隠す。冪等で、毎フレーム呼んでも同じ素材を読み込み直さない
func _show_texture(texture_rect: TextureRect, path: String) -> void:
	texture_rect.visible = not path.is_empty()
	if texture_rect.visible and (
		texture_rect.texture == null or texture_rect.texture.resource_path != path
	):
		texture_rect.texture = load(path)


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
