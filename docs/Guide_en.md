# From `ShowMessage` to Dialog4D

### A journey through FMX dialogs, from the real problem to a mechanism that addresses it

---

If you have ever written something in Delphi FMX that looked synchronous, ran fine on Windows, and then behaved differently when the same code shipped to iOS or Android — dialogs that did not block, results that arrived earlier than expected, code paths that ran before the user answered — this text is for you.

Delphi already provides the dialog tools most FMX applications should start with: `ShowMessage`, `MessageDlg`, and especially `FMX.DialogService`. Those APIs are practical, officially supported, and entirely appropriate for many scenarios.

This guide follows a natural path: start from the simplest FMX dialog (`ShowMessage`), look at how each layer behaves as application requirements grow, and only then introduce the concepts that help address those requirements when the basic tools are no longer enough.

By the end, the goal is for you to understand not only **how** to use dialogs in Delphi FMX, but **why** each layer in the dialog story exists. As a practical culmination, you will see **Dialog4D**, a complementary mechanism that consolidates these decisions into an API that is small on the surface but designed to make user decisions explicit, predictable, and visually consistent across desktop and mobile.

> **A note on positioning.** Dialog4D does not replace the dialog mechanisms that ship with Delphi. `ShowMessage`, `MessageDlg`, and `FMX.DialogService` remain valid choices for many scenarios and are the natural starting point for FMX applications. Dialog4D is a complementary layer for applications where dialogs become part of the visual identity and the application flow. The intent of this guide is not to argue that the standard mechanisms are wrong, but to walk through the FMX dialog design space and show where a dedicated mechanism becomes useful.

