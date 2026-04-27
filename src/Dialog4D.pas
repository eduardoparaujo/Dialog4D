// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Eduardo P. Araujo
// https://github.com/eduardoparaujo/Dialog4D

{*
  Unit   : Dialog4D
  Purpose: Public API facade for Dialog4D. Provides global configuration,
           asynchronous dialog entry points, thread-safe programmatic
           close, and per-form FIFO orchestration for FMX.

  Part of the Dialog4D framework - see Dialog4D.Types for the overview.

  Author        : Eduardo P. Araujo
  Created       : 2026-04-26
  Last modified : 2026-04-26
  Version       : 1.0.0

  Notes:
    - Dialog requests are always marshalled safely to the main thread.
    - Dialog presentation is pure FMX — no native OS dialog APIs are used.
    - Requests for the same form are serialized through a per-form FIFO
      queue.
    - Configuration is captured as immutable snapshots at call time.
    - Telemetry is best-effort and never interferes with dialog flow.

    - For worker-thread blocking behavior, see Dialog4D.Await. The main
      facade remains asynchronous on the UI thread by design.

  Important:
    - GRegistry is a process-wide singleton created lazily by the class
      constructor and disposed during unit finalization. After
      finalization, public methods that depend on GRegistry become no-ops.

    - Per-form state cleanup is driven by TDialog4DFormHook (owned by the
      parent form). When the form is destroyed, cleanup is scheduled
      asynchronously to the main thread so the visual tree can complete
      its own teardown first.

  History:
    1.0.0 — Initial public release.
      Configuration:
        • Global theme snapshot via ConfigureTheme.
        • Global text provider via ConfigureTextProvider.
        • Global telemetry sink via ConfigureTelemetry.
      Public entry points:
        • MessageDialogAsync — standard overload (TMsgDlgButtons).
        • MessageDialogAsync — custom overload (TArray<TDialog4DCustomButton>).
        • CloseDialog — programmatic, thread-safe close.
      Queueing & lifecycle:
        • Per-form FIFO registry serializes concurrent requests.
        • Requests captured as immutable snapshots at call time.
        • Form lifecycle tracked via a form-owned hook.
        • Pending requests discarded safely on form destruction.
      Telemetry & safety:
        • ShowRequested telemetry on entry.
        • Telemetry sink exceptions silently swallowed.
        • Public callers do not need to manage thread affinity.
*}

unit Dialog4D;

interface

uses
  System.SysUtils,
  System.UITypes,

  FMX.Forms,

  Dialog4D.Types;

