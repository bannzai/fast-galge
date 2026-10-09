# fast-galge の検証・ビルド入口。target 命名は ~/.claude/rules/makefile-target-naming.md に従う
# (`build-<対象>` = エクスポートだけ。`run` = エディタなしでの起動で、引数なしの make の既定)。
#
# GODOT は Godot 4.7 の実行ファイル。macOS ローカルの既定値は /Applications/Godot.app。CI では
# 環境変数 GODOT で Linux バイナリを渡す。ビルド・起動は CI に任せ、このマシンでは実行しない (AGENTS.md「検証方法」)。
GODOT ?= /Applications/Godot.app/Contents/MacOS/Godot
LOG_DIR := tmp
# Godot 自身のログの出力先。指定しないと user:// に書こうとし、書き込みを拒否するサンドボックスでは
# 起動に失敗するため、すべての Godot 起動に付ける ($@ は実行中の target 名)
ENGINE_LOG = --log-file $(abspath $(LOG_DIR))/$@.godot.log

# 描画付きで起動する target (screenshot / movie) の共通オプション。headless では描画されないため付けない。
# CI の Linux では Xvfb + Mesa llvmpipe 上で実行する
WINDOWED_FLAGS := --audio-driver Dummy --rendering-driver opengl3 --resolution 1280x720 --windowed --position 0,0
# 描画付き起動でだけ出る、描画に影響しない OS / ドライバ由来の行。ログの WARNING / ERROR 検査から除外する
# (llvmpipe は V-Sync を設定できない WARNING を毎回 1 件出す。macOS は入力メソッドの mach port のエラーを稀に出す)
WINDOWED_LOG_NOISE := -e 'Could not set V-Sync mode' -e 'IMKCFRunLoopWakeUpReliable'
# movie target が録画するフレーム数 (30 fps 固定。300 = 10 秒)。タイトルを 1 秒映した後、本編の最初のメッセージが
# 10 個前後、操作なしで流れるところまで映る長さ。CI の録画時間と artifact のサイズを抑えるためこれ以上は伸ばさない
MOVIE_FRAMES ?= 300

# 引数のログ (target の標準出力・標準エラーの保存先と、--log-file の Godot 自身のログ) がすべて存在して空でなく、
# 全文に WARNING / ERROR の行が無いことを検査する。Godot は診断を記録しても exit 0 で終わることがあるため、exit code
# だけで判定しない。ログが無いと grep が何も出さずに検査が通ってしまうため、先に存在を確かめる (--log-file が効かずに
# Godot のログが書かれなかった時に気づくため)。描画付き起動だけで出る既知のノイズ (WINDOWED_LOG_NOISE) と、2 番目の
# 引数に渡した grep の -e の並び (target 固有の既知のノイズ) は除く
define check_clean_log
for log in $(1); do test -s "$$log" || { echo "ログがありません: $$log"; exit 1; }; done
! grep -i -e 'WARNING' -e 'ERROR' $(1) | grep -v $(WINDOWED_LOG_NOISE) $(2) | grep -q .
endef
# プロジェクトの既定フォント (project.godot の gui/theme/custom_font と同じファイル)
PROJECT_FONT := assets/fonts/NotoSansJP-Regular.otf
# .godot/ が無い状態 (clone 直後・CI) の import でだけ出る行。Godot は import の前に既定フォントを読もうとし、まだ
# import されていないフォントを読めずにエラーを出す。文言は .import の有無で変わる (無ければ「No loader found」、
# あれば import 済みの .fontdata の「Cannot open file」「Failed loading resource」) ため、フォントのパスと最後の
# 「Error loading custom project font」で除く。import 自体は続いて成功し、以降の起動 (check / selfcheck / 撮影 /
# エクスポート) ではフォントを読めるため、フォントが壊れていればそちらのログ検査で失敗する
IMPORT_LOG_NOISE := -e '$(notdir $(PROJECT_FONT))' -e 'Error loading custom project font'

# 引数なしの make は人が手で遊んで確かめる入口 (run)。lint・検証・エクスポートは CI が行う
.DEFAULT_GOAL := run
.PHONY: import check selfcheck integration lint test screenshot movie run build-web build-windows build-macos build-linux build-all clean

# ログ・撮影の出力先。.gdignore を置き、撮影した PNG を Godot に import させない
$(LOG_DIR)/.gdignore:
	@mkdir -p $(LOG_DIR)
	@touch $@

# アセットのインポート (初回・素材追加後)。.godot/ を生成する
import: $(LOG_DIR)/.gdignore
	"$(GODOT)" --headless $(ENGINE_LOG) --path . --import > $(LOG_DIR)/import.log 2>&1; \
	echo "exit=$$?" >> $(LOG_DIR)/import.log; \
	tail -n 1 $(LOG_DIR)/import.log | grep -q '^exit=0$$'
	$(call check_clean_log,$(LOG_DIR)/import.log $(LOG_DIR)/import.godot.log,$(IMPORT_LOG_NOISE))

