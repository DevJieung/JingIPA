"""Prevent removed SDKs and merged manifest permissions from returning in exports."""
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

    def test_offline_game(self):
        no_ads.check_archive(*self.package())

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
