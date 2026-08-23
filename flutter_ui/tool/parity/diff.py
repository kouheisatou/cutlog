"""撮った2枚を重ねて、どれだけ違うかを測る。

★ 数字ひとつでは直しようがない。
  「どこが」違うかを絵にして残し、行ごとのずれも出す。
  Flutter は文字を自前で描くので、字の縁だけは必ず少し違う。
  だから「まったく同じ画素の率」と「目に見える差の率」を分けて出す。
"""
import json
import re
import sys
from pathlib import Path

from PIL import Image, ImageChops

# これ以下の差は、字の縁のなめらかさの違いとみなす（0-255）
TOLERANCE = 32


def compare(a_path: Path, b_path: Path, out_path: Path, ignore=()):
    a = Image.open(a_path).convert("RGB")
    b = Image.open(b_path).convert("RGB")

    if a.size != b.size:
        b = b.resize(a.size)
        resized = True
    else:
        resized = False

    diff = ImageChops.difference(a, b)
    gray = diff.convert("L")

    # 測らないところ（作り物のカメラの絵など）は、まっさらに塗り潰してから数える
    if ignore:
        scale = a.size[0] / 390          # 端末の画素と CSS px の比
        for box in ignore:
            gray.paste(0, (int(box["x"] * scale), int(box["y"] * scale),
                           int((box["x"] + box["w"]) * scale), int((box["y"] + box["h"]) * scale)))
            a.paste((255, 255, 255), (int(box["x"] * scale), int(box["y"] * scale),
                                      int((box["x"] + box["w"]) * scale), int((box["y"] + box["h"]) * scale)))
            b.paste((255, 255, 255), (int(box["x"] * scale), int(box["y"] * scale),
                                      int((box["x"] + box["w"]) * scale), int((box["y"] + box["h"]) * scale)))
    total = a.size[0] * a.size[1]

    strict = sum(1 for p in gray.getdata() if p > 0)
    visible = sum(1 for p in gray.getdata() if p > TOLERANCE)

    # 違うところを赤く塗った絵を残す
    mask = gray.point(lambda p: 255 if p > TOLERANCE else 0)
    overlay = a.copy()
    red = Image.new("RGB", a.size, (255, 0, 0))
    overlay.paste(red, mask=mask)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    overlay.save(out_path)

    # 横の帯ごとに、どのあたりがずれているかを出す（直す場所の当たりを付ける）
    rows = []
    w, h = a.size
    band = max(1, h // 40)
    px = list(gray.getdata())
    for top in range(0, h, band):
        bottom = min(h, top + band)
        n = sum(1 for y in range(top, bottom) for x in range(w) if px[y * w + x] > TOLERANCE)
        if n:
            rows.append({"y": top, "h": bottom - top, "pct": round(n * 100 / (w * (bottom - top)), 2)})
    rows.sort(key=lambda r: -r["pct"])

    # 字の形そのものの違い（Flutter web は Noto、Chrome は Hiragino を使う）に
    # 埋もれないよう、粗くぼかしてから測る「置き場所の差」も出す。
    # ★ こちらが本命。位置・大きさ・色のずれだけが残る。
    small_a = a.resize((a.size[0] // 8, a.size[1] // 8), Image.BOX)
    small_b = b.resize((a.size[0] // 8, a.size[1] // 8), Image.BOX)
    small_diff = ImageChops.difference(small_a, small_b).convert("L")
    small_total = small_a.size[0] * small_a.size[1]
    layout = sum(1 for p in small_diff.getdata() if p > 24)

    return {
        "layout_pct": round(layout * 100 / small_total, 3),
        "strict_pct": round(strict * 100 / total, 3),
        "visible_pct": round(visible * 100 / total, 3),
        "size": list(a.size),
        "resized": resized,
        "worst_bands": rows[:6],
    }


def main():
    root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("shots")
    ref_dir, got_dir = root / "web", root / "flutter"
    out_dir = root / "diff"

    # 画面ごとの「測らないところ」を screens.mjs から読む
    ignores = {}
    src = (Path(__file__).parent / "screens.mjs").read_text()
    for m in re.finditer(r"name: '([a-z0-9-]+)',[\s\S]{0,400}?ignore: (\[[^\]]*\])", src):
        ignores[m.group(1)] = json.loads(m.group(2).replace("x:", '"x":').replace("y:", '"y":')
                                         .replace("w:", '"w":').replace("h:", '"h":'))

    report = {}
    for ref in sorted(ref_dir.glob("*.png")):
        got = got_dir / ref.name
        if not got.exists():
            report[ref.stem] = {"missing": True}
            continue
        report[ref.stem] = compare(ref, got, out_dir / ref.name, ignores.get(ref.stem, ()))

    (root / "diff.json").write_text(json.dumps(report, ensure_ascii=False, indent=2))

    print(f"{'画面':<14}{'置き場所':>9}{'見える差':>10}{'完全一致でない':>16}")
    print("-" * 50)
    for name, r in sorted(report.items(), key=lambda kv: -(kv[1].get("layout_pct") or 0)):
        if r.get("missing"):
            print(f"{name:<14}{'まだ無い':>9}")
        else:
            print(f"{name:<14}{r['layout_pct']:>8.2f}%{r['visible_pct']:>9.2f}%{r['strict_pct']:>15.2f}%")


if __name__ == "__main__":
    main()
