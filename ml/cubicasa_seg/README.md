# CubiCasa5K room/wall segmentation

Датасет: `D:\celling_dateset\cubicasa5k` (PNG + SVG).

## Классы маски

| id | смысл |
|----|--------|
| 0 | фон |
| 1 | стена (`Wall`) |
| 2 | комната (`Space`, без Outdoor) |

## Запуск

```powershell
cd ml\cubicasa_seg
powershell -ExecutionPolicy Bypass -File .\run_pipeline.ps1
```

Или по шагам:

```powershell
python prepare_masks.py
python train.py --batch 8 --epochs 30
python export_onnx.py
```

Артефакты: `D:\celling_dateset\runs\deeplab_rooms\` (`best.pt`, `room_walls.onnx`, `history.json`).

## Инференс в приложении (следующий шаг)

Tap → softmax маски room → flood-fill компоненты → контур → углы.
ONNX Runtime / TFLite на телефоне.
