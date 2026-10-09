extends "res://scripts/dev/headless_check.gd"
## タイトルから開く設定とクレジットの検証 (画面の遷移、音量の段階とバスの音量、音量の保存データの解釈と保存・読み込み・
## バスへの反映、クレジット画面の文の組み立てと問い合わせ先)。scripts/dev/selfcheck.gd が継承し、自分の検証と一緒に
## 実行する (selfcheck.gd を 1 ファイルの行数の上限 (gdlintrc の max-file-lines) に収めるため分けている)。

## 画面と遷移表を持つ autoload のスクリプト
const GAME_STATE_SCRIPT := preload("res://scripts/game_state.gd")
## 設定とクレジットの画面の遷移の検証 (いまの画面・操作・移る先・説明)。どちらもタイトルからだけ開き、同じ操作か
## 決定でタイトルに戻る
const MENU_TRANSITION_CASES: Array[Array] = [
	[
		GAME_STATE_SCRIPT.Screen.TITLE,
		GAME_STATE_SCRIPT.Command.SETTINGS,
		GAME_STATE_SCRIPT.Screen.SETTINGS,
		"タイトルで設定を開ける",
	],
	[
		GAME_STATE_SCRIPT.Screen.SETTINGS,
		GAME_STATE_SCRIPT.Command.SETTINGS,
		GAME_STATE_SCRIPT.Screen.TITLE,
		"設定をもう一度押すとタイトルに戻る",
	],
	[
		GAME_STATE_SCRIPT.Screen.SETTINGS,
		GAME_STATE_SCRIPT.Command.CONFIRM,
		GAME_STATE_SCRIPT.Screen.TITLE,
		"設定で決定するとタイトルに戻る",
	],
	[
		GAME_STATE_SCRIPT.Screen.SETTINGS,
		GAME_STATE_SCRIPT.Command.CREDITS,
		GAME_STATE_SCRIPT.Screen.SETTINGS,
		"設定からクレジットへは移らない",
	],
	[
		GAME_STATE_SCRIPT.Screen.TITLE,
		GAME_STATE_SCRIPT.Command.CREDITS,
		GAME_STATE_SCRIPT.Screen.CREDITS,
		"タイトルでクレジットを開ける",
	],
	[
		GAME_STATE_SCRIPT.Screen.CREDITS,
		GAME_STATE_SCRIPT.Command.CREDITS,
		GAME_STATE_SCRIPT.Screen.TITLE,
		"クレジットをもう一度押すとタイトルに戻る",
	],
	[
		GAME_STATE_SCRIPT.Screen.CREDITS,
		GAME_STATE_SCRIPT.Command.CONFIRM,
		GAME_STATE_SCRIPT.Screen.TITLE,
		"クレジットで決定するとタイトルに戻る",
	],
	[
		GAME_STATE_SCRIPT.Screen.PLAYING,
		GAME_STATE_SCRIPT.Command.SETTINGS,
		GAME_STATE_SCRIPT.Screen.PLAYING,
		"会話中は設定を開けない",
	],
	[
		GAME_STATE_SCRIPT.Screen.PLAYING,
		GAME_STATE_SCRIPT.Command.CREDITS,
		GAME_STATE_SCRIPT.Screen.PLAYING,
		"会話中はクレジットを開けない",
	],
	[
		GAME_STATE_SCRIPT.Screen.ENDING,
		GAME_STATE_SCRIPT.Command.SETTINGS,
		GAME_STATE_SCRIPT.Screen.ENDING,
		"エンディングでは設定を開けない",
	],
]
## 保存データの autoload のスクリプト
const SAVE_DATA_SCRIPT := preload("res://scripts/save_data.gd")
## クレジット画面に出す内容
const CREDITS_SCRIPT := preload("res://scripts/credits.gd")
## 音量の保存・読み込みの検証で書き出す保存データ。プレイヤーの保存データ (user://) を書き換えないよう tmp/ に置く
const VOLUME_TEST_PATH: String = "res://tmp/selfcheck-volume-save.json"
## 保存データが無い時の音量の段階
const DEFAULT_VOLUME: int = SAVE_DATA_SCRIPT.DEFAULT_VOLUME
## 音量の保存データの解釈の検証 (保存データの volumes の値・期待する BGM と SE の段階・説明)。範囲外・整数でない値は
## そのバスだけ既定の音量にする
const VOLUME_PARSE_CASES: Array[Array] = [
	[{"BGM": 3, "SE": 0}, 3, 0, "範囲内の整数を読む"],
	[{"BGM": 10.0, "SE": 7}, 10, 7, "整数の値の小数表記を読む"],
	[{"BGM": -1, "SE": 11}, DEFAULT_VOLUME, DEFAULT_VOLUME, "範囲外はそのバスだけ既定"],
	[{"BGM": 2.5, "SE": "5"}, DEFAULT_VOLUME, DEFAULT_VOLUME, "整数でない・数でない値は既定"],
	[{"SE": 4}, DEFAULT_VOLUME, 4, "無いバスは既定"],
	[[3, 4], DEFAULT_VOLUME, DEFAULT_VOLUME, "辞書でなければ既定"],
]
## クレジット画面の文の組み立ての検証に使う素材の記録 (表の 2 行と、表の後の段落)
const CREDITS_SAMPLE: String = """# 素材の記録

説明の段落

| 素材 | 用途 | 作者・入手元 | ライセンス | 改変 |
|---|---|---|---|---|
| `bgm/a.ogg` | タイトルの BGM | 作者 A。https://example.com/a | CC0 | なし |
| `se/b.wav` | 決定音 | 作者 B | CC-BY 4.0 | 音量を下げた |

| 表の後の | 別の表 |
"""
## CREDITS_SAMPLE から組み立てるクレジット画面の文
const CREDITS_SAMPLE_ENTRIES: Array[String] = [
	"bgm/a.ogg\n用途: タイトルの BGM / 作者・入手元: 作者 A。https://example.com/a / ライセンス: CC0 / 改変: なし",
	"se/b.wav\n用途: 決定音 / 作者・入手元: 作者 B / ライセンス: CC-BY 4.0 / 改変: 音量を下げた",
]
## 素材の行が無い (見出しと区切りだけの) 素材の記録
const CREDITS_EMPTY: String = "| 素材 | 用途 |\n|---|---|\n"
## クレジット画面のサポートページとメールの宛先を載せている紹介ページと、サポート節の印
const SUPPORT_PAGE_PATH: String = "res://docs/index.html"
const SUPPORT_SECTION: String = 'id="support"'


