extends RefCounted
## 場面ごとの BGM の割り当てと、効果音の素材。素材は scripts/dev/generate_audio.py で作り、assets/CREDITS.md に
## 記録する。鳴らすノードは scenes/main.tscn の Audio の下 (BGM は BGM バス、効果音は SE バス。バスの音量は設定の
## 画面で変える)。

## 画面の定義
const GameStateScript := preload("res://scripts/game_state.gd")
## 共通パートの BGM
const BGM_COMMON := preload("res://assets/audio/bgm_common.ogg")
## ヒロインのルートの BGM
const BGM_ROUTE := preload("res://assets/audio/bgm_route.ogg")
## エンディングの画面の BGM
const BGM_ENDING := preload("res://assets/audio/bgm_ending.ogg")
## シナリオのファイルと、そのファイルの行で会話している間に鳴らす BGM。scenario/ の全ファイルを載せる
## (scripts/dev/selfcheck_sound.gd が確かめる)。共通 bad は共通パートから数行で終わるため共通パートの BGM を続ける
const SCENARIO_BGM: Dictionary = {
	"res://scenario/sample.json": BGM_COMMON,
	"res://scenario/common.json": BGM_COMMON,
	"res://scenario/route_hina.json": BGM_ROUTE,
	"res://scenario/route_nagi.json": BGM_ROUTE,
	"res://scenario/common_bad.json": BGM_COMMON,
}
## 効果音。GameState の signal の名前と、その signal で鳴らす素材。鳴らすノードは scenes/main.tscn の Audio の下の、
## signal と同じ名前のノード
const EFFECTS: Dictionary = {
	"message_entered": preload("res://assets/audio/se_message.wav"),
	"choice_entered": preload("res://assets/audio/se_choice.wav"),
	"timed_out": preload("res://assets/audio/se_timeout.wav"),
	"affection_changed": preload("res://assets/audio/se_affection.wav"),
}


## screen の画面で、scenario_path のシナリオのファイルの行にいる時に鳴らす BGM (繰り返す)。null なら鳴らさない。
## 会話中とバックログ (会話を止めて読み返している間も曲は途切れさせない) はファイルの BGM、エンディングはエンディングの
## BGM、タイトル・設定・クレジットは鳴らさない。SCENARIO_BGM に無いファイルは共通パートの BGM。
## 素材の読み込み設定 (.import) の Ogg Vorbis の繰り返しは既定で無効のため、ここで繰り返しを有効にする (冪等)
static func bgm_for(screen: GameStateScript.Screen, scenario_path: String) -> AudioStreamOggVorbis:
	var bgm: AudioStreamOggVorbis = null
	match screen:
		GameStateScript.Screen.PLAYING, GameStateScript.Screen.BACKLOG:
			bgm = SCENARIO_BGM.get(scenario_path, BGM_COMMON)
		GameStateScript.Screen.ENDING:
			bgm = BGM_ENDING
	if bgm != null:
		bgm.loop = true
	return bgm