type
  { ========================= }
  { == Public facade class == }
  { ========================= }

  /// <summary>
  /// Public API entry point for <c>Dialog4D</c>.
  /// </summary>
  /// <remarks>
  /// <para>
  /// All methods are class methods — the class itself holds global
  /// configuration via class vars and is not meant to be instantiated.
  /// </para>
  /// <para>
  /// <c>Dialog4D</c> is designed to make dialog flow explicit, predictable, and
  /// visually consistent across Windows, macOS, iOS and Android.
  /// </para>
  /// <para><b>Design guarantees:</b></para>
  /// <para>• Dialog requests are always marshalled safely to the main thread.</para>
  /// <para>• Dialog presentation is pure FMX — no native OS dialog APIs are used.</para>
  /// <para>• Requests for the same form are serialized through a per-form FIFO queue.</para>
  /// <para>• Configuration is captured as immutable snapshots at call time.</para>
  /// <para>• Telemetry is best-effort and never interferes with dialog flow.</para>
  /// <para><b>Core features:</b></para>
  /// <para>• Global theme configuration (<c>ConfigureTheme</c>).</para>
  /// <para>• Global text-provider registration (<c>ConfigureTextProvider</c>).</para>
  /// <para>• Global telemetry sink registration (<c>ConfigureTelemetry</c>).</para>
  /// <para>• Standard asynchronous dialogs (<c>MessageDialogAsync</c> with <c>TMsgDlgButtons</c>).</para>
  /// <para>• Custom-button asynchronous dialogs (<c>MessageDialogAsync</c> with <c>TArray&lt;TDialog4DCustomButton&gt;</c>).</para>
  /// <para>• Thread-safe programmatic close (<c>CloseDialog</c>).</para>
  /// <para>• Per-form FIFO queueing and automatic queue draining.</para>
  /// <para>• Form-lifecycle-aware cleanup through an internal hook.</para>
  /// <para>• Snapshot-based isolation of queued requests from later global changes.</para>
  /// <para>
  /// For worker-thread blocking behavior, use <c>Dialog4D.Await</c>. The main
  /// facade remains asynchronous on the UI thread by design.
  /// </para>
  /// </remarks>
  TDialog4D = class
  private
    class var FTheme: TDialog4DTheme;
    class var FTextProvider: IDialog4DTextProvider;
    class var FTelemetry: TDialog4DTelemetryProc;

    class function ResolveParentForm(const AParent: TCommonCustomForm)
      : TCommonCustomForm; static;
    class function DefaultTitle(const AProvider: IDialog4DTextProvider;
      const ADlgType: TMsgDlgType; const AExplicitTitle: string)
      : string; static;
    class function BtnToModalResult(const ABtn: TMsgDlgBtn)
      : TModalResult; static;
    class function IsDestructiveBtn(const ABtn: TMsgDlgBtn): Boolean; static;
    class procedure SafeEmitTelemetry(const AData: TDialog4DTelemetry); static;
    class function TickMs: UInt64; static;

  public
    class constructor Create;

    /// <summary>
    /// Sets the global theme used by all subsequent dialog requests.
    /// </summary>
    /// <remarks>
    /// <para>
    /// The theme is captured as a snapshot at request time, so calling this
    /// method has no effect on dialogs that are already queued or visible.
    /// </para>
    /// </remarks>
    class procedure ConfigureTheme(const ATheme: TDialog4DTheme); static;

    /// <summary>
    /// Registers the text provider used to resolve button captions and default
    /// dialog titles.
    /// </summary>
    /// <remarks>
    /// <para>Cannot be <c>nil</c>.</para>
    /// </remarks>
    class procedure ConfigureTextProvider(const AProvider
      : IDialog4DTextProvider); static;

    /// <summary>
    /// Registers the telemetry sink that receives all lifecycle events.
    /// </summary>
    /// <remarks>
    /// <para>Pass <c>nil</c> to disable telemetry.</para>
    /// </remarks>
    class procedure ConfigureTelemetry(const AProc
      : TDialog4DTelemetryProc); static;

    /// <summary>
    /// Shows a dialog asynchronously using standard <c>TMsgDlgBtn</c> buttons.
    /// </summary>
    /// <remarks>
    /// <para>
    /// Button captions are resolved via the active <c>IDialog4DTextProvider</c>.
    /// </para>
    /// </remarks>
    class procedure MessageDialogAsync(const AMessage: string;
      const ADialogType: TMsgDlgType; const AButtons: TMsgDlgButtons;
      const ADefaultButton: TMsgDlgBtn; const AOnResult: TDialog4DResultProc;
      const ATitle: string = ''; const AParent: TCommonCustomForm = nil;
      const ACancelable: Boolean = True); overload; static;

    /// <summary>
    /// Shows a dialog asynchronously using fully custom buttons.
    /// </summary>
    /// <remarks>
    /// <para>
    /// Button captions, modal results, and visual roles are specified directly
    /// in each <c>TDialog4DCustomButton</c> — no <c>TMsgDlgBtn</c> or
    /// <c>IDialog4DTextProvider</c> is involved.
    /// </para>
    /// <para><b>Default button:</b></para>
    /// <para>
    /// The default button (Enter key on desktop) is the first button in
    /// <c>AButtons</c> that has <c>IsDefault = True</c>. If none has
    /// <c>IsDefault = True</c>, the first button is promoted automatically.
    /// </para>
    /// <para><b>Cancel detection:</b></para>
    /// <para>
    /// Backdrop tap and Esc key use <c>ModalResult = mrCancel</c>, or
    /// <c>mrClose</c> when <c>TreatCloseAsCancel</c> is <c>True</c> in the theme.
    /// </para>
    /// <para><b>Example:</b></para>
    /// <code>
    /// TDialog4D.MessageDialogAsync(
    ///   'Delete "Project Alpha"? This cannot be undone.',
    ///   TMsgDlgType.mtWarning,
    ///   [
    ///     TDialog4DCustomButton.Destructive('Delete Project', mrYes),
    ///     TDialog4DCustomButton.Cancel('Keep It')
    ///   ],
    ///   procedure(const R: TModalResult)
    ///   begin
    ///     if R = mrYes then
    ///       DeleteProject;
    ///   end,
    ///   'Confirm Deletion'
    /// );
    /// </code>
    /// </remarks>
    class procedure MessageDialogAsync(const AMessage: string;
      const ADialogType: TMsgDlgType;
      const AButtons: TArray<TDialog4DCustomButton>;
      const AOnResult: TDialog4DResultProc; const ATitle: string = '';
      const AParent: TCommonCustomForm = nil;
      const ACancelable: Boolean = True); overload; static;

    /// <summary>
    /// Programmatically closes the currently visible dialog for the given form.
    /// </summary>
    /// <remarks>
    /// <para>Thread-safe. Silently ignored if no dialog is active.</para>
    /// <para>Recorded as <c>crProgrammatic</c> in telemetry.</para>
    /// </remarks>
    class procedure CloseDialog(const AForm: TCommonCustomForm = nil;
      const AResult: TModalResult = mrCancel); static;
  end;

implementation

uses
  System.Classes,
  System.Generics.Collections,
  System.SyncObjs,

  FMX.Types,

  Dialog4D.Host.FMX,
  Dialog4D.Internal.Queue,
  Dialog4D.TextProvider.Default;

{ ====================== }
{ == Request snapshot == }
{ ====================== }

