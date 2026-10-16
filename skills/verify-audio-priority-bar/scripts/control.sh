#!/usr/bin/env bash
# shellcheck disable=SC2034 # VK_* settings are read by the sourced verify-lib.sh
set -euo pipefail

VK_SCRIPT="$0"
VK_APP="audio-priority-bar"
VK_DESCRIPTION="Verify Audio Priority Bar with core tests and a fake-device menu-bar UI journey."
VK_PROJECT_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
# shellcheck source=verify-lib.sh disable=SC1091
. "$(cd "$(dirname "$0")" && pwd)/verify-lib.sh"

vk_commands_help() {
  cat <<'HELP'
  launch                 capture installed Swift and Xcode toolchain versions
  doctor                 verify the native project and toolchain are available
  exercise               run core tests and isolated fake-device UI journey
                         APB_VERIFY_RECIPE=hosted drives hosted rendered controls
  cleanup                remove run state; keep evidence
HELP
}
vk_sample_commands() { printf '%s\n' verify launch doctor exercise cleanup; }
vk_paths() {
  STATE="$VK_BASE_DIR/$VK_RUN_ID/state"
  EVIDENCE="$VK_EVIDENCE_ROOT/$VK_RUN_ID"
  DERIVED="$STATE/DerivedData"
  REAL_PREFS="$HOME/Library/Preferences/com.example.AudioPriorityBar.plist"
}

real_state_digest() {
  if [ -f "$REAL_PREFS" ]; then shasum -a 256 "$REAL_PREFS" | awk '{print $1}'; else printf '%s\n' absent; fi
}

capture_real_preferences() {
  local phase="$1"
  real_state_digest > "$STATE/real-prefs-$phase.txt"
  cp "$STATE/real-prefs-$phase.txt" "$EVIDENCE/real-prefs-$phase.txt"
  if [ -f "$REAL_PREFS" ]; then
    cp "$REAL_PREFS" "$EVIDENCE/real-prefs-$phase.plist"
    plutil -convert xml1 -o "$EVIDENCE/real-prefs-$phase.xml" "$EVIDENCE/real-prefs-$phase.plist"
  fi
}

vk_plan() {
  case "$1" in
    verify) vk_plan_line "capture installed toolchain, run core pre-check and fake-device XCUITest journey under isolated state, compare real preferences, then clean up; evidence in $EVIDENCE" ;;
    launch) vk_plan_line "record swift and Xcode versions under $STATE" ;;
    doctor) vk_plan_line "check AudioPriorityBar.xcodeproj, Package.swift, and installed toolchain" ;;
    exercise) vk_plan_line "run swift test pre-check, build and run the XCUITest fake-device journey or APB_VERIFY_RECIPE=hosted rendered controls under a throwaway bundle id; guard real preferences" ;;
    cleanup) vk_plan_line "remove $STATE; keep build/test logs in $EVIDENCE" ;;
    *) vk_unknown_command ;;
  esac
}

cmd_launch() {
  case "${APB_VERIFY_RECIPE:-ui}" in ui|hosted) ;; *) vk_fail "APB_VERIFY_RECIPE must be ui or hosted"; return 1 ;; esac
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
  capture_real_preferences before
  defaults delete com.example.AudioPriorityBar.verify >/dev/null 2>&1 || true
  defaults delete com.example.AudioPriorityBar.verify.fixture >/dev/null 2>&1 || true
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
    PRODUCT_BUNDLE_IDENTIFIER=com.example.AudioPriorityBar.verify \
    CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual \
    build-for-testing > "$STATE/xcodebuild.log" 2>&1
  [ -d "$DERIVED/Build/Products/Debug/AudioPriorityBar.app" ] || { vk_fail "isolated app build product is missing"; return 1; }
  shasum -a 256 "$DERIVED/Build/Products/Debug/AudioPriorityBar.app/Contents/MacOS/AudioPriorityBar" > "$EVIDENCE/binary-sha256.txt"
  if [ "${APB_VERIFY_RECIPE:-ui}" = hosted ]; then
    mkdir -p "$EVIDENCE/hosted"
    TEST_RUNNER_APB_VERIFY_EVIDENCE="$EVIDENCE/hosted" xcodebuild \
      -project "$VK_PROJECT_ROOT/AudioPriorityBar.xcodeproj" -scheme AudioPriorityBar \
      -destination 'platform=macOS,arch=arm64' -configuration Debug \
      -derivedDataPath "$DERIVED" -jobs 2 -parallel-testing-enabled NO \
      -only-testing:AudioPriorityBarTests -resultBundlePath "$EVIDENCE/hosted.xcresult" \
      PRODUCT_BUNDLE_IDENTIFIER=com.example.AudioPriorityBar.verify \
      CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual test > "$EVIDENCE/hosted-test.log" 2>&1
    [ -s "$EVIDENCE/hosted/rendered-actions.txt" ] || { vk_fail "rendered actions evidence missing"; return 1; }
    [ -s "$EVIDENCE/hosted/rendered-after-unmute.png" ] || { vk_fail "rendered screenshot missing"; return 1; }
  else
  local xctestrun
  xctestrun="$(find "$DERIVED/Build/Products" -maxdepth 1 -name '*.xctestrun' | head -1)"
  [ -n "$xctestrun" ] || { vk_fail "XCUITest build product is missing"; return 1; }
  xcodebuild test-without-building -xctestrun "$xctestrun" \
    -destination "platform=macOS,arch=$(uname -m)" \
    -only-testing:AudioPriorityBarUITests/AudioPriorityBarUITests/testFakeDeviceCanBeReorderedInMenuBarPanel \
    -resultBundlePath "$EVIDENCE/ui.xcresult" > "$EVIDENCE/xcode-ui-test.log" 2>&1 || { vk_fail "menu-bar UI journey failed; see $EVIDENCE/xcode-ui-test.log"; return 1; }
  fi
  capture_real_preferences after
  python3 "$VK_PROJECT_ROOT/skills/verify-audio-priority-bar/scripts/compare-preferences.py" \
    "$EVIDENCE/real-prefs-before.plist" "$EVIDENCE/real-prefs-after.plist" \
    "$EVIDENCE/preferences-comparison.json" > "$EVIDENCE/preferences-comparison.log" \
    || { vk_fail "production settings changed; see preferences-comparison.json"; return 1; }
  cp "$STATE/swift-test.log" "$EVIDENCE/swift-test.log"
  cp "$STATE/xcodebuild.log" "$EVIDENCE/xcodebuild.log"
  vk_say "core pre-check and ${APB_VERIFY_RECIPE:-ui} fake-device journey passed; production settings preserved (raw byte comparison retained; resident timestamp changes classified); physical routing unverified"
}

cmd_cleanup() {
  if [ -d "$STATE" ]; then
    if [ -f "$STATE/real-prefs-before.txt" ] && [ ! -f "$EVIDENCE/real-prefs-after.txt" ]; then
      capture_real_preferences after
    fi
    [ ! -f "$STATE/swift-test.log" ] || cp "$STATE/swift-test.log" "$EVIDENCE/swift-test.log"
    [ ! -f "$STATE/xcodebuild.log" ] || cp "$STATE/xcodebuild.log" "$EVIDENCE/xcodebuild.log"
  fi
  rm -rf "${STATE:?}"
  defaults delete com.example.AudioPriorityBar.verify >/dev/null 2>&1 || true
  defaults delete com.example.AudioPriorityBar.verify.fixture >/dev/null 2>&1 || true
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
