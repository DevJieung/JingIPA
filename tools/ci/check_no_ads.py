#!/usr/bin/env python3
"""Reject advertising SDK resources, DEX classes and Android permissions in APKs."""
import argparse
from pathlib import Path
import re
import zipfile

AD_PATHS = ('addons/admob/', 'core/ads.gd', 'com/google/android/gms/ads/',
            'com/google/ads/', 'poing/godot/admob/')
AD_CLASSES = (b'com/google/android/gms/ads/', b'com/google/ads/', b'PoingGodotAdMob')
MANIFEST_MARKERS = ('com.google.android.gms.ads', 'PoingGodotAdMob',
                    'android.permission.INTERNET', 'android.permission.ACCESS_NETWORK_STATE',
                    'android.permission.ACCESS_ADSERVICES', 'com.google.android.gms.permission.AD_ID')


def check_archive(path: Path, manifest: Path) -> None:
    with zipfile.ZipFile(path) as archive:
        for entry in archive.infolist():
            if any(part in entry.filename for part in AD_PATHS):
                raise ValueError(f'Advertising resource in APK: {entry.filename}')
            if re.fullmatch(r'classes\d*\.dex', entry.filename):
                data = archive.read(entry)
                if any(marker in data for marker in AD_CLASSES):
                    raise ValueError(f'Advertising SDK classes in {entry.filename}')
    text = manifest.read_text()
    for marker in MANIFEST_MARKERS:
        if marker in text:
            raise ValueError(f'Unexpected Android manifest entry: {marker}')


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('apk', type=Path)
    parser.add_argument('--manifest', type=Path, required=True,
                        help='aapt2 dump xmltree output for this APK')
    args = parser.parse_args()
    check_archive(args.apk, args.manifest)
    print('No advertising resources, SDK classes or network/advertising permissions in APK.')


if __name__ == '__main__':
    main()