> **Note on prerequisites.** This guide focuses on dialogs in FMX. It assumes you are comfortable with anonymous methods (closures), `TThread.Queue` for marshaling work to the main thread, and basic threading vocabulary. If those concepts are new to you, the [SafeThread4D conceptual guide](https://github.com/eduardoparaujo/SafeThread4D/blob/main/docs/Guide_en.md) covers them in detail and is the natural companion to this text.

---

## Part 1 — Why dialogs need an explicit lifecycle

A dialog looks like a small, harmless thing. The user clicks a button, a window appears asking "Save changes?", the user picks an answer, and the application continues. Three lines of code, no big deal.

The trouble is that "the application continues" is not a single concept. It is at least three different things:

1. **The application continues drawing the UI.** Animations keep playing, timers keep firing, incoming events keep arriving.
2. **The application continues the calling method.** The line right after the dialog call eventually executes.
3. **The application continues the user's flow.** The next decision, the next screen, the next question depends on the answer.

In a desktop application running on Windows, all three can sometimes look like the same thing: the dialog blocks everything, the user answers, and execution resumes from the line right after the call. The illusion that "the application stopped, then continued" is workable.

That illusion does not survive contact with FMX mobile. On iOS and Android, the operating system does not allow the application to block the main thread waiting for a user decision. The UI must keep rendering, animating, and responding to system events while the dialog is visible. The platform forces a different shape: **the call to show a dialog returns immediately, and the answer arrives later through a callback.**

This is not a quirk of FMX. It is the platform model on every modern mobile operating system. Once you accept it, every other piece of dialog design starts to make sense.

---

## Part 2 — `ShowMessage`: the simplest dialog, and its first mismatch

The most basic FMX dialog is `ShowMessage` from `FMX.Dialogs`:

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

You read this code top-to-bottom and you expect: save the document, show a confirmation, close the document.

On Windows, this is what happens. The dialog appears, the application waits for the user to dismiss it, and then `CloseDocument` runs.

On iOS and Android, this is **not** what happens. `ShowMessage` returns immediately. The dialog appears on the screen, but `CloseDocument` runs **before** the user has dismissed it. By the time the user taps "OK", the document is already closed.

The reason is exactly what we discussed in Part 1: the mobile platform does not allow the main thread to block waiting for user input. `ShowMessage` is a thin wrapper that, on mobile, returns immediately to keep the UI responsive. The visible dialog is just a side effect — the synchronous-looking call is an illusion.

This is the first important cross-platform mismatch of FMX dialogs:

> **`ShowMessage` looks synchronous, but it is only synchronous on Windows.**  
> **On mobile, the line after the call runs before the user has answered.**

If your code only runs on Windows, you can use `ShowMessage` for simple notifications and the assumption holds. As soon as the same code is built for iOS or Android, the assumption silently breaks. The bug is hard to find because the code looks correct.

A safer mental model is to assume from the start that **a dialog is never a synchronous interruption** — it is a notification that runs in parallel with the rest of your code. With this assumption, you would not write `CloseDocument` after `ShowMessage`. You would either run `CloseDocument` first and then notify, or use a dialog API that gives you a callback for "after the user answered".

---

## Part 3 — `MessageDlg`: the same cross-platform trap, with more buttons

`MessageDlg` is the next step up. It is also in `FMX.Dialogs`, and it lets you show a dialog with multiple buttons and ask the user a question:

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

This pattern is everywhere in legacy Delphi code. It reads like a normal `if` statement: "if the user said yes, save; then close". The return value of `MessageDlg` is the modal result, and the code branches on it.

On Windows, this works as it reads. On iOS, the legacy blocking overload can still behave synchronously. On Android, however, that blocking shape is not supported. If you move to a callback-based overload, the continuation is no longer the return value: on mobile, code placed after the call can execute before the user's decision is delivered.

The important lesson is not that every `MessageDlg` overload always returns immediately. The lesson is that `MessageDlg` has platform- and overload-dependent behavior, which makes return-value-based decision flow a weak foundation for cross-platform FMX code.

In FMX, `MessageDlg`'s return value should not be treated as the main cross-platform decision point. The legacy function remains familiar to Delphi developers, but when the answer actually matters across desktop and mobile, a callback-based shape is safer and easier to reason about.

This is exactly what `FMX.DialogService` provides.

---

## Part 4 — `FMX.DialogService`: the recommended path

`FMX.DialogService` is the official FMX dialog service, and it is the API family Embarcadero points developers to when moving away from legacy `FMX.Dialogs` dialog calls. It exposes the same `MessageDialog` family of calls, but the answer is delivered through an anonymous callback instead of being handled as a cross-platform return-value decision point:

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

The shape is different. The decision is no longer a return value tested in an `if` — it is a parameter delivered to a callback that runs **after** the user has answered. The `CloseDocument` call moved inside the callback, where it belongs: after the answer is known.

This is a real improvement. The continuation is explicit: code that depends on the user's answer lives inside the close callback. Depending on `PreferredMode`, the call itself may be synchronous on desktop or asynchronous on mobile, but the decision point is consistent: the callback is invoked after the user closes the dialog. For most simple cases, `FMX.DialogService` is the correct choice and there is no reason to look further. The rest of this guide is **not** an argument that `FMX.DialogService` should be avoided — it is an exploration of the FMX dialog design space, showing where additional concerns appear and how they can be addressed when they do.

### `PreferredMode`: a partial bridge between desktop and mobile expectations

`FMX.DialogService` offers a setting called `PreferredMode` that controls how dialogs render:

```delphi
TDialogService.PreferredMode := TDialogService.TPreferredMode.Sync;
```

The values are `Sync`, `Async`, and `Platform`.

In practice, `Platform` behaves differently depending on the platform family: desktop platforms prefer synchronous dialog behavior, while mobile platforms use asynchronous behavior. In addition, `Sync` is not supported on Android. That means desktop code can still be written in a more synchronous style, while mobile code must still be treated as asynchronous.

For that reason, if the same FMX codebase is expected to behave consistently across desktop and mobile, it is safer to adopt an asynchronous mental model from the start.

This is the realization that motivates the rest of this guide: **once you commit to the asynchronous shape, new design questions appear**.

---

## Part 5 — Dialog as a flow router

Once you accept that dialog calls are asynchronous, you start to see them differently. They are not "questions you ask"; they are **branches in your application's flow**.

Look at this code:

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

The method `PrepareToCloseDocument` does two things visually: it validates state, and then it asks a question. But the cross-platform behavior should be understood differently. The lines that decide what happens next — `SaveAndClose`, `CloseWithoutSaving`, or doing nothing — live inside the callback. On mobile, the method can return before the user answers; on desktop, depending on the preferred mode, it may wait. The important point is that the continuation belongs to the callback because the callback is the cross-platform-safe place where the answer is known.

This is a useful mental model:

> **A dialog call near the end of a method acts as a flow router.**  
> The original method ends; the rest of the application flow continues through one of the callback branches.

This works well, but only under one condition: the dialog call must be treated as **the last meaningful thing the method does**. If you write code after the dialog call, that code is not a cross-platform-safe continuation point; on mobile or in asynchronous mode, it can run before the user has answered.

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

  CloseDocument;  // ← BUG on mobile/async mode: may run before the user answers.
end;
```

This is the same cross-platform problem from Parts 2 and 3, but expressed in a more subtle form. Even when the dialog API provides the correct callback, the developer can still write synchronous-looking code around it and produce a cross-platform bug.

There is a discipline that emerges from this:

> **In FMX, treat every dialog call as the end of the method.**  
> **Whatever needs to run after the user's decision belongs inside the callback.**

If you internalize this rule, you start to write methods where the dialog call is naturally the last statement, and the callback contains the continuation. This is the shape that scales — the next part shows why.

---

## Part 6 — When the router meets concurrency: the queue problem

The "dialog as flow router" pattern works perfectly when **you** are the only one routing. The method that opens the dialog is also the method that decides what happens next. There is one source of dialog requests, and it is the call you just made.

Real applications are rarely that simple.

Consider a screen with three independent sources of dialog requests:

- a button the user clicks to confirm an action;
- a timer that fires every minute and warns about session expiration;
- an HTTP response handler that displays a server error when an API call fails.

Each one of these can request a dialog **at any moment**. The user can click the confirmation button while the session-expiration warning is about to fire, while a server error is arriving in the background. None of the three sources knows about the other two.

With `FMX.DialogService`, what happens?

```delphi
// Source 1: button click
TDialogService.MessageDialog(
  'Confirm purchase?',
  TMsgDlgType.mtConfirmation,
  [TMsgDlgBtn.mbYes, TMsgDlgBtn.mbNo],
  TMsgDlgBtn.mbYes,
  0,
  procedure(const R: TModalResult) begin ... end);

// Source 2: timer (runs at the same time)
TDialogService.MessageDialog(
  'Your session expires in 2 minutes.',
  TMsgDlgType.mtWarning,
  [TMsgDlgBtn.mbOK],
  TMsgDlgBtn.mbOK,
  0,
  procedure(const R: TModalResult) begin ... end);

// Source 3: server error (also runs at the same time)
TDialogService.MessageDialog(
  'Network request failed.',
  TMsgDlgType.mtError,
  [TMsgDlgBtn.mbRetry, TMsgDlgBtn.mbCancel],
  TMsgDlgBtn.mbRetry,
  0,
  procedure(const R: TModalResult) begin ... end);
```

Three independent dialog requests can arrive at nearly the same time. `FMX.DialogService` does not expose a documented per-form FIFO serialization mechanism, so the application must coordinate overlapping requests if it wants them to behave sequentially and predictably.

The naive fix is to make sure the application never requests two dialogs concurrently. But this is a discipline, not a guarantee. To enforce it, the developer would have to:

- track which dialogs are visible at any given moment;
- queue new requests manually when a dialog is already open;
- dispatch the queued requests when the active dialog closes;
- handle race conditions between the close callback and new arrivals.

In other words, the developer would have to reimplement a queue, by hand, every time. And get it right every time. And remember to wire it up across every source of dialog requests in the application.

This is exactly the kind of structural concern that does not belong in application code:

> **With `FMX.DialogService`, sequential dialog flow is a convention.**  
> **The application code must coordinate overlapping requests explicitly.**

Dialog4D approaches this differently. The framework has a per-form FIFO queue built into the mechanism. Every dialog request for the same form is automatically serialized: the second request waits in the queue until the first closes, the third waits for the second, and so on. The developer does not coordinate anything — the framework does.

> **With Dialog4D, sequential dialog flow is a guarantee of the mechanism.**

This is a different kind of correctness. The application code does not have to be defensive about concurrent dialog requests. The queue is a property of the system, not a discipline of the programmer.

Section 5.1 of the bundled demo (`Queue Demo`) shows this directly: it dispatches six dialogs in a tight loop from a `TTask.Run` worker, and the framework queues them automatically. The user sees one dialog at a time, in arrival order, with no overlap and no lost requests.

---

## Part 7 — Sequential decisions and the depth of nested callbacks

Even within a single source of dialog requests, multi-step decisions raise their own design challenge.

Consider a "Save before closing?" dialog where each answer leads to a follow-up question:

- "Yes" → save, then ask "Close now?"
- "No" → ask "Are you sure? Discarding cannot be undone."
- "Cancel" → return to the editor, no follow-up.

Written with `FMX.DialogService`, this becomes:

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

Functionally, this works. The user sees one dialog at a time, the answers are processed correctly, and the flow ends in the right place.

Visually, the indentation grows. Each branch that adds a follow-up dialog adds a level of nesting. A three-step decision is already pushing the right edge of the editor. A four-step decision becomes hard to read, and changes to one branch require careful navigation to make sure you are editing the right closure.

This is a well-known shape — it is the same "callback hell" that JavaScript faced before promises and async/await. In Delphi FMX, there is no built-in async/await for dialogs, so the indentation is the price of correctness.

Dialog4D does not eliminate the nesting — it cannot, because the asynchronous shape is fundamental. But it makes the nested code shorter and clearer in two ways:

**1. Less ceremony per call.** The `0` parameter for `HelpCtx` is gone, the type prefixes are shorter, the default-button parameter integrates with the snapshot model.

**2. Custom buttons replace generic Yes/No semantics.** Instead of `mbYes`/`mbNo` and a comment explaining what each one means, the buttons carry their own captions and roles:

```delphi
TDialog4D.MessageDialogAsync(
  'You have unsaved changes.',
  TMsgDlgType.mtWarning,
  [
    TDialog4DCustomButton.Default('Save and Close', mrYes),
    TDialog4DCustomButton.Destructive('Close Without Saving', mrNo),
    TDialog4DCustomButton.Cancel('Review Changes')
  ],
  procedure(const R1: TModalResult)
  begin
    case R1 of
      mrYes:    SaveAndClose;
      mrNo:     CloseWithoutSaving;
      mrCancel: ReturnToEditor;
    end;
  end,
  'Unsaved Changes');
```

The dialog now speaks in domain language. A reviewer reading the code sees "Save and Close", "Close Without Saving", "Review Changes" — three actions with clear meaning. The next part is dedicated to this concept.

---

## Part 8 — Buttons as vocabulary

In a classic dialog API, the buttons are an enum: `mbOK`, `mbCancel`, `mbYes`, `mbNo`, `mbAbort`, `mbRetry`, `mbIgnore`, `mbAll`, `mbNoToAll`, `mbYesToAll`, `mbHelp`, `mbClose`. The text on each button comes from a text provider — by default, the English captions "OK", "Cancel", "Yes", "No", and so on.

This works for simple confirmation dialogs. "Are you sure you want to delete?" → Yes / No. The semantics are universal enough that "Yes" and "No" mean the same thing in every context.

Real applications often need more specific language. Consider this confirmation:

> **Delete "Q4 2025 Report.xlsx"? This file will be permanently removed.**

What should the buttons say? The standard options are unsatisfying:

- "Yes" / "No" — too vague. What does "Yes" mean? Yes, delete? Yes, keep?
- "OK" / "Cancel" — also vague. Cancel what?
- "Abort" / "Retry" / "Ignore" — wrong vocabulary entirely.

The buttons that match the question are:

- "Delete Permanently"
- "Keep File"

These captions are not in any standard enum. They are domain-specific. They are clearer than any combination of the default options, because they are written in the language of the action.

`FMX.DialogService` does not provide first-class support for per-call custom button captions. Dialog4D introduces `TDialog4DCustomButton`, a record that carries a caption, a `TModalResult`, and two visual flags:

```delphi
TDialog4DCustomButton.Default     ('Save and Close',       mrYes);
TDialog4DCustomButton.Destructive ('Delete Permanently',   mrYes);
TDialog4DCustomButton.Make        ('Close Without Saving', mrNo);
TDialog4DCustomButton.Cancel      ('Keep File');
```

Four convenience constructors map to four visual roles:

- **Default** — the primary action, rendered with the accent color and triggered by Enter on desktop.
- **Destructive** — a dangerous action, rendered with the error color (typically red).
- **Make** — a neutral action with explicit flags.
- **Cancel** — a cancel-like action, with `ModalResult` always set to `mrCancel`.

The captions are passed as strings, with no enum in the middle. The application chooses what the buttons say in the language of the domain. The `TModalResult` is an integer that the callback uses to identify the answer.

There is also a useful side effect: the buttons can carry **application-defined** modal results, not just standard ones:

```delphi
const
  mrSaveAndClose = TModalResult(100);
  mrCloseNoSave  = TModalResult(101);
```

And the callback can switch on the application's own vocabulary:

```delphi
case AResult of
  mrSaveAndClose: SaveAndClose;
  mrCloseNoSave:  CloseWithoutSaving;
  mrCancel:       ReturnToEditor;
end;
```

This is a small change in shape with a meaningful consequence:

> **The dialog is no longer a generic Yes/No question.**  
> **It is a list of named actions, each with its own visual role.**

Section 10.3 of the bundled demo (`Custom buttons — all four visual roles`) shows this pattern with all four constructors visible at once.

---

## Part 9 — Capturing the right state: snapshot at call time

A subtle problem appears once you start using themes and customization at the dialog level.

Suppose your application has two themes: a light theme for daytime use and a dark theme for nighttime. The user can switch between them at any time. The application has the following code:

```delphi
ApplyDarkTheme;

// Step 1: ask the user to confirm
TDialog4D.MessageDialogAsync(
  'Save before closing?',
  ...,
  procedure(const R1: TModalResult)
  begin
    if R1 = mrYes then
    begin
      ApplyLightTheme;  // theme switch between dialogs

      // Step 2: confirm save success
      TDialog4D.MessageDialogAsync(
        'Saved successfully.',
        ...,
        procedure(const R2: TModalResult)
        begin
          ...
        end);
    end;
  end);
```

The first dialog should render in the dark theme. The second should render in the light theme. The user-visible behavior should match the theme that was active at the moment each dialog was requested.

But what happens if there is queueing pressure? What if another dialog from a different source is already on screen, and Step 1 enters the queue and waits? When Step 1 finally renders, what theme should it use — the theme that was active when the request was made, or the current global theme?

This is not a hypothetical. It happens any time the application:

- changes the theme in response to user preferences;
- changes the theme based on time of day;
- changes the text provider for localization;
- changes the telemetry sink for testing.

If the dialog uses the **current** global state at render time, it can use a theme the developer never intended for that specific dialog. The user sees Step 1 rendered in the light theme even though the dark theme was active when the question was asked. The visual flow is incoherent.

Dialog4D solves this with a **snapshot at call time**:

> **When `MessageDialogAsync` is called, the framework captures a copy of the current `FTheme` and a reference to the current `FTextProvider` into the request itself.**  
> **The dialog renders with the configuration that was active at the moment of the call, regardless of what happens to the global state afterward.**

The snapshot is a value copy. Subsequent calls to `ConfigureTheme` do not affect requests already in flight. A multi-step decision flow that switches theme between steps will render each step with the theme that was active when that step was requested.

This is what makes Dialog4D safe for applications that change global configuration at runtime. The developer does not have to worry about timing — the framework guarantees the visual identity each request was supposed to have.

Section 5.3 of the bundled demo (`Theme snapshot during queue`) demonstrates this directly: it shows a dialog with the default theme, switches to the cyberpunk theme between dialogs, and the second dialog renders correctly with the new theme without affecting the first.

---

## Part 10 — Worker threads: waiting for a decision without blocking the UI

Up to this point, the dialog model has been: the main thread asks a question, the user answers, the callback runs on the main thread. This covers most cases.

Some cases are different. Consider an import operation running on a worker thread:

```delphi
TTask.Run(
  procedure
  begin
    StartImport;
    ImportFirstBatch;

    if SomethingUnexpected then
    begin
      // Need to ask the user: continue or cancel?
      // But we are on a worker thread.
    end;

    ImportRemainingBatches;
  end);
```

The worker thread needs to ask the user a question and wait for the answer before deciding what to do next. The decision affects the worker's flow, not the UI's flow.

The naive approach — call `TDialog4D.MessageDialogAsync` from the worker — does not work, because `MessageDialogAsync` returns immediately. The worker would continue executing without waiting for the user's answer. The callback would arrive later, on the main thread, with no way to feed it back into the worker's logic.

The right shape is: the worker **blocks** until the user has answered. The main thread renders the dialog normally and stays responsive. When the user answers, the worker unblocks with the result.

Dialog4D provides `TDialog4DAwait.MessageDialogOnWorker` for exactly this:

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

The worker blocks on the await call. The main thread continues rendering normally. The dialog appears, the user answers, and the worker unblocks with the result.

There is one important rule:

> **`MessageDialogOnWorker` cannot be called from the main thread.**  
> **The framework raises `EDialog4DAwait` immediately if you try.**

The reason is simple: the main thread is the one that should render the dialog. If the main thread is parked waiting for the dialog to close, nothing can render it, and the application deadlocks. The library refuses to enter that state.

A second rule about the timeout:

> **The timeout governs the worker's patience, not the dialog's lifetime.**  
> **When the timeout expires, the worker stops waiting and returns `dasTimedOut`. The dialog stays on screen until the user dismisses it manually.**

If you want to dismiss the dialog after a worker timeout, you can call `TDialog4D.CloseDialog` from the same worker — the next part covers this.

The smart `MessageDialog` overload (without `OnWorker`) detects the calling thread and adapts: on the main thread it delegates to `MessageDialogAsync` (non-blocking), on a worker thread it delegates to `MessageDialogOnWorker` (blocking). This lets shared code call `MessageDialog` regardless of thread context, but it is best used when the calling thread is genuinely uncertain — when you know which thread you are on, the explicit calls are clearer.

Section 8.1 of the bundled demo (`MessageDialogOnWorker — blocking`) shows this pattern live, with logging of the worker's blocked state and the moment it unblocks.

---

## Part 11 — Closing programmatically, theming, and telemetry

Three more concerns appear in real applications, and Dialog4D addresses each one:

### Closing the active dialog programmatically

Sometimes the application needs to dismiss a dialog without the user clicking a button. Examples:

- the operation that prompted the dialog is cancelled by another part of the application;
- a server response makes the question obsolete;
- a worker thread times out and wants to clean up the visible dialog;
- the navigation flow moves to another screen.

`FMX.DialogService` does not provide a built-in way to close the active dialog programmatically. The dialog stays visible until the user dismisses it, even if the question is no longer relevant.

Dialog4D provides `TDialog4D.CloseDialog`:

```delphi
// Thread-safe — can be called from any thread
TDialog4D.CloseDialog(MyForm, mrCancel);
```

The active dialog for the given form is dismissed, the user callback fires with the result you passed, and the queue advances normally. Telemetry records the close as `crProgrammatic`.

This is what enables cleanup patterns like "the dialog asks for confirmation, but if the user takes too long, we cancel automatically and proceed with a default action".

### Theming as application identity

A dialog is not just a question — it is a visual surface that participates in the application's identity. Default OS dialogs have one look. Themed dialogs in your application palette have another. The same dialog shown in a corporate-neutral theme reads differently from the same dialog shown in a high-contrast neon theme.

Dialog4D treats theming as a first-class concern. `TDialog4DTheme` is a value record with fields for geometry, overlay, typography, accent palette, button visuals, and the default-button highlight ring. The theme is configured globally:

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

Themes are captured as snapshots at call time (Part 9), so changing the theme between dialogs does not affect dialogs already in flight.

Sections 2.1, 2.2, and 2.3 of the bundled demo show three pre-built themes — *Custom*, *Dark*, and *Cyberpunk* — with the same dialog rendering in three completely different visual identities.

### Telemetry as observability

When something goes wrong in production, you want to know what the user did. Did they click the dangerous button? Did they cancel? Did they ignore the warning? Did the dialog ever even appear?

`FMX.DialogService` does not provide built-in structured telemetry for dialog lifecycle and close reasons. The dialog appears, the callback fires, the result is delivered — but there is no ready-made record of the full interaction flow.

Dialog4D emits seven lifecycle events through a configurable telemetry sink:

```delphi
TDialog4D.ConfigureTelemetry(
  procedure(const AData: TDialog4DTelemetry)
  begin
    TFile.AppendAllText(
      'dialog_events.log',
      TDialog4DTelemetryFormat.FormatTelemetry(AData) + sLineBreak);
  end);
```

The events cover the full lifecycle: `tkShowRequested`, `tkShowDisplayed`, `tkCloseRequested`, `tkClosed`, `tkCallbackInvoked`, `tkCallbackSuppressed`, `tkOwnerDestroying`. Each event carries the dialog type, title, message length, button count, default result, the close reason (button, backdrop, key, programmatic, owner-destroying), the triggered button (kind and caption), elapsed time, and an absolute timestamp.

The sink is best-effort: exceptions raised inside the sink are silently swallowed by the framework. A misbehaving telemetry consumer cannot break the dialog flow.

This is what turns dialog interaction into **observable application behavior**. Section 2.6 of the bundled demo toggles telemetry live and shows every event flowing into the on-screen log.

---

## Part 12 — Dialog4D: the concepts in a cohesive package

Putting all the pieces together, Dialog4D is the FMX dialog mechanism that consolidates the decisions made along this guide.

### What each piece solves

| Concept | What it solves |
|---|---|
| `MessageDialogAsync` | Asynchronous dialogs with a callback that runs on the main thread, on every platform |
| Per-form FIFO queue | Concurrent dialog requests are serialized automatically; no overlap |
| Snapshot at call time | Theme and text provider captured at the moment of the call; not affected by later changes |
| `TDialog4DCustomButton` | Buttons with domain-language captions and four visual roles (default, destructive, cancel, neutral) |
| `TDialog4DAwait.MessageDialogOnWorker` | Worker threads can wait for a user decision without blocking the UI |
| `TDialog4D.CloseDialog` | Programmatic dismissal of the active dialog, from any thread |
| `TDialog4DTheme` | First-class theming with a snapshot model |
| `IDialog4DTextProvider` | Pluggable text provider for localization |
| `TDialog4D.ConfigureTelemetry` | Seven lifecycle events with close reason, button context, and timing |
| `DialogService4D` | Drop-in migration facade for `FMX.DialogService` callers |

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

- works identically on Windows, macOS, iOS, and Android;
- never blocks the main thread, on any platform;
- speaks domain language in the button captions;
- enforces the "dialog as flow router" pattern by shape;
- queues automatically if another dialog is requested concurrently for the same form;
- captures the active theme at call time, immune to theme changes between steps;
- emits telemetry events that an external sink can log for observability.

These properties are not opt-in features. They are the default behavior of every `MessageDialogAsync` call.

### A note on intent

Dialog4D was not built to compete with `FMX.DialogService`. It was built to address the cases where the recommended approach starts to push coordination concerns into application code: queueing, snapshots, custom buttons, programmatic close, theming consistency, telemetry, and worker-thread integration. For the simple case of a one-off OS-styled message, `FMX.DialogService` remains a good choice. For applications where dialogs are part of the visual identity and the application flow, Dialog4D consolidates the patterns into a mechanism that does not need to be rebuilt in every project.

The result is an API with a small public surface — three configuration calls, two `MessageDialogAsync` overloads, one `CloseDialog`, and the await family — but dense in correct decisions underneath. With a small amount of configuration, the developer obtains:

- asynchronous dialogs with deterministic lifecycle on every platform;
- per-form FIFO queueing without manual coordination;
- snapshot-based isolation of queued requests;
- custom buttons with four visual roles;
- worker-thread await with timeout;
- programmatic close from any thread;
- complete theming with a default-button highlight model;
- pluggable text provider for localization;
- structured telemetry with seven lifecycle events;
- form-destruction safety with callback suppression;
- and a drop-in migration facade for existing `FMX.DialogService` callers.

---

## Recommended reading

For readers who want to go deeper into the FMX framework and asynchronous patterns in Delphi, three references are worth highlighting:

- **[Embarcadero DocWiki — `TDialogService.MessageDialog`](https://docwiki.embarcadero.com/Libraries/Florence/en/FMX.DialogService.TDialogService.MessageDialog)** — the official FMX dialog service reference, including synchronous/asynchronous behavior according to `PreferredMode` and platform.
- **[Marco Cantù — *Object Pascal Handbook*](https://www.embarcadero.com/products/delphi/object-pascal-handbook)** — a book/eBook on modern Object Pascal, including anonymous methods; the [author page](https://www.marcocantu.com/objectpascalhandbook/) also keeps references to printed editions and Amazon links.
- The companion **[SafeThread4D conceptual guide](https://github.com/eduardoparaujo/SafeThread4D/blob/main/docs/Guide_en.md)** — for a deeper treatment of threading, `Synchronize`, `Queue`, and worker-thread coordination patterns referenced throughout this guide.

---

## Epilogue — Next steps

If you have made it this far, you have a solid conceptual foundation in FMX dialogs. You know **why** each layer in the dialog story exists, from the simplest `ShowMessage` to a fully-featured queueing and observable mechanism.

Natural next steps:

1. **Clone Dialog4D** and run the bundled demo. Each of the ten sections in the demo corresponds to a concept covered in this guide.
2. **Read the [project README](../README.md)**, with the API surface and migration recipes.
3. **Read [`Architecture.md`](Architecture.md)** if you want to understand the mechanism from the inside — the registry, the visual host, the close pipeline, and the form-destruction handling.
4. **Read the source code** calmly. The library is not large, and the pieces map directly onto the concepts in this guide.

If, at some point, you find yourself manually coordinating dialog queueing, working around theme changes between steps, or wishing you had observability of which dialogs the user actually saw, it may be time to stop rebuilding the mechanism from scratch in every project.

---

*This text is an introductory conceptual guide. For practical usage and mechanism details, consult the [README.md](../README.md), the architecture notes in [`Architecture.md`](Architecture.md), and the project examples.*
