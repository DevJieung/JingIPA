#!/usr/bin/env python3
"""Inject only AdMob settings during export and verify the packaged values."""

import argparse
import json
from pathlib import Path
import re
import struct
import zipfile


ENV_SETTINGS = {
    "ADMOB_APP_ID": "admob/general/android/app_id",
    "ADMOB_REWARD_CARD_CHANGE_ID": "rewards/android/card_change_unit_id",
    "ADMOB_REWARD_MERGE_RESTORE_ID": "rewards/android/merge_restore_unit_id",
    "ADMOB_REWARD_REVIVE_ID": "rewards/android/revive_unit_id",
}
OPTIONAL_SETTINGS = {
    "ADMOB_REWARD_CRYSTAL_ID": "rewards/android/crystal_unit_id",
    "ADMOB_TEST_DEVICE_IDS": "rewards/android/test_device_ids",
}
FORMAT_SETTINGS = {
    "ADMOB_REWARD_CARD_CHANGE_FORMAT": ("rewards/android/card_change_format", "rewarded"),
    "ADMOB_REWARD_MERGE_RESTORE_FORMAT": ("rewards/android/merge_restore_format", "rewarded_interstitial"),
    "ADMOB_REWARD_REVIVE_FORMAT": ("rewards/android/revive_format", "rewarded_interstitial"),
    "ADMOB_REWARD_CRYSTAL_FORMAT": ("rewards/android/crystal_format", "rewarded_interstitial"),
}


def read_settings(env_path: Path) -> dict:
    # Do not source .env: unrelated credentials and shell expressions stay inert.
    values = {}
    for number, line in enumerate(env_path.read_text(encoding="utf-8-sig").splitlines(), 1):
        match = re.match(r"\s*(?:export\s+)?([A-Z_][A-Z0-9_]*)\s*=\s*(.*)", line)
        if not match or match[1] not in ENV_SETTINGS | OPTIONAL_SETTINGS | FORMAT_SETTINGS:
            continue
        key, raw = match.groups()
        match = re.fullmatch(r'''(?:"([^"\r\n]*)"|'([^'\r\n]*)'|([^\s#'"\r\n]*))\s*(?:#.*)?''', raw)
        if not match or key in values:
            raise ValueError(f"{env_path.name}:{number}: invalid or duplicate {key}")
        values[key] = next(value for value in match.groups() if value is not None)
    settings = {}
    for key, setting in (ENV_SETTINGS | OPTIONAL_SETTINGS).items():
        value = values.get(key, "")
        if key == "ADMOB_TEST_DEVICE_IDS":
            device_ids = [item.strip() for item in value.split(",") if item.strip()]
            if any(not re.fullmatch(r"[A-Fa-f0-9]{32}", item) for item in device_ids):
                raise ValueError(f"{key}: expected comma-separated SDK test device IDs")
            settings[setting] = device_ids
            continue
        if key in OPTIONAL_SETTINGS and not value:
            continue
        separator = "~" if key == "ADMOB_APP_ID" else "/"
        if not re.fullmatch(r"ca-app-pub-\d{16}" + separator + r"\d{10}", value):
            raise ValueError(f"{key}: missing or invalid AdMob ID (expected separator {separator})")
        settings[setting] = value
    # The shop heal and game-over revive both restore the crystal.
    settings.setdefault("rewards/android/crystal_unit_id", settings[ENV_SETTINGS["ADMOB_REWARD_REVIVE_ID"]])
    for key, (setting, fallback) in FORMAT_SETTINGS.items():
        if key == "ADMOB_REWARD_CRYSTAL_FORMAT" and "ADMOB_REWARD_CRYSTAL_ID" not in values:
            fallback = settings["rewards/android/revive_format"]
        value = values.get(key, fallback)
        if value not in {"rewarded", "rewarded_interstitial"}:
            raise ValueError(f"{key}: expected rewarded or rewarded_interstitial")
        settings[setting] = value
    return settings


