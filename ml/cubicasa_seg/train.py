"""Train DeepLabV3-MobileNetV3 wall/room seg on CubiCasa5K prepared masks."""

from __future__ import annotations

import argparse
import json
import time
from pathlib import Path

import torch
import torch.nn as nn
from torch.utils.data import DataLoader
from torchvision.models.segmentation import (
    DeepLabV3_MobileNet_V3_Large_Weights,
    deeplabv3_mobilenet_v3_large,
)
from tqdm import tqdm

from dataset import FloorplanSegDataset


def build_model(num_classes: int = 3) -> nn.Module:
    weights = DeepLabV3_MobileNet_V3_Large_Weights.DEFAULT
    model = deeplabv3_mobilenet_v3_large(weights=weights)
    # Replace final 1x1 (COCO 21-class → our 3-class).
    model.classifier[4] = nn.Conv2d(256, num_classes, kernel_size=1)
    # Aux head (if present) has a different in_channels — drop it to avoid mismatch.
    model.aux_classifier = None
    return model


@torch.no_grad()
def eval_miou(model, loader, device, num_classes: int = 3) -> float:
    model.eval()
    inter = torch.zeros(num_classes, device=device)
    union = torch.zeros(num_classes, device=device)
    for images, masks in loader:
        images = images.to(device)
        masks = masks.to(device)
        pred = model(images)["out"].argmax(1)
        for c in range(num_classes):
            pred_c = pred == c
            gt_c = masks == c
            inter[c] += (pred_c & gt_c).sum()
            union[c] += (pred_c | gt_c).sum()
    ious = []
    for c in range(1, num_classes):  # skip bg
        if union[c] > 0:
            ious.append((inter[c] / union[c]).item())
    return float(sum(ious) / max(len(ious), 1))


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--data", default=r"D:\celling_dateset\prepared_masks")
    ap.add_argument("--out", default=r"D:\celling_dateset\runs\deeplab_rooms")
    ap.add_argument("--size", type=int, default=512)
    ap.add_argument("--batch", type=int, default=8)
    ap.add_argument("--epochs", type=int, default=30)
    ap.add_argument("--lr", type=float, default=3e-4)
    ap.add_argument("--workers", type=int, default=4)
    ap.add_argument("--resume", default="")
    args = ap.parse_args()

    out_dir = Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    print(f"device={device}")

    train_ds = FloorplanSegDataset(args.data, "train", size=args.size, augment=True)
    val_ds = FloorplanSegDataset(args.data, "val", size=args.size, augment=False)
    train_loader = DataLoader(
        train_ds,
        batch_size=args.batch,
        shuffle=True,
        num_workers=args.workers,
        pin_memory=device.type == "cuda",
    )
    val_loader = DataLoader(
        val_ds,
        batch_size=args.batch,
        shuffle=False,
        num_workers=max(1, args.workers // 2),
        pin_memory=device.type == "cuda",
    )
    print(f"train={len(train_ds)} val={len(val_ds)}")

    model = build_model(3).to(device)
    opt = torch.optim.AdamW(model.parameters(), lr=args.lr, weight_decay=1e-4)
    sched = torch.optim.lr_scheduler.CosineAnnealingLR(opt, T_max=args.epochs)
    # walls are thin → upweight class 1
    crit = nn.CrossEntropyLoss(weight=torch.tensor([0.5, 3.0, 1.5], device=device))

    start_epoch = 0
    best = 0.0
    history: list[dict] = []
    if args.resume and Path(args.resume).exists():
        ckpt = torch.load(args.resume, map_location=device)
        model.load_state_dict(ckpt["model"])
        opt.load_state_dict(ckpt["opt"])
        start_epoch = ckpt.get("epoch", 0) + 1
        best = ckpt.get("best", 0.0)
        print(f"resumed epoch={start_epoch} best={best:.4f}")

    for epoch in range(start_epoch, args.epochs):
        model.train()
        loss_sum = 0.0
        t0 = time.time()
        pbar = tqdm(train_loader, desc=f"epoch {epoch+1}/{args.epochs}")
        for images, masks in pbar:
            images = images.to(device)
            masks = masks.to(device)
            opt.zero_grad(set_to_none=True)
            pred = model(images)
            loss = crit(pred["out"], masks)
            loss.backward()
            opt.step()
            loss_sum += loss.item()
            pbar.set_postfix(loss=f"{loss.item():.3f}")
        sched.step()
        train_loss = loss_sum / max(len(train_loader), 1)
        miou = eval_miou(model, val_loader, device)
        row = {
            "epoch": epoch + 1,
            "train_loss": train_loss,
            "val_miou": miou,
            "sec": time.time() - t0,
        }
        history.append(row)
        print(f"epoch {epoch+1}: loss={train_loss:.4f} val_mIoU={miou:.4f}")

        ckpt = {
            "epoch": epoch,
            "model": model.state_dict(),
            "opt": opt.state_dict(),
            "best": best,
            "args": vars(args),
        }
        torch.save(ckpt, out_dir / "last.pt")
        if miou >= best:
            best = miou
            ckpt["best"] = best
            torch.save(ckpt, out_dir / "best.pt")
            print(f"  saved best.pt (mIoU={best:.4f})")
        (out_dir / "history.json").write_text(json.dumps(history, indent=2), encoding="utf-8")

    print(f"done. best mIoU={best:.4f} -> {out_dir / 'best.pt'}")


if __name__ == "__main__":
    main()
