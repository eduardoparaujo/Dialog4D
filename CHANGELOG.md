# Changelog

All notable changes to Dialog4D are documented in this file.

Dialog4D follows Semantic Versioning for public releases.

---

## 1.0.1 — 2026-05-01

### Fixed

- Corrected `Dialog4D.Await` timeout behavior so smart `MessageDialog` overloads no longer invoke the user callback when the worker wait times out.
- Replaced internal `TThread.Queue` usage with `TThread.ForceQueue` in `Dialog4D.Internal.Queue`, preserving asynchronous dispatch even when work is scheduled from the main thread.
- Moved automatic parent-form resolution to the main-thread execution path, avoiding `Screen.ActiveForm` / `Application.MainForm` fallback access from worker threads.
- Ensured custom-button arrays are copied at request time, preserving request snapshot semantics even if the caller later modifies the original dynamic array.
- Added validation preventing custom buttons from using `mrNone` as a modal result.
- Improved owner-destroying lifecycle handling so close and callback-suppression telemetry are emitted more consistently when the parent form is destroyed.
- Fixed a lifetime edge case where parent-form destruction during the queued final callback path could allow the active request snapshot to be released by two different cleanup paths.
- Prevented stale open-animation completion callbacks in `Dialog4D.Host.FMX` from emitting out-of-order `tkShowDisplayed` telemetry when a close transition interrupts the opening animation.
- Hardened telemetry formatting so quoted text fields are escaped consistently and CR/LF/TAB characters are normalized for single-line log output.
- Corrected demo example 5.1 so queued callbacks log the correct dialog index instead of capturing the mutable loop variable.
- Restored the previous `FMX.DialogService` preferred mode after the demo comparison scenario so the demo does not leave global DialogService state changed.

### Changed

- Moved per-form state destruction outside the registry critical section during form-destruction cleanup, keeping the registry lock scoped to short map/state publication steps.
- Clarified `DialogService4D` positioning as an adapter for common `FMX.DialogService`-style callback code, not as a full behavioral clone of `FMX.DialogService`.
- Clarified Dialog4D positioning as an FMX-rendered dialog layer for scenarios that need theming, per-form queueing, request snapshots, telemetry, or worker-thread integration.
- Clarified that Dialog4D has no third-party dependency, rather than no dependency at all, because it intentionally depends on Delphi/FMX.
- Clarified global configuration guidance: theme, text provider and telemetry configuration should be performed during application initialization or another controlled configuration point.
- Clarified request snapshot behavior for theme, text provider, telemetry sink, callback and button definitions.
- Clarified telemetry callback semantics so callback telemetry is not over-promised as proof that arbitrary downstream application code completed.
- Standardized unit headers with consistent metadata and version history format.
- Consolidated the `IsMainThreadSafe` helper in `Dialog4D.Internal.Queue.pas`, removing duplicate copies from the public facade and the await helper.

### Documentation

- Added `CHANGELOG.md` as the release-history source for the project.
- Updated `README.md` to align wording with Dialog4D 1.0.1 behavior and clarify request snapshots, await timeout semantics, telemetry boundaries, programmatic close, and `DialogService4D` adapter positioning.
- Updated `docs/Architecture.md` to reflect the 1.0.1 lifecycle, callback, owner-destroying, queueing, snapshot, telemetry, and await semantics.
- Updated `docs/Guide_en.md` and `docs/Guide_pt-BR.md` to use a scope-oriented explanation and align both language versions with the same conceptual structure.
- Adjusted documentation wording around `FMX.DialogService` to present Dialog4D as a complementary FMX-rendered dialog layer for specific coordination needs.
- Updated demo documentation and comments to clarify example 5.1 queue callback behavior and example 9.1 `FMX.DialogService` preferred-mode restoration.

### Tests

- Expanded the automated DUnitX suite to 65 tests.
- Added regression coverage for:
  - asynchronous `ForceQueue` behavior;
  - custom-button `mrNone` rejection;
  - facade-level validation for manually constructed invalid custom buttons;
  - telemetry formatter escaping and single-line normalization;
  - await timeout behavior without callback invocation.

### Compatibility

- No public API signature changes.
- Existing examples and normal usage remain compatible.
- Existing code using valid custom buttons is unaffected.
- Code that attempted to use `mrNone` as a custom-button result now fails fast by design, because `mrNone` is reserved as the internal "no result" value.

---

## 1.0.0 — 2026-04-26

### Added

- Initial public release of Dialog4D.
- Added `TDialog4D` public facade with asynchronous dialog entry points.
- Added standard-button dialogs using `TMsgDlgButtons`.
- Added custom-button dialogs using `TDialog4DCustomButton`.
- Added per-form FIFO dialog orchestration so dialogs for the same form do not overlap.
- Added FMX-rendered visual host with themed dialog layout.
- Added global theme configuration through `TDialog4DTheme`.
- Added global text-provider support through `IDialog4DTextProvider`.
- Added default English text provider.
- Added structured telemetry through `TDialog4DTelemetry`.
- Added telemetry formatting helper for log/demo output.
- Added worker-thread await support through `TDialog4DAwait`.
- Added `DialogService4D` adapter for common `FMX.DialogService`-style callback code.
- Added programmatic close support through `TDialog4D.CloseDialog`.
- Added demo application covering:
  - basic dialog types;
  - custom themes;
  - text provider customization;
  - telemetry;
  - keyboard behavior;
  - queueing;
  - programmatic close;
  - await scenarios;
  - custom buttons;
  - FMX.DialogService comparison.
- Added DUnitX automated test suite.
