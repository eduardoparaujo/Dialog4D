# From FMX Dialog Basics to Dialog4D

**Version:** 1.0.1 — 2026-05-01

### A conceptual journey through FMX dialogs, asynchronous flow, and explicit dialog coordination

---

If you have ever written Delphi FMX code that looked synchronous on desktop and
then needed a different continuation shape on mobile — dialogs that return
before the user answers, callbacks that carry the real result, or code paths
that must move inside a close handler — this text is for you.

Delphi already provides the dialog tools most FMX applications should start
with: `ShowMessage`, `MessageDlg`, and especially `FMX.DialogService`. Those
APIs are practical, officially supported, and appropriate for many scenarios.

This guide follows a natural path: start from simple FMX dialog calls, look at
how each layer behaves as application requirements grow, and only then
introduce the concepts that help when an application needs additional
coordination around dialogs.

By the end, the goal is for you to understand not only **how** to use dialogs in
Delphi FMX, but **why** each layer in the dialog story exists. As a practical
culmination, you will see **Dialog4D**, a complementary library that consolidates
these concerns into a small public API designed to make user decisions explicit,
observable, queue-aware, and visually consistent inside an FMX-rendered dialog
surface.

> **Scope note.** This guide walks through different ways of working with
> dialogs in FMX, from the APIs already available in Delphi to scenarios where
> the application needs more coordination around the decision flow. Dialog4D
> appears in this context as a complementary layer for FMX-rendered dialogs,
> with focus on theming, per-form queueing, configuration snapshots, telemetry,
> and worker-thread integration.

