extends RefCounted
## クレジット画面に出す内容。素材の出典は素材の記録 (assets/CREDITS.md) の表をそのまま読んで出し (出典を 2 箇所に
## 書かないため。エクスポートには export_presets.cfg の include_filter で含める)、法務ドキュメントと問い合わせ先は
## 紹介ページ (docs/。GitHub Pages) の URL を開く。

## 素材の記録
const CREDITS_PATH: String = "res://assets/CREDITS.md"
## 利用規約・プライバシーポリシー (docs/Terms-ja.md・docs/PrivacyPolicy-ja.md の公開先)
const TERMS_URL: String = "https://bannzai.github.io/fast-galge/Terms-ja"
const PRIVACY_URL: String = "https://bannzai.github.io/fast-galge/PrivacyPolicy-ja"
## サポートページ (紹介ページ docs/index.html のサポート節) と、そこに載せている問い合わせのメールの宛先
const SUPPORT_URL: String = "https://bannzai.github.io/fast-galge/#support"
const MAIL_URL: String = "mailto:bannzai.app@gmail.com"
## 素材の表に行が無い時にクレジット画面に出す文
const NO_ENTRIES_TEXT: String = "外部の素材は使っていません"


## 素材の記録 (CREDITS_PATH) を読み、クレジット画面に出す文にする。読めない時はエラーを出して空の文を返す
static func load_text() -> String:
	if not FileAccess.file_exists(CREDITS_PATH):
		push_error("素材の記録が読めない: %s" % CREDITS_PATH)
		return ""
	var entries: Array[String] = entries_of(FileAccess.get_file_as_string(CREDITS_PATH))
	if entries.is_empty():
		return NO_ENTRIES_TEXT
	return "\n\n".join(PackedStringArray(entries))


## markdown (素材の記録の中身) の最初の表の、見出しの行と区切りの行を除いた各行を、クレジット画面に出す文にする。
## 1 行目に最初の列 (素材)、2 行目に残りの列を「見出し: 値」で並べる。バッククォートは外す
static func entries_of(markdown: String) -> Array[String]:
	var rows: Array[PackedStringArray] = []
	for line: String in markdown.split("\n"):
		var trimmed: String = line.strip_edges()
		if trimmed.begins_with("|"):
			rows.append(_cells(trimmed))
		elif not rows.is_empty():
			break
	var entries: Array[String] = []
	if rows.size() <= 2:
		return entries
	var header: PackedStringArray = rows[0]
	for row: PackedStringArray in rows.slice(2):
		var details: PackedStringArray = []
		for column: int in range(1, row.size()):
			var heading: String = header[column] if column < header.size() else ""
			details.append("%s: %s" % [heading, row[column]])
		entries.append("%s\n%s" % [row[0], " / ".join(details)])
	return entries


## 表の 1 行 (row。前後の | を含む) の各列の値。前後の空白とバッククォートを外す
static func _cells(row: String) -> PackedStringArray:
	var cells: PackedStringArray = []
	for cell: String in row.trim_prefix("|").trim_suffix("|").split("|"):
		cells.append(cell.strip_edges().replace("`", ""))
	return cells
