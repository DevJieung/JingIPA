#!/usr/bin/env python3
"""Prepare a disposable GitHub runner checkout for Godot mobile exports."""
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
from admob_config import inject_project, read_settings


def main():
    if os.environ.get("GITHUB_ACTIONS") != "true":
        raise SystemExit("This script only modifies disposable GitHub Actions checkouts.")
    version = os.environ["GODOT_VERSION"]
    templates = Path.home() / ".local/share/godot/export_templates" / (version + ".stable")
    android = ROOT / "android"
    (android / "build").mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(templates / "android_source.zip") as archive:
        archive.extractall(android / "build")
    (android / ".gdignore").touch()
    (android / ".build_version").write_text(version + ".stable")
    (android / "build/gradlew").chmod(0o755)

    keystore = Path(os.environ["GODOT_ANDROID_KEYSTORE_DEBUG_PATH"])
    keystore.parent.mkdir(parents=True, exist_ok=True)
    if not keystore.exists():
        subprocess.run([
            "keytool", "-genkeypair", "-keystore", str(keystore), "-storepass", "android",
            "-keypass", "android", "-alias", "androiddebugkey", "-dname", "CN=Android Debug,O=Android,C=US",
            "-keyalg", "RSA", "-keysize", "2048", "-validity", "10000", "-noprompt",
        ], check=True)
    settings = Path.home() / ".config/godot" / ("editor_settings-" + ".".join(version.split(".")[:2]) + ".tres")
    settings.parent.mkdir(parents=True, exist_ok=True)
    settings.write_text('[gd_resource type="EditorSettings" format=3]\n\n[resource]\n' +
                        'export/android/java_sdk_path = ' + json.dumps(os.environ["JAVA_HOME"]) + '\n' +
                        'export/android/android_sdk_path = ' + json.dumps(os.environ["ANDROID_HOME"]) + '\n')

    # Inject Android ads only in this disposable checkout.
    project = ROOT / "project.godot"
    content = project.read_text()
    ad_config = os.environ.get("POKERDEFENSE_ADMOB_ENV", "")
    if ad_config:
        env_file = Path(os.environ["RUNNER_TEMP"]) / "pokerdefense-admob.env"
        env_file.write_text(ad_config)
        env_file.chmod(0o600)
        try:
            content = inject_project(content, read_settings(env_file))
        finally:
            env_file.unlink()
    else:
        print("AdMob: using the checked-in Google test placements.")
    project.write_text(content)

    presets = ROOT / "export_presets.cfg"
    content = presets.read_text()
    for key, env_key, pattern in [
        ("bundle_identifier", "IOS_BUNDLE_ID", r"[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+"),
        ("app_store_team_id", "IOS_TEAM_ID", r"[A-Z0-9]{10}"),
    ]:
        value = os.environ.get(env_key, "")
        if value:
            if not re.fullmatch(pattern, value):
                raise SystemExit("Invalid " + env_key)
            content = re.sub(r"(?m)^application/" + key + r"=.*$", "application/" + key + "=" + json.dumps(value), content)
    presets.write_text(content)


if __name__ == "__main__":
    main()
