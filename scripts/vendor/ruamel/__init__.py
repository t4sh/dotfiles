"""Expose the unmodified wheel namespace to zipimport on Python 3.9 and newer."""
from pathlib import Path

__path__ = [str(Path(__file__).resolve().parents[1] / "ruamel_yaml-0.19.1-py3-none-any.whl" / "ruamel")]