# 起動検証。メインシーンとスクリプトがロードでき、_ready が走ることを boot 出力で確認する
check: import
	"$(GODOT)" --headless $(ENGINE_LOG) --path . --quit > $(LOG_DIR)/check.log 2>&1; \
	echo "exit=$$?" >> $(LOG_DIR)/check.log; \
	grep -q '^fast-galge boot$$' $(LOG_DIR)/check.log
	tail -n 1 $(LOG_DIR)/check.log | grep -q '^exit=0$$'
	$(call check_clean_log,$(LOG_DIR)/check.log $(LOG_DIR)/check.godot.log)

# 画面の遷移表・会話エンジンの計算・シナリオの形式と所要時間・全シーンのロード・全素材の assets/CREDITS.md への
# 記録の検証 (headless)
selfcheck: import
	"$(GODOT)" --headless $(ENGINE_LOG) --path . --script res://scripts/dev/selfcheck.gd > $(LOG_DIR)/selfcheck.log 2>&1; \
	echo "exit=$$?" >> $(LOG_DIR)/selfcheck.log; \
	grep -q '^selfcheck OK$$' $(LOG_DIR)/selfcheck.log
	tail -n 1 $(LOG_DIR)/selfcheck.log | grep -q '^exit=0$$'
	$(call check_clean_log,$(LOG_DIR)/selfcheck.log $(LOG_DIR)/selfcheck.godot.log)

# キー入力とマウスのクリックでメインシーンを動かす入力統合テスト (headless)。会話の自動送り・選択・時間切れ・
# バックログの開閉・エンディングへの到達と、表示の追従を確認する。--fixed-fps で会話の時間を実時間から切り離し、
# 本編 5 周 (5 つのエンディング。ルートに入る周は 1 周 約 5 分) を待たずに流す
integration: import
	"$(GODOT)" --headless $(ENGINE_LOG) --path . --fixed-fps 60 --script res://scripts/dev/integration.gd > $(LOG_DIR)/integration.log 2>&1; \
	echo "exit=$$?" >> $(LOG_DIR)/integration.log; \
	grep -q '^integration OK$$' $(LOG_DIR)/integration.log
	tail -n 1 $(LOG_DIR)/integration.log | grep -q '^exit=0$$'
	$(call check_clean_log,$(LOG_DIR)/integration.log $(LOG_DIR)/integration.godot.log)

# GDScript の lint (gdtoolkit の gdlint。設定は ./gdlintrc)
lint:
	gdlint scripts/

# headless 検証の一括実行 (描画付きの screenshot / movie は含まない)
test: lint check selfcheck integration

# 実際の描画で代表画面を撮影する (headless の検証では見た目の崩れを検出できない)。撮影した PNG は目視してから
# 完了報告する
screenshot: import
	rm -f $(LOG_DIR)/screenshot-*.png
	"$(GODOT)" $(ENGINE_LOG) --path . $(WINDOWED_FLAGS) --script res://scripts/dev/screenshot.gd > $(LOG_DIR)/screenshot.log 2>&1; \
	echo "exit=$$?" >> $(LOG_DIR)/screenshot.log; \
	tail -n 1 $(LOG_DIR)/screenshot.log | grep -q '^exit=0$$'
	$(call check_clean_log,$(LOG_DIR)/screenshot.log $(LOG_DIR)/screenshot.godot.log)
	ls $(LOG_DIR)/screenshot-*.png

# 起動〜タイトル表示〜本編の文字送りを Movie Maker モードで録画して mp4 にする (起動直後の描画崩れ・真っ黒の検出と、
# 文字送りの速さの目視のため。headless は dummy レンダラで落ちるため描画付きで起動する)。タイトルから本編を始める
# 操作は scripts/dev/movie.gd が行う。真っ黒な動画を成功と誤認しないよう、終了 1 秒前のフレームの輝度平均
# (Y。limited range のため真っ黒 = 16) が 32 以上であることも検査する
movie: import
	rm -f $(LOG_DIR)/movie.avi $(LOG_DIR)/movie.mp4
	"$(GODOT)" $(ENGINE_LOG) --path . $(WINDOWED_FLAGS) --write-movie $(LOG_DIR)/movie.avi --fixed-fps 30 --quit-after $(MOVIE_FRAMES) --script res://scripts/dev/movie.gd > $(LOG_DIR)/movie.log 2>&1; \
	echo "exit=$$?" >> $(LOG_DIR)/movie.log; \
	tail -n 1 $(LOG_DIR)/movie.log | grep -q '^exit=0$$'
	$(call check_clean_log,$(LOG_DIR)/movie.log $(LOG_DIR)/movie.godot.log)
	ffmpeg -loglevel error -y -i $(LOG_DIR)/movie.avi -c:v libx264 -pix_fmt yuv420p $(LOG_DIR)/movie.mp4
	rm -f $(LOG_DIR)/movie.avi
	ffmpeg -v error -sseof -1 -i $(LOG_DIR)/movie.mp4 -frames:v 1 -vf signalstats,metadata=print:key=lavfi.signalstats.YAVG:file=- -f null - \
	  | awk -F= '/YAVG/ { found = 1; exit ($$2 >= 32) ? 0 : 1 } END { if (!found) exit 1 }'

