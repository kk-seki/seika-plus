# -*- coding: utf-8 -*-
"""GAP認証産地Excelの「認証期限」を、サイトで確かめた新しい期限に書き換える（SEIKA＋の月2回のGAPチェック用）。

使い方（3つ）:
  1) JGAP：SEIKA＋で延ばした分をExcelに入れる
     python3 gap_excel_update.py jgap <元のExcel> <延ばした分のJSON> <出力するExcel> <YYYY-MM-DD>
       （昔の形 python3 gap_excel_update.py <元> <JSON> <出力> <日付> でも同じ）
       JSON: [{coop_name, item_name, jgap_no, jgap_name, old_expires, new_expires}, ...]
  2) GGAP：調べる行とGGNを出す
     python3 gap_excel_update.py ggap-targets <Excel> <YYYY-MM-DD> [日数=60]
       → [{row, coop_name, item_name, ggn, expires}]（期限切れ・日数以内に切れる・期限が空欄か「-」の GGAP 行）
          ggn は 番号（AP列）か その右（AR列）の「40」で始まる13けたの数字。ないときは null。
  3) GGAP：サイトの結果をExcelに入れる
     python3 gap_excel_update.py ggap-apply <元のExcel> <結果のJSON> <出力するExcel> <YYYY-MM-DD>
       結果のJSON: [{row, ggn, result, valid_to, group_name}]（result が certified で、valid_to が今の期限より新しいか、期限が空欄の行だけ書く）
       → {saved, changed:[{row, coop_name, item_name, ggn, before, after}], rows:[SEIKA＋に渡す行]}

どれも：見つかった行の「認証期限」（AQ列）だけを書き換え、セルを黄色にしてメモを付ける。それ以外のセル・書式・行は触らない。
前の日付のチェックで付けた黄色とメモは消す（同じ日に付けたものは残す。JGAP と GGAP を同じ日に続けて入れられる）。
書き換えたものがあるときだけ保存する。結果は JSON で標準出力に出す。
"""
import sys, json, re, unicodedata, datetime
import openpyxl
from openpyxl.styles import PatternFill
from openpyxl.comments import Comment

AUTHOR = "SEIKA+自動"
MARK_RE = re.compile(r"サイトで自動更新 (\d{4}/\d{2}/\d{2})")
YELLOW = PatternFill(fill_type="solid", fgColor="FFFF00")
NOFILL = PatternFill(fill_type=None)
COL_STATUS, COL_NAME, COL_ITEM, COL_CERT, COL_NO, COL_EXP, COL_AFTER = 1, 2, 4, 41, 42, 43, 44  # A, B, D, AO, AP, AQ, AR

ITEM_ALIAS = {"ロメインレタス": "ロメイン", "たまねぎ": "玉葱", "玉ねぎ": "玉葱", "長ねぎ": "長葱", "ねぎ": "長葱",
              "チンゲン菜": "青梗菜", "ちんげんさい": "青梗菜"}


def nk(s):
    return re.sub(r"[\s　]+", "", unicodedata.normalize("NFKC", str(s or ""))).strip()


def item_key(s):
    k = nk(s)
    return nk(ITEM_ALIAS.get(k, k))


def no_key(s):
    return re.sub(r"\D", "", unicodedata.normalize("NFKC", str(s or ""))).lstrip("0")


def name_key(s):
    k = nk(s)
    k = re.sub(r"(株式会社|有限会社|農事組合法人|\(株\)|\(有\)|㈱|㈲)", "", k)
    return k.upper()


def as_date(v):
    if isinstance(v, datetime.datetime):
        return v.date()
    if isinstance(v, datetime.date):
        return v
    m = re.search(r"(\d{4})\D+(\d{1,2})\D+(\d{1,2})", unicodedata.normalize("NFKC", str(v or "")))
    if m:
        try:
            return datetime.date(int(m[1]), int(m[2]), int(m[3]))
        except ValueError:
            return None
    return None


def ggn_of(*vals):
    for v in vals:
        if isinstance(v, (int, float)) and not isinstance(v, bool):
            v = str(int(v))
        for m in re.finditer(r"(?<!\d)(40\d{11})(?!\d)", unicodedata.normalize("NFKC", str(v or ""))):
            return m.group(1)
    return None


def is_ggap(ws, r):
    c = nk(ws.cell(r, COL_CERT).value).upper()
    return c in ("GGAP", "GLOBALGAP", "GLOBALG.A.P.")


def clear_old_marks(ws, today):
    tday = f"{today:%Y/%m/%d}"
    for r in range(5, ws.max_row + 1):
        c = ws.cell(r, COL_EXP)
        if c.comment is None:
            continue
        m = MARK_RE.search(c.comment.text or "")
        if m and m.group(1) != tday:
            c.comment = None
            c.fill = NOFILL


def write_exp(ws, r, new, today, before, src):
    c = ws.cell(r, COL_EXP)
    c.value = datetime.datetime(new.year, new.month, new.day)
    c.number_format = "yyyy/m/d;@"
    c.fill = YELLOW
    cm = Comment(f"{src}サイトで自動更新 {today:%Y/%m/%d}\n前：{before}", AUTHOR)
    cm.width, cm.height = 260, 90
    c.comment = cm


def before_text(v):
    d = as_date(v)
    return d.strftime("%Y/%m/%d") if d else (str(v).strip() if v not in (None, "") else "空欄")


