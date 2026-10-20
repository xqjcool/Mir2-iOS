"""Validate the coordinate-based Mengzhong map art-reference repairs."""
from pathlib import Path
import csv
import hashlib
import json
import struct


ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "GameData"
MAP = DATA / "maps" / "3"


def read_json(path: Path):
    return json.loads(path.read_text(encoding="utf8"))


manifest = read_json(ROOT / "mengzhong-image-reference-patch.json")
scene = read_json(MAP / "scene.json")
report = read_json(MAP / "export-report.json")
source_audit = read_json(ROOT / "mengzhong-remaining-source-audit.json")
residual_audit = read_json(ROOT / "mengzhong-residual-noimage-audit.json")
field_audit = read_json(ROOT / "mengzhong-field-rules-validation.json")
repairs = manifest["operations"]
assert manifest["candidateCommit"] == "754d5f271e25272d367d984cc49dea93fac2bed4"
assert len(repairs) == 19
assert sum(item["action"].startswith("clear_") for item in repairs) == 17
assert sum(item["action"].startswith("remap_") for item in repairs) == 2
assert manifest["changedBytes"] == 39
assert manifest["doorAnimationAndWalkabilityBytesPreserved"] is True
assert manifest["replacementFrameChecks"] == {
    "objects5656PixelEqualToBundledMapAsset": True,
    "tiles2302PixelEqualToCurrentWZLLibrary": True,
}

assert scene["sourceSHA256"] == manifest["patchedMapSHA256"]
assert report["sourceSHA256"] == manifest["patchedMapSHA256"]
added = manifest["application"]["addedFrontObject"]
assert added == {
    "texture": "objects-5656",
    "x": 962,
    "y": 333,
    "sourceFrame": "Objects.wil frame 5656",
    "fileSHA256": hashlib.sha256((MAP / "objects-5656.png").read_bytes()).hexdigest(),
}
assert scene["objects"].count({"texture": "objects-5656", "x": 962, "y": 333}) == 1
texture = scene["textures"]["objects-5656"]
assert texture["width"] == 48 and texture["height"] == 640
texture_header = (DATA / texture["file"]).read_bytes()[:24]
assert struct.unpack(">II", texture_header[16:24]) == (48, 640)

chunk = manifest["application"]["updatedGroundChunk"]
chunk_path = ROOT / chunk["file"]
chunk_data = chunk_path.read_bytes()
assert hashlib.sha256(chunk_data).hexdigest() == chunk["sha256"]
assert struct.unpack(">II", chunk_data[16:24]) == (chunk["width"], chunk["height"]) == (768, 512)

assert not report["missing"]
assert len(report["nonRenderingPlaceholders"]) == 13
assert all(item["status"] == "empty_frame_no_visible_content" for item in report["nonRenderingPlaceholders"])
assert len(report["nonImageMarkers"]) == 5
assert all(item["classification"] == "flag_only_no_image" for item in report["nonImageMarkers"])
assert report["referenceRepairs"]["remainingVisibleMissing"] == 0
assert source_audit["uniqueUnresolved"] == 0
assert source_audit["placementsUnresolved"] == 0
assert source_audit["clientVisibleArtComplete"] is True
assert source_audit["serverConfigChanged"] is False
assert field_audit["mapArtComplete"] is True
assert residual_audit["emptyFrameSlots"]["count"] == 13
assert residual_audit["emptyFrameSlots"]["allSourceRecordsMatchReferenceFirst12Bytes"] is True
assert residual_audit["emptyFrameSlots"]["nonzeroAnimationFieldCount"] == 13
assert residual_audit["noImageMarkers"]["count"] == 5
assert residual_audit["safeCleanupConclusion"]["drawableExports"] is True
assert residual_audit["safeCleanupConclusion"]["sourceMapBytes"] is False
empty_coords = {(item["x"], item["y"]) for item in residual_audit["emptyFrameSlots"]["coordinates"]}
assert not any((item["x"], item["y"]) in empty_coords for item in scene["objects"])

with (ROOT / "mengzhong-remaining-indices.csv").open(encoding="utf8", newline="") as stream:
    placeholders = list(csv.DictReader(stream))
assert len(placeholders) == 13
assert all(item["status"] == "non_rendering_placeholder" for item in placeholders)

print("PASS Mengzhong image references: 19 repairs, 0 visible misses, 13 empty placeholders, 5 no-image flags")