def inject_project(project: str, settings: dict) -> str:
    sections = {}
    for path, value in settings.items():
        section, key = path.split("/", 1)
        encoded = json.dumps(value, ensure_ascii=False)
        if isinstance(value, list):
            encoded = "PackedStringArray(" + ", ".join(json.dumps(item) for item in value) + ")"
        sections.setdefault(section, {})[key] = encoded
    for section, entries in sections.items():
        header = re.search(r"(?m)^\[" + re.escape(section) + r"\]\s*$", project)
        if header is None:
            project += "\n[" + section + "]\n"
            header = re.search(r"(?m)^\[" + re.escape(section) + r"\]\s*$", project)
        start = header.end()
        following = re.search(r"(?m)^\[", project[start:])
        end = start + following.start() if following else len(project)
        body = project[start:end]
        for key, value in entries.items():
            pattern = r"(?m)^" + re.escape(key) + r"=.*$"
            entry = key + "=" + value
            body = re.sub(pattern, lambda _match: entry, body) if re.search(pattern, body) else body.rstrip() + "\n" + entry + "\n\n"
        project = project[:start] + body + project[end:]
    return project


def binary_settings(data: bytes) -> dict:
    if data[:4] != b"ECFG":
        raise ValueError("APK project.binary has an unexpected format")
    result = {}
    position = 8
    for _ in range(struct.unpack_from("<I", data, 4)[0]):
        size = struct.unpack_from("<I", data, position)[0]
        position += 4
        key = data[position:position + size].decode("utf-8")
        position += size
        size = struct.unpack_from("<I", data, position)[0]
        position += 4
        value = data[position:position + size]
        position += size
        result[key] = value
    return result


def verify_apk(apk: Path, manifest: Path, settings: dict) -> None:
    manifest_text = manifest.read_text()
    app_id = settings[ENV_SETTINGS["ADMOB_APP_ID"]]
    if not re.search(r'com\.google\.android\.gms\.ads\.APPLICATION_ID[^\n]*\n[^\n]*' + re.escape(app_id), manifest_text):
        raise ValueError("APK manifest AdMob application ID does not match .env")
    with zipfile.ZipFile(apk) as archive:
        if any(Path(name).name == ".env" or Path(name).name.startswith(".env.") for name in archive.namelist()):
            raise ValueError("APK must not contain .env files")
        packaged = binary_settings(archive.read("assets/project.binary"))
        for key, expected in settings.items():
            value = packaged.get(key, b"")
            if isinstance(expected, list):
                valid = len(value) >= 8 and struct.unpack_from("<II", value) == (34, len(expected))
                offset = 8
                for item in expected:
                    size = struct.unpack_from("<I", value, offset)[0] if valid else 0
                    offset += 4
                    valid = valid and value[offset:offset + size].rstrip(b"\0").decode() == item
                    offset += (size + 3) & ~3
            else:
                valid = len(value) >= 8 and struct.unpack_from("<I", value)[0] == 4
                size = struct.unpack_from("<I", value, 4)[0] if valid else 0
                valid = valid and value[8:8 + size].decode() == expected
            if not valid:
                raise ValueError(f"APK setting does not match .env: {key}")
    print("AdMob APK verified: application ID, placement IDs/formats, test devices; no .env packaged")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--env", type=Path, required=True)
    parser.add_argument("--project", type=Path)
    parser.add_argument("--apk", type=Path)
    parser.add_argument("--manifest", type=Path)
    args = parser.parse_args()
    try:
        settings = read_settings(args.env)
        if args.project:
            args.project.write_text(inject_project(args.project.read_text(), settings))
            print("AdMob .env configuration applied for export")
        elif args.apk and args.manifest:
            verify_apk(args.apk, args.manifest, settings)
        else:
            parser.error("use --project or both --apk and --manifest")
    except (OSError, ValueError, KeyError, struct.error) as error:
        parser.exit(1, f"AdMob configuration failed: {error}\n")


if __name__ == "__main__":
    main()
