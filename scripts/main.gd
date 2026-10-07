extends Control
## メインシーン。GameState の画面に合わせてタイトル・会話・バックログ・エンディングの表示を切り替える。
## 会話エンジン (高速な文字送り・制限時間つき選択肢・好感度・バックログの中身) は土台の issue で足し、
## このシーンは画面の切り替えと入力の受け口だけを持つ。

## autoload の GameState のスクリプト。autoload 名の識別子で参照すると、--script で起動する scripts/dev/ の検証が
## autoload の登録前にこのスクリプトをコンパイルして失敗するため、ノードとして取る
const GameStateScript := preload("res://scripts/game_state.gd")
## 入力のアクションと、GameState に送る操作
const SCREEN_ACTIONS: Dictionary = {
	"confirm": GameStateScript.Command.CONFIRM,
	"backlog": GameStateScript.Command.BACKLOG,
}
## 画面ごとの見出し。表示している画面が分かる最小の表示 (見た目は関門 2 のデザインの反映で作り直す)
const SCREEN_LABELS: Dictionary = {
	GameStateScript.Screen.TITLE: "fast-galge",
	GameStateScript.Screen.PLAYING: "PLAYING",
	GameStateScript.Screen.BACKLOG: "BACKLOG",
	GameStateScript.Screen.ENDING: "ENDING",
}
## 画面ごとの操作の案内
const SCREEN_HINTS: Dictionary = {
	GameStateScript.Screen.TITLE: "Press Enter",
	GameStateScript.Screen.PLAYING: "B: backlog",
	GameStateScript.Screen.BACKLOG: "B / Enter: back",
	GameStateScript.Screen.ENDING: "Enter: title",
}

## 起動検証 (make check) が確認する起動の印
const BOOT_MESSAGE: String = "fast-galge boot"

## 画面の見出し (SCREEN_LABELS) を表示するラベル
@onready var title_label: Label = $Title
## 操作の案内 (SCREEN_HINTS) を表示するラベル
@onready var hint_label: Label = $Hint


## 起動の印を出し、GameState の画面に合わせた表示にする
func _ready() -> void:
	print(BOOT_MESSAGE)
	_refresh()


## 入力のアクションを GameState の操作に写し、画面が移ったら表示を更新する
func _unhandled_input(event: InputEvent) -> void:
	var game_state: Node = get_tree().root.get_node_or_null("GameState")
	if game_state == null:
		return
	for action: String in SCREEN_ACTIONS:
		if event.is_action_pressed(action):
			if game_state.apply(SCREEN_ACTIONS[action]):
				_refresh()
			get_viewport().set_input_as_handled()
			return


## GameState の画面に合わせて表示を更新する
func _refresh() -> void:
	var game_state: Node = get_tree().root.get_node_or_null("GameState")
	var screen: GameStateScript.Screen = (
		game_state.screen if game_state != null else GameStateScript.Screen.TITLE
	)
	title_label.text = SCREEN_LABELS[screen]
	hint_label.text = SCREEN_HINTS[screen]
