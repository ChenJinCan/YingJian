#!/usr/bin/env python3

"""Isolated OpenCV baseline for Tickets 17/18; never imported by the app."""

import argparse
import json
import shutil
from pathlib import Path

import cv2
import numpy as np


def face_mask(shape, faces):
    height, width = shape[:2]
    mask = np.zeros((height, width), dtype=np.uint8)
    for face in faces:
        x, y, box_width, box_height = face["bounding_box"]
        center = (int((x + box_width / 2) * width), int((1 - y - box_height / 2) * height))
        axes = (max(1, int(box_width * width * 0.52)), max(1, int(box_height * height * 0.53)))
        cv2.ellipse(mask, center, axes, 0, 0, 360, 255, -1, cv2.LINE_AA)
    return cv2.GaussianBlur(mask, (0, 0), 4)


def smoothing_candidate(source, mask):
    filtered = cv2.bilateralFilter(source, 9, 35, 11)
    alpha = (mask.astype(np.float32) / 255.0 * 0.35)[..., None]
    return np.clip(source * (1 - alpha) + filtered * alpha, 0, 255).astype(np.uint8)


def blemish_candidate(source, mask):
    values = source.astype(np.float32)
    blue, green, red = cv2.split(values)
    red_excess = red - (green + blue) * 0.5
    local_red_excess = cv2.GaussianBlur(red_excess, (0, 0), 7)
    local_red = cv2.GaussianBlur(red, (0, 0), 7)
    evidence = (red_excess - local_red_excess > 8) & (local_red - red < 22) & (mask > 96)
    evidence = evidence.astype(np.uint8) * 255
    evidence = cv2.morphologyEx(evidence, cv2.MORPH_OPEN, np.ones((3, 3), np.uint8))
    evidence = cv2.dilate(evidence, np.ones((3, 3), np.uint8), iterations=1)
    repaired = cv2.inpaint(source, evidence, 3, cv2.INPAINT_TELEA)
    alpha = (cv2.GaussianBlur(evidence, (0, 0), 0.7).astype(np.float32) / 255.0 * 0.7)[..., None]
    return np.clip(source * (1 - alpha) + repaired * alpha, 0, 255).astype(np.uint8)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=["smoothing", "blemish"])
    parser.add_argument("source")
    parser.add_argument("metadata")
    parser.add_argument("output")
    args = parser.parse_args()
    source = cv2.imread(args.source, cv2.IMREAD_COLOR)
    if source is None:
        raise SystemExit("source image is unreadable")
    metadata = json.loads(Path(args.metadata).read_text())
    faces = [
        face for face in metadata.get("detected_faces", [])
        if face["index"] in metadata.get("applicable_face_indices", [0] if metadata.get("applicable") else [])
    ]
    if len(metadata.get("detected_faces", [])) > 3:
        faces = []
    mask = face_mask(source.shape, faces)
    applied = bool(faces)
    if args.mode == "smoothing" and applied:
        result = smoothing_candidate(source, mask)
    elif args.mode == "blemish" and applied:
        result = blemish_candidate(source, mask)
    destination = Path(args.output)
    destination.parent.mkdir(parents=True, exist_ok=True)
    if applied:
        if not cv2.imwrite(str(destination), result, [cv2.IMWRITE_JPEG_QUALITY, 95]):
            raise SystemExit("output image could not be written")
    else:
        shutil.copyfile(args.source, destination)
    print(json.dumps({
        "schema": 1,
        "mode": args.mode,
        "opencv_version": cv2.__version__,
        "source": args.source,
        "output": str(destination),
        "face_count": len(faces),
        "applied": applied,
        "engineering_only": True,
        "quality_passed": False,
    }, sort_keys=True))


if __name__ == "__main__":
    main()
