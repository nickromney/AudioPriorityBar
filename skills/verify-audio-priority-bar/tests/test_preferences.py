"""Exercise settings preservation with real plist snapshots and negative mutations."""
import copy
import importlib.util
import json
import plistlib
import tempfile
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location("preferences", Path(__file__).parents[1] / "scripts/compare-preferences.py")
preferences = importlib.util.module_from_spec(spec)
spec.loader.exec_module(preferences)


class PreferenceIsolationTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.before = {"speakerPriorities": ["desk", "builtin"], "knownDevices": json.dumps([
            {"uid": "desk", "name": "Desk", "lastSeen": 100.0, "isInput": False}
        ]).encode()}
        self.after = copy.deepcopy(self.before)
        self.devices = json.loads(self.before["knownDevices"])

    def result(self):
        self.after["knownDevices"] = json.dumps(self.devices).encode()
        paths = [Path(self.directory.name) / name for name in ("before.plist", "after.plist")]
        for path, value in zip(paths, (self.before, self.after)):
            path.write_bytes(plistlib.dumps(value))
        return preferences.compare(*paths)

    def test_identical_bytes(self):
        self.assertEqual(self.result()["classification"], "bytes-unchanged")

    def test_only_advancing_timestamp_accepted(self):
        self.devices[0]["lastSeen"] = 130.0
        result = self.result()
        self.assertEqual(result["classification"], "resident-lastSeen-only")
        self.assertFalse(result["raw_bytes_unchanged"])

    def test_priority_change_rejected(self):
        self.after["speakerPriorities"].reverse()
        with self.assertRaises(ValueError):
            self.result()

    def test_fixture_uid_rejected(self):
        self.devices.append({"uid": "verify-speaker", "name": "Fixture", "lastSeen": 130.0})
        with self.assertRaises(ValueError):
            self.result()

    def test_device_content_change_rejected(self):
        for field, value in (("name", "Changed"), ("isInput", 0)):
            with self.subTest(field=field):
                self.devices = json.loads(self.before["knownDevices"])
                self.devices[0][field] = value
                with self.assertRaises(ValueError):
                    self.result()

    def test_backwards_timestamp_rejected(self):
        self.devices[0]["lastSeen"] = 99.0
        with self.assertRaises(ValueError):
            self.result()

    def test_missing_timestamp_rejected(self):
        del self.devices[0]["lastSeen"]
        with self.assertRaises(ValueError):
            self.result()

    def test_nonfinite_or_boolean_timestamp_rejected(self):
        for value in (float("nan"), float("inf"), True):
            with self.subTest(value=value):
                self.devices[0]["lastSeen"] = value
                with self.assertRaises(ValueError):
                    self.result()

    def test_data_to_string_with_advancing_timestamp_rejected(self):
        self.devices[0]["lastSeen"] = 130.0
        before_path = Path(self.directory.name) / "before.plist"
        after_path = Path(self.directory.name) / "after.plist"
        before_path.write_bytes(plistlib.dumps(self.before))
        self.after["knownDevices"] = json.dumps(self.devices)
        after_path.write_bytes(plistlib.dumps(self.after))
        with self.assertRaisesRegex(ValueError, "must remain plist Data"):
            preferences.compare(before_path, after_path)

    def test_identity_and_order_rejected(self):
        self.devices[0]["uid"] = "other"
        with self.assertRaises(ValueError):
            self.result()


if __name__ == "__main__":
    unittest.main()
