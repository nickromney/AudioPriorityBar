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
  [[ "$output" == *"xcodebuild build"* ]]
}
