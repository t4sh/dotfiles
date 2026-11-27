#!/usr/bin/env python3
"""Copy and compare backup entries without dropping filesystem metadata."""

from __future__ import annotations

import argparse
from contextlib import contextmanager
import ctypes
import ctypes.util
import errno
from functools import lru_cache, partial
import hashlib
import os
from pathlib import Path
import shutil
import stat
import subprocess
import sys
import tempfile
from typing import Iterator


_COPYFILE_STAT = 0x02
_COPYFILE_NOFOLLOW = (1 << 18) | (1 << 19)
_XATTR_NOFOLLOW = 0x0001
_ACL_TYPE_EXTENDED = 0x00000100
_O_EXEC_DARWIN = 0x40000000  # Darwin fcntl.h: O_SEARCH combines O_EXEC and O_DIRECTORY
_AT_FDCWD_DARWIN = -2
_RENAME_EXCL = 0x00000004  # macOS renameatx_np: fail if the destination exists
_AT_FDCWD_LINUX = -100
_RENAME_NOREPLACE = 1  # Linux renameat2: fail if the destination exists


@lru_cache(maxsize=1)
def _darwin_lib():
    if sys.platform != "darwin":
        return None
    return ctypes.CDLL(ctypes.util.find_library("System") or None, use_errno=True)


def directory_search_flag() -> int:
    """Return the host flag for lookup without needing directory read access."""
    if sys.platform == "darwin":
        return getattr(os, "O_SEARCH", _O_EXEC_DARWIN | os.O_DIRECTORY)
    return getattr(os, "O_SEARCH", getattr(os, "O_PATH", os.O_RDONLY))


def rename_noreplace(source: str | Path, destination: str | Path, parent_fd: int | None = None, *,
                     source_fd: int | None = None) -> None:
    """Atomically move an entry into a vacant name, optionally relative to held directories."""
    libc = ctypes.CDLL(None, use_errno=True)
    if sys.platform == "darwin":
        at_cwd, rename, flag = _AT_FDCWD_DARWIN, libc.renameatx_np, _RENAME_EXCL
    elif sys.platform.startswith("linux"):
        at_cwd, rename, flag = _AT_FDCWD_LINUX, getattr(libc, "renameat2", None), _RENAME_NOREPLACE
        if rename is None:
            raise OSError(errno.ENOTSUP, "renameat2 is unavailable")
    else:
        raise OSError(errno.ENOTSUP, "no no-replace rename on this platform")
    rename.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_int, ctypes.c_char_p, ctypes.c_uint]
    rename.restype = ctypes.c_int
    result = rename(at_cwd if source_fd is None else source_fd, os.fsencode(source),
                    at_cwd if parent_fd is None else parent_fd, os.fsencode(destination), flag)
    if result != 0:
        error = ctypes.get_errno()
        raise OSError(error, os.strerror(error), str(destination))


def _iter_xattrs(path: Path | int) -> Iterator[tuple[str, bytes]]:
    is_fd = isinstance(path, int)
    lib = _darwin_lib()
    if lib is None:
        if not hasattr(os, "listxattr"):
            return
        options = {} if is_fd else {"follow_symlinks": False}
        names = os.listxattr(path, **options)
        for name in names:
            yield name, os.getxattr(path, name, **options)
        return

    listxattr = lib.flistxattr if is_fd else lib.listxattr
    identifier_type = ctypes.c_int if is_fd else ctypes.c_char_p
    listxattr.argtypes = [identifier_type, ctypes.c_void_p, ctypes.c_size_t, ctypes.c_int]
    listxattr.restype = ctypes.c_ssize_t
    getxattr = lib.fgetxattr if is_fd else lib.getxattr
    getxattr.argtypes = [
        identifier_type, ctypes.c_char_p, ctypes.c_void_p, ctypes.c_size_t,
        ctypes.c_uint32, ctypes.c_int,
    ]
    getxattr.restype = ctypes.c_ssize_t
    identifier = path if is_fd else os.fsencode(path)
    options = 0 if is_fd else _XATTR_NOFOLLOW
    size = listxattr(identifier, None, 0, options)
    if size < 0:
        error = ctypes.get_errno()
        if error in (errno.ENOTSUP, errno.EOPNOTSUPP):
            return
        raise OSError(error, os.strerror(error), str(path))
    if size == 0:
        return
    names_buffer = ctypes.create_string_buffer(size)
    actual_size = listxattr(identifier, names_buffer, size, options)
    if actual_size < 0:
        error = ctypes.get_errno()
        raise OSError(error, os.strerror(error), str(path))

    for raw_name in names_buffer.raw[:actual_size].split(b"\0"):
        if not raw_name:
            continue
        value_size = getxattr(
            identifier, raw_name, None, 0, 0, options
        )
        if value_size < 0:
            error = ctypes.get_errno()
            raise OSError(error, os.strerror(error), str(path))
        value = ctypes.create_string_buffer(value_size)
        actual_value_size = getxattr(
            identifier, raw_name, value, value_size, 0, options
        )
        if actual_value_size < 0:
            error = ctypes.get_errno()
            raise OSError(error, os.strerror(error), str(path))
        yield os.fsdecode(raw_name), value.raw[:actual_value_size]


