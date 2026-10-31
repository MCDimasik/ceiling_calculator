# Prepare masks then train DeepLab on CubiCasa5K (RTX GPU if available).
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $Root

$LogDir = "D:\celling_dateset\runs"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$Log = Join-Path $LogDir "pipeline.log"

function Log($msg) {
  $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $msg
  Add-Content -Path $Log -Value $line
  Write-Host $line
}

Log "=== CubiCasa seg pipeline start ==="

# Prefer CUDA wheel if GPU present.
$hasGpu = $false
try {
  nvidia-smi | Out-Null
  $hasGpu = $true
} catch {}

if ($hasGpu) {
  Log "Installing torch CUDA 12.4..."
  python -m pip install --upgrade pip
  python -m pip install torch torchvision --index-url https://download.pytorch.org/whl/cu124
} else {
  Log "No GPU — CPU torch"
  python -m pip install torch torchvision
}

python -m pip install pillow numpy tqdm opencv-python-headless onnx

Log "Preparing masks..."
python prepare_masks.py --workers 8 2>&1 | Tee-Object -FilePath (Join-Path $LogDir "prepare.log")

Log "Training..."
python train.py --batch 8 --epochs 30 --workers 4 2>&1 | Tee-Object -FilePath (Join-Path $LogDir "train.log")

Log "Export ONNX..."
python export_onnx.py 2>&1 | Tee-Object -FilePath (Join-Path $LogDir "export.log")

Log "=== done ==="