## 設定とクレジットの画面の遷移 (MENU_TRANSITION_CASES) と、GameState の実体でタイトルから開いても会話が始まらず、
## 同じ操作でタイトルに戻ること
func _check_menu_transitions() -> void:
	for case: Array in MENU_TRANSITION_CASES:
		var actual: GAME_STATE_SCRIPT.Screen = GAME_STATE_SCRIPT.next_screen(case[0], case[1])
		_check(actual == case[2], "遷移: %s" % case[3])
	for command: GAME_STATE_SCRIPT.Command in [
		GAME_STATE_SCRIPT.Command.SETTINGS, GAME_STATE_SCRIPT.Command.CREDITS
	]:
		var opener: Node = GAME_STATE_SCRIPT.new()
		_check(
			opener.apply(command) and opener.lines.is_empty() and not opener.is_playing(),
			"apply: タイトルで設定・クレジットを開いても会話は始まらない (%d)" % command
		)
		_check(
			opener.apply(command) and opener.screen == GAME_STATE_SCRIPT.Screen.TITLE,
			"apply: 設定・クレジットからタイトルに戻る (%d)" % command
		)
		opener.free()


## 音量の段階とバスの音量 (dB) の対応、バス (default_bus_layout.tres) があること、保存データの音量の解釈
## (VOLUME_PARSE_CASES)、音量を変えると保存されてバスへ反映され、別のインスタンスで読み込み直しても (再起動の代わり)
## 保たれること
func _check_volumes() -> void:
	for bus: String in SAVE_DATA_SCRIPT.VOLUME_BUSES:
		_check(AudioServer.get_bus_index(bus) >= 0, "音量: バス %s が default_bus_layout.tres にある" % bus)
	var max_volume: int = SAVE_DATA_SCRIPT.MAX_VOLUME
	_check(SAVE_DATA_SCRIPT.volume_db(0) == SAVE_DATA_SCRIPT.MUTED_DB, "音量: 0 段は消音の大きさ")
	_check(is_equal_approx(SAVE_DATA_SCRIPT.volume_db(max_volume), 0.0), "音量: 最大の段は 0 dB")
	@warning_ignore("integer_division")
	var half: int = max_volume / 2
	_check(
		absf(SAVE_DATA_SCRIPT.volume_db(half) - linear_to_db(float(half) / max_volume)) < 0.01,
		"音量: 段階は振幅の比として dB にする"
	)
	for level: int in range(max_volume):
		_check(
			SAVE_DATA_SCRIPT.volume_db(level) < SAVE_DATA_SCRIPT.volume_db(level + 1),
			"音量: %d 段より %d 段のほうが大きい" % [level, level + 1]
		)
	for case: Array in VOLUME_PARSE_CASES:
		var parsed: Dictionary = SAVE_DATA_SCRIPT.parse(
			JSON.stringify({"version": 1, "volumes": case[0]})
		)
		_check(
			not parsed["broken"] and parsed["volumes"] == {"BGM": case[1], "SE": case[2]},
			"保存データの音量: %s (%s)" % [case[3], parsed["volumes"]]
		)
	_check_volume_file()


