from pathlib import Path

import numpy as np
from PIL import Image

import iso_base


def _make_diamond_png(path: Path, w: int = 32, h: int = 32) -> None:
    """畫一個底座菱形:赤道在 y=h//2,半寬 h//4,線性收到上下頂點。"""
    arr = np.zeros((h, w, 4), dtype=np.uint8)
    cx, eq, max_hw = w // 2, h // 2, h // 4
    for y in range(h):
        hw = max_hw - abs(y - eq)
        if hw < 0:
            continue
        arr[y, cx - hw : cx + hw + 1, :] = (255, 0, 0, 255)
    Image.fromarray(arr, "RGBA").save(path)


def test_analyze_diamond(tmp_path):
    png = tmp_path / "diamond.png"
    _make_diamond_png(png, 32, 32)

    r = iso_base.analyze(png)
    assert r is not None
    assert r["tex_size"] == (32, 32)
    # 赤道在 image y=16 → iso_sort_offset = (32-1) - 16 = 15
    assert r["iso_sort_offset"] == 15.0
    # node-relative 四點:front, right, back, left
    assert r["collision_points"] == [(0.0, 8.0), (8.0, 0.0), (0.0, -8.0), (-8.0, 0.0)]


def test_analyze_transparent_returns_none(tmp_path):
    png = tmp_path / "blank.png"
    Image.new("RGBA", (16, 16), (0, 0, 0, 0)).save(png)
    assert iso_base.analyze(png) is None
