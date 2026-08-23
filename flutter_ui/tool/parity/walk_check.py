"""触ってみた各手順の絵を、本物の絵と重ねて判を押す。

★ 「何かが出た」ではなく「正しい画面に着いた」ことを見る。
  似て非なる画面に着いても気づけるようにするため。
"""
import json
import sys
from pathlib import Path

from PIL import Image, ImageChops

# これを超えたら「別の画面に居る」とみなす（置き場所の差）
LIMIT = 12.0


def layout_diff(a_path: Path, b_path: Path) -> float:
    a = Image.open(a_path).convert("RGB")
    b = Image.open(b_path).convert("RGB")
    if a.size != b.size:
        b = b.resize(a.size)
    w, h = a.size[0] // 8, a.size[1] // 8
    d = ImageChops.difference(a.resize((w, h), Image.BOX), b.resize((w, h), Image.BOX)).convert("L")
    return sum(1 for p in d.getdata() if p > 24) * 100 / (w * h)


def main():
    root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("shots")
    steps = json.loads((root / "walk" / "_report.json").read_text())

    print(f"{'手順':<26}{'着いた先':>10}{'判定':>8}")
    print("-" * 46)
    bad = 0
    for s in steps:
        want = s.get("expect")
        if not s["ok"]:
            print(f"{s['name']:<26}{'—':>10}{'だめ':>8}  {s.get('error','')}")
            bad += 1
            continue
        if not want:
            print(f"{s['name']:<26}{'—':>10}{'ok':>8}")
            continue
        ref = root / "web" / f"{want}.png"
        if not ref.exists():
            print(f"{s['name']:<26}{want:>10}{'比べる相手なし':>8}")
            continue
        pct = layout_diff(ref, Path(s["file"]))
        ok = pct <= (s.get("allow") or LIMIT)
        if not ok:
            bad += 1
        print(f"{s['name']:<26}{want:>10}{('ok' if ok else 'ちがう'):>8}  差 {pct:.1f}%")

    print(f"\n{len(steps) - bad}/{len(steps)} 手順が通りました。")
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
