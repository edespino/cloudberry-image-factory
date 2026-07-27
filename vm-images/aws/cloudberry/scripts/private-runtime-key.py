#!/usr/bin/python3
"""Create and populate a private per-invocation key file without following links."""

from __future__ import annotations

import os
from pathlib import Path
import secrets
import stat
import sys
from typing import NoReturn


def fail(message: str) -> NoReturn:
    print(f"Error: {message}", file=sys.stderr)
    raise SystemExit(1)


def open_validated_directory(
    path_value: str, *, label: str, exact_mode: int | None
) -> tuple[Path, int]:
    if not path_value:
        fail(f"{label} is required")
    path = Path(path_value)
    try:
        before = path.lstat()
    except OSError:
        fail(f"{label} is unavailable")
    if stat.S_ISLNK(before.st_mode) or not stat.S_ISDIR(before.st_mode):
        fail(f"{label} must be a non-symlink directory")
    if before.st_uid != os.geteuid():
        fail(f"{label} must be owned by the current uid")
    mode = stat.S_IMODE(before.st_mode)
    if exact_mode is not None and mode != exact_mode:
        fail(f"{label} must have mode {exact_mode:04o}")
    if exact_mode is None and mode & 0o022:
        fail(f"{label} must not be writable by group or world")
    flags = os.O_RDONLY | os.O_DIRECTORY | getattr(os, "O_CLOEXEC", 0)
    flags |= getattr(os, "O_NOFOLLOW", 0)
    try:
        descriptor = os.open(path, flags)
    except OSError:
        fail(f"{label} could not be opened safely")
    opened = os.fstat(descriptor)
    if (opened.st_dev, opened.st_ino) != (before.st_dev, before.st_ino):
        os.close(descriptor)
        fail(f"{label} changed during validation")
    return path, descriptor


def open_validated_runtime(path_value: str) -> tuple[Path, int]:
    return open_validated_directory(
        path_value, label="XDG_RUNTIME_DIR", exact_mode=0o700
    )


def create_fallback_runtime() -> tuple[Path, int]:
    base_value = os.environ.get("RUNNER_TEMP") or os.environ.get("TMPDIR")
    base, base_fd = open_validated_directory(
        base_value or "", label="fallback runtime base", exact_mode=None
    )
    try:
        for _ in range(32):
            name = f"cloudberry-runtime-{secrets.token_hex(12)}"
            try:
                os.mkdir(name, 0o700, dir_fd=base_fd)
            except FileExistsError:
                continue
            runtime_fd = os.open(
                name,
                os.O_RDONLY
                | os.O_DIRECTORY
                | getattr(os, "O_CLOEXEC", 0)
                | getattr(os, "O_NOFOLLOW", 0),
                dir_fd=base_fd,
            )
            result = os.fstat(runtime_fd)
            if (
                result.st_uid != os.geteuid()
                or stat.S_IMODE(result.st_mode) != 0o700
            ):
                os.close(runtime_fd)
                fail("fallback runtime has unsafe ownership or mode")
            return base / name, runtime_fd
    finally:
        os.close(base_fd)
    fail("fallback runtime could not be allocated")


def create_directory(runtime: Path, runtime_fd: int) -> None:
    for _ in range(32):
        name = f"cloudberry-packer-{secrets.token_hex(12)}"
        try:
            os.mkdir(name, 0o700, dir_fd=runtime_fd)
        except FileExistsError:
            continue
        directory_fd = os.open(
            name,
            os.O_RDONLY
            | os.O_DIRECTORY
            | getattr(os, "O_CLOEXEC", 0)
            | getattr(os, "O_NOFOLLOW", 0),
            dir_fd=runtime_fd,
        )
        try:
            result = os.fstat(directory_fd)
            if result.st_uid != os.geteuid() or stat.S_IMODE(result.st_mode) != 0o700:
                fail("private key directory has unsafe ownership or mode")
        finally:
            os.close(directory_fd)
        print(runtime / name)
        return
    fail("private key directory could not be allocated")


def write_key(runtime_fd: int, directory_name: str, filename: str) -> None:
    if "/" in directory_name or directory_name in {"", ".", ".."}:
        fail("private key directory name is invalid")
    if "/" in filename or filename in {"", ".", ".."}:
        fail("private key filename is invalid")
    directory_fd = os.open(
        directory_name,
        os.O_RDONLY
        | os.O_DIRECTORY
        | getattr(os, "O_CLOEXEC", 0)
        | getattr(os, "O_NOFOLLOW", 0),
        dir_fd=runtime_fd,
    )
    try:
        result = os.fstat(directory_fd)
        if result.st_uid != os.geteuid() or stat.S_IMODE(result.st_mode) != 0o700:
            fail("private key directory has unsafe ownership or mode")
        key_fd = os.open(
            filename,
            os.O_WRONLY
            | os.O_CREAT
            | os.O_EXCL
            | getattr(os, "O_CLOEXEC", 0)
            | getattr(os, "O_NOFOLLOW", 0),
            0o600,
            dir_fd=directory_fd,
        )
        try:
            while chunk := sys.stdin.buffer.read(65536):
                view = memoryview(chunk)
                while view:
                    view = view[os.write(key_fd, view) :]
            os.fchmod(key_fd, 0o600)
        finally:
            os.close(key_fd)
    finally:
        os.close(directory_fd)


def main() -> None:
    runtime_value = os.environ.get("XDG_RUNTIME_DIR", "")
    runtime, runtime_fd = (
        open_validated_runtime(runtime_value)
        if runtime_value
        else create_fallback_runtime()
    )
    try:
        if sys.argv[1:] == ["create"]:
            create_directory(runtime, runtime_fd)
            return
        if len(sys.argv) == 4 and sys.argv[1] == "write":
            write_key(runtime_fd, sys.argv[2], sys.argv[3])
            return
        fail("invalid private runtime helper invocation")
    finally:
        os.close(runtime_fd)


if __name__ == "__main__":
    main()
