"""Tests for manifest.export_surface_map()."""
from __future__ import annotations

import json
from pathlib import Path

import pytest

import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "pipeline"))

import manifest


@pytest.fixture
def tmp_project(tmp_path, monkeypatch):
    """Point manifest at a temp project root."""
    monkeypatch.setattr(manifest, "_project_root", lambda: tmp_path)
    (tmp_path / "art_source" / "tilesets").mkdir(parents=True)
    (tmp_path / "game" / "assets" / "audio").mkdir(parents=True)
    return tmp_path


def _write_tileset(root: Path, name: str, fields: dict) -> None:
    d = root / "art_source" / "tilesets" / name
    d.mkdir(exist_ok=True)
    payload = {"status": "completed", "tileset_id": "x", **fields}
    (d / "asset.json").write_text(json.dumps(payload), encoding="utf-8")


def test_export_includes_tilesets_with_surface_id(tmp_project):
    _write_tileset(tmp_project, "courtyard_grass_dirt", {"surface_id": "grass"})
    _write_tileset(tmp_project, "market_tile_concrete", {"surface_id": "concrete"})

    out = manifest.export_surface_map()

    expected = tmp_project / "game" / "assets" / "audio" / "surface_map.json"
    assert out == expected
    data = json.loads(expected.read_text(encoding="utf-8"))
    assert data == {
        "courtyard_grass_dirt": "grass",
        "market_tile_concrete": "concrete",
    }


def test_export_skips_tilesets_without_surface_id(tmp_project):
    _write_tileset(tmp_project, "with_surface", {"surface_id": "wood"})
    _write_tileset(tmp_project, "no_surface", {})              # missing key
    _write_tileset(tmp_project, "null_surface", {"surface_id": None})  # explicit null
    _write_tileset(tmp_project, "empty_surface", {"surface_id": ""})  # empty string

    manifest.export_surface_map()

    data = json.loads(
        (tmp_project / "game" / "assets" / "audio" / "surface_map.json").read_text("utf-8")
    )
    assert data == {"with_surface": "wood"}


def test_export_overwrites_existing_file(tmp_project):
    target = tmp_project / "game" / "assets" / "audio" / "surface_map.json"
    target.write_text('{"stale": "data"}', encoding="utf-8")

    _write_tileset(tmp_project, "fresh", {"surface_id": "stone"})
    manifest.export_surface_map()

    assert json.loads(target.read_text("utf-8")) == {"fresh": "stone"}