def _darwin_xattrs(path: Path | int) -> dict[str, bytes]:
    return dict(_iter_xattrs(path))


def _sync_xattrs(source_attrs, destination_attrs, set_attribute, remove_attribute) -> None:
    for name in destination_attrs.keys() - source_attrs.keys():
        remove_attribute(name)
    for name, value in source_attrs.items():
        if destination_attrs.get(name) != value:
            set_attribute(name, value)


def _copy_xattrs(source: Path, destination: Path) -> None:
    source_attrs = _darwin_xattrs(source)
    destination_attrs = _darwin_xattrs(destination)
    if sys.platform == "darwin":
        lib = _darwin_lib()
        setxattr = lib.setxattr
        setxattr.argtypes = [
            ctypes.c_char_p, ctypes.c_char_p, ctypes.c_void_p, ctypes.c_size_t,
            ctypes.c_uint32, ctypes.c_int,
        ]
        setxattr.restype = ctypes.c_int
        removexattr = lib.removexattr
        removexattr.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_int]
        removexattr.restype = ctypes.c_int
        options = _XATTR_NOFOLLOW
        destination_bytes = os.fsencode(destination)

        def remove_attribute(name):
            if removexattr(destination_bytes, os.fsencode(name), options) != 0:
                error = ctypes.get_errno()
                raise OSError(error, os.strerror(error), str(destination))

        def set_attribute(name, value):
            payload = ctypes.create_string_buffer(value)
            if setxattr(destination_bytes, os.fsencode(name), payload, len(value), 0, options) != 0:
                error = ctypes.get_errno()
                raise OSError(error, os.strerror(error), str(destination))
    else:
        def remove_attribute(name):
            os.removexattr(destination, name, follow_symlinks=not source.is_symlink())

        def set_attribute(name, value):
            os.setxattr(destination, name, value, follow_symlinks=not source.is_symlink())
    _sync_xattrs(source_attrs, destination_attrs, set_attribute, remove_attribute)


def _copy_xattrs_fd(source: Path | int, destination_fd: int, apply_step) -> None:
    """Copy extended attributes to an already-open destination entry."""
    source_attrs = _darwin_xattrs(source)
    destination_attrs = _darwin_xattrs(destination_fd)
    if sys.platform == "darwin":
        lib = _darwin_lib()
        setxattr = lib.fsetxattr
        setxattr.argtypes = [
            ctypes.c_int, ctypes.c_char_p, ctypes.c_void_p, ctypes.c_size_t,
            ctypes.c_int, ctypes.c_int,
        ]
        setxattr.restype = ctypes.c_int
        removexattr = lib.fremovexattr
        removexattr.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_int]
        removexattr.restype = ctypes.c_int

        def remove_attribute(name):
            if removexattr(destination_fd, os.fsencode(name), 0) != 0:
                error = ctypes.get_errno()
                raise OSError(error, os.strerror(error), name)

        def set_attribute(name, value):
            payload = ctypes.create_string_buffer(value)
            if setxattr(destination_fd, os.fsencode(name), payload, len(value), 0, 0) != 0:
                error = ctypes.get_errno()
                raise OSError(error, os.strerror(error), name)
    else:
        def remove_attribute(name):
            os.removexattr(destination_fd, name)

        def set_attribute(name, value):
            os.setxattr(destination_fd, name, value)
    for name in sorted(destination_attrs.keys() - source_attrs.keys()):
        apply_step(partial(remove_attribute, name), "xattrs", None, name)
    for name, value in sorted(source_attrs.items()):
        if destination_attrs.get(name) != value:
            digest = hashlib.sha256(value).hexdigest()
            apply_step(partial(set_attribute, name, value), "xattrs", digest, name)