type
  /// <summary>
  /// Immutable request snapshot.
  /// </summary>
  /// <remarks>
  /// <para>
  /// Captures all parameters of a single <c>MessageDialogAsync</c> call so the
  /// request is fully self-contained when it travels through the registry
  /// queue and onto the main thread.
  /// </para>
  /// <para><b>Construction paths:</b></para>
  /// <para>• <c>Create(...)</c> — standard <c>TMsgDlgButtons</c> + default <c>TMsgDlgBtn</c>.</para>
  /// <para>• <c>CreateCustom(...)</c> — <c>TArray&lt;TDialog4DCustomButton&gt;</c>.</para>
  /// <para>
  /// The <c>HasCustomButtons</c> flag tells the visual host which path to take
  /// when materializing <c>TDialog4DButtonConfiguration</c> entries.
  /// </para>
  /// </remarks>
  TDialog4DRequest = class
  public
    ParentForm: TCommonCustomForm;
    MessageText: string;
    DialogType: TMsgDlgType;

    { -- Standard button path (TMsgDlgButtons) -- }
    Buttons: TMsgDlgButtons;
    DefaultButton: TMsgDlgBtn;

    { -- Custom button path (TArray<TDialog4DCustomButton>) -- }
    HasCustomButtons: Boolean;
    CustomButtons: TArray<TDialog4DCustomButton>;

    OnResult: TDialog4DResultProc;
    Title: string;
    Cancelable: Boolean;
    Theme: TDialog4DTheme;
    TextProvider: IDialog4DTextProvider;

    /// <summary>Constructor for the standard TMsgDlgButtons path.</summary>
    constructor Create(const AParent: TCommonCustomForm; const AMessage: string;
      const ADialogType: TMsgDlgType; const AButtons: TMsgDlgButtons;
      const ADefaultButton: TMsgDlgBtn; const AOnResult: TDialog4DResultProc;
      const ATitle: string; const ACancelable: Boolean;
      const ATheme: TDialog4DTheme; const AProvider: IDialog4DTextProvider);

    /// <summary>Constructor for the TDialog4DCustomButton path.</summary>
    constructor CreateCustom(const AParent: TCommonCustomForm;
      const AMessage: string; const ADialogType: TMsgDlgType;
      const AButtons: TArray<TDialog4DCustomButton>;
      const AOnResult: TDialog4DResultProc; const ATitle: string;
      const ACancelable: Boolean; const ATheme: TDialog4DTheme;
      const AProvider: IDialog4DTextProvider);
  end;

constructor TDialog4DRequest.Create(const AParent: TCommonCustomForm;
  const AMessage: string; const ADialogType: TMsgDlgType;
  const AButtons: TMsgDlgButtons; const ADefaultButton: TMsgDlgBtn;
  const AOnResult: TDialog4DResultProc; const ATitle: string;
  const ACancelable: Boolean; const ATheme: TDialog4DTheme;
  const AProvider: IDialog4DTextProvider);
begin
  inherited Create;
  ParentForm := AParent;
  MessageText := AMessage;
  DialogType := ADialogType;
  Buttons := AButtons;
  DefaultButton := ADefaultButton;
  HasCustomButtons := False;
  SetLength(CustomButtons, 0);
  OnResult := AOnResult;
  Title := ATitle;
  Cancelable := ACancelable;
  Theme := ATheme;
  TextProvider := AProvider;
end;

constructor TDialog4DRequest.CreateCustom(const AParent: TCommonCustomForm;
  const AMessage: string; const ADialogType: TMsgDlgType;
  const AButtons: TArray<TDialog4DCustomButton>;
  const AOnResult: TDialog4DResultProc; const ATitle: string;
  const ACancelable: Boolean; const ATheme: TDialog4DTheme;
  const AProvider: IDialog4DTextProvider);
begin
  inherited Create;
  ParentForm := AParent;
  MessageText := AMessage;
  DialogType := ADialogType;
  Buttons := [];
  DefaultButton := TMsgDlgBtn.mbOK;
  HasCustomButtons := True;
  CustomButtons := AButtons;
  OnResult := AOnResult;
  Title := ATitle;
  Cancelable := ACancelable;
  Theme := ATheme;
  TextProvider := AProvider;
end;

{ ================================== }
{ == Form hook and per-form state == }
{ ================================== }

type
  TDialog4DFormState = class;

  /// <summary>
  /// Lightweight component owned by the parent form.
  /// </summary>
  /// <remarks>
  /// <para>
  /// When the form is destroyed (and consequently its owned components), this
  /// hook's destructor schedules registry cleanup on the main thread so any
  /// queued requests for that form are discarded safely.
  /// </para>
  /// </remarks>
  TDialog4DFormHook = class(TComponent)
  private
    FForm: TCommonCustomForm;
  public
    constructor Create(AOwner: TComponent; AForm: TCommonCustomForm);
      reintroduce;
    destructor Destroy; override;
  end;

  /// <summary>
  /// Per-form runtime state.
  /// </summary>
  /// <remarks>
  /// <para>
  /// Holds the FIFO queue of pending requests, the active request and its
  /// visual host, and the form hook used to detect form destruction.
  /// </para>
  /// </remarks>
  TDialog4DFormState = class
  public
    Active: Boolean;
    Queue: TQueue<TDialog4DRequest>;
    Hook: TDialog4DFormHook;
    ActiveRequest: TDialog4DRequest;
    ActiveHost: TDialog4DHostFMX;

    constructor Create;
    destructor Destroy; override;
  end;

constructor TDialog4DFormState.Create;
begin
  inherited Create;
  Active := False;
  Queue := TQueue<TDialog4DRequest>.Create;
  Hook := nil;
  ActiveRequest := nil;
  ActiveHost := nil;
end;

