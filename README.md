<p align="center">
  <img src="assets/banner.png" alt="Dialog4D" width="900">
</p>

# Dialog4D

**Asynchronous, themeable, queue-aware dialog library for Delphi FMX — designed to make user decisions explicit, predictable, and visually consistent across desktop and mobile.**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Delphi](https://img.shields.io/badge/Delphi-11%2B-red.svg)](https://www.embarcadero.com/products/delphi)

**Dialog4D** is a dialog library built around a single idea: **a dialog is not only a notification — it is a decision point in application flow**. It focuses on application-level dialog concerns that may sit outside the default platform-dialog path: app-rendered visual consistency, queue-aware request orchestration, structured telemetry, and explicit worker-thread coordination. It expresses those concerns as an asynchronous, themeable, FMX-rendered mechanism across Windows, macOS, iOS, and Android.

Every dialog is rendered as an FMX overlay inside the parent form. No native operating-system dialog is created. The application keeps centralized control over appearance, behavior, lifecycle, queueing, and telemetry, while preserving the asynchronous model required by FMX on mobile platforms.

---

## Why this project exists

Delphi ships with `FMX.DialogService`, which is a practical default and aligns dialog presentation with the native platform. It remains a good choice for many applications, especially when native/platform-styled dialogs are preferred.

For applications that require stronger visual consistency, queue-aware behavior, richer instrumentation, or more explicit control over dialog flow, a pure-FMX approach may be a better fit.

Real applications often need more than "show a message and get a result". They need dialogs that drive flow rather than just announce events: per-form serialization so queued requests do not overlap, snapshot-based isolation so theme changes do not affect requests already in flight, worker-thread coordination that does not block the UI, structured telemetry that records *why* a dialog closed and not just *that* it closed, and a way to request a programmatic close from worker code when the application context changes, while the actual close operation is marshalled to the main thread.

**Dialog4D** is designed around those concerns. The asynchronous model is the contract, not an option. Per-form FIFO queueing is built in. Themes are captured at call time. Telemetry covers seven lifecycle events with close-reason tracking. Worker-thread integration uses an explicit await helper instead of crossing the thread boundary informally. The programming model remains consistent across the supported platform family.

The library is intentionally focused: **structured asynchronous dialogs as decision mechanisms with explicit lifecycle**. It does not try to be a general UI toolkit, a notification system, or a wizard framework. It provides one predictable dialog runner, and stops there.

---

## Table of contents

- [Quick overview](#quick-overview)
- [Design philosophy](#design-philosophy)
- [Dialogs as decisions, not notifications](#dialogs-as-decisions-not-notifications)
- [When to use Dialog4D](#when-to-use-dialog4d)
- [Requirements](#requirements)
- [Installation](#installation)
- [Documentation](#documentation)
- [Changelog](#changelog)
- [Quick start](#quick-start)
- [Features](#features)
- [Dialog lifecycle](#dialog-lifecycle)
- [Asynchronous model](#asynchronous-model)
- [Theming](#theming)
- [Telemetry](#telemetry)
- [Architecture](#architecture)
- [Repository layout](#repository-layout)
- [Demo applications](#demo-applications)
- [Screenshots](#screenshots)
- [Testing](#testing)
- [Adapting FMX.DialogService-style code](#adapting-fmxdialogservice-style-code)
- [Design decisions](#design-decisions)
- [Scope and limitations](#scope-and-limitations)
- [Versioning](#versioning)
- [License](#license)

---

## Quick overview

**Confirmation dialog**

```delphi
TDialog4D.MessageDialogAsync(
  'Do you want to delete this record? This action cannot be undone.',
  TMsgDlgType.mtConfirmation,
  [TMsgDlgBtn.mbYes, TMsgDlgBtn.mbNo],
  TMsgDlgBtn.mbNo,
  procedure(const AResult: TModalResult)
  begin
    if AResult = mrYes then
      DeleteRecord;
  end
);
```

**Custom buttons with semantic roles**

```delphi
TDialog4D.MessageDialogAsync(
  'You have unsaved changes.',
  TMsgDlgType.mtWarning,
  [
    TDialog4DCustomButton.Default('Save and Close', mrYes),
    TDialog4DCustomButton.Destructive('Close Without Saving', mrNo),
    TDialog4DCustomButton.Cancel('Review Changes')
  ],
  procedure(const AResult: TModalResult)
  begin
    case AResult of
      mrYes:    SaveAndClose;
      mrNo:     CloseWithoutSaving;
      mrCancel: ReturnToEditor;
    end;
  end,
  'Unsaved Changes'
);
```

**Worker-thread await**

```delphi
TTask.Run(
  procedure
  var
    LStatus: TDialog4DAwaitStatus;
    LResult: TModalResult;
  begin
    LResult := TDialog4DAwait.MessageDialogOnWorker(
      'The import is taking longer than expected. Continue?',
      TMsgDlgType.mtConfirmation,
      [TMsgDlgBtn.mbYes, TMsgDlgBtn.mbNo],
      TMsgDlgBtn.mbYes,
      LStatus,
      'Import', nil, True,
      30_000 // 30-second timeout
    );

    if (LStatus = dasCompleted) and (LResult = mrYes) then
      ContinueImport
    else
      CancelImport;
  end
);
```

---

## Design philosophy

Dialog4D is built on four principles:

**1. Asynchronous over modal.**  
Dialogs return immediately. The UI thread is never blocked, and the calling code never waits inline. This matches the FMX mobile model and keeps the control flow explicit.

**2. Decision over notification.**  
A dialog is a question the application asks the user, and the answer drives flow. Custom buttons, default-button highlighting, cancel detection, and structured telemetry exist so that the answer is unambiguous and the next step is explicit.

**3. Snapshot over ambient global state.**  
Theme values, text-provider reference, telemetry sink, callback, and button definitions are captured at request time. A dialog already queued behind another keeps the request configuration that existed when it was requested, even if the application changes global configuration afterward.

**4. Observable over opaque.**  
Seven lifecycle events flow through a telemetry sink: `ShowRequested`, `ShowDisplayed`, `CloseRequested`, `Closed`, `CallbackInvoked`, `CallbackSuppressed`, and `OwnerDestroying`. Every close carries a close reason and full timing data.

---

## Dialogs as decisions, not notifications

There is a common desktop-oriented synchronous pattern in Delphi code where a dialog is treated as a yes/no question that pauses the entire application:

```delphi
if MessageDlg('Save changes?', mtConfirmation, [mbYes, mbNo], 0) = mrYes then
  SaveDocument;
```

This reads naturally for desktop code. In multi-platform FMX applications, however, synchronous dialog flow can make some scenarios harder to reason about:

- it can block the main thread until the user answers;
- it may not match mobile interaction models as naturally as an asynchronous callback flow;
- queueing, structured telemetry, and programmatic close usually need to be handled by application code;
- form-destruction and worker-thread integration require careful coordination.

Dialog4D adopts a different shape. The result is delivered through a callback, not a synchronous return value. Multiple sequential decisions are written as chained callbacks. The flow is more explicit: the user decision is treated as an asynchronous event in the application lifecycle.

A second important difference is queueing. `FMX.DialogService` leaves request orchestration to application code. Dialog4D adds a per-form FIFO layer: when a second request is made for the same form, it waits and is dispatched only after the first dialog closes.

That is not a criticism of platform dialogs; it is a different shape for applications that want dialog requests to be explicit, queued, observable decision points. Over time, it helps clarify where a dialog is truly part of flow and where another UI pattern may be more appropriate.

---

## When to use Dialog4D

| Scenario | Recommended approach |
|---|---|
| FMX application that needs visual consistency across platforms | **Dialog4D** |
| Multi-step decision flow with sequential or branching dialogs | **Dialog4D** |
| Worker thread that needs to wait for a user decision | **Dialog4D** with `TDialog4DAwait` |
| Application that must dismiss a dialog programmatically | **Dialog4D** with `CloseDialog` |
| Application requiring custom buttons with domain language | **Dialog4D** with `TDialog4DCustomButton` |
| Logging, auditing, or observability of user decisions | **Dialog4D** telemetry |
| Existing callback-based `FMX.DialogService`-style code you want to adapt gradually | **Dialog4D** with `DialogService4D` facade |
| Native/platform-styled message box with no custom theme, queue, or telemetry requirement | `FMX.DialogService` |

Dialog4D shines when the dialog is part of the application's flow and visual identity, not just a transient OS message.

---

## Requirements

- **Delphi 11** or later
- **FireMonkey (FMX)** application
- No third-party dependencies beyond Delphi/FMX

---

## Installation

Add the `src` folder to your project's Search Path, then include the units you need.

For standard asynchronous dialogs:

```delphi
uses
  Dialog4D;
```

When needed:

```delphi
uses
  Dialog4D.Types,
  Dialog4D.Await;
```

---

## Documentation

Additional documentation is available in the `docs/` folder:

- [Architecture.md](docs/Architecture.md) — architecture notes and internal design overview
- [Guide_en.md](docs/Guide_en.md) — conceptual guide in English
- [Guide_pt-BR.md](docs/Guide_pt-BR.md) — conceptual guide in Brazilian Portuguese

This README remains the main entry point, while the `docs/` folder holds supporting material and deeper explanations.

---

## Changelog

Release history is maintained in [CHANGELOG.md](CHANGELOG.md).

Current release: **1.0.1 — 2026-05-01**.

---

## Quick start

### Information dialog

```delphi
TDialog4D.MessageDialogAsync(
  'Your file was saved successfully.',
  TMsgDlgType.mtInformation,
  [TMsgDlgBtn.mbOK],
  TMsgDlgBtn.mbOK,
  procedure(const AResult: TModalResult)
  begin
    // Executed on the main thread after the user closes the dialog
  end
);
```

### Programmatic close

```delphi
TDialog4D.CloseDialog(MainForm, mrCancel);
```

---

## Features

- Pure-FMX visual host
- Per-form FIFO queueing
- Await helper for worker threads
- Custom buttons with arbitrary captions and `TModalResult`
- Programmatic close with main-thread marshaling
- Request-time snapshots for theme, text provider, telemetry sink, callbacks, and buttons
- Structured telemetry with close-reason tracking
- Desktop keyboard handling and Android back-button support
- Safe suppression of callbacks during owner destruction

---

## Dialog lifecycle

At a high level, a request can emit these lifecycle events on the normal close path:

1. **ShowRequested** — the request enters the public API
2. **ShowDisplayed** — the visual host becomes visible
3. **CloseRequested** — a button, key, backdrop, or programmatic close triggers shutdown
4. **Closed** — the visual tree is disposed
5. **CallbackInvoked** or **CallbackSuppressed** — the close-callback pipeline either reaches the callback stage or is intentionally skipped

When the parent form begins destruction while a dialog is active, Dialog4D emits
**OwnerDestroying**. This event represents an owner-destruction path, not a
regular sixth step in the normal close sequence.

`CallbackInvoked` describes Dialog4D's close-callback pipeline. It should not be
interpreted as a guarantee that arbitrary downstream application code completed
successfully.

---

## Asynchronous model

Dialog4D is asynchronous on the UI thread by design. The main API never blocks.

If a worker thread must explicitly wait for a user decision, use `Dialog4D.Await`, which provides:

- smart overloads that adapt to thread context;
- worker-only blocking overloads;
- timeout support;
- optional callback re-dispatch to the main thread.

`MessageDialogOnWorker` is worker-thread only. It raises `EDialog4DAwait` when
called from the main thread, when no buttons are supplied, or when the internal
show path raises before the dialog can be completed.

Timeout does not close the visual dialog. It only ends the worker wait. When a
smart worker-side overload times out, the callback is not invoked.

When the smart `TDialog4DAwait.MessageDialog` overload is called from a worker
thread, its callback runs on the worker thread by default. Pass
`ACallbackOnMain = True` to re-dispatch that callback to the main thread.

This keeps the asynchronous model explicit and avoids hidden platform-specific behavior.

---

## Theming

Dialog4D theming is not only about "changing the color of a message box", but about integrating dialogs into the application's visual identity.

```delphi
var
  LTheme: TDialog4DTheme;
begin
  LTheme := TDialog4DTheme.Default;
  LTheme.SurfaceColor     := $FF1E1E2E;
  LTheme.TextTitleColor   := $FFCDD6F4;
  LTheme.TextMessageColor := $FF9399B2;
  LTheme.AccentInfoColor  := $FF89B4FA;
  LTheme.AccentErrorColor := $FFF38BA8;
  LTheme.OverlayOpacity   := 0.60;
  LTheme.MessageTextAlign := dtaLeading;

  TDialog4D.ConfigureTheme(LTheme);
end;
```

### Themed example — Cyberpunk style

```delphi
var
  LTheme: TDialog4DTheme;
begin
  LTheme := TDialog4DTheme.Default;

  LTheme.SurfaceColor     := $FF14101F;
  LTheme.TextTitleColor   := $FFFF5EA8;
  LTheme.TextMessageColor := $FFB8C7FF;

  LTheme.AccentInfoColor    := $FF00E5FF;
  LTheme.AccentWarningColor := $FFFFC857;
  LTheme.AccentErrorColor   := $FFFF4D6D;
  LTheme.AccentConfirmColor := $FF9D7CFF;
  LTheme.AccentNeutralColor := $FF2E294E;

  LTheme.ButtonNeutralFillColor   := $FF201A33;
  LTheme.ButtonNeutralTextColor   := $FFEAE6FF;
  LTheme.ButtonNeutralBorderColor := $FF5B4B8A;

  LTheme.OverlayOpacity   := 0.72;
  LTheme.MessageTextAlign := dtaLeading;

  TDialog4D.ConfigureTheme(LTheme);
end;
```

---

## Telemetry

Dialog4D telemetry is intended for real instrumentation: logging, diagnostics, demos, light auditing, and analysis of interaction flow. Telemetry is best-effort: exceptions raised by the telemetry sink are swallowed by the dialog pipeline so instrumentation cannot break dialog flow.

```delphi
uses
  Dialog4D,
  Dialog4D.Types,
  Dialog4D.Telemetry.Format;

TDialog4D.ConfigureTelemetry(
  procedure(const AData: TDialog4DTelemetry)
  begin
    TFile.AppendAllText(
      'dialog_events.log',
      TDialog4DTelemetryFormat.FormatTelemetry(AData) + sLineBreak
    );
  end
);
```

### Lifecycle events

| Event | Meaning |
|---|---|
| `tkShowRequested` | `MessageDialogAsync` was called and the request was registered |
| `tkShowDisplayed` | The overlay became visible and the opening animation finished |
| `tkCloseRequested` | A close request occurred (button, backdrop, key, etc.) |
| `tkClosed` | The visual tree was destroyed |
| `tkCallbackInvoked` | The Dialog4D close-callback pipeline reached the callback stage |
| `tkCallbackSuppressed` | The callback was intentionally skipped for safety |
| `tkOwnerDestroying` | The parent form began destruction while the dialog still existed |

---

## Architecture

At a unit level, the mechanism is split into clear responsibilities:

- `Dialog4D` — public API facade and per-form FIFO orchestration
- `Dialog4D.Types` — public contracts, theme, telemetry, custom buttons
- `Dialog4D.Host.FMX` — internal FMX visual host
- `Dialog4D.Await` — worker-thread await helper
- `Dialog4D.Internal.Queue` — shared `TThread.ForceQueue`-based main-thread queue helper
- `Dialog4D.TextProvider.Default` — built-in English provider
- `Dialog4D.Telemetry.Format` — optional formatter for telemetry records
- `DialogService4D` — migration-friendly adapter facade

---

## Repository layout

```text
Dialog4D/
├── .gitattributes
├── .gitignore
├── LICENSE
├── README.md
├── CHANGELOG.md
│
├── assets/
│   ├── banner.png
│   └── screenshots/
│       ├── default-confirmation.png
│       ├── default-error.png
│       ├── custom-buttons-destructive.png
│       ├── custom-buttons-stacked.png
│       ├── cyberpunk-theme.png
│       └── long-message-scroll.png
│
├── docs/
│   ├── Architecture.md
│   ├── Guide_en.md
│   └── Guide_pt-BR.md
│
├── examples/
│   └── BasicDemo/
│       ├── project/
│       │   ├── Dialog4D_Demo.dpr
│       │   └── Dialog4D_Demo.dproj
│       └── src/
│           ├── Dialog4D.BasicDemo.Main.pas
│           ├── Dialog4D.BasicDemo.Main.fmx
│           └── Dialog4D.BasicDemo.Workflow.pas
│
├── src/
│   ├── Dialog4D.pas
│   ├── Dialog4D.Await.pas
│   ├── Dialog4D.Host.FMX.pas
│   ├── Dialog4D.Internal.Queue.pas
│   ├── Dialog4D.Telemetry.Format.pas
│   ├── Dialog4D.TextProvider.Default.pas
│   ├── Dialog4D.Types.pas
│   └── DialogService4D.pas
│
└── tests/
    ├── project/
    │   ├── Dialog4D.Tests.dpr
    │   └── Dialog4D.Tests.dproj
    └── src/
        ├── Dialog4D.Tests.Await.Core.pas
        ├── Dialog4D.Tests.Facade.Core.pas
        ├── Dialog4D.Tests.Internal.Queue.pas
        ├── Dialog4D.Tests.Support.pas
        ├── Dialog4D.Tests.Telemetry.Format.pas
        ├── Dialog4D.Tests.TextProvider.Default.pas
        └── Dialog4D.Tests.Types.pas
```

---

## Demo applications

The `examples/BasicDemo/` folder contains a self-contained FMX application that demonstrates the public surface of Dialog4D.

It is organized into:

- `examples/BasicDemo/project/` — Delphi project files
- `examples/BasicDemo/src/` — demo form, workflow helper, and all example scenarios

The demo acts both as:

- a practical usage reference; and
- a manual validation surface for the visual host.

---

## Screenshots

Representative screenshots from the bundled demo are available in `assets/screenshots/`.

### Default confirmation

<p align="center">
  <img src="assets/screenshots/default-confirmation.png" width="480" alt="Default confirmation">
</p>

### Default error

<p align="center">
  <img src="assets/screenshots/default-error.png" width="480" alt="Default error">
</p>

### Custom buttons — destructive action

<p align="center">
  <img src="assets/screenshots/custom-buttons-destructive.png" width="480" alt="Custom buttons — destructive action">
</p>

### Custom buttons — stacked layout

<p align="center">
  <img src="assets/screenshots/custom-buttons-stacked.png" width="480" alt="Custom buttons — stacked layout">
</p>

### Cyberpunk theme

<p align="center">
  <img src="assets/screenshots/cyberpunk-theme.png" width="480" alt="Cyberpunk theme">
</p>

### Long message with scroll

<p align="center">
  <img src="assets/screenshots/long-message-scroll.png" width="480" alt="Long message with scroll">
</p>

---

## Testing

The automated suite currently contains **65 DUnitX tests** focused on deterministic contracts:

- default text-provider behavior;
- telemetry formatting, including quote escaping and single-line normalization;
- queue helper behavior, including asynchronous `ForceQueue` dispatch from the main thread;
- public value contracts and custom-button validation;
- facade-level validation for manually constructed invalid custom buttons;
- await guard behavior and timeout behavior without callback invocation.

Visual host integration is validated through the bundled demo rather than automated FMX rendering tests. To run the suite, open `tests/project/Dialog4D.Tests.dproj` in Delphi and execute the project.

---

## Adapting FMX.DialogService-style code

Dialog4D includes `DialogService4D`, a migration-friendly adapter facade over
`TDialog4D`.

It provides a familiar surface for common asynchronous `MessageDialog` usage,
but it is not intended to be a full behavioral clone of `FMX.DialogService` or
all of its overloads. `FMX.DialogService` remains the appropriate choice when
native/platform dialog behavior is desired.

### Step by step

For common callback-based `MessageDialog` calls:

1. Add `DialogService4D` to the `uses` clause.
2. Replace calls to `TDialogService.MessageDialog` with
   `TDialogService4D.MessageDialogAsync`.
3. Remove the positional `HelpCtx` argument (`Dialog4D` does not use it).
4. Review the callback logic and keep the flow asynchronous.
5. Optionally configure a theme and a text provider at application startup.

### Example

Before, using `FMX.DialogService`:

```delphi
TDialogService.MessageDialog(
  'Delete this item?',
  TMsgDlgType.mtConfirmation,
  [TMsgDlgBtn.mbYes, TMsgDlgBtn.mbNo],
  TMsgDlgBtn.mbNo,
  0,
  procedure(const AResult: TModalResult)
  begin
    if AResult = mrYes then
      DeleteItem;
  end
);
```

After, using `DialogService4D`:

```delphi
TDialogService4D.MessageDialogAsync(
  'Delete this item?',
  TMsgDlgType.mtConfirmation,
  [TMsgDlgBtn.mbYes, TMsgDlgBtn.mbNo],
  TMsgDlgBtn.mbNo,
  procedure(const AResult: TModalResult)
  begin
    if AResult = mrYes then
      DeleteItem;
  end
);
```

### Note on `PreferredMode`

`TDialogService.PreferredMode` (`Sync`, `Async`, or `Platform`) allows different
dialog behaviors depending on platform and rendering mode.

In `Platform` mode, desktop platforms may prefer synchronous behavior while
mobile platforms prefer asynchronous behavior. In addition, `Sync` is not
supported on Android. For that reason, mobile FMX applications benefit from
being written with an asynchronous dialog model in mind.

Dialog4D adopts a single approach across the supported FMX platform family:
dialogs are always asynchronous on the UI thread. This keeps the programming
model uniform across desktop and mobile and avoids code shapes that behave
differently depending on platform assumptions.

The bundled demo, section **9.1 — FMX.DialogService callback ordering
comparison**, exists to help visualize that difference in flow.

### Recommendation

`DialogService4D` is useful when adapting existing code that already follows a
callback-based `TDialogService.MessageDialog` style.

For new code, prefer calling `TDialog4D` directly. The facade exists for
source-level convenience, not as the preferred API for greenfield development.

---

## Design decisions

### Why per-form queueing instead of a global queue?

In multi-window applications, dialogs belonging to different forms are logically independent. A global queue would force the user to dismiss a dialog from Form A before seeing a dialog from Form B. Per-form queueing matches user expectations better: each window manages its own dialog sequence.

### Why does Dialog4D queue requests instead of relying on callback chaining?

Both `FMX.DialogService` and Dialog4D allow multi-step decision flows to be written by chaining dialog calls inside callbacks. For a single source of dialog requests, that may be enough.

The limitation appears when requests come from independent sources — a button click, a timer, a server response, or a worker thread reporting a result. `FMX.DialogService` leaves that orchestration to application code. Dialog4D adds a per-form FIFO layer, so the second request for the same form is dispatched only after the first one closes.

Callback chaining is a convention the developer maintains. Queueing is provided by the mechanism rather than rebuilt at each call site.

### Why is the theme captured at call time?

Because queued dialogs should preserve the request configuration that existed when they were requested. Theme values, text-provider reference, telemetry sink, callback, and button definitions are captured at request time, so later global changes do not alter dialogs already queued or visible.

### Why does the user callback execute after the visual tree is disposed of?

Because callbacks frequently start the next dialog, navigate to another screen, or destroy the parent form. Disposing of the visual tree first prevents callbacks from interacting with a half-destroyed dialog.

### Why is `MessageDialogOnWorker` forbidden on the main thread?

Because the main thread must never block waiting for a dialog it is itself responsible for rendering. A blocking call from the main thread would deadlock.

### Why is `Dialog4D.Internal.Queue` extracted as a separate unit?

Because the same "queue work onto the main thread" pattern is needed by the public facade, the await helper, and the visual host. A single internal owner keeps fixes centralized and dependencies explicit.

### Why no synchronous overload of `MessageDialogAsync`?

Because Dialog4D is intentionally built around a single asynchronous UI-thread model across the supported platform family. That keeps the API shape uniform and the flow explicit.

---

## Scope and limitations

This version of **Dialog4D** is focused on:

- asynchronous message dialogs with `TMsgDlgType` semantics;
- per-form FIFO queueing with snapshot-based isolation;
- worker-thread blocking await with timeout;
- custom buttons with arbitrary captions and modal results;
- programmatic close with main-thread marshaling;
- configurable theming, including a snapshot model and a default-button highlight;
- pluggable text providers for localization;
- structured telemetry with seven lifecycle events and close-reason tracking;
- form-destruction safety with callback suppression;
- an adapter facade for common callback-based `FMX.DialogService`-style calls.

At this stage, it is **not** intended to:

- provide input dialogs (text input, number input, date picker);
- offer wizard or multi-step modal flows as a built-in primitive;
- render native OS dialogs;
- support VCL;
- replace toast notifications, snack bars, or in-app banners.

The scope boundary is intentional. This first stage is deliberately focused on getting the asynchronous decision dialog right.

---

## Versioning

The project follows [Semantic Versioning](https://semver.org/).

See [CHANGELOG.md](CHANGELOG.md) for release history.

---

## License

MIT License — see [LICENSE](LICENSE).

Copyright (c) 2026 Eduardo P. Araujo
