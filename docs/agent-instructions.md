# Agent instructions

- Convoke contains the Swift server in `server/`, protocol fixtures in `protocol/`, and the iPhone app and local ConvokeCore package in `ios/Convoke/`. The ticket is the implementation specification.
- For test scope and platform prerequisites, read `docs/development.md`. The Linux commit checks are `swift build --package-path server`, `swift test --package-path server`, and `bash ios/Convoke/scripts/test-portable-core.sh`. The portable harness uses a test-only Combine stand-in; it is not an Apple-platform pass.
- This is a Linux container without Xcode, Apple SDKs, or a physical iPhone. Run all relevant available checks and record exact results. Write and inspect Apple-platform tests even when they cannot run here. Mark Mac/iPhone checks Pending for the owner after merge; their unavailability alone is not an implementation blocker or a claim that tests passed.
- The owner performs Mac/Xcode and physical-device acceptance after merge. Do not contact a Mac or production host, invent hardware evidence, or weaken tests to hide a known defect. Model API or code defects still require investigation; only unavailable platform execution is deferred.
