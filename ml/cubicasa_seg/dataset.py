from __future__ import annotations

from pathlib import Path

import numpy as np
import torch
from PIL import Image
from torch.utils.data import Dataset
import torchvision.transforms.functional as TF


class FloorplanSegDataset(Dataset):
    """Reads prepared_masks/{split}/*/mask.png + image_path.txt."""

    def __init__(
        self,
        root: str | Path,
        split: str = "train",
        size: int = 512,
        augment: bool = False,
    ):
        self.root = Path(root) / split
        self.size = size
        self.augment = augment
        self.samples = sorted(
            [p for p in self.root.iterdir() if p.is_dir() and (p / "mask.png").exists()]
        )
        if not self.samples:
            raise FileNotFoundError(f"No samples in {self.root}")

    def __len__(self) -> int:
        return len(self.samples)

    def __getitem__(self, idx: int):
        d = self.samples[idx]
        img_path = (d / "image_path.txt").read_text(encoding="utf-8").strip()
        image = Image.open(img_path).convert("RGB")
        mask = Image.open(d / "mask.png")

        image = TF.resize(image, [self.size, self.size], antialias=True)
        mask = TF.resize(mask, [self.size, self.size], interpolation=TF.InterpolationMode.NEAREST)

        if self.augment:
            if torch.rand(1).item() < 0.5:
                image = TF.hflip(image)
                mask = TF.hflip(mask)
            if torch.rand(1).item() < 0.5:
                image = TF.vflip(image)
                mask = TF.vflip(mask)
            angle = float(torch.empty(1).uniform_(-12, 12))
            image = TF.rotate(image, angle, fill=255)
            mask = TF.rotate(mask, angle, fill=0, interpolation=TF.InterpolationMode.NEAREST)

        img_t = TF.to_tensor(image)
        img_t = TF.normalize(img_t, mean=[0.485, 0.456, 0.406], std=[0.229, 0.224, 0.225])
        mask_t = torch.from_numpy(np.array(mask, dtype=np.int64))
        return img_t, mask_t
