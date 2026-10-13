#!/usr/bin/env python3
"""Reject advertising SDK resources, DEX classes and Android permissions in APKs.

The game has no ads. It does sell one permanent unlock through Google Play Billing
(docs/STORE.md); that library merges android.permission.INTERNET and
ACCESS_NETWORK_STATE into the manifest, so those two are expected, and the billing
permission must be present. Advertising permissions and SDKs stay forbidden.
"""
import argparse
from pathlib import Path
import re
import zipfile

AD_PATHS = ('addons/admob/', 'core/ads.gd', 'com/google/android/gms/ads/',
            'com/google/ads/', 'poing/godot/admob/')
AD_CLASSES = (b'com/google/android/gms/ads/', b'com/google/ads/', b'PoingGodotAdMob')
MANIFEST_MARKERS = ('com.google.android.gms.ads', 'PoingGodotAdMob',
                    'android.permission.ACCESS_ADSERVICES', 'com.google.android.gms.permission.AD_ID')
# Permissions the build is allowed to request. Anything else fails the check, so a new
# plugin cannot quietly widen what the game asks for.
ALLOWED_PERMISSIONS = ('android.permission.INTERNET', 'android.permission.ACCESS_NETWORK_STATE',
                       'com.android.vending.BILLING')
PERMISSION = re.compile(r'uses-permission.*?\n.*?android:name\([^)]*\)="([^"]+)"')
BILLING_PERMISSION = 'com.android.vending.BILLING'


def check_archive(path: Path, manifest: Path, require_billing: bool = False) -> None:
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
    requested = set(PERMISSION.findall(text))
    # The app's own signature permission is generated per package id.
    unexpected = sorted(name for name in requested
                        if name not in ALLOWED_PERMISSIONS and not name.endswith('.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION'))
    if unexpected:
        raise ValueError(f'Unexpected Android permissions: {", ".join(unexpected)}')
    if require_billing and BILLING_PERMISSION not in requested:
        raise ValueError('The Play Billing permission is missing: purchases cannot work in this APK')


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('apk', type=Path)
    parser.add_argument('--manifest', type=Path, required=True,
                        help='aapt2 dump xmltree output for this APK')
    args = parser.parse_args()
    check_archive(args.apk, args.manifest, require_billing=True)
    print('No advertising resources, SDK classes or advertising permissions in APK; Play Billing is present.')


if __name__ == '__main__':
    main()