## 音量を変えると保存されてバスへ反映され、別のインスタンスで読み込み直しても保たれること。保存先は VOLUME_TEST_PATH
func _check_volume_file() -> void:
	var path: String = ProjectSettings.globalize_path(VOLUME_TEST_PATH)
	_remove_save_files(path)
	var max_volume: int = SAVE_DATA_SCRIPT.MAX_VOLUME
	var saver: Node = SAVE_DATA_SCRIPT.new()
	saver.load_from(path)
	_check(saver.volumes == SAVE_DATA_SCRIPT.default_volumes(), "音量: 保存データが無ければ既定の音量")
	saver.set_volume("BGM", 3)
	_check(FileAccess.file_exists(path), "音量: 変えると保存データを書き出す")
	saver.set_volume("SE", max_volume + 5)
	_check(saver.volumes["SE"] == max_volume, "音量: 最大より上げても最大で止まる")
	saver.set_volume("SE", -5)
	_check(saver.volumes["SE"] == 0, "音量: 0 より下げても 0 で止まる")
	var written: String = FileAccess.get_file_as_string(path)
	saver.set_volume("SE", 0)
	_check(FileAccess.get_file_as_string(path) == written, "音量: 同じ段に変えても保存データは変わらない")
	saver.free()
	var loader: Node = SAVE_DATA_SCRIPT.new()
	loader.load_from(path)
	_check(loader.volumes == {"BGM": 3, "SE": 0}, "音量: 読み込み直しても変えた音量が保たれる")
	for bus: String in SAVE_DATA_SCRIPT.VOLUME_BUSES:
		var index: int = AudioServer.get_bus_index(bus)
		var expected_db: float = SAVE_DATA_SCRIPT.volume_db(loader.volumes[bus])
		_check(
			index >= 0 and is_equal_approx(AudioServer.get_bus_volume_db(index), expected_db),
			"音量: 読み込んだ音量がバス %s に反映される" % bus
		)
	loader.load_from(path)
	_check(loader.volumes == {"BGM": 3, "SE": 0}, "音量: 読み込みは冪等")
	loader.free()
	_remove_save_files(path)


## path の保存データと、退避したファイル・書き出し途中のファイルを消す (前の実行が途中で止まっていても、保存データが
## 無い状態から検証を始めるため)
func _remove_save_files(path: String) -> void:
	_remove_file(path)
	_remove_file(path + SAVE_DATA_SCRIPT.BROKEN_SUFFIX)
	_remove_file(path + SAVE_DATA_SCRIPT.WRITING_SUFFIX)


## クレジット画面の文の組み立て (CREDITS_SAMPLE) と、サポートページ・メールの宛先が紹介ページ (docs/index.html) の
## サポート節と一致すること
func _check_credits_text() -> void:
	_check(
		CREDITS_SCRIPT.entries_of(CREDITS_SAMPLE) == CREDITS_SAMPLE_ENTRIES,
		"クレジット画面: 表の各行を見出し付きの文にする (%s)" % [CREDITS_SCRIPT.entries_of(CREDITS_SAMPLE)]
	)
	_check(CREDITS_SCRIPT.entries_of(CREDITS_EMPTY).is_empty(), "クレジット画面: 素材の行が無い表は 0 件")
	_check(CREDITS_SCRIPT.entries_of("").is_empty(), "クレジット画面: 表が無ければ 0 件")
	var page: String = FileAccess.get_file_as_string(SUPPORT_PAGE_PATH)
	_check(
		CREDITS_SCRIPT.SUPPORT_URL.ends_with("#support") and page.contains(SUPPORT_SECTION),
		"クレジット画面: サポートページの節が紹介ページにある"
	)
	_check(
		page.contains('href="%s"' % CREDITS_SCRIPT.MAIL_URL),
		"クレジット画面: メールの宛先が紹介ページのサポート節の宛先と同じ"
	)
