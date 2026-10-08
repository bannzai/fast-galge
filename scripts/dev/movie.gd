extends "res://scripts/dev/game_driver.gd"
## 起動の録画 (Makefile の movie target) で、タイトルから本編を始めて、文字送りが操作なしで進む様子を映すための操作。
## 録画の長さは Makefile の --quit-after が決めるため、このスクリプトからは終了しない。

## タイトルを映しておく時間 (秒)。起動直後の描画崩れ・真っ黒を、録画の冒頭で見分けられる長さ
const TITLE_SHOW_TIME: float = 1.0


## tree の準備が終わってから _run() を始める (シーンの追加は _initialize() の後でないとできない)
func _initialize() -> void:
	_run.call_deferred()


## 物理フレームを進めながら入力を流すため、同じ実行中に重ねて呼び出さない
func _run() -> void:
	_add_main()
	await create_timer(TITLE_SHOW_TIME).timeout
	await _hold_keys([KEY_ENTER], 1)
