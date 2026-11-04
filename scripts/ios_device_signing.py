"""Sign the existing device app on macOS; never change its registered bundle ID.

Certificate and profile inputs are GitHub Actions secrets, decoded only into a
temporary directory. This supports development/ad hoc device installation, not
App Store export. Neither a Team ID nor a Sign in with Apple .p8 key can replace
the certificate's private key and the device provisioning profile.
"""

import argparse
import base64
import hashlib
import json
import os
import plistlib
import re
import secrets
import shlex
import shutil
import subprocess
import sys
import tempfile
import zipfile
from datetime import datetime, timezone
from pathlib import Path

TEAM_ID = 'V4FGY5SRSX'
BUNDLE_ID = 'com.meokkiri.meokkiri'
APPLE_SIGN_IN = 'com.apple.developer.applesignin'


def command(*args):
    # Arguments may contain a keychain/certificate password. Never render them,
    # subprocess exceptions, or arbitrary tool output in build logs.
    result = subprocess.run(args, capture_output=True)
    if result.returncode:
        stage = Path(args[0]).name + ' ' + args[1]
        known_errors = ['MAC verification failed', 'User interaction is not allowed',
                        'errSecInternalComponent', 'The specified item could not be found',
                        'No such file or directory', 'invalid argument',
                        'code object is not signed at all', 'a sealed resource is missing or invalid']
        output = (result.stdout + result.stderr).decode(errors='replace')
        reason = next((error for error in known_errors if error in output), 'sensitive output withheld')
        target = ' (' + Path(args[-1]).name + ')' if Path(args[0]).name == 'codesign' else ''
        raise RuntimeError(stage + target + ' failed: ' + reason)
    return result.stdout


def validate_profile(profile, *, now=None):
    now = now or datetime.now(timezone.utc)
    if profile.get('TeamIdentifier') != [TEAM_ID]:
        raise ValueError('Profile must belong to the registered Meokkiri team.')
    entitlements = profile.get('Entitlements', {})
    if entitlements.get('application-identifier') != TEAM_ID + '.' + BUNDLE_ID:
        raise ValueError('Profile must use the original explicit Meokkiri bundle ID.')
    if entitlements.get('com.apple.developer.team-identifier') != TEAM_ID:
        raise ValueError('Profile entitlement team does not match.')
    if entitlements.get(APPLE_SIGN_IN) != ['Default']:
        raise ValueError('Regenerate the profile with Sign in with Apple enabled.')
    expiration = profile.get('ExpirationDate')
    if not isinstance(expiration, datetime):
        raise ValueError('Profile has no valid expiration date.')
    if expiration.tzinfo is None:
        expiration = expiration.replace(tzinfo=timezone.utc)
    if expiration <= now:
        raise ValueError('Provisioning profile has expired.')
    devices = profile.get('ProvisionedDevices')
    if (profile.get('ProvisionsAllDevices') or not isinstance(devices, list)
            or not devices or any(not isinstance(device, str) or not device for device in devices)):
        raise ValueError('Use a development or ad hoc profile containing the test iPhone.')
    certificates = profile.get('DeveloperCertificates')
    if not isinstance(certificates, list) or not certificates or any(
            not isinstance(certificate, bytes) or not certificate for certificate in certificates):
        raise ValueError('Profile has no signing certificates.')
    if type(entitlements.get('get-task-allow')) is not bool:
        raise ValueError('Profile must specify the device signing type.')
    return {
        'signing': 'development' if entitlements['get-task-allow'] else 'ad-hoc',
        'teamId': TEAM_ID, 'bundleId': BUNDLE_ID,
        'appleSignInEntitlementPresent': True,
        'profileExpiresAt': expiration.isoformat(),
        'provisionedDeviceCount': len(devices),
        'specificDeviceInstallationTested': False,
    }


def app_entitlements(profile):
    """Request only the app's Apple login plus the required signing identity.

    A profile authorizes capabilities; it is not the app's entitlement file.
    In particular its keychain wildcard must be narrowed to this app's group.
    """
    allowed = profile['Entitlements'].get('keychain-access-groups', [])
    default_group = TEAM_ID + '.' + BUNDLE_ID
    if allowed and not any(
            group == default_group or (group.endswith('*') and default_group.startswith(group[:-1]))
            for group in allowed if isinstance(group, str)):
        raise ValueError('Profile does not allow the app default keychain group.')
    result = {key: profile['Entitlements'][key] for key in [
        'application-identifier', 'com.apple.developer.team-identifier', APPLE_SIGN_IN, 'get-task-allow',
    ]}
    if allowed:
        result['keychain-access-groups'] = [default_group]
    return result