destructor TDialog4DFormState.Destroy;
(*
  Per-form state teardown.

  Strategy
  - Drain any pending requests still in the queue: the registry guarantees
    no thread will enqueue after this point, so a simple sequential drain
    is enough.
  - Free the active request separately — it is tracked outside the queue
    while a dialog is being shown.
  - Do not free ActiveHost: the host's lifetime is owned by the show
    callback chain, which will Free it after the user callback runs.
    Setting the field to nil is the only safe action here.

  Invariants
  - Caller has already removed this state from the registry map; no other
    thread can reach it after that point.
*)
var
  LRequest: TDialog4DRequest;
begin
  if Assigned(Queue) then
    while Queue.Count > 0 do
    begin
      LRequest := Queue.Dequeue;
      LRequest.Free;
    end;

  FreeAndNil(ActiveRequest);
  ActiveHost := nil;
  Queue.Free;

  inherited;
end;

constructor TDialog4DFormHook.Create(AOwner: TComponent;
  AForm: TCommonCustomForm);
begin
  inherited Create(AOwner);
  FForm := AForm;
end;

{ ============== }
{ == Registry == }
{ ============== }

type
  /// <summary>
  /// Process-wide registry that maps each parent form to its
  /// <c>TDialog4DFormState</c>.
  /// </summary>
  /// <remarks>
  /// <para>
  /// Serializes dialog requests per form via a FIFO queue and a single
  /// critical section.
  /// </para>
  /// <para><b>Synchronization model:</b></para>
  /// <para>
  /// <c>FCrit</c> guards <c>FMap</c> and the lifecycle flags on each
  /// <c>TDialog4DFormState</c> (<c>Active</c>, <c>ActiveRequest</c>,
  /// <c>ActiveHost</c>, <c>Queue</c>).
  /// </para>
  /// <para>
  /// It is intentionally a <c>TCriticalSection</c> rather than a collection of
  /// <c>TInterlocked</c> operations: the invariant being protected is composite
  /// (state map + per-form queue + active flags) and cannot be expressed as a
  /// single atomic read-modify-write.
  /// </para>
  /// </remarks>
  TDialog4DRegistry = class
  private
    FCrit: TCriticalSection;
    FMap: TDictionary<TCommonCustomForm, TDialog4DFormState>;

    function GetOrCreateStateLocked(const AForm: TCommonCustomForm)
      : TDialog4DFormState;
    procedure ShowRequestOnUI(const AReq: TDialog4DRequest);

  public
    constructor Create;
    destructor Destroy; override;

    procedure EnqueueOrShow(const AReq: TDialog4DRequest);
    procedure OnFormDestroyed(const AForm: TCommonCustomForm);
    procedure OnDialogFinished(const AForm: TCommonCustomForm);
    procedure CloseActiveDialog(const AForm: TCommonCustomForm;
      const AResult: TModalResult);
  end;

var
  GRegistry: TDialog4DRegistry = nil;

destructor TDialog4DFormHook.Destroy;
(*
  Form-destruction notification.

  Strategy
  - Capture FForm into a local variable and clear the field BEFORE
    scheduling cleanup. This guarantees the queued anonymous procedure
    cannot observe a half-destroyed hook if the form's destructor pumps
    messages while running.
  - Schedule registry cleanup asynchronously to the main thread so the
    form's own visual teardown can complete before per-form state
    (including any active host) is disposed of.

  Invariants
  - GRegistry may be freed during application shutdown between the
    queueing and the dispatch — the queued closure re-checks before use.
*)
var
  LForm: TCommonCustomForm;
begin
  LForm := FForm;
  FForm := nil;

  if Assigned(LForm) and Assigned(GRegistry) then
    QueueOnMainThread(
      procedure
      begin
        if Assigned(GRegistry) then
          GRegistry.OnFormDestroyed(LForm);
      end);

  inherited;
end;

constructor TDialog4DRegistry.Create;
begin
  inherited Create;
  FCrit := TCriticalSection.Create;
  FMap := TDictionary<TCommonCustomForm, TDialog4DFormState>.Create;
end;

destructor TDialog4DRegistry.Destroy;
var
  Pair: TPair<TCommonCustomForm, TDialog4DFormState>;
begin
  // No locking needed here — destruction of the registry happens during
  // unit finalization, after all forms (and therefore all hooks) are gone.
  for Pair in FMap do
    Pair.Value.Free;
  FMap.Free;
  FCrit.Free;

  inherited;
end;

function TDialog4DRegistry.GetOrCreateStateLocked
  (const AForm: TCommonCustomForm): TDialog4DFormState;
begin
  // Caller must already hold FCrit.
  if not FMap.TryGetValue(AForm, Result) then
  begin
    Result := TDialog4DFormState.Create;
    Result.Hook := TDialog4DFormHook.Create(AForm, AForm);
    FMap.Add(AForm, Result);
  end;
end;

procedure TDialog4DRegistry.OnFormDestroyed(const AForm: TCommonCustomForm);
var
  LState: TDialog4DFormState;
begin
  if not Assigned(AForm) then
    Exit;

  FCrit.Acquire;
  try
    if FMap.TryGetValue(AForm, LState) then
    begin
      FMap.Remove(AForm);
      LState.Free;
    end;
  finally
    FCrit.Release;
  end;
end;

