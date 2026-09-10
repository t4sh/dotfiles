#!/usr/bin/env python3
"""Capture/check/merge explicitly managed Hermes preferences, never auth stores."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
from urllib.parse import urlsplit


FIELDS = {
    "model": "default provider base_url context_length streaming api_mode",
    "agent": "max_turns service_tier fast_auto_seconds verbose reasoning_effort",
    "display": "compact busy_input_mode bell_on_complete bell_on_prompt show_reasoning background_process_notifications streaming skin interim_assistant_messages tool_progress cleanup_progress long_running_notifications busy_ack_detail",
    "compression": "enabled checkpoint_required progress_notices threshold target_ratio protect_last_n min_tail_user_messages max_attempts proactive_prune_tokens proactive_prune_min_result_chars proactive_prune_min_reclaim_tokens hygiene_max_turn_hold_seconds protect_first_n codex_gpt55_autoraise codex_app_server_auto codex_responses_native idle_compact_after_seconds",
    "memory": "memory_enabled user_profile_enabled memory_char_limit user_char_limit nudge_interval",
    "prompt_caching": "cache_ttl",
    "stt": "enabled language",
    "stt.local": "model",
    "stt.openai": "model language",
    "updates": "check pre_update_backup backup_keep non_interactive_local_changes",
    "telemetry.shared_metrics": "enabled send",
}


def read_config(path):
    text = path.read_text(encoding="utf-8")
    try:
        value = json.loads(text)
    except json.JSONDecodeError:
        # Use Hermes's existing YAML dependency; don't install a second runtime.
        python = Path.home() / ".hermes/hermes-agent/venv/bin/python"
        if not python.is_file():
            raise ValueError("Initialize Hermes first: its Python runtime is needed to read YAML")
        result = subprocess.run(
            [str(python), "-c", "import sys,json,yaml; print(json.dumps(yaml.safe_load(sys.stdin.read())))"],
            input=text, text=True, capture_output=True)
        if result.returncode:
            raise ValueError("Hermes YAML could not be parsed; config retained")
        value = json.loads(result.stdout)
    if not isinstance(value, dict) or not value:
        raise ValueError("Hermes config must be a nonempty object")
    return value


def section(data, path):
    for key in path.split("."):
        data = data.get(key, {})
        if not isinstance(data, dict):
            raise ValueError("Invalid Hermes section: " + path)
    return data


def put(data, path, key, value):
    for part in path.split("."):
        if part in data and not isinstance(data[part], dict):
            raise ValueError("Cannot merge Hermes section: " + path)
        data = data.setdefault(part, {})
    data[key] = value


def project(data):
    result = {}
    for path, keys in FIELDS.items():
        src = section(data, path)
        for key in keys.split():
            if key not in src:
                continue
            value = src[key]
            if type(value) not in (str, int, float, bool, type(None)):
                raise ValueError("Invalid preference type: " + path + "." + key)
            if isinstance(value, str) and re.search(r"(?:sk-|ghp_|glpat-|/Users/|Bearer |\$\{)", value):
                raise ValueError("Nonportable or credential-like preference: " + path + "." + key)
            if key == "base_url" and value:
                url = urlsplit(value)
                if url.scheme not in ("http", "https") or not url.hostname or url.username or url.password or url.query or url.fragment:
                    raise ValueError("Model base_url must have no embedded credentials, query or fragment")
            put(result, path, key, value)
    aliases = section(data, "model").get("aliases")
    if aliases is not None:
        if not isinstance(aliases, dict) or any(
            not isinstance(k, str) or not isinstance(v, str) or
            not re.fullmatch(r"[\w./:@+-]+", k) or not re.fullmatch(r"[\w./:@+-]+", v)
            for k, v in aliases.items()
        ):
            raise ValueError("Model aliases must map names to model identifiers")
        put(result, "model", "aliases", aliases)
    if not result.get("model", {}).get("default"):
        raise ValueError("Hermes model.default is missing; prior snapshot retained")
    return result


def write_atomic(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    text = json.dumps(data, indent=2, sort_keys=True, allow_nan=False) + "\n"
    if path.is_file() and path.read_text() == text:
        return
    fd, name = tempfile.mkstemp(prefix=".hermes-prefs-", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(text)
        os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def merge(base, saved):
    for key, value in saved.items():
        if isinstance(value, dict) and key != "aliases":
            if key in base and not isinstance(base[key], dict):
                raise ValueError("Cannot merge Hermes section: " + key)
            merge(base.setdefault(key, {}), value)
        else:
            base[key] = value
    return base


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("capture", "check", "restore", "audit"))
    parser.add_argument("--live", type=Path, default=Path.home() / ".hermes/config.yaml")
    parser.add_argument("--snapshot", type=Path, default=Path(os.environ.get("DOTFILES", Path(__file__).resolve().parents[1])) / "apps/hermes/config.json")
    args = parser.parse_args()
    try:
        if args.mode == "capture":
            write_atomic(args.snapshot, project(read_config(args.live)))
        else:
            saved = read_config(args.snapshot)
            if project(saved) != saved:
                raise ValueError("Hermes snapshot contains unmanaged fields")
            if args.mode == "check" and project(read_config(args.live)) != saved:
                raise ValueError("Hermes preferences differ; run make backup-hermes")
            if args.mode == "restore":
                base = read_config(args.live) if args.live.exists() else {}
                write_atomic(args.live, merge(base, saved))
        print("Hermes preferences: " + args.mode + " passed")
        return 0
    except (OSError, ValueError) as error:
        print(str(error))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
