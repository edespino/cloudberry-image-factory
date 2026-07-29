#!/usr/bin/python3
"""Validate describe-images against the approved not-publicly-shared policy."""

from __future__ import annotations

import json
import sys
from typing import NoReturn


def fail() -> NoReturn:
    print(
        "Error: existing AMI metadata did not satisfy approved, "
        "not-publicly-shared recovery policy.",
        file=sys.stderr,
    )
    raise SystemExit(1)


def main() -> None:
    if len(sys.argv) != 4:
        fail()
    expected_id, expected_owner, allowed_name_prefix = sys.argv[1:]
    try:
        payload = json.load(sys.stdin)
        images = payload["Images"]
        if not isinstance(images, list) or len(images) != 1:
            fail()
        image = images[0]
        if not isinstance(image, dict):
            fail()
        name = image.get("Name")
        if (
            image.get("ImageId") != expected_id
            or image.get("OwnerId") != expected_owner
            or image.get("State") != "available"
            or image.get("Public") is not False
            or not isinstance(name, str)
            or not name.startswith(allowed_name_prefix)
        ):
            fail()
    except (KeyError, TypeError, ValueError, json.JSONDecodeError):
        fail()
    print(name)


if __name__ == "__main__":
    main()