procedure TDialog4DRegistry.CloseActiveDialog(const AForm: TCommonCustomForm;
const AResult: TModalResult);
(*
  Programmatic close.

  Strategy
  - Snapshot the active host pointer under FCrit, then call CloseProgram
    OUTSIDE the lock. Calling user-facing host methods while holding FCrit
    risks deadlock: the host may queue work that ultimately needs the
    same lock to complete.

  Outcomes
  - Active host found: CloseProgram is invoked with AResult; the host's
    own close pipeline takes over and eventually invokes the user
    callback (subject to the normal owner-destroying suppression rules).
  - No active host: silently ignored.

  Invariants
  - Must run on the main thread (the public API marshals to main before
    invoking this).
*)
var
  LState: TDialog4DFormState;
  LHost: TDialog4DHostFMX;
begin
  if not Assigned(AForm) then
    Exit;

  LHost := nil;
  FCrit.Acquire;
  try
    if FMap.TryGetValue(AForm, LState) then
      LHost := LState.ActiveHost;
  finally
    FCrit.Release;
  end;

  if Assigned(LHost) then
    LHost.CloseProgram(AResult);
end;

procedure TDialog4DRegistry.ShowRequestOnUI(const AReq: TDialog4DRequest);
(*
  Materialize and present a queued request on the main thread.

  Strategy
  - Drop silently when the parent form has been destroyed between enqueue
    and dispatch (OnFormDestroyed already cleaned up per-form state).
  - Resolve the text provider (fall back to the default if none).
  - Build the TDialog4DButtonConfiguration list:
    * HasCustomButtons = True: use TDialog4DCustomButton entries
      verbatim. Btn is set to mbOK as a placeholder (custom buttons
      have no standard kind; telemetry consumers should use
      ButtonCaption to identify them).
    * HasCustomButtons = False: walk TMsgDlgButtons, expanding each
      TMsgDlgBtn into its standard ModalResult, default flag, and
      provider-resolved caption.
  - Resolve the title (explicit > provider default).
  - Create the visual host, publish ActiveRequest/ActiveHost on the
    per-form state under FCrit (so concurrent CloseDialog can find them),
    and start ShowDialog.
  - Wire the result callback as a closure that:
    * Re-queues itself onto the main thread to run the user callback
      from a clean stack (outside any animation finish handler or
      reentrant context).
    * Clears ActiveRequest/ActiveHost on the per-form state under the
      lock, then frees host and request OUTSIDE the lock.
    * Drains the next request in the FIFO via OnDialogFinished, but
      only if the form is still alive.

  Outcomes
  - Form alive at dispatch time: dialog is built and shown; user callback
    is invoked when the dialog closes; the FIFO advances on completion.
  - Form already destroyed: the request is freed and nothing is shown.
  - ShowDialog raises: rollback restores per-form state to non-active and
    re-raises so the exception surfaces on the main loop.

  Invariants
  - Runs on the main thread (called from QueueOnMainThread paths).
  - Lock-discipline: FCrit is held only for short atomic publication and
    cleanup of pointers. All FMX work and Free calls happen outside the lock.
*)
var
  LHost: TDialog4DHostFMX;
  LButtonList: TList<TDialog4DButtonConfiguration>;
  LMsgDlgBtn: TMsgDlgBtn;
  LSpec: TDialog4DButtonConfiguration;
  LTitleResolved: string;
  LProvider: IDialog4DTextProvider;
  LTheme: TDialog4DTheme;
  LForm: TCommonCustomForm;
  LRequest: TDialog4DRequest;
  LState: TDialog4DFormState;
  I: Integer;
