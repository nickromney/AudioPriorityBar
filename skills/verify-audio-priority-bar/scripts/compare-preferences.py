#!/usr/bin/env python3
"""Permit only resident known-device lastSeen refreshes; preserve all settings."""
import json
import math
import plistlib
import sys
from pathlib import Path


def identical(left, right):
    if type(left) is not type(right):
        return False
    if isinstance(left, dict):
        return left.keys() == right.keys() and all(identical(left[key], right[key]) for key in left)
    if isinstance(left, list):
        return len(left) == len(right) and all(identical(a, b) for a, b in zip(left, right))
    return left == right


def compare(before_path, after_path):
    before_file, after_file = Path(before_path), Path(after_path)
    if not before_file.exists() or not after_file.exists():
        if not before_file.exists() and not after_file.exists():
            return {"accepted": True, "classification": "both-absent", "raw_bytes_unchanged": True}
        raise ValueError("production preference file appeared or disappeared")
    before_bytes, after_bytes = before_file.read_bytes(), after_file.read_bytes()
    if before_bytes == after_bytes:
        return {"accepted": True, "classification": "bytes-unchanged", "raw_bytes_unchanged": True}
    before, after = plistlib.loads(before_bytes), plistlib.loads(after_bytes)
    if not isinstance(before, dict) or not isinstance(after, dict):
        raise ValueError("preferences must be dictionaries")
    if before.keys() != after.keys():
        raise ValueError("preference keys changed")
    for key in before:
        if key != "knownDevices" and not identical(before[key], after[key]):
            raise ValueError(f"production setting changed: {key}")
    if "knownDevices" not in before:
        raise ValueError("changed bytes without known-device metadata")
    if type(before["knownDevices"]) is not bytes or type(after["knownDevices"]) is not bytes:
        raise ValueError("knownDevices must remain plist Data")
    old_devices, new_devices = json.loads(before["knownDevices"]), json.loads(after["knownDevices"])
    if not isinstance(old_devices, list) or not isinstance(new_devices, list) or len(old_devices) != len(new_devices):
        raise ValueError("known-device membership changed")
    changes = []
    seen = set()
    for old, new in zip(old_devices, new_devices):
        if not isinstance(old, dict) or not isinstance(new, dict) or old.keys() != new.keys():
            raise ValueError("known-device record fields changed")
        uid = old.get("uid")
        if not isinstance(uid, str) or uid in seen or new.get("uid") != uid:
            raise ValueError("known-device identity/order changed")
        seen.add(uid)
        for key in old:
            if key != "lastSeen" and not identical(old[key], new[key]):
                raise ValueError(f"known-device content changed: {uid}/{key}")
        old_time, new_time = old.get("lastSeen"), new.get("lastSeen")
        if any(type(value) not in (int, float) or not math.isfinite(value) for value in (old_time, new_time)):
            raise ValueError(f"missing or invalid lastSeen: {uid}")
        if new_time < old_time:
            raise ValueError(f"lastSeen moved backwards: {uid}")
        if new_time != old_time:
            changes.append({"uid": uid, "before": old_time, "after": new_time})
    if not changes:
        raise ValueError("changed bytes without any advancing resident timestamps")
    return {"accepted": True, "classification": "resident-lastSeen-only", "raw_bytes_unchanged": False,
            "settings_unchanged": True, "timestamp_changes": changes}


def main():
    try:
        result = compare(sys.argv[1], sys.argv[2])
    except (ValueError, TypeError, KeyError, plistlib.InvalidFileException) as error:
        result = {"accepted": False, "classification": "unexpected-preference-change", "reason": str(error)}
    Path(sys.argv[3]).write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result))
    return 0 if result["accepted"] else 1


if __name__ == "__main__":
    sys.exit(main())
