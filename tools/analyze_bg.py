from __future__ import annotations

from pathlib import Path


def _fmt_rgb(rgb: tuple[int, int, int]) -> str:
    return "#{:02X}{:02X}{:02X}".format(*rgb)


def analyze(path: Path, *, colors: int = 10) -> dict:
    # Pillow is already available in this project via Kivy's deps on Windows.
    from PIL import Image

    im = Image.open(path).convert("RGB")
    im_s = im.resize((180, 180))
    pal = im_s.quantize(colors=colors).convert("RGB")
    items = pal.getcolors(180 * 180) or []
    items.sort(reverse=True, key=lambda x: x[0])

    top = [c for _, c in items[:6]]
    px = list(im_s.getdata())
    avg = tuple(sum(p[i] for p in px) // len(px) for i in range(3))
    return {"avg": avg, "top": top}


def main() -> int:
    base = Path(__file__).resolve().parents[1] / "assets"
    targets = {
        "bg_light": base / "bg_light.png",
        "bg_dark": base / "bg_dark.png",
    }

    for name, p in targets.items():
        d = analyze(p)
        print(name, str(p))
        print(" avg", d["avg"], _fmt_rgb(d["avg"]))
        print(" top", [(_fmt_rgb(c), c) for c in d["top"]])
        print()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