def _acl_text(path: Path | int) -> str | None:
    lib = _darwin_lib()
    if lib is None:
        return None
    is_fd = isinstance(path, int)
    if is_fd:
        function_name = "acl_get_fd_np"
    else:
        function_name = "acl_get_link_np" if path.is_symlink() else "acl_get_file"
    get_acl = getattr(lib, function_name, None)
    if get_acl is None:
        return None
    get_acl.argtypes = [ctypes.c_int if is_fd else ctypes.c_char_p, ctypes.c_int]
    get_acl.restype = ctypes.c_void_p
    ctypes.set_errno(0)
    acl = get_acl(path if is_fd else os.fsencode(path), _ACL_TYPE_EXTENDED)
    if not acl:
        error = ctypes.get_errno()
        if error in (0, errno.ENOTSUP, errno.EOPNOTSUPP, errno.EINVAL, errno.ENOENT):
            return None
        raise OSError(error, os.strerror(error), str(path))
    try:
        acl_to_text = lib.acl_to_text
        acl_to_text.argtypes = [ctypes.c_void_p, ctypes.POINTER(ctypes.c_ssize_t)]
        acl_to_text.restype = ctypes.c_void_p
        length = ctypes.c_ssize_t()
        text = acl_to_text(acl, ctypes.byref(length))
        if not text:
            error = ctypes.get_errno()
            raise OSError(error, os.strerror(error), str(path))
        try:
            return ctypes.string_at(text, length.value).decode("utf-8")
        finally:
            lib.acl_free.argtypes = [ctypes.c_void_p]
            lib.acl_free.restype = ctypes.c_int
            lib.acl_free(text)
    finally:
        lib.acl_free.argtypes = [ctypes.c_void_p]
        lib.acl_free.restype = ctypes.c_int
        lib.acl_free(acl)


def file_metadata_fd(fd: int) -> tuple[dict[str, bytes], str | None]:
    """Read the extended metadata of an open file without another path lookup."""
    return _darwin_xattrs(fd), _acl_text(fd)


def fingerprint(path: Path) -> dict[str, object] | None:
    """Return content and metadata identity for a file, link, or directory."""
    path = Path(path)
    try:
        info = path.lstat()
    except FileNotFoundError:
        return None

    if stat.S_ISDIR(info.st_mode):
        entry_kind = "directory"
    elif stat.S_ISREG(info.st_mode):
        entry_kind = "file"
    elif stat.S_ISLNK(info.st_mode):
        entry_kind = "symlink"
    else:
        entry_kind = "special"

    result: dict[str, object] = {
        "kind": entry_kind,
        "mode": stat.S_IMODE(info.st_mode),
        "xattrs": {
            name: hashlib.sha256(value).hexdigest()
            for name, value in _iter_xattrs(path)
        },
    }
    acl = _acl_text(path)
    if acl is not None:
        result["acl"] = acl
    if entry_kind == "file":
        digest = hashlib.sha256()
        with path.open("rb") as source:
            for block in iter(lambda: source.read(1024 * 1024), b""):
                digest.update(block)
        result["sha256"] = digest.hexdigest()
    elif entry_kind == "symlink":
        result["target"] = os.readlink(path)
    return result


def _copy_native_metadata(source: Path, destination: Path) -> bool:
    lib = _darwin_lib()
    if lib is None:
        return False
    copyfile = lib.copyfile
    copyfile.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_void_p, ctypes.c_uint32]
    copyfile.restype = ctypes.c_int
    flags = _COPYFILE_STAT | _COPYFILE_NOFOLLOW
    if copyfile(os.fsencode(source), os.fsencode(destination), None, flags) != 0:
        error = ctypes.get_errno()
        raise OSError(error, os.strerror(error), str(destination))
    return True


