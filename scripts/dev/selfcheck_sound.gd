extends "res://scripts/dev/selfcheck_menu.gd"
## 場面ごとの BGM と効果音の検証 (場面と BGM の対応、全シナリオのファイルに BGM が決まっていること、素材の読み込みと
## BGM の繰り返し、メインシーンの BGM・効果音のノードが設定の音量のバスを通ること、GameState が効果音のきっかけを
## 知らせる回数、本編を進めた時の BGM の移り変わり)。scripts/dev/selfcheck.gd が継承し、自分の検証と一緒に実行する
## (selfcheck.gd を 1 ファイルの行数の上限 (gdlintrc の max-file-lines) に収めるため分けている)。

## 場面ごとの BGM と効果音の素材
const SOUND_SCRIPT := preload("res://scripts/sound.gd")
## 場面と BGM の対応の検証 (画面・会話している行のシナリオのファイル・期待する BGM (null は鳴らさない)・説明)
const BGM_CASES: Array[Array] = [
	[GAME_STATE_SCRIPT.Screen.TITLE, "", null, "タイトルでは鳴らさない"],
	[GAME_STATE_SCRIPT.Screen.SETTINGS, "", null, "設定では鳴らさない"],
	[GAME_STATE_SCRIPT.Screen.CREDITS, "", null, "クレジットでは鳴らさない"],
	[
		GAME_STATE_SCRIPT.Screen.PLAYING,
		"res://scenario/common.json",
		SOUND_SCRIPT.BGM_COMMON,
		"共通パートの会話中は共通パートの BGM",
	],
	[
		GAME_STATE_SCRIPT.Screen.PLAYING,
		"res://scenario/route_hina.json",
		SOUND_SCRIPT.BGM_ROUTE,
		"ヒナのルートの会話中はルートの BGM",
	],
	[
		GAME_STATE_SCRIPT.Screen.PLAYING,
		"res://scenario/route_nagi.json",
		SOUND_SCRIPT.BGM_ROUTE,
		"ナギのルートの会話中はルートの BGM",
	],
	[
		GAME_STATE_SCRIPT.Screen.PLAYING,
		"res://scenario/common_bad.json",
		SOUND_SCRIPT.BGM_COMMON,
		"共通 bad の会話中は共通パートの BGM を続ける",
	],
	[
		GAME_STATE_SCRIPT.Screen.PLAYING,
		"res://scenario/sample.json",
		SOUND_SCRIPT.BGM_COMMON,
		"サンプルの会話中は共通パートの BGM",
	],
	[
		GAME_STATE_SCRIPT.Screen.BACKLOG,
		"res://scenario/route_hina.json",
		SOUND_SCRIPT.BGM_ROUTE,
		"バックログを開いても会話中の BGM を続ける",
	],
	[
		GAME_STATE_SCRIPT.Screen.ENDING,
		"res://scenario/route_nagi.json",
		SOUND_SCRIPT.BGM_ENDING,
		"ルートのエンディングはエンディングの BGM",
	],
	[
		GAME_STATE_SCRIPT.Screen.ENDING,
		"res://scenario/common_bad.json",
		SOUND_SCRIPT.BGM_ENDING,
		"共通 bad のエンディングもエンディングの BGM",
	],
]
## 選んだ選択肢で好感度が変わるかの検証 (選択肢の好感度の変化・変わるか・説明)
const CHANGES_AFFECTION_CASES: Array[Array] = [
	[{"hina": 1}, true, "上がる"],
	[{"hina": -1}, true, "下がる"],
	[{"hina": 0}, false, "0 だけなら変わらない"],
	[{}, false, "変化が書かれていない"],
	[{"hina": 0, "nagi": -1}, true, "1 人でも変われば変わる"],
]
## 効果音の数 (文字送り・選択肢の表示・時間切れ・好感度の変化。issue #10 の完了条件)
const EFFECT_COUNT: int = 4


## 場面ごとの BGM と効果音の検証をすべて行う
func _check_sound() -> void:
	_check_bgm_cases()
	_check_sound_assets()
	_check_sound_nodes()
	_check_sound_events()
	for case: Array in MAIN_ENDING_CASES:
		_check_main_bgm(case)


