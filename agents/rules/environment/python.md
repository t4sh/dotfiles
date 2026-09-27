# Python environment contract

For `pyproject.toml`, `requirements.txt`, or `setup.py`, prefer `uv` when `uv.lock` exists; otherwise use `pip` in the active virtual environment. Never install globally. Activate the environment before project scripts.
