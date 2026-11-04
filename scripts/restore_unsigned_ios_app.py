"""Reuse an already verified macOS device build only for identical app sources."""

import argparse
import json
import re
import subprocess
import sys
import tempfile
from pathlib import Path

from verify_ios_ipa import ROOT, verify_ipa, verify_source


def check_input(directory, expected_sha256):
    if not re.fullmatch(r'[0-9a-f]{64}', expected_sha256):
        raise ValueError('A pinned original IPA SHA-256 is required.')
    files = {}
    for name in ['validation.json', 'source-manifest.json']:
        matches = list(directory.rglob(name))
        if len(matches) != 1:
            raise ValueError('Expected one original artifact file: ' + name)
        files[name] = json.loads(matches[0].read_text())
    source, _ = verify_source()
    if files['source-manifest.json'] != source:
        raise ValueError('Original build source manifest differs from this release.')
    original = files['validation.json']
    if (original.get('status') != 'passed' or original.get('signing') != 'unsigned'
            or original.get('sha256') != expected_sha256
            or original.get('sameClientSourceVerified') is not True
            or original.get('releaseAotVerified') is not True):
        raise ValueError('Original macOS build validation is not the expected release.')
    ipas = list(directory.rglob('*.ipa'))
    if len(ipas) != 1:
        raise ValueError('Expected exactly one original unsigned IPA.')
    actual = verify_ipa(ipas[0])
    if actual['sha256'] != expected_sha256:
        raise ValueError('Original IPA SHA-256 does not match the pinned release.')
    return ipas[0], actual


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--directory', required=True, type=Path)
    parser.add_argument('--sha256', required=True)
    parser.add_argument('--check-only', action='store_true')
    args = parser.parse_args()
    ipa, report = check_input(args.directory.resolve(), args.sha256)
    if not args.check_only:
        if sys.platform != 'darwin':
            raise RuntimeError('Restore signed-build inputs on the macOS CI runner.')
        with tempfile.TemporaryDirectory(prefix='meokkiri-unsigned-') as directory:
            subprocess.run(['ditto', '-x', '-k', str(ipa), directory], check=True)
            app = ROOT / 'build/ios/iphoneos/Runner.app'
            app.parent.mkdir(parents=True, exist_ok=True)
            if app.exists():
                raise ValueError('Refusing to overwrite a pre-existing app build.')
            subprocess.run(['ditto', str(Path(directory) / 'Payload/Runner.app'), str(app)], check=True)
        locks = list(args.directory.rglob('Podfile.lock'))
        if len(locks) != 1:
            raise ValueError('Original CocoaPods lockfile is missing or ambiguous.')
        (ROOT / 'ios/Podfile.lock').write_bytes(locks[0].read_bytes())
    print(json.dumps({'originalIpaVerified': True, 'originalIpaSha256': report['sha256'],
                      'identicalCommonSourceVerified': True,
                      'commonSourceSha256': report['commonSourceSha256'],
                      'versionName': report['versionName'], 'versionCode': report['versionCode'],
                      'checkOnly': args.check_only}, indent=2))


if __name__ == '__main__':
    main()