## 場面と BGM の対応 (BGM_CASES) と、サンプルと本編の全シナリオのファイルが SCENARIO_BGM にあり、SCENARIO_BGM に
## 使われないファイルが無いこと (scenario/ の全ファイルがサンプルか本編に入っていることは selfcheck.gd が確かめる)
func _check_bgm_cases() -> void:
	for case: Array in BGM_CASES:
		_check(SOUND_SCRIPT.bgm_for(case[0], case[1]) == case[2], "場面と BGM: %s" % case[3])
	var paths: Array = SAMPLE_SCENARIO_PATHS + GAME_STATE_SCRIPT.MAIN_SCENARIO_PATHS
	for path: String in paths:
		_check(SOUND_SCRIPT.SCENARIO_BGM.has(path), "場面と BGM: %s の BGM が決まっている" % path)
	for path: String in SOUND_SCRIPT.SCENARIO_BGM:
		_check(path in paths, "場面と BGM: %s はサンプルか本編のシナリオ" % path)


## BGM が Ogg Vorbis として読めて長さがあり、3 曲が別の曲で、鳴らす時は繰り返すこと。効果音が 4 種あり、WAV として
## 読めて長さがあり、別の音で、きっかけの名前が GameState の signal であること
func _check_sound_assets() -> void:
	var bgms: Array = [SOUND_SCRIPT.BGM_COMMON, SOUND_SCRIPT.BGM_ROUTE, SOUND_SCRIPT.BGM_ENDING]
	for bgm: Variant in bgms:
		_check(
			bgm is AudioStreamOggVorbis and bgm.get_length() > 0.0,
			"BGM: %s を Ogg Vorbis として読める" % bgm.resource_path
		)
		_check(bgms.count(bgm) == 1, "BGM: %s は他の場面と別の曲" % bgm.resource_path)
	for case: Array in BGM_CASES:
		var played: AudioStreamOggVorbis = SOUND_SCRIPT.bgm_for(case[0], case[1])
		_check(played == null or played.loop, "BGM: 鳴らす BGM は繰り返す (%s)" % case[3])
	_check(
		SOUND_SCRIPT.EFFECTS.size() == EFFECT_COUNT,
		"効果音: %d 種ある (%d 種)" % [EFFECT_COUNT, SOUND_SCRIPT.EFFECTS.size()]
	)
	var game_state: Node = GAME_STATE_SCRIPT.new()
	for event: String in SOUND_SCRIPT.EFFECTS:
		var effect: Variant = SOUND_SCRIPT.EFFECTS[event]
		_check(
			effect is AudioStreamWAV and effect.get_length() > 0.0,
			"効果音: %s の音を WAV として読める" % event
		)
		_check(
			SOUND_SCRIPT.EFFECTS.values().count(effect) == 1, "効果音: %s は他のきっかけと別の音" % event
		)
		_check(game_state.has_signal(event), "効果音: %s は GameState の signal" % event)
	game_state.free()
	_check(
		db_to_linear(SOUND_SCRIPT.BGM_VOLUME_DB) + db_to_linear(SOUND_SCRIPT.EFFECT_VOLUME_DB) <= 1.0,
		"音量: BGM と効果音を最大の音量で重ねても振幅の比の和が 1 を超えない (割れない)"
	)
	_check(
		SOUND_SCRIPT.EFFECT_VOLUME_DB > SOUND_SCRIPT.BGM_VOLUME_DB,
		"音量: 効果音が BGM に埋もれないよう、効果音のノードの音量を BGM より大きくする"
	)


## メインシーンの BGM のノードが BGM のバス、効果音のノードが効果音のバスで鳴らし、どちらも設定の画面で音量を変える
## バス (SaveData の VOLUME_BUSES) であること
func _check_sound_nodes() -> void:
	var main: Node = MAIN_SCENE.instantiate()
	var bgm_player: AudioStreamPlayer = main.get_node_or_null("Audio/Bgm")
	_check(
		bgm_player != null and bgm_player.bus == &"BGM" and SAVE_DATA_SCRIPT.VOLUME_BUSES.has("BGM"),
		"音量のバス: BGM は設定で音量を変える BGM のバスで鳴らす"
	)
	for event: String in SOUND_SCRIPT.EFFECTS:
		var effect_player: AudioStreamPlayer = main.get_node_or_null("Audio/" + event)
		_check(
			(
				effect_player != null
				and effect_player.bus == &"SE"
				and SAVE_DATA_SCRIPT.VOLUME_BUSES.has("SE")
			),
			"音量のバス: 効果音 %s は設定で音量を変える効果音のバスで鳴らす" % event
		)
	main.free()


