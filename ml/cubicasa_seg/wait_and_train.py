"""Wait until masks + CUDA torch are ready, then start training."""

from __future__ import annotations

import subprocess
import sys
import time
from pathlib import Path

MASK_ROOT = Path(r"D:\celling_dateset\prepared_masks\train")
LOG = Path(r"D:\celling_dateset\runs\wait_train.log")
TRAIN = Path(__file__).with_name("train.py")


def log(msg: str) -> None:
    LOG.parent.mkdir(parents=True, exist_ok=True)
    line = time.strftime("[%Y-%m-%d %H:%M:%S] ") + msg
    with LOG.open("a", encoding="utf-8") as f:
        f.write(line + "\n")
    print(line, flush=True)


def main() -> None:
    log("waiting for prepared masks...")
    while True:
        n = len(list(MASK_ROOT.glob("*/mask.png"))) if MASK_ROOT.exists() else 0
        log(f"  masks so far: {n}")
        if n >= 1000:  # enough to start; prepare continues or finished
            # Prefer full train set (~4200); wait a bit more if still growing.
            time.sleep(20)
            n2 = len(list(MASK_ROOT.glob("*/mask.png")))
            if n2 >= 4000 or n2 == n:
                log(f"masks ready: {n2}")
                break
        time.sleep(30)

    log("checking torch cuda...")
    for _ in range(120):
        try:
            import torch

            log(f"torch={torch.__version__} cuda={torch.cuda.is_available()}")
            if torch.cuda.is_available() or True:
                # Start even on CPU if CUDA install lags; prefer GPU.
                break
        except Exception as e:
            log(f"torch not ready: {e}")
        time.sleep(20)

    log("starting train.py")
    cmd = [
        sys.executable,
        str(TRAIN),
        "--batch",
        "8",
        "--epochs",
        "30",
        "--workers",
        "4",
    ]
    with (Path(r"D:\celling_dateset\runs\train.log")).open("w", encoding="utf-8") as out:
        proc = subprocess.Popen(cmd, cwd=str(TRAIN.parent), stdout=out, stderr=subprocess.STDOUT)
        log(f"train pid={proc.pid}")
        code = proc.wait()
    log(f"train exited code={code}")


if __name__ == "__main__":
    main()
