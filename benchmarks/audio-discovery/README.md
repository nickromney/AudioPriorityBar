# Audio discovery performance investigation

Run on 2026-10-05, Apple Silicon Mac mini, Swift release optimization.
Scope: read-only `AudioDeviceService.getDevices()`, using the actual connected
CoreAudio devices. The harness does not switch routing, write levels, or change
preferences. Three records were present: built-in speaker, Teams input/output.
This measures discovery, not complete UI refresh or persistence.

## Reproduce

From the repository root:

```sh
mkdir -p .build/performance
swiftc -O -g -module-cache-path .build/performance/cache \
  AudioPriorityBar/Models/AudioDevice.swift \
  AudioPriorityBar/Services/BluetoothBatteryReader.swift \
  AudioPriorityBar/Services/AudioDeviceService.swift \
  benchmarks/audio-discovery/main.swift \
  -o .build/performance/discovery \
  -framework IOBluetooth -framework CoreAudio -framework AudioToolbox
hyperfine --warmup 3 --runs 10 --export-json .build/performance/baseline.json \
  '.build/performance/discovery 200'
xcrun xctrace record --template 'Time Profiler' \
  --output .build/performance/baseline.trace --time-limit 10s \
  --launch -- .build/performance/discovery 2000
```

The sandbox returned zero devices; measurements required unsandboxed read access.
Do not use empty-device sandbox results to judge performance. Keep devices and
connections stable while capturing and comparing golden output. Output includes
hardware identifiers; captured device outputs remain in ignored build storage.

## Findings and decision

The initial baseline was 231.6 ± 4.2 ms per 200 calls. Time Profiler recorded 532
stack samples: discovery appeared in 528, device creation in 519, battery lookup
in 386, and Bluetooth paired-device enumeration in 361 (67.9%). These are
inclusive sample counts, not additive percentages or wall-time attribution.

| Opportunity | Impact | Confidence | Effort | Score |
| --- | --- | --- | --- | --- |
| Batch paired Bluetooth enumeration within each discovery pass | 3 | 4 | 2 | 6.0 |

A single-lever trial reused a lazy Bluetooth device snapshot within a pass,
without retaining it across refreshes. Measurements did **not** establish a gain,
so the production changes were removed. Raw results are in `comparison.json`.
The trial implementation is not included in this repository's final changes.

| Metric (200 calls/process) | Original | Trial |
| --- | --- | --- |
| Mean ± standard deviation | 251.7 ± 27.5 ms | 260.4 ± 57.1 ms |
| p50 | 248.8 ms | 250.5 ms |
| p95 / p99, nearest rank | 296.9 ms | 409.6 ms |
| Calls/s including process startup | 794.6 | 768.0 |
| Maximum reported memory | 13,942,784 bytes | 13,942,784 bytes |

Ten runs are insufficient for robust tail estimates; p95/p99 both select the
maximum. OS Bluetooth caching, process startup and IPC variation limit the
conclusion. A fresh Time Profiler recording was also saved for the trial in
`.build/performance/after.trace`; its export was not analyzed. The benchmark
provides no evidence to justify shipping this change.

## Behavior evidence for the discarded trial

- Ordering preserved: same CoreAudio iteration and input-before-output order.
- Tie-breaking unchanged: same first matching Bluetooth device and battery
  fallback sequence.
- Floating-point: identical battery conversion code.
- RNG seeds: N/A.
- Golden outputs: `shasum -a 256 -c .build/performance/golden_checksums.txt`
  passed against the complete ordered device records on the connected setup.
- Limitation: connections changing during a discovery pass could produce
  different results with a snapshot; dynamic connection equivalence was not
  proven, and no connected headset battery scenario was exercised.

Verification: 39 existing Swift core tests passed; `make build` succeeded for
the trial; `git diff --check` passed. The service-only harness also compiled.
Existing CFString pointer warnings and local Xcode simulator/plugin diagnostics
were observed. No app was installed or launched, and no commits were created.
There is no production change to roll back.

Next useful measurement: complete manager refresh with isolated preferences,
and discovery with a connected Bluetooth headset and more physical outputs.
Any further optimization needs a fresh profile and behavior evidence for that
workload.
