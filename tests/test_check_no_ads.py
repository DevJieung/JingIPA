"""Prevent removed ad SDKs and unlisted manifest permissions from entering exports."""
import importlib.util
from pathlib import Path
import tempfile
import unittest
import zipfile

SPEC = importlib.util.spec_from_file_location('no_ads', Path(__file__).resolve().parents[1] / 'tools/ci/check_no_ads.py')
no_ads = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(no_ads)


class PackageChecks(unittest.TestCase):
    def package(self, files=None, manifest='manifest package=com.devjieung.stellardefense'):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        root = Path(directory.name)
        apk = root / 'sd-tst.apk'
        with zipfile.ZipFile(apk, 'w') as archive:
            for name, content in (files or {'classes.dex': b'org/godotengine/godot/'}).items():
                archive.writestr(name, content)
        xml = root / 'manifest.txt'
        xml.write_text(manifest)
        return apk, xml

    @staticmethod
    def permissions(*names):
        lines = ['N: android=http://schemas.android.com/apk/res/android', '  E: manifest (line=2)']
        for index, name in enumerate(names):
            lines.append(f'    E: uses-permission (line={10 + index})')
            lines.append(f'      A: http://schemas.android.com/apk/res/android:name(0x01010003)="{name}" (Raw: "{name}")')
        return '\n'.join(lines) + '\n'

    def test_game_without_permissions(self):
        no_ads.check_archive(*self.package())

    def test_billing_build(self):
        manifest = self.permissions('android.permission.INTERNET', 'android.permission.ACCESS_NETWORK_STATE',
                                    'com.android.vending.BILLING',
                                    'com.devjieung.stellardefense.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION')
        no_ads.check_archive(*self.package(manifest=manifest), require_billing=True)

    def test_billing_permission_required_for_store_build(self):
        with self.assertRaises(ValueError):
            no_ads.check_archive(*self.package(manifest=self.permissions('android.permission.INTERNET')), require_billing=True)

    def test_unlisted_permission(self):
        for name in ('android.permission.ACCESS_FINE_LOCATION', 'android.permission.READ_CONTACTS', 'android.permission.CAMERA'):
            with self.subTest(name=name), self.assertRaises(ValueError):
                no_ads.check_archive(*self.package(manifest=self.permissions('com.android.vending.BILLING', name)))

    def test_removed_script_and_plugin_resources(self):
        for name in ('assets/core/ads.gd.remap', 'assets/addons/admob/plugin.cfg'):
            with self.subTest(name=name), self.assertRaises(ValueError):
                no_ads.check_archive(*self.package({name: b'resource'}))

    def test_sdk_in_secondary_dex(self):
        for marker in no_ads.AD_CLASSES:
            with self.subTest(marker=marker), self.assertRaises(ValueError):
                no_ads.check_archive(*self.package({'classes2.dex': b'dex\x00' + marker}))

    def test_manifest_permissions_and_metadata(self):
        for marker in no_ads.MANIFEST_MARKERS:
            with self.subTest(marker=marker), self.assertRaises(ValueError):
                no_ads.check_archive(*self.package(manifest='manifest\n' + marker))
