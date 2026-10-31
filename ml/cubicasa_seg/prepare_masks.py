"""Rasterize CubiCasa5K SVG Wall/Space polygons → PNG masks (0=bg, 1=wall, 2=room)."""

from __future__ import annotations

import argparse
import re
import xml.etree.ElementTree as ET
from concurrent.futures import ProcessPoolExecutor, as_completed
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw
from tqdm import tqdm

NS = {"svg": "http://www.w3.org/2000/svg"}


def _parse_points(s: str) -> list[tuple[float, float]]:
    nums = [float(x) for x in re.findall(r"[-+]?\d*\.?\d+(?:[eE][-+]?\d+)?", s)]
    return list(zip(nums[0::2], nums[1::2]))


def _class_of(el: ET.Element) -> str:
    return (el.attrib.get("class") or "").strip()


def _ancestor_class(el: ET.Element, parent_map: dict) -> str:
    """CubiCasa puts Wall/Space on parent <g>, not on the <polygon> itself."""
    parts: list[str] = []
    cur: ET.Element | None = el
    while cur is not None:
        c = _class_of(cur)
        if c:
            parts.append(c)
        cur = parent_map.get(cur)
    return " ".join(parts)


def svg_to_mask(svg_path: Path, out_w: int, out_h: int) -> np.ndarray:
    """Return HxW uint8 mask: 0 bg, 1 wall, 2 room."""
    tree = ET.parse(svg_path)
    root = tree.getroot()
    parent_map = {c: p for p in root.iter() for c in p}
    vb = root.attrib.get("viewBox")
    if vb:
        parts = [float(x) for x in vb.replace(",", " ").split()]
        sx0, sy0, sw, sh = parts[0], parts[1], parts[2], parts[3]
    else:
        sx0, sy0 = 0.0, 0.0
        sw = float(root.attrib.get("width", out_w))
        sh = float(root.attrib.get("height", out_h))

    scale_x = out_w / max(sw, 1e-6)
    scale_y = out_h / max(sh, 1e-6)

    room_img = Image.new("L", (out_w, out_h), 0)
    wall_img = Image.new("L", (out_w, out_h), 0)
    room_draw = ImageDraw.Draw(room_img)
    wall_draw = ImageDraw.Draw(wall_img)

    for el in root.iter():
        tag = el.tag.split("}")[-1]
        if tag not in ("polygon", "polyline"):
            continue
        cls = _ancestor_class(el, parent_map)
        tokens = set(cls.split())
        pts_attr = el.attrib.get("points")
        if not pts_attr:
            continue
        pts = _parse_points(pts_attr)
        if len(pts) < 3:
            continue
        pix = [((x - sx0) * scale_x, (y - sy0) * scale_y) for x, y in pts]
        is_wall = "Wall" in tokens
        is_space = "Space" in tokens
        is_outdoor = "Outdoor" in tokens
        # Skip tiny dimension/furniture polygons tagged only as BoundaryPolygon etc.
        if is_wall:
            wall_draw.polygon(pix, outline=255, fill=255)
        elif is_space and not is_outdoor:
            room_draw.polygon(pix, outline=255, fill=255)

    room = np.array(room_img)
    wall = np.array(wall_img)
    mask = np.zeros((out_h, out_w), dtype=np.uint8)
    mask[room > 0] = 2
    mask[wall > 0] = 1  # walls win over room fill
    return mask


def _process_one(args: tuple[str, str, str, str]) -> str | None:
    rel, data_root, out_root, split = args
    rel = rel.strip().strip("/")
    if not rel:
        return None
    sample = Path(data_root) / rel
    svg = sample / "model.svg"
    img_path = sample / "F1_scaled.png"
    if not img_path.exists():
        img_path = sample / "F1_original.png"
    if not svg.exists() or not img_path.exists():
        return f"skip:{rel}"

    with Image.open(img_path) as im:
        w, h = im.size
    mask = svg_to_mask(svg, w, h)
    out_dir = Path(out_root) / split / rel.replace("/", "__")
    out_dir.mkdir(parents=True, exist_ok=True)
    Image.fromarray(mask, mode="L").save(out_dir / "mask.png")
    # Copy / symlink image reference as path file.
    (out_dir / "image_path.txt").write_text(str(img_path.resolve()), encoding="utf-8")
    return None


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "--data-root",
        default=r"D:\celling_dateset\cubicasa5k\cubicasa5k",
    )
    ap.add_argument(
        "--out-root",
        default=r"D:\celling_dateset\prepared_masks",
    )
    ap.add_argument("--workers", type=int, default=8)
    ap.add_argument("--max-samples", type=int, default=0, help="0 = all")
    args = ap.parse_args()

    data_root = Path(args.data_root)
    out_root = Path(args.out_root)
    out_root.mkdir(parents=True, exist_ok=True)

    for split in ("train", "val", "test"):
        lines = (data_root / f"{split}.txt").read_text(encoding="utf-8").splitlines()
        if args.max_samples > 0:
            lines = lines[: args.max_samples]
        jobs = [(ln, str(data_root), str(out_root), split) for ln in lines if ln.strip()]
        print(f"{split}: {len(jobs)} samples -> {out_root / split}")
        errors = 0
        with ProcessPoolExecutor(max_workers=args.workers) as ex:
            futs = [ex.submit(_process_one, j) for j in jobs]
            for fut in tqdm(as_completed(futs), total=len(futs), desc=split):
                err = fut.result()
                if err:
                    errors += 1
        print(f"  done, skipped/errors≈{errors}")


if __name__ == "__main__":
    main()