def copy_entry(source: Path, destination: Path) -> None:
    """Copy one file, symlink, or empty directory and preserve its metadata."""
    source = Path(source)
    destination = Path(destination)
    info = source.lstat()
    if destination.exists() or destination.is_symlink():
        raise FileExistsError(destination)

    if stat.S_ISREG(info.st_mode):
        if sys.platform == "darwin":
            # copyfile(3) reissues quarantine records during an ordinary data copy.
            subprocess.run(["/usr/bin/ditto", "--rsrc", "--extattr", "--acl", "--qtn",
                            str(source), str(destination)], check=True)
        else:
            shutil.copy2(source, destination, follow_symlinks=False)
        return
    if stat.S_ISLNK(info.st_mode):
        if sys.platform == "darwin":
            subprocess.run(
                ["/bin/cp", "-pRP", str(source), str(destination)],
                check=True, capture_output=True, text=True,
            )
            # Some macOS versions of cp omit attributes attached to the link.
            _copy_xattrs(source, destination)
        else:
            os.symlink(os.readlink(source), destination)
            _copy_fallback_metadata(source, destination, symlink=True)
        return
    if stat.S_ISDIR(info.st_mode):
        destination.mkdir(mode=0o700)
        apply_directory_metadata(source, destination)
        return
    raise ValueError(f"unsupported backup entry type: {source}")


def _copy_fallback_metadata(source: Path, destination: Path, *, symlink: bool = False) -> None:
    if not symlink:
        shutil.copystat(source, destination, follow_symlinks=False)
    _copy_xattrs(source, destination)


def apply_directory_metadata(source: Path, destination: Path) -> None:
    """Mirror mode, extended attributes, and ACL from source onto destination."""
    source = Path(source)
    destination = Path(destination)
    if not stat.S_ISDIR(source.lstat().st_mode) or not stat.S_ISDIR(destination.lstat().st_mode):
        raise ValueError("directory metadata requires two directories")
    _apply_metadata(source, destination)


def _apply_metadata_step(write, field, value, attribute=None) -> None:
    write()


def apply_directory_metadata_fd(source: Path, destination_fd: int, *, apply_step=_apply_metadata_step) -> None:
    """Copy mode, extended attributes, and ACL to an already-open directory.

    Each step performs one metadata write through the held descriptor. A
    publisher can use apply_step to journal the expected state before the write.
    """
    source = Path(source)
    if not stat.S_ISDIR(source.lstat().st_mode):
        raise ValueError("directory metadata requires a source directory")
    info = source.stat()
    destination_mode = os.fstat(destination_fd).st_mode
    if not stat.S_ISDIR(destination_mode):
        raise ValueError("directory metadata requires a destination directory")

    mode = stat.S_IMODE(info.st_mode)
    set_mode = partial(os.fchmod, destination_fd, mode)
    # An xattr write needs write access on macOS. If the new mode grants it,
    # set that mode first. When dropping access, copy the attributes first.
    grant_write = mode & stat.S_IWUSR and not destination_mode & stat.S_IWUSR
    if grant_write:
        apply_step(set_mode, "mode", mode)
    _copy_xattrs_fd(source, destination_fd, apply_step)
    if not grant_write:
        apply_step(set_mode, "mode", mode)
    if sys.platform == "darwin":
        apply_step(partial(_copy_acl_fd, source, destination_fd), "acl", _acl_text(source))


@contextmanager
def _source_acl(source: Path | int):
    """Yield the source ACL, including an empty ACL when it has none."""
    lib = _darwin_lib()
    is_fd = isinstance(source, int)
    get_acl = lib.acl_get_fd_np if is_fd else lib.acl_get_file
    get_acl.argtypes = [ctypes.c_int if is_fd else ctypes.c_char_p, ctypes.c_int]
    get_acl.restype = ctypes.c_void_p
    acl = get_acl(source if is_fd else os.fsencode(source), _ACL_TYPE_EXTENDED)
    if not acl:
        error = ctypes.get_errno()
        if error not in (0, errno.ENOTSUP, errno.EOPNOTSUPP, errno.EINVAL, errno.ENOENT):
            raise OSError(error, os.strerror(error), str(source))
        acl_init = lib.acl_init
        acl_init.argtypes = [ctypes.c_int]
        acl_init.restype = ctypes.c_void_p
        acl = acl_init(0)
        if not acl:
            error = ctypes.get_errno()
            raise OSError(error, os.strerror(error), str(source))
    try:
        yield lib, acl
    finally:
        lib.acl_free.argtypes = [ctypes.c_void_p]
        lib.acl_free.restype = ctypes.c_int
        lib.acl_free(acl)


