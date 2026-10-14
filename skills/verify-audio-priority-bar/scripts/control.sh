#!/usr/bin/env bash
# shellcheck disable=SC2034 # VK_* settings are read by the sourced verify-lib.sh
set -euo pipefail

VK_SCRIPT="$0"
VK_APP="audio-priority-bar"
VK_DESCRIPTION="Verify Audio Priority Bar's native core tests and build without installing or launching the app."
VK_PROJECT_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
# shellcheck source=verify-lib.sh disable=SC1091
. "$(cd "$(dirname "$0")" && pwd)/verify-lib.sh"

vk_commands_help() {
  cat <<'HELP'
  launch                 capture installed Swift and Xcode toolchain versions
  doctor                 verify the native project and toolchain are available
  exercise               run core tests and build the app into run-owned state
  cleanup                remove run state; keep evidence
HELP
}
vk_sample_commands() { printf '%s\n' verify launch doctor exercise cleanup; }
vk_paths() {
  STATE="$VK_BASE_DIR/$VK_RUN_ID/state"
  EVIDENCE="$VK_EVIDENCE_ROOT/$VK_RUN_ID"
  DERIVED="$STATE/DerivedData"
}

vk_plan() {
  case "$1" in
    verify) vk_plan_line "capture installed toolchain, run swift core tests, build app into isolated state; evidence in $EVIDENCE" ;;
    launch) vk_plan_line "record swift and Xcode versions under $STATE" ;;
    doctor) vk_plan_line "check AudioPriorityBar.xcodeproj, Package.swift, and installed toolchain" ;;
    exercise) vk_plan_line "run swift test with isolated scratch space and xcodebuild build with 2 jobs under $STATE" ;;
    cleanup) vk_plan_line "remove $STATE; keep build/test logs in $EVIDENCE" ;;
    *) vk_unknown_command ;;
  esac
}

cmd_launch() {
  mkdir -p "$STATE" "$EVIDENCE"
  vk_mark_current
  vk_record_revision "$EVIDENCE/revision.txt"
  command -v swift >/dev/null 2>&1 || { vk_fail "Swift is not installed"; return 1; }
  command -v xcodebuild >/dev/null 2>&1 || { vk_fail "Xcode command-line tools are not installed"; return 1; }
  swift --version > "$STATE/swift-version.txt"
  xcodebuild -version > "$STATE/xcode-version.txt"
  cp "$STATE/swift-version.txt" "$EVIDENCE/swift-version.txt"
  cp "$STATE/xcode-version.txt" "$EVIDENCE/xcode-version.txt"
  vk_say "captured installed Swift and Xcode versions"
}

cmd_doctor() {
  [ -d "$VK_PROJECT_ROOT/AudioPriorityBar.xcodeproj" ] || { vk_fail "Xcode project is missing"; return 1; }
  [ -f "$VK_PROJECT_ROOT/Package.swift" ] || { vk_fail "Swift core package is missing"; return 1; }
  [ -s "$STATE/swift-version.txt" ] && [ -s "$STATE/xcode-version.txt" ] || { vk_fail "toolchain capture missing; launch first"; return 1; }
  vk_expect_contains "$STATE/swift-version.txt" "Apple Swift"
  vk_expect_contains "$STATE/xcode-version.txt" "Xcode"
  vk_say "OK native project and installed toolchain are ready"
}

cmd_exercise() {
  cmd_doctor >/dev/null
  (
    cd "$VK_PROJECT_ROOT"
    swift test --scratch-path "$STATE/swiftpm" --jobs 2
  ) > "$STATE/swift-test.log" 2>&1
  grep -E -q 'Executed [0-9]+ tests?, with 0 failures' "$STATE/swift-test.log" || { vk_fail "Swift core test summary is missing"; return 1; }
  xcodebuild \
    -project "$VK_PROJECT_ROOT/AudioPriorityBar.xcodeproj" \
    -scheme AudioPriorityBar \
    -destination 'platform=macOS,arch=arm64' \
    -configuration Debug \
    -derivedDataPath "$DERIVED" \
    -jobs 2 \
    -disableAutomaticPackageResolution \
    CODE_SIGNING_ALLOWED=NO \
    build > "$STATE/xcodebuild.log" 2>&1
  [ -d "$DERIVED/Build/Products/Debug/AudioPriorityBar.app" ] || { vk_fail "isolated app build product is missing"; return 1; }
  cp "$STATE/swift-test.log" "$EVIDENCE/swift-test.log"
  cp "$STATE/xcodebuild.log" "$EVIDENCE/xcodebuild.log"
  vk_say "core tests passed and app built under isolated run state"
}

cmd_cleanup() {
  if [ -d "$STATE" ]; then
    [ ! -f "$STATE/swift-test.log" ] || cp "$STATE/swift-test.log" "$EVIDENCE/swift-test.log"
    [ ! -f "$STATE/xcodebuild.log" ] || cp "$STATE/xcodebuild.log" "$EVIDENCE/xcodebuild.log"
  fi
  rm -rf "${STATE:?}"
  rmdir "$VK_BASE_DIR/$VK_RUN_ID" 2>/dev/null || true
  vk_clear_current
  vk_say "removed run-owned Swift scratch and app build; evidence kept at $EVIDENCE"
}

vk_verify_recipes() { cmd_exercise; }
vk_dispatch() {
  local cmd="$1"
  shift
  case "$cmd" in
    launch) cmd_launch ;;
    doctor) cmd_doctor ;;
    exercise) cmd_exercise ;;
    cleanup) cmd_cleanup ;;
    *) vk_unknown_command ;;
  esac
}
vk_main "$@"
