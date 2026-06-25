#!/usr/bin/env python3
import importlib

try:
    importlib.import_module("sageattention")
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
    print(f"WARN: sageattention import deferred in build environment: {exc}")
else:
    print("sageattention import OK")
