#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../.." && pwd)"
  CONTROL="$REPO_ROOT/skills/verify-audio-priority-bar/scripts/control.sh"
}

@test "doctor fails before launch without creating state" {
  run env VERIFY_RUN_ID=doctor-before-launch VERIFY_BASE_DIR="$BATS_TEST_TMPDIR/state" VERIFY_EVIDENCE_ROOT="$BATS_TEST_TMPDIR/evidence" "$CONTROL" --execute doctor
  [ "$status" -ne 0 ]
  [[ "$output" == *"launch first"* ]]
  [ ! -e "$BATS_TEST_TMPDIR/state" ]
}

@test "exercise preview names isolated native checks" {
  run "$CONTROL" --dry-run exercise
  [ "$status" -eq 0 ]
  [[ "$output" == *"swift test"* ]]
  [[ "$output" == *"build and run the XCUITest"* ]]
  [[ "$output" == *"XCUITest fake-device journey"* ]]
}

@test "exercise recipe builds and drives the isolated fake-device UI" {
  run grep -F 'PRODUCT_BUNDLE_IDENTIFIER=com.example.AudioPriorityBar.verify' "$CONTROL"
  [ "$status" -eq 0 ]
  run grep -F -- '--verify-ui' "$REPO_ROOT/AudioPriorityBar/AudioPriorityBarApp.swift"
  [ "$status" -eq 0 ]
  run grep -F 'real-prefs-before.txt' "$CONTROL"
  [ "$status" -eq 0 ]
  run grep -F 'testFakeDeviceCanBeReorderedInMenuBarPanel' "$CONTROL"
  [ "$status" -eq 0 ]
}

@test "production preferences comparator rejects setting and device mutations" {
  run python3 "$REPO_ROOT/skills/verify-audio-priority-bar/tests/test_preferences.py"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Ran 10 tests"* ]]
}