> **Note on prerequisites.** This guide focuses on dialogs in FMX. It assumes
> you are comfortable with anonymous methods (closures), `TThread.Queue` /
> main-thread marshaling, and basic threading vocabulary. If those concepts are
> new to you, the [SafeThread4D conceptual guide](https://github.com/eduardoparaujo/SafeThread4D/blob/main/docs/Guide_en.md)
> covers them in detail and is a natural companion to this text.

---

## Part 1 — Why dialogs need an explicit lifecycle

A dialog looks like a small, harmless thing. The user clicks a button, a window
appears asking "Save changes?", the user picks an answer, and the application
continues. Three lines of code, no big deal.

The trouble is that "the application continues" is not a single concept. It is
at least three different things:

1. **The application continues drawing the UI.** Animations keep playing,
   timers keep firing, incoming events keep arriving.
2. **The application continues the calling method.** The line right after the
   dialog call eventually executes.
3. **The application continues the user's flow.** The next decision, the next
   screen, or the next action depends on the answer.

In a traditional desktop-style modal flow, those three concepts can appear to be
the same thing: the dialog blocks the caller, the user answers, and execution
continues from the next line.

In cross-platform FMX code, especially when mobile targets are involved, that is
not a safe universal assumption. FMX has APIs whose behavior depends on the
platform, the selected presentation mode, and whether the call uses a callback
shape. The practical lesson is simple:

> **Do not treat a user decision as a synchronous function return unless the API
> and platform contract explicitly support that usage.**

Once you accept that, every other piece of dialog design becomes easier to
reason about.

---

## Part 2 — `ShowMessage`: the simplest dialog and the first mental model

The simplest dialog shape is a notification:

```delphi
uses
  FMX.Dialogs;

procedure TForm1.btSaveClick(Sender: TObject);
begin
  SaveDocument;
  ShowMessage('Document saved.');
  CloseDocument;
end;
```

You read this code top-to-bottom and may expect: save the document, show a
confirmation, then close the document.

For simple desktop-style notifications, this may be acceptable. But it is not a
good general pattern for cross-platform continuation logic. A notification does
not make a meaningful decision; it merely informs the user. If the code after
the notification depends on the user dismissing the message, the continuation is
already in the wrong place.

FMX's service-oriented dialog APIs make this platform sensitivity explicit. For
example, the official `TDialogService.ShowMessage` documentation describes
desktop behavior as synchronous and mobile behavior as asynchronous in the
platform-oriented mode. That means code that assumes "the line after the dialog
runs after the user closes it" is fragile when reused across different FMX
targets.

A safer mental model is:

> **A notification is not a continuation point.**  
> **If something must happen after the user dismisses a dialog, use an API shape
> that gives you an after-close callback.**

This mental shift prepares us for the next layer.

---

## Part 3 — `MessageDlg`: more buttons, same need for care

`MessageDlg` is the next step up. It lets you ask a question with multiple
buttons:

```delphi
uses
  FMX.Dialogs;

procedure TForm1.btCloseClick(Sender: TObject);
begin
  if MessageDlg('Save changes before closing?',
                TMsgDlgType.mtConfirmation,
                [TMsgDlgBtn.mbYes, TMsgDlgBtn.mbNo, TMsgDlgBtn.mbCancel],
                0) = mrYes then
    SaveDocument;

  CloseDocument;
end;
```

This shape is familiar to Delphi developers. It reads like a normal `if`
statement: if the user said yes, save; then close.

In modern FMX code, however, `MessageDlg` has important platform and overload
considerations. The official documentation marks `FMX.Dialogs.MessageDlg` as
deprecated and points developers toward async dialog-service APIs. It also
documents that blocking support varies by platform and that callback-based
calls are non-blocking on mobile platforms.

So the lesson is not "never use familiar dialog calls." The lesson is narrower
and more practical:

> **Return-value-based dialog flow is not the strongest foundation for
> cross-platform FMX decision logic.**

When the user's answer actually controls what happens next, a callback-based
shape is clearer and safer.

That is exactly what `FMX.DialogService` provides.

---

## Part 4 — `FMX.DialogService`: the recommended service-oriented path

`FMX.DialogService` is the official FMX dialog service family. It is the natural
place to go when you want a callback-based dialog shape in FMX:

```delphi
uses
  FMX.DialogService;

procedure TForm1.btCloseClick(Sender: TObject);
begin
  TDialogService.MessageDialog(
    'Save changes before closing?',
    TMsgDlgType.mtConfirmation,
    [TMsgDlgBtn.mbYes, TMsgDlgBtn.mbNo, TMsgDlgBtn.mbCancel],
    TMsgDlgBtn.mbNo,
    0,
    procedure(const AResult: TModalResult)
    begin
      if AResult = mrYes then
        SaveDocument;

      CloseDocument;
    end);
end;
```

The shape is different. The decision is no longer a return value tested in an
`if`; it is a parameter delivered to a callback that runs after the user has
closed the dialog. The continuation moved inside the callback, where the answer
is known.

This is a real improvement. For many applications, `FMX.DialogService` is the
right tool: it is built into FMX, it manages platform differences, and it fits
the standard FireMonkey dialog model.

The rest of this guide is not an argument against `FMX.DialogService`. It is an
exploration of what happens when an application needs extra structure around
dialogs: per-form queueing, request-time visual snapshots, custom per-call
button vocabulary, programmatic close, telemetry, or worker-thread wait
semantics.

### `PreferredMode`: bridging desktop and mobile expectations

`TDialogService` exposes `PreferredMode` with three values: `Platform`, `Async`,
and `Sync`.

In platform mode, desktop platforms prefer synchronous behavior and mobile
platforms prefer asynchronous behavior. `Sync` is not supported on Android.
This is an important design clue: if one codebase targets both desktop and
mobile, an asynchronous mental model is usually the safest common denominator.

Once you commit to the asynchronous shape, new design questions appear.

---

## Part 5 — Dialog as a flow router

Once you accept that dialog calls are asynchronous, you start to see them
differently. They are not merely questions; they are **branches in your
application flow**.

```delphi
procedure TForm1.PrepareToCloseDocument;
begin
  ValidateState;

  TDialogService.MessageDialog(
    'Save changes before closing?',
    TMsgDlgType.mtConfirmation,
    [TMsgDlgBtn.mbYes, TMsgDlgBtn.mbNo, TMsgDlgBtn.mbCancel],
    TMsgDlgBtn.mbYes,
    0,
    procedure(const AResult: TModalResult)
    begin
      case AResult of
        mrYes:    SaveAndClose;
        mrNo:     CloseWithoutSaving;
        mrCancel: ;  // user changed their mind
      end;
    end);
end;
```

The method validates state and asks a question. The continuation belongs to the
callback because the callback is where the answer is known.

This is a useful mental model:

> **A dialog call near the end of a method acts as a flow router.**  
> The method starts a decision, and the continuation flows through one of the
> callback branches.

This works well under one discipline: the dialog call should usually be the last
meaningful statement in the method. Code that depends on the user's answer
belongs inside the callback.

```delphi
procedure TForm1.PrepareToCloseDocument;
begin
  ValidateState;

  TDialogService.MessageDialog(
    'Save changes before closing?',
    ...
    procedure(const AResult: TModalResult)
    begin
      if AResult = mrYes then
        SaveDocument;
    end);

  CloseDocument;  // Not a cross-platform-safe continuation point.
end;
```

The rule is simple:

> **In FMX, treat the dialog callback as the continuation.**  
> Whatever needs to run after the user's decision belongs inside the callback.

---

## Part 6 — When the router meets concurrency: the queue problem

The "dialog as flow router" pattern works well when one source controls the
flow. Real applications often have multiple independent sources that may request
dialogs:

- a button click that asks for confirmation;
- a timer warning about session expiration;
- a server response that reports an error;
- a worker thread reporting an exceptional condition.

Each source can request a dialog at a different time. If the application wants
those dialogs to appear one at a time, in order, it needs a coordination policy.

`FMX.DialogService` does not expose a Dialog4D-style per-form FIFO queue in its
public API. That is not a flaw; it simply means that if an application needs
that specific serialization rule, the application needs to provide the
coordination.

The application-level coordination usually involves:

- tracking whether a dialog is already active;
- storing pending requests;
- dispatching the next request after the active one closes;
- avoiding races between close callbacks and new arrivals.

Dialog4D builds this specific policy into the mechanism:

> **For each parent form, Dialog4D serializes dialog requests through a FIFO
> queue.**

A request for the same form waits behind the active one. Requests for different
forms remain independent. This is useful when multiple sources can ask
questions in the same screen and the application wants one visible dialog at a
time for that form.

Section 5.1 of the bundled demo (`Queue burst`) shows this directly: it
dispatches six dialogs from a `TTask.Run` worker, and the Dialog4D queue
presents them one at a time.

---

## Part 7 — Sequential decisions and nested callbacks

Even within a single source of dialog requests, multi-step decisions raise their
own design challenge.

Consider a "Save before closing?" dialog where each answer leads to a different
path:

- "Yes" → save, then ask "Close now?"
- "No" → ask "Are you sure? Discarding cannot be undone."
- "Cancel" → return to the editor, no follow-up.

Written with callback-based dialogs, this naturally becomes nested callbacks:

```delphi
TDialogService.MessageDialog(
  'Save changes before closing?',
  TMsgDlgType.mtConfirmation,
  [TMsgDlgBtn.mbYes, TMsgDlgBtn.mbNo, TMsgDlgBtn.mbCancel],
  TMsgDlgBtn.mbYes,
  0,
  procedure(const R1: TModalResult)
  begin
    case R1 of
      mrYes:
        begin
          SaveDocument;
          TDialogService.MessageDialog(
            'Changes saved. Close now?',
            TMsgDlgType.mtInformation,
            [TMsgDlgBtn.mbOK, TMsgDlgBtn.mbCancel],
            TMsgDlgBtn.mbOK,
            0,
            procedure(const R2: TModalResult)
            begin
              if R2 = mrOk then
                CloseDocument;
            end);
        end;

      mrNo:
        TDialogService.MessageDialog(
          'Discard all changes?',
          TMsgDlgType.mtWarning,
          [TMsgDlgBtn.mbYes, TMsgDlgBtn.mbCancel],
          TMsgDlgBtn.mbCancel,
          0,
          procedure(const R2: TModalResult)
          begin
            if R2 = mrYes then
              CloseWithoutSaving;
          end);

      mrCancel:
        ;  // back to editor
    end;
  end);
```

Functionally, this is a valid shape. The user sees one question, then the next
question depends on the first answer.

The cost is readability. Each additional decision can add another level of
indentation. That is not a problem unique to any dialog API; it is the normal
price of callback-based asynchronous flow.

Dialog4D does not remove the asynchronous shape. It keeps the flow explicit, but
tries to make each dialog call carry more meaning by reducing ceremony and by
allowing domain-specific button captions.

---

## Part 8 — Buttons as vocabulary

Standard dialog buttons are intentionally small and generic: `OK`, `Cancel`,
`Yes`, `No`, `Abort`, `Retry`, `Ignore`, and so on. That vocabulary is perfect
for many dialogs.

Real applications sometimes need more specific action language. Consider this
confirmation:

> **Delete "Q4 2025 Report.xlsx"? This file will be permanently removed.**

The domain-specific actions are clearer than generic Yes/No:

- "Delete Permanently"
- "Keep File"

Dialog4D adds `TDialog4DCustomButton` for this case. Each custom button carries
a caption, a `TModalResult`, and visual role flags:

```delphi
TDialog4DCustomButton.Default     ('Save and Close',       mrYes);
TDialog4DCustomButton.Destructive ('Delete Permanently',   mrYes);
TDialog4DCustomButton.Make        ('Close Without Saving', mrNo);
TDialog4DCustomButton.Cancel      ('Keep File');
```

The convenience constructors represent four roles:

- **Default** — the primary action, rendered with the accent color and
  triggered by Enter on desktop.
- **Destructive** — a dangerous action, rendered with the error color.
- **Make** — a neutral action with explicit flags.
- **Cancel** — a cancel-like action, with `ModalResult = mrCancel`.

Custom buttons can also use application-defined modal results:

```delphi
const
  mrSaveAndClose = TModalResult(100);
  mrCloseNoSave  = TModalResult(101);
```

```delphi
case AResult of
  mrSaveAndClose: SaveAndClose;
  mrCloseNoSave:  CloseWithoutSaving;
  mrCancel:       ReturnToEditor;
end;
```

`mrNone` is reserved as Dialog4D's internal "no result" value and is rejected as
a custom-button result.

This is the conceptual shift:

> **The dialog is not only a Yes/No question.**  
> It can be a list of named actions, each with its own visual role.

---

## Part 9 — Capturing the right state: request-time snapshots

A subtle problem appears once dialogs become themeable and queueable.

Suppose your application has a dark theme and a light theme. It queues a dialog
while the dark theme is active, then the user changes the theme before the
dialog is actually displayed. Which theme should the queued dialog use?

Dialog4D answers that with request-time snapshots:

> **When `MessageDialogAsync` is called, Dialog4D captures the configuration
> needed by that request.**

The captured data includes:

- a value copy of `TDialog4DTheme`;
- the text-provider reference;
- the telemetry sink;
- the result callback;
- the button definitions, including a copied custom-button array.

Later calls to `ConfigureTheme` do not affect requests already in flight. A
queued dialog renders with the theme that was active when the request was made.

This is intentionally a snapshot of the request configuration. It is not a deep
clone of arbitrary objects behind provider or callback references. The theme is
copied by value, while provider/sink/callback values are captured as references
or procedure values.

Section 5.3 of the bundled demo (`Theme snapshot`) demonstrates the behavior by
switching themes between dialogs.

---

## Part 10 — Worker threads: waiting for a decision without blocking the UI

Most dialog flows start on the main thread and continue through a main-thread
callback. Some workflows are different.

Consider an import operation running on a worker thread:

```delphi
TTask.Run(
  procedure
  begin
    StartImport;
    ImportFirstBatch;

    if SomethingUnexpected then
    begin
      // Need to ask the user: continue or cancel?
      // But this code is running on a worker thread.
    end;

    ImportRemainingBatches;
  end);
```

The worker needs a decision before it can continue. A normal asynchronous dialog
call returns immediately, so the worker would keep running before the answer is
known.

Dialog4D provides `TDialog4DAwait.MessageDialogOnWorker` for this specific
shape:

```delphi
TTask.Run(
  procedure
  var
    LStatus: TDialog4DAwaitStatus;
    LResult: TModalResult;
  begin
    StartImport;
    ImportFirstBatch;

    if SomethingUnexpected then
    begin
      LResult := TDialog4DAwait.MessageDialogOnWorker(
        'The import found unexpected data. Continue?',
        TMsgDlgType.mtConfirmation,
        [TMsgDlgBtn.mbYes, TMsgDlgBtn.mbNo],
        TMsgDlgBtn.mbYes,
        LStatus,
        'Import', nil, True,
        30_000  // 30-second timeout
      );

      if (LStatus = dasTimedOut) or (LResult = mrNo) then
        Exit;  // cancel the import
    end;

    ImportRemainingBatches;
  end);
```

This gives the worker thread synchronous wait semantics while preserving the
normal asynchronous UI pipeline:

- the worker blocks waiting for a result or timeout;
- the main thread remains free to render and process the dialog;
- the visual dialog is created through the normal Dialog4D pipeline;
- timeout ends only the worker wait, not the visual dialog itself.

There are two important rules:

> **`MessageDialogOnWorker` cannot be called from the main thread.**  
> Dialog4D raises `EDialog4DAwait` immediately if you try.

Dialog4D also raises `EDialog4DAwait` when no buttons are supplied or when the
underlying show pipeline cannot present the dialog.

The reason is straightforward: the main thread is responsible for rendering and
processing the dialog. If it blocks waiting for the dialog result, the dialog
cannot complete.

> **Timeout governs the worker's patience, not the dialog's lifetime.**  
> When the timeout expires, the worker returns `dasTimedOut` with `mrNone`. The
> visual dialog may still remain on screen.

If the application wants to dismiss the still-visible dialog after a timeout, it
can request `TDialog4D.CloseDialog` separately.

The smart `TDialog4DAwait.MessageDialog` overload detects the calling thread:

- on the main thread, it delegates to `MessageDialogAsync`;
- on a worker thread, it delegates to `MessageDialogOnWorker`.

When called from a worker thread, the callback runs on the worker thread by
default. Pass `ACallbackOnMain = True` to redispatch the callback to the main
thread.

Section 8.1 of the bundled demo (`Worker await`) shows this pattern live, with
logging of the worker's blocked state and the moment it unblocks.

---

## Part 11 — Programmatic close, theming, and telemetry

Three more concerns often appear in applications where dialogs are part of the
flow.

### Programmatic close

Sometimes the application needs to dismiss a dialog without waiting for the user
to click a button. Examples:

- the operation that prompted the dialog is cancelled elsewhere;
- a server response makes the question obsolete;
- a worker thread times out and wants to clean up the visible dialog;
- navigation moves the user to another screen.

Dialog4D adds `TDialog4D.CloseDialog` for this case:

```delphi
TDialog4D.CloseDialog(MyForm, mrCancel);
```

This requests closure of the active Dialog4D dialog for the given form. The
actual visual close is marshalled to the main thread when needed. Telemetry
records the close as `crProgrammatic`.

### Theming as application identity

A dialog is not only a question; it is also a visual surface inside the
application. If dialogs are part of the application's visual identity, it can be
useful to render them through the same FMX styling model as the rest of the UI.

`TDialog4DTheme` is a value record with fields for geometry, overlay,
typography, accent palette, button visuals, and the default-button highlight
ring:

```delphi
var
  LTheme: TDialog4DTheme;
begin
  LTheme := TDialog4DTheme.Default;
  LTheme.SurfaceColor     := $FF1E1E2E;
  LTheme.AccentInfoColor  := $FF89B4FA;
  LTheme.OverlayOpacity   := 0.60;
  TDialog4D.ConfigureTheme(LTheme);
end;
```

Themes are captured at request time, so changing the theme between requests does
not affect dialogs already queued.

### Telemetry as observability

When something goes wrong in production, it can be useful to know how the dialog
flow behaved. Did the dialog appear? How long was it visible? Was it closed by a
button, backdrop, key, programmatic close, or form destruction?

Dialog4D emits lifecycle events through a configurable telemetry sink:

```delphi
TDialog4D.ConfigureTelemetry(
  procedure(const AData: TDialog4DTelemetry)
  begin
    TFile.AppendAllText(
      'dialog_events.log',
      TDialog4DTelemetryFormat.FormatTelemetry(AData) + sLineBreak);
  end);
```

The events cover: `tkShowRequested`, `tkShowDisplayed`, `tkCloseRequested`,
`tkClosed`, `tkCallbackInvoked`, `tkCallbackSuppressed`, and
`tkOwnerDestroying`.

Telemetry is best-effort. Exceptions raised inside the sink are swallowed by the
Dialog4D pipeline so instrumentation cannot break dialog flow.

Telemetry records the Dialog4D lifecycle. It should not be treated as proof that
a domain operation launched by an application callback completed successfully;
domain success/failure belongs to application logic.

---

## Part 12 — Dialog4D: the concepts in a cohesive package

Putting the pieces together, Dialog4D consolidates the patterns discussed in
this guide into one FMX-rendered dialog library.

### What each piece solves

| Concept | What it solves |
|---|---|
| `MessageDialogAsync` | Asynchronous dialogs with a result callback on the main-thread UI path |
| Per-form FIFO queue | Dialog requests for the same form are serialized automatically |
| Request-time snapshot | Theme values and request configuration remain stable while queued |
| `TDialog4DCustomButton` | Buttons with domain-language captions and visual roles |
| `TDialog4DAwait.MessageDialogOnWorker` | Worker threads can wait for a user decision without blocking the UI |
| `TDialog4D.CloseDialog` | Programmatic close request for the active Dialog4D dialog |
| `TDialog4DTheme` | Configurable FMX-rendered dialog theming |
| `IDialog4DTextProvider` | Pluggable text provider for localization |
| `TDialog4D.ConfigureTelemetry` | Lifecycle observability with close reason, button context, and timing |
| `DialogService4D` | Adapter for common `FMX.DialogService`-style callback code |

### A complete example bringing the parts together

Returning to the close-document scenario from Part 1, written with Dialog4D:

```delphi
uses
  Dialog4D,
  Dialog4D.Types;

procedure TForm1.btCloseClick(Sender: TObject);
begin
  TDialog4D.MessageDialogAsync(
    'You have unsaved changes.',
    TMsgDlgType.mtWarning,
    [
      TDialog4DCustomButton.Default     ('Save and Close',       mrYes),
      TDialog4DCustomButton.Destructive ('Close Without Saving', mrNo),
      TDialog4DCustomButton.Cancel      ('Review Changes')
    ],
    procedure(const R1: TModalResult)
    begin
      case R1 of
        mrYes:
          begin
            SaveDocument;
            TDialog4D.MessageDialogAsync(
              'Document saved. Close now?',
              TMsgDlgType.mtInformation,
              [
                TDialog4DCustomButton.Default ('Close Document', mrOk),
                TDialog4DCustomButton.Cancel  ('Keep Open')
              ],
              procedure(const R2: TModalResult)
              begin
                if R2 = mrOk then
                  CloseDocument;
              end,
              'Save Completed');
          end;

        mrNo:
          DiscardAndClose;

        mrCancel:
          ReturnToEditor;
      end;
    end,
    'Unsaved Changes');
end;
```

This code:

- uses one asynchronous Dialog4D API shape across the supported FMX platforms;
- keeps the main thread unblocked;
- speaks domain language in the button captions;
- makes the continuation explicit in callbacks;
- queues automatically if another Dialog4D request is already active for the
  same form;
- captures the active theme at request time;
- emits lifecycle telemetry that an application can log for observability.

### A note on intent

Dialog4D was built to make certain FMX dialog concerns easier to handle when
they appear together: queueing, request snapshots, custom buttons, programmatic
close, theming, telemetry, and worker-thread wait semantics.

For a simple OS/platform-styled message, `FMX.DialogService` remains a good
choice. For applications where dialogs are part of the visual identity and the
application flow, Dialog4D provides those coordination patterns in one place.

The result is a small public surface — configuration calls,
`MessageDialogAsync`, `CloseDialog`, and the await family — with explicit
lifecycle decisions underneath:

- asynchronous dialog flow on the UI thread;
- per-form FIFO queueing;
- request-time snapshots;
- custom buttons with visual roles;
- worker-thread await with timeout;
- programmatic close with main-thread marshaling;
- configurable theming;
- pluggable text provider;
- structured telemetry;
- form-destruction safety with callback suppression;
- and an adapter for common `FMX.DialogService`-style callback code.

---

## Recommended reading

For readers who want to go deeper into FMX dialogs and asynchronous patterns in
Delphi, these references are useful:

- **[Embarcadero DocWiki — `TDialogService.MessageDialog`](https://docwiki.embarcadero.com/Libraries/Florence/en/FMX.DialogService.TDialogService.MessageDialog)** — the official FMX dialog service reference, including synchronous/asynchronous behavior according to `PreferredMode` and platform.
- **[Embarcadero DocWiki — `TDialogService.TPreferredMode`](https://docwiki.embarcadero.com/Libraries/Florence/en/FMX.DialogService.TDialogService.TPreferredMode)** — the official description of `Platform`, `Async`, and `Sync` modes.
- **[Embarcadero DocWiki — `FMX.Dialogs.MessageDlg`](https://docwiki.embarcadero.com/Libraries/Athens/en/FMX.Dialogs.MessageDlg)** — notes on legacy `MessageDlg`, callbacks, blocking behavior, and Android support.
- **[Marco Cantù — *Object Pascal Handbook*](https://www.embarcadero.com/products/delphi/object-pascal-handbook)** — a book/eBook on modern Object Pascal, including anonymous methods.
- The companion **[SafeThread4D conceptual guide](https://github.com/eduardoparaujo/SafeThread4D/blob/main/docs/Guide_en.md)** — for a deeper treatment of threading, `Synchronize`, `Queue`, and worker-thread coordination patterns referenced throughout this guide.

---

## Epilogue — Next steps

If you have made it this far, you have a solid conceptual foundation in FMX
dialogs. You know why each layer in the dialog story exists, from a simple
notification to a queue-aware and observable dialog mechanism.

Natural next steps:

1. **Clone Dialog4D** and run the bundled demo. Each of the ten sections in the
   demo corresponds to a concept covered in this guide.
2. **Read the [project README](../README.md)** for the API surface and usage
   examples.
3. **Read [`Architecture.md`](Architecture.md)** if you want to understand the
   mechanism from the inside — the registry, the visual host, the close
   pipeline, form-destruction handling, and await layer.
4. **Read the source code** calmly. The library is not large, and the pieces map
   directly onto the concepts in this guide.

If you find yourself repeatedly coordinating dialog queues, preserving visual
configuration across queued requests, or adding observability around dialog
decisions, Dialog4D may be a useful layer to evaluate.

---

*This text is an introductory conceptual guide. For practical usage and
mechanism details, consult the [README.md](../README.md), the architecture notes
in [`Architecture.md`](Architecture.md), and the project examples.*