def _copy_acl_fd(source: Path | int, destination_fd: int) -> None:
    """Copy or clear a macOS extended ACL without resolving the target path."""
    with _source_acl(source) as (lib, acl):
        set_acl = lib.acl_set_fd_np
        set_acl.argtypes = [ctypes.c_int, ctypes.c_void_p, ctypes.c_int]
        set_acl.restype = ctypes.c_int
        if set_acl(destination_fd, acl, _ACL_TYPE_EXTENDED) != 0:
            error = ctypes.get_errno()
            raise OSError(error, os.strerror(error), str(source))


def apply_file_metadata_fd(source_fd: int, destination_fd: int) -> None:
    """Copy file metadata to an owned staging file through open descriptors."""
    source = os.fstat(source_fd)
    if not stat.S_ISREG(source.st_mode) or not stat.S_ISREG(os.fstat(destination_fd).st_mode):
        raise ValueError("file metadata requires two regular files")
    mode = stat.S_IMODE(source.st_mode)
    lib = _darwin_lib()
    if lib is not None:
        copyfile = lib.fcopyfile
        copyfile.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.c_void_p, ctypes.c_uint32]
        copyfile.restype = ctypes.c_int
        if copyfile(source_fd, destination_fd, None, _COPYFILE_STAT) != 0:
            error = ctypes.get_errno()
            raise OSError(error, f"could not copy Zed staging file metadata: {os.strerror(error)}")
        os.fchmod(destination_fd, mode | stat.S_IWUSR)
    try:
        _copy_xattrs_fd(source_fd, destination_fd, _apply_metadata_step)
    finally:
        os.fchmod(destination_fd, mode)
    if lib is not None:
        _copy_acl_fd(source_fd, destination_fd)


def _copy_acl(source: Path, destination: Path) -> None:
    """Copy or clear a macOS extended ACL on a path whose temp inode is owned."""
    with _source_acl(source) as (lib, acl):
        set_acl = lib.acl_set_file
        set_acl.argtypes = [ctypes.c_char_p, ctypes.c_int, ctypes.c_void_p]
        set_acl.restype = ctypes.c_int
        if set_acl(os.fsencode(destination), _ACL_TYPE_EXTENDED, acl) != 0:
            error = ctypes.get_errno()
            raise OSError(error, os.strerror(error), str(destination))


def replace_bytes(candidate: Path, data: bytes, metadata_source: Path) -> None:
    """Atomically replace staged bytes and restore their intended metadata."""
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=".stabilizing.", dir=candidate.parent
    )
    temporary = Path(temporary_name)
    try:
        output = os.fdopen(descriptor, "wb")
        descriptor = -1
        with output:
            output.write(data)
            output.flush()
            os.fsync(output.fileno())
        apply_file_metadata(metadata_source, temporary)
        os.replace(temporary, candidate)
    finally:
        if descriptor >= 0:
            os.close(descriptor)
        temporary.unlink(missing_ok=True)


def install_content(source: Path, destination: Path) -> None:
    """Install prepared bytes with the metadata of the existing staged file."""
    data = source.read_bytes()
    try:
        existing = destination.lstat()
    except FileNotFoundError:
        replace_bytes(destination, data, source)
        return
    if not stat.S_ISREG(existing.st_mode):
        raise ValueError(f"expected a regular snapshot file: {destination}")
    if destination.read_bytes() != data:
        replace_bytes(destination, data, destination)


def apply_file_metadata(source: Path, destination: Path) -> None:
    if not all(stat.S_ISREG(p.lstat().st_mode) for p in (source, destination)):
        raise ValueError("file metadata requires two regular files")
    _apply_metadata(source, destination)


def _apply_metadata(source: Path, destination: Path) -> None:
    if _copy_native_metadata(source, destination):
        # copyfile can refresh quarantine and apply a restrictive ACL before
        # returning. Use stat-only metadata, then reconcile xattrs before ACL.
        mode = stat.S_IMODE(source.stat().st_mode)
        os.chmod(destination, mode | stat.S_IWUSR)
        try:
            _copy_xattrs(source, destination)
        finally:
            os.chmod(destination, mode)
        _copy_acl(source, destination)
        return
    _copy_xattrs(source, destination)
    shutil.copystat(source, destination, follow_symlinks=False)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Install prepared snapshot bytes, preserving saved metadata.")
    parser.add_argument("source", type=Path)
    parser.add_argument("destination", type=Path)
    args = parser.parse_args()
    try:
        install_content(args.source, args.destination)
    except (OSError, ValueError) as error:
        sys.exit(f"Could not install staged snapshot: {error}")
