# Local validation

These replace the old branch-specific `bash.sh` checklist. Run them from any
working directory; they locate the repository relative to their own paths.
They check the current checkout, allow uncommitted work, and never fetch, pull,
switch branches, deploy, or change signing settings in the project.

## Linux / Factory

```bash
/path/to/convoke/scripts/check-linux.sh
```

Runs the server build and default tests, then the existing limited portable
client-core tests. Requires Swift (CI currently uses 6.4.2) and the usual Swift
Linux build dependencies. The first server build may download dependencies.

The portable tests use a **test-only Combine stand-in**. They do not prove real
Combine behavior, Apple adapters, audio hardware, or an iOS build. A Linux pass
is not a replacement for the Mac gate.

## macOS / Xcode

```bash
/path/to/convoke/scripts/check-macos.sh
```

Runs the server build and default tests, then delegates to
`ios/Convoke/scripts/test-apple.sh` for real-Combine package tests, actual iOS
simulator tests, and an unsigned iPhoneOS build. This is stronger than the old
script's simulator `build-for-testing` step, which did not execute tests.
Requires macOS 26+, full Xcode 26+, Swift 6.2+, and an installed compatible iPhone
simulator. See `ios/Convoke/README.md` for Apple test details.

The existing Apple runner retains logs and result bundles. Set
`APPLE_TEST_OUTPUT_DIR` to choose their parent directory and optionally
`SIMULATOR_UDID` to select an available compatible iPhone simulator.
Unsigned device compilation does not install the app or replace physical-device
acceptance testing.

## Server only (either platform)

```bash
/path/to/convoke/scripts/check-server.sh
```

Records the revision, working-tree changes, and Swift version, then builds and
tests the server. The server wrapper clears `CONVOKE_TEST_KOKORO_URL` and
`CONVOKE_TEST_SYSTEM_VOICE` in its subprocess so optional live-service/audio
smokes stay opt-in. The Apple runner similarly excludes optional audio checks.
Run those separately using the instructions in the server and iOS READMEs.

All scripts stop on failure. Existing CI workflows remain unchanged.