def validate_app_entitlements(entitlements, profile):
    expected = app_entitlements(profile)
    for key in ['application-identifier', 'com.apple.developer.team-identifier', APPLE_SIGN_IN]:
        if entitlements.get(key) != expected.get(key):
            raise ValueError('Signed app/profile entitlement mismatch: ' + key)
    if entitlements.get('get-task-allow') != expected['get-task-allow']:
        raise ValueError('Signed app/profile debugging entitlement mismatch.')
    if entitlements.get('keychain-access-groups', []) != expected.get('keychain-access-groups', []):
        raise ValueError('Signed app/profile keychain groups do not match.')
    if set(entitlements) - set(expected):
        raise ValueError('Signed app requests unconfigured extra entitlements.')


def decoded_profile(path):
    return plistlib.loads(command('security', 'cms', '-D', '-i', str(path)))


def verify_signed_app(app):
    if sys.platform != 'darwin':
        raise RuntimeError('Signed-app signature verification requires the macOS CI runner.')
    info = plistlib.loads((app / 'Info.plist').read_bytes())
    if info.get('CFBundleIdentifier') != BUNDLE_ID:
        raise ValueError('Signed app must preserve the registered Meokkiri bundle ID.')
    profile = decoded_profile(app / 'embedded.mobileprovision')
    report = validate_profile(profile)
    print('Verifying the app and all nested code signatures.', flush=True)
    command('codesign', '--verify', '--deep', '--strict', str(app))
    print('Reading the signed ARM64 app entitlements.', flush=True)
    actual = plistlib.loads(command('codesign', '-d', '--arch', 'arm64', '--entitlements=-', '--xml', str(app)))
    validate_app_entitlements(actual, profile)
    # Confirm the app's leaf signing certificate is one of this profile's
    # certificates, rather than trusting an entitlement's declared Team ID.
    with tempfile.TemporaryDirectory(prefix='meokkiri-cert-check-') as directory:
        prefix = Path(directory) / 'certificate'
        print('Extracting the app signing certificate.', flush=True)
        # This option has an optional argument, so bind its prefix with '='.
        # A separate prefix is otherwise treated as another code object.
        command('codesign', '-d', '--arch', 'arm64', '--extract-certificates=' + str(prefix), str(app))
        leaf = Path(str(prefix) + '0').read_bytes()
        if leaf not in profile['DeveloperCertificates']:
            raise ValueError('App signing certificate is not allowed by its profile.')
    return {**report, 'signatureCryptographicallyVerified': True,
            'appleSignInEntitlementVerified': True,
            'signedAppAndProfileEntitlementsMatch': True,
            'signingCertificateMatchesProfile': True}


def verify_signed_ipa(path):
    if sys.platform != 'darwin':
        raise RuntimeError('Verify signed IPA signatures on the macOS CI runner.')
    with zipfile.ZipFile(path) as archive:
        for name in archive.namelist():
            parts = Path(name).parts
            if name.startswith('/') or '..' in parts:
                raise ValueError('Unsafe IPA archive entry.')
    with tempfile.TemporaryDirectory(prefix='meokkiri-ipa-check-') as directory:
        command('ditto', '-x', '-k', str(path.resolve()), directory)
        return verify_signed_app(Path(directory) / 'Payload/Runner.app')


