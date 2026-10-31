from pathlib import Path
import re
from collections import Counter

root = Path(r"D:\celling_dateset\cubicasa5k\cubicasa5k\colorful\10052\model.svg")
t = root.read_text(encoding="utf-8", errors="ignore")
classes = re.findall(r'class="([^"]+)"', t)
c = Counter()
for cl in classes:
    for part in cl.split():
        c[part] += 1
print(c.most_common(50))
print("polygons", len(re.findall(r"<polygon", t)))
