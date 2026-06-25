#!/usr/bin/env python3
import importlib.metadata as md


def present(name: str) -> bool:
    try:
        md.distribution(name)
        return True
    except md.PackageNotFoundError:
        return False


opencv_variants = [
    name
    for name in (
        "opencv-python",
        "opencv-python-headless",
        "opencv-contrib-python",
        "opencv-contrib-python-headless",
    )
    if present(name)
]
assert opencv_variants == ["opencv-contrib-python-headless"], opencv_variants

import cv2  # noqa: E402
assert hasattr(cv2, "ximgproc"), "opencv contrib modules are missing"

assert present("onnxruntime-gpu"), "onnxruntime-gpu is missing"
assert not present("onnxruntime"), "plain onnxruntime should not be installed"

import numpy  # noqa: E402
assert numpy.__version__.startswith("2.2."), numpy.__version__

import torch  # noqa: E402
assert "+cu128" in torch.__version__, torch.__version__
assert torch.version.cuda == "12.8", torch.version.cuda

from huggingface_hub import split_torch_state_dict_into_shards  # noqa: F401,E402
import diffusers  # noqa: F401,E402
import transformers  # noqa: F401,E402

if present("sageattention"):
    try:
        import sageattention  # noqa: F401,E402
        print("sageattention import OK")
    except Exception as exc:
        text = str(exc).lower()
        fatal_markers = (
            "glibcxx",
            "glibc_",
            "undefined symbol",
            "symbol not found",
            "cannot open shared object",
            "cannot load",
        )
        if any(marker in text for marker in fatal_markers):
            raise
        print(f"WARN: sageattention import deferred: {exc}")

print(f"SMOKE OK | numpy {numpy.__version__} | torch {torch.__version__}")
