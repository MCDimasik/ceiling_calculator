"""Generate Android/web launcher icons from assets/media/logo-visota.PNG."""
from __future__ import annotations

from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "assets" / "media" / "logo-visota.PNG"
RES = ROOT / "android" / "app" / "src" / "main" / "res"
WEB = ROOT / "web" / "icons"


def make_opaque_icon(im: Image.Image, size: int, pad_ratio: float = 0.12) -> Image.Image:
    bg = Image.new("RGBA", (size, size), (255, 255, 255, 255))
    inner = int(size * (1 - 2 * pad_ratio))
    logo = im.copy()
    logo.thumbnail((inner, inner), Image.Resampling.LANCZOS)
    x = (size - logo.width) // 2
    y = (size - logo.height) // 2
    bg.paste(logo, (x, y), logo)
    return bg


def make_fg(im: Image.Image, size: int) -> Image.Image:
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    inner = int(size * 0.66)
    logo = im.copy()
    logo.thumbnail((inner, inner), Image.Resampling.LANCZOS)
    x = (size - logo.width) // 2
    y = (size - logo.height) // 2
    canvas.paste(logo, (x, y), logo)
    return canvas


def main() -> None:
    im = Image.open(SRC).convert("RGBA")
    print("logo", im.size)

    densities = {
        "mipmap-mdpi": 48,
        "mipmap-hdpi": 72,
        "mipmap-xhdpi": 96,
        "mipmap-xxhdpi": 144,
        "mipmap-xxxhdpi": 192,
    }
    for folder, size in densities.items():
        out = RES / folder / "ic_launcher.png"
        out.parent.mkdir(parents=True, exist_ok=True)
        make_opaque_icon(im, size).save(out, "PNG")
        print("wrote", out.name, folder, size)

    fg_densities = {
        "drawable-mdpi": 108,
        "drawable-hdpi": 162,
        "drawable-xhdpi": 216,
        "drawable-xxhdpi": 324,
        "drawable-xxxhdpi": 432,
    }
    for folder, size in fg_densities.items():
        out = RES / folder / "ic_launcher_foreground.png"
        if not out.parent.exists():
            continue
        make_fg(im, size).save(out, "PNG")
        print("wrote", out.name, folder, size)

    WEB.mkdir(parents=True, exist_ok=True)
    for name, size in (
        ("Icon-192.png", 192),
        ("Icon-512.png", 512),
        ("Icon-maskable-192.png", 192),
        ("Icon-maskable-512.png", 512),
    ):
        make_opaque_icon(im, size, pad_ratio=0.11).save(WEB / name, "PNG")
        print("wrote web", name)

    fav = make_opaque_icon(im, 32)
    fav.save(ROOT / "web" / "favicon.png", "PNG")
    print("done")


if __name__ == "__main__":
    main()