begin
  if not Assigned(AReq) then
    Exit;

  LRequest := AReq;
  LForm := LRequest.ParentForm;

  if (not Assigned(LForm)) or (csDestroying in LForm.ComponentState) then
  begin
    LRequest.Free;
    Exit;
  end;

  LProvider := LRequest.TextProvider;
  if not Assigned(LProvider) then
    LProvider := TDialog4DDefaultTextProvider.Create;

  LTheme := LRequest.Theme;

  LButtonList := TList<TDialog4DButtonConfiguration>.Create;
  try
    if LRequest.HasCustomButtons then
    begin
      // Custom button path.
      // Btn is a placeholder (mbOK) — telemetry consumers use Caption.
      for I := 0 to High(LRequest.CustomButtons) do
      begin
        LSpec.Btn := TMsgDlgBtn.mbOK;
        LSpec.ModalResult := LRequest.CustomButtons[I].ModalResult;
        LSpec.IsDefault := LRequest.CustomButtons[I].IsDefault;
        LSpec.IsDestructive := LRequest.CustomButtons[I].IsDestructive;
        LSpec.Caption := LRequest.CustomButtons[I].Caption;
        LButtonList.Add(LSpec);
      end;
    end
    else
    begin
      // Standard button path (TMsgDlgButtons + IDialog4DTextProvider).
      for LMsgDlgBtn in LRequest.Buttons do
      begin
        LSpec.Btn := LMsgDlgBtn;
        LSpec.ModalResult := TDialog4D.BtnToModalResult(LMsgDlgBtn);
        LSpec.IsDefault := (LMsgDlgBtn = LRequest.DefaultButton);
        LSpec.IsDestructive := TDialog4D.IsDestructiveBtn(LMsgDlgBtn);
        LSpec.Caption := LProvider.ButtonText(LMsgDlgBtn);
        LButtonList.Add(LSpec);
      end;
    end;

    LTitleResolved := TDialog4D.DefaultTitle(LProvider, LRequest.DialogType,
      LRequest.Title);

    LHost := TDialog4DHostFMX.Create(LTheme);
    try
      LHost.Telemetry := TDialog4D.FTelemetry;

      // Publish active request and host under the lock so concurrent
      // CloseDialog calls can find them.
      FCrit.Acquire;
      try
        if FMap.TryGetValue(LForm, LState) then
        begin
          LState.ActiveRequest := LRequest;
          LState.ActiveHost := LHost;
        end;
      finally
        FCrit.Release;
      end;

      LHost.ShowDialog(LForm, LTitleResolved, LRequest.MessageText,
        LButtonList.ToArray, LRequest.Cancelable,
        procedure(const AResult: TModalResult)
        begin
          // Re-queue onto the main thread so the user callback runs from
          // a clean stack — outside any animation finish handler.
          QueueOnMainThread(
            procedure
            begin
              try
                if Assigned(LForm) and not(csDestroying in LForm.ComponentState)
                then
                  if Assigned(LRequest.OnResult) then
                    LRequest.OnResult(AResult);
              finally
                // Clear active references under the lock, then dispose
                // outside — Free can be expensive and we don't want to
                // block other threads waiting to read the registry.
                FCrit.Acquire;
                try
                  if FMap.TryGetValue(LForm, LState) then
                  begin
                    if LState.ActiveRequest = LRequest then
                      LState.ActiveRequest := nil;
                    if LState.ActiveHost = LHost then
                      LState.ActiveHost := nil;
                  end;
                finally
                  FCrit.Release;
                end;
                LHost.Free;
                LRequest.Free;

                // Drain the next request only if the form is still alive.
                if Assigned(GRegistry) and Assigned(LForm) and
                  not(csDestroying in LForm.ComponentState) then
                  GRegistry.OnDialogFinished(LForm);
              end;
            end);
        end, LRequest.DialogType);
    except
      // ShowDialog raised — roll back active publication and rethrow.
      FCrit.Acquire;
      try
        if FMap.TryGetValue(LForm, LState) then
        begin
          if LState.ActiveRequest = LRequest then
            LState.ActiveRequest := nil;
          if LState.ActiveHost = LHost then
            LState.ActiveHost := nil;
          LState.Active := False;
        end;
      finally
        FCrit.Release;
      end;
      LHost.Free;
      LRequest.Free;
      raise;
    end;

  finally
    LButtonList.Free;
  end;
end;

procedure TDialog4DRegistry.EnqueueOrShow(const AReq: TDialog4DRequest);
(*
  Entry point for new requests.

  Strategy
  - Decide under FCrit whether to enqueue (a dialog is already active for
    this form) or to start showing now.
  - The actual ShowRequestOnUI call happens OUTSIDE the lock — it builds
    the visual tree and may trigger long-running FMX operations that
    must not run with the registry locked.

  Outcomes
  - Form has an active dialog: request is appended to the FIFO; will be
    drained later by OnDialogFinished.
  - Form has no active dialog: state is marked Active and ShowRequestOnUI
    runs immediately.

  Invariants
  - Caller must have already validated AReq.ParentForm.
*)
var
  LState: TDialog4DFormState;
  LShowNow: Boolean;
begin
  if not Assigned(AReq) then
    Exit;
  if not Assigned(AReq.ParentForm) then
    raise Exception.Create('Dialog4D: parent form is required.');

  LShowNow := False;
  FCrit.Acquire;
  try
    LState := GetOrCreateStateLocked(AReq.ParentForm);
    if LState.Active then
    begin
      LState.Queue.Enqueue(AReq);
      Exit;
    end;
    LState.Active := True;
    LShowNow := True;
  finally
    FCrit.Release;
  end;

  if LShowNow then
    ShowRequestOnUI(AReq);
end;

procedure TDialog4DRegistry.OnDialogFinished(const AForm: TCommonCustomForm);
(*
  FIFO drain after a dialog completes.

  Strategy
  - Same lock discipline as EnqueueOrShow: decide under FCrit, dispatch
    outside.
  - When a queued request is dequeued, mark Active=True again so any
    concurrent EnqueueOrShow calls go straight to the queue and don't
    race with the dispatch.

  Outcomes
  - Queue empty: per-form state is left Active=False; the next
    EnqueueOrShow will start a new dialog.
  - Queue non-empty: next request is dispatched via ShowRequestOnUI.
*)
var
  LState: TDialog4DFormState;
  LNextRequest: TDialog4DRequest;
begin
  if not Assigned(AForm) then
    Exit;

  LNextRequest := nil;
  FCrit.Acquire;
  try
    if not FMap.TryGetValue(AForm, LState) then
      Exit;
    LState.Active := False;
    if LState.Queue.Count > 0 then
    begin
      LNextRequest := LState.Queue.Dequeue;
      LState.Active := True;
    end;
  finally
    FCrit.Release;
  end;

  if Assigned(LNextRequest) then
    ShowRequestOnUI(LNextRequest);