def sign_app(app, report_path):
    if sys.platform != 'darwin':
        raise RuntimeError('Device signing requires the macOS CI runner.')
    names = ['MEOKKIRI_IOS_CERTIFICATE_P12_BASE64', 'MEOKKIRI_IOS_PROFILE_BASE64']
    if any(not os.environ.get(name) for name in names):
        raise ValueError('Configure the certificate P12 and device profile GitHub Actions secrets.')
    info = plistlib.loads((app / 'Info.plist').read_bytes())
    if info.get('CFBundleIdentifier') != BUNDLE_ID:
        raise ValueError('Refusing to sign a different bundle ID.')
    source = Path(__file__).resolve().parents[1] / 'ios/Runner/Runner.entitlements'
    if plistlib.loads(source.read_bytes()) != {APPLE_SIGN_IN: ['Default']}:
        raise ValueError('Review new source capabilities before changing device signing entitlements.')
    if list(app.rglob('*.appex')) or [p for p in app.rglob('*.app') if p != app]:
        raise ValueError('Embedded app targets require their own profiles; unsupported by this workflow.')
    with tempfile.TemporaryDirectory(prefix='meokkiri-signing-') as directory:
        root = Path(directory)
        cert, profile_path = root / 'certificate.p12', root / 'profile.mobileprovision'
        for name, path in zip(names, [cert, profile_path]):
            path.write_bytes(base64.b64decode(os.environ[name], validate=True))
            path.chmod(0o600)
        profile = decoded_profile(profile_path)
        validate_profile(profile)
        entitlements_path = root / 'entitlements.plist'
        entitlements_path.write_bytes(plistlib.dumps(app_entitlements(profile)))
        keychain = root / 'signing.keychain-db'
        password = secrets.token_urlsafe(32)
        previous_keychains = shlex.split(command('security', 'list-keychains', '-d', 'user').decode())
        command('security', 'create-keychain', '-p', password, str(keychain))
        try:
            command('security', 'set-keychain-settings', '-lut', '21600', str(keychain))
            command('security', 'unlock-keychain', '-p', password, str(keychain))
            # codesign's private-key lookup also uses the user search list even
            # when --keychain selects the certificate. Restore it on all exits.
            command('security', 'list-keychains', '-d', 'user', '-s', str(keychain), *previous_keychains)
            command('security', 'import', str(cert), '-k', str(keychain), '-P',
                    os.environ.get('MEOKKIRI_IOS_CERTIFICATE_PASSWORD', ''),
                    '-T', '/usr/bin/codesign', '-T', '/usr/bin/security')
            command('security', 'set-key-partition-list', '-S', 'apple-tool:,apple:,codesign:',
                    '-s', '-k', password, str(keychain))
            identities = command('security', 'find-identity', '-v', '-p', 'codesigning',
                                 str(keychain)).decode()
            allowed = {hashlib.sha1(cert).hexdigest().upper() for cert in profile['DeveloperCertificates']}
            matches = [digest for digest in re.findall(r'\b[0-9A-F]{40}\b', identities) if digest in allowed]
            if len(set(matches)) != 1:
                raise ValueError('P12 must contain exactly one valid identity allowed by the profile.')
            identity = matches[0]
            print('Signing identity matches the device profile.', flush=True)
            nested = set(app.rglob('*.framework')) | set(app.rglob('*.dylib'))
            for path in sorted(nested, key=lambda p: (-len(p.parts), str(p))):
                if not path.is_symlink():
                    print('Signing nested code: ' + path.name, flush=True)
                    command('codesign', '--force', '--sign', identity, '--keychain', str(keychain),
                            '--timestamp=none', str(path))
            shutil.copyfile(profile_path, app / 'embedded.mobileprovision')
            command('codesign', '--force', '--sign', identity, '--keychain', str(keychain),
                    '--timestamp=none', '--generate-entitlement-der',
                    '--entitlements', str(entitlements_path), str(app))
            report = verify_signed_app(app)
            report_path.parent.mkdir(parents=True, exist_ok=True)
            report_path.write_text(json.dumps(report, indent=2) + '\n')
            print(json.dumps(report, indent=2))
        finally:
            try:
                command('security', 'list-keychains', '-d', 'user', '-s', *previous_keychains)
            finally:
                command('security', 'delete-keychain', str(keychain))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', required=True, type=Path)
    parser.add_argument('--report', required=True, type=Path)
    args = parser.parse_args()
    sign_app(args.app.resolve(), args.report)


if __name__ == '__main__':
    try:
        main()
    except (RuntimeError, ValueError) as error:
        raise SystemExit(str(error)) from None
    except Exception as error:
        raise SystemExit('iOS signing failed (' + type(error).__name__ + '); sensitive output withheld.') from None
