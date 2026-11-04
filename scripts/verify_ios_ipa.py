"""Verify shared release sources and a device ARM64 Flutter IPA."""

import argparse
import hashlib
import json
import plistlib
import re
import struct
import zipfile
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def verify_arm64_macho(data, name):
    """Flutter's AOT framework may use a universal container with one ARM64 slice."""
    if len(data) < 8:
        raise RuntimeError('Truncated Mach-O executable: ' + name)
    magic, cpu = struct.unpack_from('<II', data)
    if magic == 0xFEEDFACF and cpu == 0x0100000C:
        return
    formats = {
        b'\xca\xfe\xba\xbe': ('>', False), b'\xbe\xba\xfe\xca': ('<', False),
        b'\xca\xfe\xba\xbf': ('>', True), b'\xbf\xba\xfe\xca': ('<', True),
    }
    if data[:4] not in formats:
        raise RuntimeError('Expected a device ARM64 Mach-O executable: ' + name)
    endian, wide = formats[data[:4]]
    count = struct.unpack_from(endian + 'I', data, 4)[0]
    record = endian + ('IIQQII' if wide else 'IIIII')
    record_size = struct.calcsize(record)
    if not 1 <= count <= 16 or len(data) < 8 + count * record_size:
        raise RuntimeError('Invalid universal Mach-O header: ' + name)
    for index in range(count):
        cpu, _, offset, size, *_ = struct.unpack_from(record, data, 8 + index * record_size)
        if (cpu != 0x0100000C or offset < 8 + count * record_size
                or size < 8 or offset + size > len(data)):
            raise RuntimeError('Invalid or non-device ARM64 Mach-O slice: ' + name)
        if struct.unpack_from('<II', data, offset) != (0xFEEDFACF, 0x0100000C):
            raise RuntimeError('ARM64 slice header does not match the universal table: ' + name)


def verify_source():
    source = json.loads((ROOT / 'ci/source-manifest.json').read_text())
    for name, digest in source['files'].items():
        actual = hashlib.sha256((ROOT / name).read_bytes()).hexdigest()
        if actual != digest:
            raise RuntimeError('Shared web source changed: ' + name)
    config = json.loads((ROOT / 'config/firebase.mkr-web.ios.json').read_text())
    if (config.get('USE_FIREBASE') is not True
            or config.get('USE_FIREBASE_EMULATORS', False)
            or config.get('FIREBASE_PROJECT_ID') != 'mkr-web'
            or ':ios:' not in config.get('FIREBASE_APP_ID', '')):
        raise RuntimeError('The registered production Firebase iOS configuration is required.')
    return source, config


def verify_ipa(path, *, signing='unsigned'):
    if signing not in {'unsigned', 'device'}:
        raise ValueError('Unsupported IPA signing mode.')
    source, config = verify_source()
    version, build = re.search(
        r'^version:\s*(\S+)\+(\d+)\s*$', (ROOT / 'pubspec.yaml').read_text(), re.M,
    ).groups()
    with zipfile.ZipFile(path) as archive:
        names = archive.namelist()
        if len(names) != len(set(names)) or archive.testzip() is not None:
            raise RuntimeError('IPA contains duplicate entries or corrupt ZIP data.')
        prefix = 'Payload/Runner.app/'
        info = plistlib.loads(archive.read(prefix + 'Info.plist'))
        expected = {
            'CFBundleIdentifier': 'com.meokkiri.meokkiri',
            'CFBundleShortVersionString': version,
            'CFBundleVersion': build,
        }
        for key, value in expected.items():
            if info.get(key) != value:
                raise RuntimeError('Unexpected IPA metadata: ' + key)
        binaries = [prefix + info['CFBundleExecutable'], prefix + 'Frameworks/App.framework/App']
        for name in binaries:
            verify_arm64_macho(archive.read(name), name)
        aot = archive.read(binaries[1])
        markers = [config['FIREBASE_APP_ID'].encode(), b'mkr-web',
                   b'pod-seats-scroll', b'waiting-garden-scroll',
                   b'occupantEmojis', b'ownSeatIndex', b'pod-occupant-']
        for marker in markers:
            if marker not in aot:
                raise RuntimeError('Missing Firebase or release feature marker: ' + repr(marker))
        assets = prefix + 'Frameworks/App.framework/flutter_assets/'
        if any(name.endswith('/kernel_blob.bin') for name in names):
            raise RuntimeError('Debug Dart kernel found in release IPA.')
        garden = 'assets/brand/waiting-garden-v1.webp'
        if hashlib.sha256(archive.read(assets + garden)).hexdigest() != source['files'][garden]:
            raise RuntimeError('Garden illustration differs from the web release.')
        has_signing_data = (prefix + '_CodeSignature/CodeResources' in names
                            or prefix + 'embedded.mobileprovision' in names)
        if signing == 'unsigned' and has_signing_data:
            raise RuntimeError('This workflow must report an unsigned IPA; unexpected signing data found.')
        if signing == 'device' and not has_signing_data:
            raise RuntimeError('Device-signed IPA has no signing data.')
    signing_report = {'signing': 'unsigned', 'signatureCryptographicallyVerified': False,
                      'appleSignInEntitlementVerified': False}
    if signing == 'device':
        from ios_device_signing import verify_signed_ipa
        signing_report = verify_signed_ipa(path)
    return {
        'status': 'passed', 'verifiedAt': datetime.now(timezone.utc).isoformat(),
        'file': path.name, 'sizeBytes': path.stat().st_size,
        'sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
        'versionName': version, 'versionCode': int(build),
        'bundleId': info['CFBundleIdentifier'], 'deviceFamilies': info.get('UIDeviceFamily'),
        'minimumOSVersion': info.get('MinimumOSVersion'), 'architecture': 'arm64',
        'buildMode': 'release', 'releaseAotVerified': True, **signing_report,
        'firebaseProject': config['FIREBASE_PROJECT_ID'], 'firebaseAppId': config['FIREBASE_APP_ID'],
        'sameClientSourceVerified': True, 'sourceFilesVerified': len(source['files']),
        'commonSourceSha256': source['commonSourceSha256'], 'gardenAssetVerified': True,
        'testFlightUploaded': False, 'deviceInstallationTested': False,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check-source', action='store_true')
    parser.add_argument('--ipa', type=Path)
    parser.add_argument('--report', type=Path)
    parser.add_argument('--signing', choices=['unsigned', 'device'], default='unsigned')
    args = parser.parse_args()
    if args.check_source:
        source, _ = verify_source()
        print('Verified shared web source files:', len(source['files']))
    if args.ipa:
        report = verify_ipa(args.ipa, signing=args.signing)
        if args.report:
            args.report.parent.mkdir(parents=True, exist_ok=True)
            args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
        print(json.dumps(report, ensure_ascii=False, indent=2))
    if not args.check_source and not args.ipa:
        parser.error('Use --check-source or --ipa.')


if __name__ == '__main__':
    main()