end;

{ =============== }
{ == TDialog4D == }
{ =============== }

class function TDialog4D.TickMs: UInt64;
begin
  Result := TThread.GetTickCount64;
end;

class procedure TDialog4D.SafeEmitTelemetry(const AData: TDialog4DTelemetry);
var
  LProc: TDialog4DTelemetryProc;
begin
  LProc := FTelemetry;
  if not Assigned(LProc) then
    Exit;

  try
    LProc(AData);
  except
    // Telemetry must never affect dialog flow — exceptions in the sink
    // are silently swallowed.
  end;
end;

class constructor TDialog4D.Create;
begin
  FTheme := TDialog4DTheme.Default;
  FTextProvider := TDialog4DDefaultTextProvider.Create;
  FTelemetry := nil;

  if not Assigned(GRegistry) then
    GRegistry := TDialog4DRegistry.Create;
end;

class procedure TDialog4D.ConfigureTheme(const ATheme: TDialog4DTheme);
begin
  FTheme := ATheme;
end;

class procedure TDialog4D.ConfigureTextProvider(const AProvider
  : IDialog4DTextProvider);
begin
  if not Assigned(AProvider) then
    raise Exception.Create('Dialog4D: TextProvider cannot be nil.');
  FTextProvider := AProvider;
end;

class procedure TDialog4D.ConfigureTelemetry(const AProc
  : TDialog4DTelemetryProc);
begin
  FTelemetry := AProc;
end;

class function TDialog4D.ResolveParentForm(const AParent: TCommonCustomForm)
  : TCommonCustomForm;
begin
  // Resolution order: explicit > active form > main form. Returning nil is
  // valid here — the caller raises if no form can be resolved.
  if Assigned(AParent) then
    Exit(AParent);
  if Assigned(Screen.ActiveForm) then
    Exit(Screen.ActiveForm);
  Result := Application.MainForm;
end;

class function TDialog4D.DefaultTitle(const AProvider: IDialog4DTextProvider;
const ADlgType: TMsgDlgType; const AExplicitTitle: string): string;
begin
  if AExplicitTitle.Trim <> '' then
    Exit(AExplicitTitle);

  if Assigned(AProvider) then
    Result := AProvider.TitleForType(ADlgType)
  else
    Result := '';
end;

class function TDialog4D.BtnToModalResult(const ABtn: TMsgDlgBtn): TModalResult;
begin
  case ABtn of
    TMsgDlgBtn.mbOK:
      Result := mrOk;
    TMsgDlgBtn.mbCancel:
      Result := mrCancel;
    TMsgDlgBtn.mbYes:
      Result := mrYes;
    TMsgDlgBtn.mbNo:
      Result := mrNo;
    TMsgDlgBtn.mbAbort:
      Result := mrAbort;
    TMsgDlgBtn.mbRetry:
      Result := mrRetry;
    TMsgDlgBtn.mbIgnore:
      Result := mrIgnore;
    TMsgDlgBtn.mbAll:
      Result := mrAll;
    TMsgDlgBtn.mbNoToAll:
      Result := mrNoToAll;
    TMsgDlgBtn.mbYesToAll:
      Result := mrYesToAll;
    TMsgDlgBtn.mbHelp:
      Result := mrHelp;
    TMsgDlgBtn.mbClose:
      Result := mrClose;
  else
    Result := mrNone;
  end;
end;

class function TDialog4D.IsDestructiveBtn(const ABtn: TMsgDlgBtn): Boolean;
begin
  // Only Abort is treated as destructive in the standard set; for custom
  // buttons the caller flags IsDestructive explicitly on TDialog4DCustomButton.
  Result := (ABtn = TMsgDlgBtn.mbAbort);
end;

{ == Helpers == }

function CountMsgDlgButtons(const AButtons: TMsgDlgButtons): Integer;
var
  LBtn: TMsgDlgBtn;
begin
  Result := 0;
  for LBtn := Low(TMsgDlgBtn) to High(TMsgDlgBtn) do
    if LBtn in AButtons then
      Inc(Result);
end;

{ == Standard button overload == }

class procedure TDialog4D.MessageDialogAsync(const AMessage: string;
const ADialogType: TMsgDlgType; const AButtons: TMsgDlgButtons;
const ADefaultButton: TMsgDlgBtn; const AOnResult: TDialog4DResultProc;
const ATitle: string; const AParent: TCommonCustomForm;
const ACancelable: Boolean);
(*
  Standard-button asynchronous entry point.

  Strategy
  - Validate inputs (parent form resolved, at least one button).
  - Resolve text provider (fall back to default if none).
  - Build an immutable TDialog4DRequest snapshot capturing every parameter
    plus a copy of the current FTheme — later ConfigureTheme calls do not
    affect this request.
  - Marshal the rest of the work to the main thread:
    * Emit ShowRequested telemetry.
    * Hand the request to GRegistry, which decides whether to show it
      immediately or enqueue behind an active dialog.

  Outcomes
  - Application running normally: dialog is queued or shown.
  - Application shutting down (GRegistry already freed): the request is
    freed and the call becomes a silent no-op.

  Invariants
  - Safe to call from any thread; all FMX work runs on the main thread.
*)
var
  LParentForm: TCommonCustomForm;
  LRequest: TDialog4DRequest;
  LProvider: IDialog4DTextProvider;
