extends Node
## ゲーム進行の状態 (autoload の GameState)。いま表示している画面 (タイトル・会話中・バックログ・エンディング) を持ち、
## 画面をまたいで参照する値はここに集める (UI ノードに状態を持たせない)。
## 会話の進行 (シナリオの位置・好感度・選択肢の残り時間) は会話エンジンの土台の issue で足す。

## 表示している画面。会話が進むのは PLAYING の間だけで、BACKLOG を開いている間は止まる
enum Screen { TITLE, PLAYING, BACKLOG, ENDING }
## 画面を切り替える操作 (project.godot の入力の confirm / backlog)
enum Command { CONFIRM, BACKLOG }

## 画面ごとに受け付ける操作と、その操作で移る画面。ここに無い操作はその画面では何もしない。
## ENDING へは操作ではなく会話の終わり (finish) で移る
const TRANSITIONS: Dictionary = {
	Screen.TITLE: {Command.CONFIRM: Screen.PLAYING},
	Screen.PLAYING: {Command.BACKLOG: Screen.BACKLOG},
	Screen.BACKLOG: {Command.BACKLOG: Screen.PLAYING, Command.CONFIRM: Screen.PLAYING},
	Screen.ENDING: {Command.CONFIRM: Screen.TITLE},
}

## 表示している画面。起動時はタイトル
var screen: Screen = Screen.TITLE


## current の画面で command を受けた時に移る画面。受け付けない操作なら current のまま。
## 遷移表の検証 (scripts/dev/selfcheck.gd) が autoload の実体なしで呼べるよう static にする
static func next_screen(current: Screen, command: Command) -> Screen:
	var accepted: Dictionary = TRANSITIONS.get(current, {})
	return accepted.get(command, current)


## command を受けて画面を移す。移ったら true
func apply(command: Command) -> bool:
	var next: Screen = next_screen(screen, command)
	if next == screen:
		return false
	screen = next
	return true


## 会話が進む画面 (会話中) か
func is_playing() -> bool:
	return screen == Screen.PLAYING


## 会話の終わり。エンディングの画面に移る
func finish() -> void:
	screen = Screen.ENDING