## GameState が効果音のきっかけ (signal) を知らせる回数の検証 (サンプルシナリオ)。メッセージの行に着くたびに文字送り、
## 選択肢の行に着くと選択肢の表示、好感度が変わる選択肢を選ぶと好感度の変化、時間切れで時間切れ (好感度の変化は
## 知らせない)。好感度が変わるかの判定 (CHANGES_AFFECTION_CASES) と、行を読んだシナリオのファイルも確かめる
func _check_sound_events() -> void:
	for case: Array in CHANGES_AFFECTION_CASES:
		_check(
			ConversationScript.changes_affection(case[0]) == case[1],
			"好感度の変化の判定: %s" % case[2]
		)
	var game_state: Node = GAME_STATE_SCRIPT.new()
	game_state.scenario_paths = SAMPLE_SCENARIO_PATHS
	var counts: Dictionary = {}
	for event: String in SOUND_SCRIPT.EFFECTS:
		counts[event] = 0
		game_state.connect(event, func() -> void: counts[event] += 1)
	_check(game_state.scenario_path().is_empty(), "シナリオのファイル: 始める前は無い")
	game_state.apply(GAME_STATE_SCRIPT.Command.CONFIRM)
	_check(
		game_state.scenario_path() == SAMPLE_SCENARIO_PATHS[0],
		"シナリオのファイル: 会話している行を読んだファイル"
	)
	_check(counts["message_entered"] == 1, "効果音のきっかけ: 最初のメッセージで文字送り")
	_fast_forward(game_state, _is_choosing.bind(game_state))
	_check(
		counts == _event_counts(game_state.backlog.size(), 1, 0, 0),
		"効果音のきっかけ: 選択肢まで、メッセージごとに文字送りと、選択肢の表示が 1 回 (%s)" % counts
	)
	game_state.choose(0)
	_fast_forward(game_state, func() -> bool: return false)
	_check(
		counts == _event_counts(game_state.backlog.size() - 1, 1, 0, 1),
		"効果音のきっかけ: 好感度が上がる選択肢を選ぶと好感度の変化が 1 回 (%s)" % counts
	)
	game_state.apply(GAME_STATE_SCRIPT.Command.CONFIRM)
	for event: String in counts:
		counts[event] = 0
	game_state.apply(GAME_STATE_SCRIPT.Command.CONFIRM)
	game_state.advance(60.0)
	_check(
		counts == _event_counts(game_state.backlog.size() - 1, 1, 1, 0),
		"効果音のきっかけ: 時間切れは時間切れを 1 回知らせ、好感度の変化は知らせない (%s)" % counts
	)
	game_state.free()


## 効果音のきっかけごとの回数 (文字送り messages・選択肢の表示 choices・時間切れ timeouts・好感度の変化 changes)
func _event_counts(messages: int, choices: int, timeouts: int, changes: int) -> Dictionary:
	return {
		"message_entered": messages,
		"choice_entered": choices,
		"timed_out": timeouts,
		"affection_changed": changes,
	}


## 本編を case (MAIN_ENDING_CASES の 1 つ) の進め方で最後まで GameState で進めた時に鳴る BGM の移り変わりが、ルートに
## 入る周は共通パート → ルート → エンディング、共通 bad の周は共通パート → エンディングであること
func _check_main_bgm(case: Array) -> void:
	var game_state: Node = GAME_STATE_SCRIPT.new()
	game_state.apply(GAME_STATE_SCRIPT.Command.CONFIRM)
	var heard: Array = [SOUND_SCRIPT.bgm_for(game_state.screen, game_state.scenario_path())]
	while game_state.is_playing():
		var pick: int = (
			_pick_for_case(case, game_state.lines, game_state.position)
			if _is_choosing(game_state)
			else ConversationScript.TIMEOUT
		)
		if pick != ConversationScript.TIMEOUT:
			game_state.choose(pick)
		else:
			game_state.advance(FAST_FORWARD_STEP)
		var bgm: AudioStream = SOUND_SCRIPT.bgm_for(game_state.screen, game_state.scenario_path())
		if heard.back() != bgm:
			heard.append(bgm)
	var expected: Array = (
		[SOUND_SCRIPT.BGM_COMMON, SOUND_SCRIPT.BGM_ENDING]
		if case[1].is_empty()
		else [SOUND_SCRIPT.BGM_COMMON, SOUND_SCRIPT.BGM_ROUTE, SOUND_SCRIPT.BGM_ENDING]
	)
	_check(
		heard == expected,
		(
			"本編の BGM: %s までの BGM が %s の順に移る (%s)"
			% [
				case[0],
				expected.map(func(bgm: AudioStream) -> String: return bgm.resource_path),
				heard.map(func(bgm: AudioStream) -> String: return bgm.resource_path),
			]
		)
	)
	game_state.free()
