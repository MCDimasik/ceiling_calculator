"""Export best.pt → ONNX for later mobile / Flutter inference."""

from __future__ import annotations

import argparse
from pathlib import Path

import torch
import torch.nn as nn
from torchvision.models.segmentation import deeplabv3_mobilenet_v3_large


def build_model(num_classes: int = 3) -> nn.Module:
    model = deeplabv3_mobilenet_v3_large(weights=None)
    model.classifier[4] = nn.Conv2d(256, num_classes, kernel_size=1)
    if model.aux_classifier is not None:
        model.aux_classifier = None
    return model


class SegWrapper(nn.Module):
    def __init__(self, model: nn.Module):
        super().__init__()
        self.model = model

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        return self.model(x)["out"]


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--ckpt", default=r"D:\celling_dateset\runs\deeplab_rooms\best.pt")
    ap.add_argument("--out", default=r"D:\celling_dateset\runs\deeplab_rooms\room_walls.onnx")
    ap.add_argument("--size", type=int, default=512)
    args = ap.parse_args()

    ckpt = torch.load(args.ckpt, map_location="cpu")
    model = build_model(3)
    model.load_state_dict(ckpt["model"], strict=False)
    model.eval()
    wrapped = SegWrapper(model)

    dummy = torch.randn(1, 3, args.size, args.size)
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    torch.onnx.export(
        wrapped,
        dummy,
        str(out),
        input_names=["input"],
        output_names=["logits"],
        dynamic_axes={"input": {0: "batch"}, "logits": {0: "batch"}},
        opset_version=17,
    )
    print(f"wrote {out}")


if __name__ == "__main__":
    main()
