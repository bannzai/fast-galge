# fast-galge の検証・ビルド入口。target 命名は ~/.claude/rules/makefile-target-naming.md に従う
# (`build-<対象>` = エクスポートだけ。`run` = エディタなしでの起動。`verify` = 人の操作なしで終わる検査)。
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
# movie target が録画するフレーム数 (30 fps 固定。150 = 5 秒)。操作なしの起動〜タイトルの表示の確認には
# 数秒あれば足り、CI の録画時間と artifact のサイズを抑えるため
MOVIE_FRAMES ?= 150

# 引数のログ (target の標準出力・標準エラーの保存先と、--log-file の Godot 自身のログ) の全文に WARNING / ERROR の行が
# 無いことを検査する。Godot は診断を記録しても exit 0 で終わることがあるため、exit code だけで判定しない。
# 描画付き起動だけで出る既知のノイズ (WINDOWED_LOG_NOISE) は除く
define check_clean_log
! grep -i -e 'WARNING' -e 'ERROR' $(1) | grep -v $(WINDOWED_LOG_NOISE) | grep -q .
endef

.DEFAULT_GOAL := verify
.PHONY: verify import check selfcheck integration lint test screenshot movie run build-web clean

# 人の操作なしで終わる検査の一括実行 (引数なしの make)。CI の lint / check-and-export job と同じ内容
verify: test

# ログ・撮影の出力先。.gdignore を置き、撮影した PNG を Godot に import させない
$(LOG_DIR)/.gdignore:
	@mkdir -p $(LOG_DIR)
	@touch $@

# アセットのインポート (初回・素材追加後)。.godot/ を生成する
import: $(LOG_DIR)/.gdignore
	"$(GODOT)" --headless $(ENGINE_LOG) --path . --import > $(LOG_DIR)/import.log 2>&1; \
	echo "exit=$$?" >> $(LOG_DIR)/import.log; \
	tail -n 1 $(LOG_DIR)/import.log | grep -q '^exit=0$$'
	$(call check_clean_log,$(LOG_DIR)/import.log $(LOG_DIR)/import.godot.log)

# 起動検証。メインシーンとスクリプトがロードでき、_ready が走ることを boot 出力で確認する
check: import
	"$(GODOT)" --headless $(ENGINE_LOG) --path . --quit > $(LOG_DIR)/check.log 2>&1; \
	echo "exit=$$?" >> $(LOG_DIR)/check.log; \
	grep -q '^fast-galge boot$$' $(LOG_DIR)/check.log
	tail -n 1 $(LOG_DIR)/check.log | grep -q '^exit=0$$'
	$(call check_clean_log,$(LOG_DIR)/check.log $(LOG_DIR)/check.godot.log)

# 画面の遷移表・全シーンのロード・全素材の assets/CREDITS.md への記録の検証 (headless)
selfcheck: import
	"$(GODOT)" --headless $(ENGINE_LOG) --path . --script res://scripts/dev/selfcheck.gd > $(LOG_DIR)/selfcheck.log 2>&1; \
	echo "exit=$$?" >> $(LOG_DIR)/selfcheck.log; \
	grep -q '^selfcheck OK$$' $(LOG_DIR)/selfcheck.log
	tail -n 1 $(LOG_DIR)/selfcheck.log | grep -q '^exit=0$$'
	$(call check_clean_log,$(LOG_DIR)/selfcheck.log $(LOG_DIR)/selfcheck.godot.log)

# キー入力でメインシーンを動かす入力統合テスト (headless)。タイトル → 会話中 → バックログ → 会話中の画面の遷移と、
# 見出しの追従を確認する
integration: import
	"$(GODOT)" --headless $(ENGINE_LOG) --path . --script res://scripts/dev/integration.gd > $(LOG_DIR)/integration.log 2>&1; \
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

# 操作を伴わない起動〜タイトル表示を Movie Maker モードで録画して mp4 にする (起動直後の描画崩れ・真っ黒を
# 検出する。headless は dummy レンダラで落ちるため描画付きで起動する)。真っ黒な動画を成功と誤認しないよう、
# 終了 1 秒前のフレームの輝度平均 (Y。limited range のため真っ黒 = 16) が 32 以上であることも検査する
movie: import
	rm -f $(LOG_DIR)/movie.avi $(LOG_DIR)/movie.mp4
	"$(GODOT)" $(ENGINE_LOG) --path . $(WINDOWED_FLAGS) --write-movie $(LOG_DIR)/movie.avi --fixed-fps 30 --quit-after $(MOVIE_FRAMES) > $(LOG_DIR)/movie.log 2>&1; \
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

# Web エクスポート (シングルスレッド)。プリセット名は export_presets.cfg と一致させる。
# 実行には Godot 4.7 の Web 用 export template (web_nothreads_release.zip) が必要 (AGENTS.md「検証方法」参照)
build-web: import
	@mkdir -p build/web
	"$(GODOT)" --headless $(ENGINE_LOG) --path . --export-release "Web" build/web/index.html > $(LOG_DIR)/build-web.log 2>&1; \
	echo "exit=$$?" >> $(LOG_DIR)/build-web.log; \
	tail -n 1 $(LOG_DIR)/build-web.log | grep -q '^exit=0$$'
	$(call check_clean_log,$(LOG_DIR)/build-web.log $(LOG_DIR)/build-web.godot.log)
	test -f build/web/index.html
	test -f build/web/index.wasm
	test -f build/web/index.pck

clean:
	rm -rf build $(LOG_DIR)