# エディタなしでゲームを起動する (人が遊んで確かめる)。先にアセットをインポートする (.godot/ が無い初回や素材の
# 追加後に、エディタを開かずに起動すると素材が読み込めず起動に失敗するため)
run: import
	"$(GODOT)" $(ENGINE_LOG) --path .

# 引数の pck に scenario/ の全ファイルと、同梱フォントとそのライセンス文が入っていることを検査する。JSON と
# ライセンス文はスクリプトから参照されないデータで、export_presets.cfg の include_filter から漏れると、headless の
# 検証は通るのにエクスポートしたゲームだけ会話が始まらない・ライセンス文を同梱せずに配布することになる。フォントは
# Web ビルドがシステムフォントを使えず、入っていないと日本語が表示されないため。フォントのパスは pck の中では
# .import の参照にしか一致しないため、本体 (.godot/imported/<ファイル名>-<hash>.fontdata) も確かめる (macOS は pck が
# zip の中の .app に入るため検査しない)
PCK_REQUIRED_FILES := $(wildcard scenario/*.json) $(PROJECT_FONT) .godot/imported/$(notdir $(PROJECT_FONT))- assets/fonts/OFL.txt
define check_files_in_pck
for file in $(PCK_REQUIRED_FILES); do grep -qa "$$file" $(1) || { echo "pck にファイルがありません: $$file"; exit 1; }; echo "pck に格納: $$file"; done
endef

# エクスポート。プリセット名は export_presets.cfg と一致させる。実行には Godot 4.7 の各プラットフォームの export template が
# 必要 (AGENTS.md「検証方法」参照)。build/ に .gdignore を置き、エクスポート済みの画像を 2 回目以降の import で Godot に
# 読ませない。配信するのはデスクトップ 3 プラットフォーム (Steam) と iOS (別 issue で足す) で、Web は webtunnel で
# runner 上のブラウザから遊ぶ検証専用 (ADR 0002)
build-web: import
	@mkdir -p build/web
	@touch build/.gdignore
	"$(GODOT)" --headless $(ENGINE_LOG) --path . --export-release "Web" build/web/index.html > $(LOG_DIR)/build-web.log 2>&1; \
	echo "exit=$$?" >> $(LOG_DIR)/build-web.log; \
	tail -n 1 $(LOG_DIR)/build-web.log | grep -q '^exit=0$$'
	$(call check_clean_log,$(LOG_DIR)/build-web.log $(LOG_DIR)/build-web.godot.log)
	test -f build/web/index.html
	test -f build/web/index.wasm
	test -f build/web/index.pck
	$(call check_files_in_pck,build/web/index.pck)

build-macos: import
	@mkdir -p build/macos
	@touch build/.gdignore
	"$(GODOT)" --headless $(ENGINE_LOG) --path . --export-release "macOS" build/macos/fast-galge.zip > $(LOG_DIR)/build-macos.log 2>&1; \
	echo "exit=$$?" >> $(LOG_DIR)/build-macos.log; \
	tail -n 1 $(LOG_DIR)/build-macos.log | grep -q '^exit=0$$'
	$(call check_clean_log,$(LOG_DIR)/build-macos.log $(LOG_DIR)/build-macos.godot.log)
	test -f build/macos/fast-galge.zip

build-windows: import
	@mkdir -p build/windows
	@touch build/.gdignore
	"$(GODOT)" --headless $(ENGINE_LOG) --path . --export-release "Windows Desktop" build/windows/fast-galge.exe > $(LOG_DIR)/build-windows.log 2>&1; \
	echo "exit=$$?" >> $(LOG_DIR)/build-windows.log; \
	tail -n 1 $(LOG_DIR)/build-windows.log | grep -q '^exit=0$$'
	$(call check_clean_log,$(LOG_DIR)/build-windows.log $(LOG_DIR)/build-windows.godot.log)
	test -f build/windows/fast-galge.exe
	test -f build/windows/fast-galge.pck
	$(call check_files_in_pck,build/windows/fast-galge.pck)

build-linux: import
	@mkdir -p build/linux
	@touch build/.gdignore
	"$(GODOT)" --headless $(ENGINE_LOG) --path . --export-release "Linux" build/linux/fast-galge.x86_64 > $(LOG_DIR)/build-linux.log 2>&1; \
	echo "exit=$$?" >> $(LOG_DIR)/build-linux.log; \
	tail -n 1 $(LOG_DIR)/build-linux.log | grep -q '^exit=0$$'
	$(call check_clean_log,$(LOG_DIR)/build-linux.log $(LOG_DIR)/build-linux.godot.log)
	test -f build/linux/fast-galge.x86_64
	test -f build/linux/fast-galge.pck
	$(call check_files_in_pck,build/linux/fast-galge.pck)

# Steam に提出するデスクトップ 3 プラットフォームの一括エクスポート
build-all: build-macos build-windows build-linux

clean:
	rm -rf build $(LOG_DIR)
