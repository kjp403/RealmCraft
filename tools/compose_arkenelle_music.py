#!/usr/bin/env python3
"""DEPRECATED. Kyle's Music.zip tracks live in assets/audio/music/.

This used to synthesize placeholder loops. Running it would overwrite the
real soundtrack — see assets/audio/music/ORIGIN.txt.
"""
from __future__ import annotations

import sys


def main() -> int:
    print(
        "Refusing to overwrite assets/audio/music — those files are Kyle's "
        "soundtrack, not the old synthesized loops.\n"
        "See assets/audio/music/ORIGIN.txt.",
        file=sys.stderr,
    )
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