def save(wb, out):
    try:
        wb.calculation.fullCalcOnLoad = True
    except Exception:
        pass
    wb.save(out)


def cmd_jgap(src, upd_json, out, today):
    ups = json.load(open(upd_json, encoding="utf-8"))
    tday = datetime.date.fromisoformat(today)
    wb = openpyxl.load_workbook(src)
    ws = wb["Sheet1"]
    clear_old_marks(ws, tday)
    rows = []
    for r in range(5, ws.max_row + 1):
        name, item = ws.cell(r, COL_NAME).value, ws.cell(r, COL_ITEM).value
        if name and item:
            rows.append((r, name_key(name), item_key(item), no_key(ws.cell(r, COL_NO).value)))
    changed, not_found, already = [], [], []
    for u in ups:
        new = datetime.date.fromisoformat(u["new_expires"])
        ik, nok = item_key(u["item_name"]), no_key(u.get("jgap_no"))
        hit = [r for r in rows if nok and r[3] == nok and r[2] == ik]
        if not hit:
            ck = name_key(u["coop_name"])
            hit = [r for r in rows if r[2] == ik and ck and (r[1] == ck or ck in r[1] or r[1] in ck)]
        if not hit:
            not_found.append(u)
            continue
        for (r, *_rest) in hit:
            cur = as_date(ws.cell(r, COL_EXP).value)
            if cur is not None and cur >= new:
                already.append({"row": r, "coop": ws.cell(r, COL_NAME).value, "item": ws.cell(r, COL_ITEM).value, "expires": cur.isoformat()})
                continue
            before = before_text(ws.cell(r, COL_EXP).value)
            write_exp(ws, r, new, tday, before + f"\nサイト：{u.get('jgap_name','')}（{u.get('jgap_no','')}）", "JGAP")
            changed.append({"row": r, "coop": ws.cell(r, COL_NAME).value, "item": ws.cell(r, COL_ITEM).value,
                            "before": before, "after": new.strftime("%Y/%m/%d")})
    if changed:
        save(wb, out)
    return {"saved": bool(changed), "changed": changed, "not_found": not_found, "already": already}


def cmd_ggap_targets(src, today, days="60"):
    tday = datetime.date.fromisoformat(today)
    limit = tday + datetime.timedelta(days=int(days))
    ws = openpyxl.load_workbook(src)["Sheet1"]
    out = []
    for r in range(5, ws.max_row + 1):
        name, item = ws.cell(r, COL_NAME).value, ws.cell(r, COL_ITEM).value
        if not name or not item or not is_ggap(ws, r):
            continue
        if "認証取得済" not in nk(ws.cell(r, COL_STATUS).value):
            continue
        exp = as_date(ws.cell(r, COL_EXP).value)
        if exp is not None and exp > limit:
            continue
        out.append({"row": r, "coop_name": str(name).strip(), "item_name": str(item).strip(),
                    "ggn": ggn_of(ws.cell(r, COL_NO).value, ws.cell(r, COL_AFTER).value),
                    "expires": exp.isoformat() if exp else None})
    return out


def cmd_ggap_apply(src, res_json, out, today):
    res = json.load(open(res_json, encoding="utf-8"))
    tday = datetime.date.fromisoformat(today)
    wb = openpyxl.load_workbook(src)
    ws = wb["Sheet1"]
    clear_old_marks(ws, tday)
    changed, rows = [], []
    for x in res:
        r = int(x["row"])
        name, item = ws.cell(r, COL_NAME).value, ws.cell(r, COL_ITEM).value
        if not name or not item or not is_ggap(ws, r):
            continue
        ggn = x.get("ggn") or None
        if ggn and ggn != ggn_of(ws.cell(r, COL_NO).value, ws.cell(r, COL_AFTER).value):
            continue  # 行がずれている（別の行）ときは書かない
        result = x.get("result") or ("no_ggn" if not ggn else "not_searched")
        new = None
        if result == "certified":
            try:
                new = datetime.date.fromisoformat(str(x.get("valid_to") or ""))
            except ValueError:
                result = "not_searched"
        rows.append({"coop_name": str(name).strip(), "item_name": str(item).strip(), "ggn": ggn, "result": result,
                     "valid_to": new.isoformat() if new else None, "group_name": x.get("group_name") or ""})
        if result != "certified":
            continue
        cur = as_date(ws.cell(r, COL_EXP).value)
        if cur is not None and cur >= new:
            continue
        before = before_text(ws.cell(r, COL_EXP).value)
        write_exp(ws, r, new, tday, before + f"\nGGN：{ggn}" + (f"（{x.get('group_name')}）" if x.get("group_name") else ""), "GLOBALG.A.P.")
        changed.append({"row": r, "coop_name": str(name).strip(), "item_name": str(item).strip(), "ggn": ggn,
                        "before": before, "after": new.strftime("%Y/%m/%d")})
    if changed:
        save(wb, out)
    return {"saved": bool(changed), "changed": changed, "rows": rows}


def main(argv):
    if argv and argv[0] == "ggap-targets":
        r = cmd_ggap_targets(*argv[1:4])
    elif argv and argv[0] == "ggap-apply":
        r = cmd_ggap_apply(*argv[1:5])
    elif argv and argv[0] == "jgap":
        r = cmd_jgap(*argv[1:5])
    else:
        r = cmd_jgap(*argv[0:4])
    print(json.dumps(r, ensure_ascii=False, indent=1))


if __name__ == "__main__":
    main(sys.argv[1:])