begin
  LParentForm := ResolveParentForm(AParent);
  if not Assigned(LParentForm) then
    raise Exception.Create('Dialog4D: no parent form available.');
  if AButtons = [] then
    raise Exception.Create('Dialog4D: at least one button is required.');

  LProvider := FTextProvider;
  if not Assigned(LProvider) then
    LProvider := TDialog4DDefaultTextProvider.Create;

  LRequest := TDialog4DRequest.Create(LParentForm, AMessage, ADialogType,
    AButtons, ADefaultButton, AOnResult, ATitle, ACancelable, FTheme,
    LProvider);

  QueueOnMainThread(
    procedure
    var
      LData: TDialog4DTelemetry;
    begin
      LData.Kind := tkShowRequested;
      LData.DialogType := ADialogType;
      LData.Title := ATitle;
      LData.MessageLen := Length(AMessage);
      LData.ButtonsCount := CountMsgDlgButtons(AButtons);
      LData.HasCancelButton := (TMsgDlgBtn.mbCancel in AButtons);
      LData.DefaultResult := BtnToModalResult(ADefaultButton);
      LData.Result := mrNone;
      LData.CloseReason := crNone;
      LData.Tick := TickMs;
      LData.ElapsedMs := 0;
      SafeEmitTelemetry(LData);

      if Assigned(GRegistry) then
        GRegistry.EnqueueOrShow(LRequest)
      else
        LRequest.Free;
    end);
end;

{ == Custom button overload == }

class procedure TDialog4D.MessageDialogAsync(const AMessage: string;
const ADialogType: TMsgDlgType; const AButtons: TArray<TDialog4DCustomButton>;
const AOnResult: TDialog4DResultProc; const ATitle: string;
const AParent: TCommonCustomForm; const ACancelable: Boolean);
(*
  Custom-button asynchronous entry point.

  Strategy
  - Same shape as the standard overload: validate, snapshot, marshal.
  - Telemetry computation walks the custom-button array to derive
    HasCancelButton (any ModalResult = mrCancel) and DefaultResult (the
    first explicit IsDefault, or the first button as a fallback) so the
    snapshot matches what the visual host will resolve.

  Outcomes
  - Same as the standard overload: queued or shown synchronously, or
    silently dropped on application shutdown.

  Invariants
  - Safe to call from any thread.
  - The custom button array is captured into the snapshot — callers may
    free or mutate their local array immediately after this call returns.
*)
var
  LParentForm: TCommonCustomForm;
  LRequest: TDialog4DRequest;
  LProvider: IDialog4DTextProvider;
begin
  LParentForm := ResolveParentForm(AParent);
  if not Assigned(LParentForm) then
    raise Exception.Create('Dialog4D: no parent form available.');
  if Length(AButtons) = 0 then
    raise Exception.Create('Dialog4D: at least one button is required.');

  LProvider := FTextProvider;
  if not Assigned(LProvider) then
    LProvider := TDialog4DDefaultTextProvider.Create;

  LRequest := TDialog4DRequest.CreateCustom(LParentForm, AMessage, ADialogType,
    AButtons, AOnResult, ATitle, ACancelable, FTheme, LProvider);

  QueueOnMainThread(
    procedure
    var
      LData: TDialog4DTelemetry;
      I: Integer;
      LHasCancel: Boolean;
      LDefaultResult: TModalResult;
    begin
      // Default result mirrors the host's resolution: first explicit
      // IsDefault, otherwise first button.
      LHasCancel := False;
      LDefaultResult := mrNone;

      for I := 0 to High(AButtons) do
      begin
        if AButtons[I].ModalResult = mrCancel then
          LHasCancel := True;
        if AButtons[I].IsDefault and (LDefaultResult = mrNone) then
          LDefaultResult := AButtons[I].ModalResult;
      end;

      if (LDefaultResult = mrNone) and (Length(AButtons) > 0) then
        LDefaultResult := AButtons[0].ModalResult;

      LData.Kind := tkShowRequested;
      LData.DialogType := ADialogType;
      LData.Title := ATitle;
      LData.MessageLen := Length(AMessage);
      LData.ButtonsCount := Length(AButtons);
      LData.HasCancelButton := LHasCancel;
      LData.DefaultResult := LDefaultResult;
      LData.Result := mrNone;
      LData.CloseReason := crNone;
      LData.Tick := TickMs;
      LData.ElapsedMs := 0;
      SafeEmitTelemetry(LData);

      if Assigned(GRegistry) then
        GRegistry.EnqueueOrShow(LRequest)
      else
        LRequest.Free;
    end);
end;

class procedure TDialog4D.CloseDialog(const AForm: TCommonCustomForm;
const AResult: TModalResult);
begin
  // Marshal to the main thread — host operations must run there, and the
  // public API must be safe to call from any thread.
  QueueOnMainThread(
    procedure
    var
      LForm: TCommonCustomForm;
    begin
      LForm := ResolveParentForm(AForm);
      if not Assigned(LForm) then
        Exit;

      if Assigned(GRegistry) then
        GRegistry.CloseActiveDialog(LForm, AResult);
    end);
end;

initialization

finalization

FreeAndNil(GRegistry);

end.
