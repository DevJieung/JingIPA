import importlib.util
from pathlib import Path
import tempfile
import unittest


spec = importlib.util.spec_from_file_location("admob_config", Path(__file__).resolve().parents[1] / "tools/admob_config.py")
config = importlib.util.module_from_spec(spec)
spec.loader.exec_module(config)


class AdMobConfigTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.env = Path(self.directory.name) / ".env"
        self.content = "\n".join(
            f'{key}="ca-app-pub-1111111111111111{"~" if key == "ADMOB_APP_ID" else "/"}{index:010d}" # placement'
            for index, key in enumerate(config.ENV_SETTINGS, 1)
        )
        self.env.write_text(self.content)

    def test_allowlist_and_crystal_fallback(self):
        self.env.write_text(self.content + "\nUNRELATED_SECRET=$(do_not_execute)\n")
        settings = config.read_settings(self.env)
        self.assertEqual(len(settings), 10)
        self.assertEqual(settings["rewards/android/crystal_unit_id"], settings["rewards/android/revive_unit_id"])
        self.assertNotIn("do_not_execute", str(settings))
        self.assertEqual(settings["rewards/android/card_change_format"], "rewarded")
        self.assertEqual(settings["rewards/android/merge_restore_format"], "rewarded_interstitial")
        self.assertEqual(settings["rewards/android/revive_format"], "rewarded_interstitial")

    def test_format_override_and_fallback(self):
        self.env.write_text(self.content + "\nADMOB_REWARD_REVIVE_FORMAT=rewarded\n")
        settings = config.read_settings(self.env)
        self.assertEqual(settings["rewards/android/crystal_format"], "rewarded")
        self.assertEqual(settings["rewards/android/revive_format"], "rewarded")
        self.env.write_text(self.content + "\nADMOB_REWARD_MERGE_RESTORE_FORMAT=interstitial\n")
        with self.assertRaises(ValueError):
            config.read_settings(self.env)

    def test_optional_ids(self):
        self.env.write_text(self.content + "\nexport ADMOB_REWARD_CRYSTAL_ID='ca-app-pub-1111111111111111/9999999999'\nADMOB_TEST_DEVICE_IDS=ABCDEF0123456789ABCDEF0123456789,0123456789ABCDEF0123456789ABCDEF\n")
        settings = config.read_settings(self.env)
        self.assertTrue(settings["rewards/android/crystal_unit_id"].endswith("/9999999999"))
        self.assertEqual(len(settings["rewards/android/test_device_ids"]), 2)

    def test_invalid_config_fails_without_echoing_values(self):
        for content in ("", self.content.replace("~", "/"), self.content + "\nADMOB_APP_ID=sensitive-value", self.content.replace("/0000000002", "/$(sensitive-value)")):
            self.env.write_text(content)
            with self.assertRaises(ValueError) as caught:
                config.read_settings(self.env)
            self.assertNotIn("sensitive-value", str(caught.exception))

    def test_inject_preserves_other_settings_and_is_repeatable(self):
        original = 'config_version=5\n\n[admob]\n\ngeneral/ios/enabled=false\n\n[application]\n\nconfig/name="Game"\n\n[rewards]\n\nandroid/revive_unit_id="old"\n'
        settings = config.read_settings(self.env)
        injected = config.inject_project(original, settings)
        self.assertIn('general/ios/enabled=false', injected)
        self.assertIn('config/name="Game"', injected)
        self.assertEqual(injected.count("android/revive_unit_id="), 1)
        self.assertEqual(injected, config.inject_project(injected, settings))
        self.assertNotIn('"old"', injected)


if __name__ == "__main__":
    unittest.main()
