// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Eduardo P. Araujo
// https://github.com/eduardoparaujo/Dialog4D

{*
  Unit   : Dialog4D
  Purpose: Public API facade for Dialog4D. Provides global configuration,
           asynchronous dialog entry points, programmatic close, and
           per-form FIFO orchestration for FMX.

  Part of the Dialog4D public API layer.

  Author        : Eduardo P. Araujo
  Created       : 2026-04-26
  Last modified : 2026-05-01
  Version       : 1.0.1

  Notes:
    - Dialog presentation is pure FMX — no native OS dialog APIs are used.
    - Requests for the same form are serialized through a per-form FIFO
      queue.
    - Dialog display and close operations are marshalled to the main thread
      when the public API is called from a worker thread.
    - Request configuration is captured as a snapshot at call time:
        • theme
        • text provider
        • telemetry sink
        • callback
        • button definitions
    - Telemetry is best-effort and never interferes with dialog flow.

    - Global configuration methods (ConfigureTheme, ConfigureTextProvider
      and ConfigureTelemetry) are intended to be called during application
      initialization or from a controlled main-thread configuration path.
      They are not designed as high-frequency concurrent mutation APIs.

    - For worker-thread blocking behavior, see Dialog4D.Await. The main
      facade remains non-modal and asynchronous by design.

  Important:
    - GRegistry is a process-wide singleton created lazily by the class
      constructor and disposed during unit finalization. After finalization,
      queued public calls that depend on GRegistry become no-ops.

    - Per-form state cleanup is driven by a form-owned registry hook. When
      the form is destroyed, the registry marks the per-form state as
      owner-destroying and schedules cleanup asynchronously to the main
      thread.

    - The final application-callback path claims ownership of the active
      request snapshot before invoking user code. This prevents the active
      request from being released by both the registry cleanup path and the
      queued final callback path when form destruction is re-entered during
      callback processing.

  History:
    1.0.1 — 2026-05-01 — Defensive contract and lifetime correction.
      • Moved automatic parent-form resolution into the main-thread execution
        path, avoiding Screen.ActiveForm/Application.MainForm access from
        worker threads.
      • Added a telemetry snapshot to TDialog4DRequest so queued dialogs use
        the telemetry sink captured at request time.
      • Changed custom-button snapshot storage to Copy(AButtons), preventing
        later caller-side mutations from changing queued requests.
      • Added validation that rejects custom buttons with ModalResult = mrNone,
        matching the public contract documented in Dialog4D.Types.
      • Corrected ShowRequested telemetry so cancel/default information follows
        the same effective rules used by the visual host.
      • Initialized telemetry records deterministically before emission.
      • Added owner-destroying state tracking and final-callback ownership
        claiming to avoid active request lifetime conflicts when parent-form
        destruction is re-entered during callback processing.
      • Updated comments to distinguish main-thread marshaling from global
        configuration mutation.
      • Moved per-form state destruction outside the registry critical section
        during form-destruction cleanup, keeping FCrit scoped to map/state
        publication only.
      • Removed the local IsMainThreadSafe duplicate; the canonical primitive
        now lives in Dialog4D.Internal.Queue and is shared with the await
        helper.

    1.0.0 — 2026-04-26 — Initial public release.
      Configuration:
        • Global theme snapshot via ConfigureTheme.
        • Global text provider via ConfigureTextProvider.
        • Global telemetry sink via ConfigureTelemetry.
      Public entry points:
        • MessageDialogAsync — standard overload (TMsgDlgButtons).
        • MessageDialogAsync — custom overload (TArray<TDialog4DCustomButton>).
        • CloseDialog — programmatic close.
      Queueing & lifecycle:
        • Per-form FIFO registry serializes concurrent requests.
        • Requests captured as immutable snapshots at call time.
        • Form lifecycle tracked via a form-owned hook.
        • Pending requests discarded safely on form destruction.
      Telemetry & safety:
        • ShowRequested telemetry on entry.
        • Telemetry sink exceptions silently swallowed.
        • Public callers do not need to manage UI-thread affinity for dialog
          display and close operations.
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
  /// <para>
  /// • Dialog display and close operations are marshalled to the main thread
  /// when called from worker code.
  /// </para>
  /// <para>
  /// • Dialog presentation is pure FMX — no native OS dialog APIs are used.
  /// </para>
  /// <para>
  /// • Requests for the same form are serialized through a per-form FIFO queue.
  /// </para>
  /// <para>
  /// • Theme, provider, telemetry, callback and buttons are captured as request
  /// snapshots.
  /// </para>
  /// <para>
  /// • Telemetry is best-effort and never interferes with dialog flow.
  /// </para>
  /// <para><b>Core features:</b></para>
  /// <para>
  /// • Global theme configuration (<c>ConfigureTheme</c>).
  /// </para>
  /// <para>
  /// • Global text-provider registration (<c>ConfigureTextProvider</c>).
  /// </para>
  /// <para>
  /// • Global telemetry sink registration (<c>ConfigureTelemetry</c>).
  /// </para>
  /// <para>
  /// • Standard asynchronous dialogs (<c>MessageDialogAsync</c> with
  /// <c>TMsgDlgButtons</c>).
  /// </para>
  /// <para>
  /// • Custom-button asynchronous dialogs (<c>MessageDialogAsync</c> with
  /// <c>TArray&lt;TDialog4DCustomButton&gt;</c>).
  /// </para>
  /// <para>
  /// • Programmatic close (<c>CloseDialog</c>).
  /// </para>
  /// <para>
  /// • Per-form FIFO queueing and automatic queue draining.
  /// </para>
  /// <para>
  /// • Form-lifecycle-aware cleanup through an internal hook.
  /// </para>
  /// <para>
  /// • Snapshot-based isolation of queued requests from later global changes.
  /// </para>
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
    class procedure SafeEmitTelemetry(const AData: TDialog4DTelemetry;
      const AProc: TDialog4DTelemetryProc); static;
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
    /// <para>Thread-safe. Worker calls are marshalled to the main thread.</para>
    /// <para>Silently ignored if no dialog is active.</para>
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
  /// <para>
  /// • <c>Create(...)</c> — standard <c>TMsgDlgButtons</c> plus default
  /// <c>TMsgDlgBtn</c>.
  /// </para>
  /// <para>
  /// • <c>CreateCustom(...)</c> —
  /// <c>TArray&lt;TDialog4DCustomButton&gt;</c>.
  /// </para>
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
    Telemetry: TDialog4DTelemetryProc;

    /// <summary>Constructor for the standard TMsgDlgButtons path.</summary>
    constructor Create(const AParent: TCommonCustomForm; const AMessage: string;
      const ADialogType: TMsgDlgType; const AButtons: TMsgDlgButtons;
      const ADefaultButton: TMsgDlgBtn; const AOnResult: TDialog4DResultProc;
      const ATitle: string; const ACancelable: Boolean;
      const ATheme: TDialog4DTheme; const AProvider: IDialog4DTextProvider;
      const ATelemetry: TDialog4DTelemetryProc);

    /// <summary>Constructor for the TDialog4DCustomButton path.</summary>
    constructor CreateCustom(const AParent: TCommonCustomForm;
      const AMessage: string; const ADialogType: TMsgDlgType;
      const AButtons: TArray<TDialog4DCustomButton>;
      const AOnResult: TDialog4DResultProc; const ATitle: string;
      const ACancelable: Boolean; const ATheme: TDialog4DTheme;
      const AProvider: IDialog4DTextProvider;
      const ATelemetry: TDialog4DTelemetryProc);
  end;

constructor TDialog4DRequest.Create(const AParent: TCommonCustomForm;
  const AMessage: string; const ADialogType: TMsgDlgType;
  const AButtons: TMsgDlgButtons; const ADefaultButton: TMsgDlgBtn;
  const AOnResult: TDialog4DResultProc; const ATitle: string;
  const ACancelable: Boolean; const ATheme: TDialog4DTheme;
  const AProvider: IDialog4DTextProvider;
  const ATelemetry: TDialog4DTelemetryProc);
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
  Telemetry := ATelemetry;
end;

constructor TDialog4DRequest.CreateCustom(const AParent: TCommonCustomForm;
  const AMessage: string; const ADialogType: TMsgDlgType;
  const AButtons: TArray<TDialog4DCustomButton>;
  const AOnResult: TDialog4DResultProc; const ATitle: string;
  const ACancelable: Boolean; const ATheme: TDialog4DTheme;
  const AProvider: IDialog4DTextProvider;
  const ATelemetry: TDialog4DTelemetryProc);
begin
  inherited Create;
  ParentForm := AParent;
  MessageText := AMessage;
  DialogType := ADialogType;
  Buttons := [];
  DefaultButton := TMsgDlgBtn.mbOK;
  HasCustomButtons := True;
  CustomButtons := Copy(AButtons);
  OnResult := AOnResult;
  Title := ATitle;
  Cancelable := ACancelable;
  Theme := ATheme;
  TextProvider := AProvider;
  Telemetry := ATelemetry;
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
    OwnerDestroying: Boolean;
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
  OwnerDestroying := False;
  Queue := TQueue<TDialog4DRequest>.Create;
  Hook := nil;
  ActiveRequest := nil;
  ActiveHost := nil;
end;

destructor TDialog4DFormState.Destroy;
(*
  Per-form state teardown.

  Strategy
  - Drain any pending requests still in the queue. The registry has already
    removed this state from FMap, so no new request can reach this instance.
  - ActiveRequest has two possible owners during teardown:
      • this form state, when the visual host was destroyed before the final
        facade callback was queued;
      • the queued final facade callback, after it claims the active request
        under FCrit.
  - If ActiveRequest is still assigned here, this state is the last owner and
    must free it. If it is already nil, the queued final callback has claimed
    it and will free it.
  - Do not free ActiveHost. The visual host lifetime is owned by the host
    owner-destroying path or by the queued final facade callback. This state
    only publishes the pointer so CloseDialog can find the active host.

  Invariants
  - Caller has already removed this state from the registry map.
  - ActiveRequest disposal paths are mutually exclusive: exactly one of
    {this destructor, the queued final facade callback} frees the request.
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

  if Assigned(ActiveRequest) then
  begin
    LRequest := ActiveRequest;
    ActiveRequest := nil;
    LRequest.Free;
  end;

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
  /// <c>FCrit</c> guards <c>FMap</c> and the lifecycle fields on each
  /// <c>TDialog4DFormState</c> (<c>Active</c>, <c>OwnerDestroying</c>,
  /// <c>ActiveRequest</c>, <c>ActiveHost</c>, <c>Queue</c>).
  /// </para>
  /// <para>
  /// It is intentionally a <c>TCriticalSection</c> rather than a collection of
  /// <c>TInterlocked</c> operations: the invariant being protected is composite
  /// (state map + per-form queue + active flag + owner-destroying flag +
  /// active request/host publication) and cannot be expressed as a single
  /// atomic read-modify-write.
  /// </para>
  /// <para>
  /// The lock is held only for short map/state publication steps. Object
  /// destruction and FMX work must happen outside the critical section.
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
    procedure MarkFormDestroying(const AForm: TCommonCustomForm);
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
  - Capture FForm into a local variable and clear the field before queuing
    cleanup. The hook itself is being destroyed by the parent form.
  - Mark the form state as owner-destroying immediately, while the form object
    is still in the destruction path. This lets any already queued final
    callback skip the application OnResult and avoid draining the FIFO.
  - Schedule registry cleanup asynchronously to the main thread. This allows
    the form's own component/visual teardown to continue before pending
    requests are discarded and the per-form state is removed.

  Invariants
  - GRegistry may be freed during application shutdown between queueing and
    dispatch; the queued closure re-checks before use.
*)
var
  LForm: TCommonCustomForm;
begin
  LForm := FForm;
  FForm := nil;

  if Assigned(LForm) and Assigned(GRegistry) then
  begin
    GRegistry.MarkFormDestroying(LForm);

    QueueOnMainThread(
      procedure
      begin
        if Assigned(GRegistry) then
          GRegistry.OnFormDestroyed(LForm);
      end);
  end;

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

procedure TDialog4DRegistry.MarkFormDestroying(const AForm: TCommonCustomForm);
var
  LState: TDialog4DFormState;
begin
  if not Assigned(AForm) then
    Exit;

  FCrit.Acquire;
  try
    if FMap.TryGetValue(AForm, LState) then
      LState.OwnerDestroying := True;
  finally
    FCrit.Release;
  end;
end;

procedure TDialog4DRegistry.OnFormDestroyed(const AForm: TCommonCustomForm);
var
  LState: TDialog4DFormState;
begin
  if not Assigned(AForm) then
    Exit;

  LState := nil;

  FCrit.Acquire;
  try
    if FMap.TryGetValue(AForm, LState) then
      FMap.Remove(AForm);
  finally
    FCrit.Release;
  end;

  LState.Free;
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
    if FMap.TryGetValue(AForm, LState) and not LState.OwnerDestroying then
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
  - Drop safely when the parent form is missing or is already destroying.
  - Resolve the text provider (fall back to the default if none).
  - Build the normalized button list used by the FMX visual host.
  - Create the visual host and publish ActiveRequest/ActiveHost under FCrit.
    If the form state has already entered owner-destroying mode, abort before
    showing anything.
  - The host close callback queues the final facade callback onto the main
    loop. That final callback first claims ActiveRequest/ActiveHost ownership
    under FCrit, then invokes the application callback only if the form state
    has not entered owner-destroying mode.
  - The final callback always frees the host it owns after a normal close. It
    frees the request only if it successfully claimed the request ownership.

  Outcomes
  - Form alive: dialog is shown; application callback may run; FIFO advances.
  - Form owner-destroying before show: request and host are disposed and
    nothing is shown.
  - Form owner-destroying during the queued final callback window: application
    callback is skipped, request/host lifetime remains single-owner, and FIFO
    draining is left to form-destruction cleanup.
  - ShowDialog raises: active publication is rolled back and the exception is
    re-raised.

  Invariants
  - Runs on the main thread.
  - FCrit is held only for short publication/claim operations. FMX work,
    callbacks, and Free calls happen outside the lock.
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
  LPublished: Boolean;
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
      LHost.Telemetry := LRequest.Telemetry;

      LPublished := False;
      FCrit.Acquire;
      try
        if FMap.TryGetValue(LForm, LState) and not LState.OwnerDestroying then
        begin
          LState.ActiveRequest := LRequest;
          LState.ActiveHost := LHost;
          LPublished := True;
        end;
      finally
        FCrit.Release;
      end;

      if not LPublished then
      begin
        LHost.Free;
        LRequest.Free;
        Exit;
      end;

      LHost.ShowDialog(LForm, LTitleResolved, LRequest.MessageText,
        LButtonList.ToArray, LRequest.Cancelable,
        procedure(const AResult: TModalResult)
        begin
          QueueOnMainThread(
            procedure
            var
              LClaimedRequest: Boolean;
              LCanInvokeCallback: Boolean;
              LCanDrainQueue: Boolean;
              LStateLocal: TDialog4DFormState;
              LClaimedState: TDialog4DFormState;
            begin
              LClaimedRequest := False;
              LCanInvokeCallback := False;
              LCanDrainQueue := False;
              LClaimedState := nil;

              FCrit.Acquire;
              try
                if FMap.TryGetValue(LForm, LStateLocal) then
                begin
                  LClaimedState := LStateLocal;
                  LCanInvokeCallback := not LStateLocal.OwnerDestroying;

                  if LStateLocal.ActiveRequest = LRequest then
                  begin
                    LStateLocal.ActiveRequest := nil;
                    LClaimedRequest := True;
                  end;

                  if LStateLocal.ActiveHost = LHost then
                    LStateLocal.ActiveHost := nil;
                end;
              finally
                FCrit.Release;
              end;

              try
                if LClaimedRequest and LCanInvokeCallback and
                  Assigned(LRequest.OnResult) then
                  LRequest.OnResult(AResult);
              finally
                // The final facade callback owns the host after a normal
                // close. The request is freed here only if this callback
                // successfully claimed ActiveRequest above.
                LHost.Free;

                if LClaimedRequest then
                  LRequest.Free;

                if LClaimedRequest and Assigned(GRegistry) then
                begin
                  FCrit.Acquire;
                  try
                    if FMap.TryGetValue(LForm, LStateLocal) and
                      (LStateLocal = LClaimedState) then
                      LCanDrainQueue := not LStateLocal.OwnerDestroying;
                  finally
                    FCrit.Release;
                  end;

                  if LCanDrainQueue then
                    GRegistry.OnDialogFinished(LForm);
                end;
              end;
            end);
        end, LRequest.DialogType);
    except
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
  - Decide under FCrit whether to enqueue or show immediately.
  - If the form state is already owner-destroying, discard the request.
  - Dispatch outside the lock.

  Invariants
  - Caller has already validated AReq.ParentForm.
*)
var
  LState: TDialog4DFormState;
  LShowNow: Boolean;
  LDiscard: Boolean;
begin
  if not Assigned(AReq) then
    Exit;
  if not Assigned(AReq.ParentForm) then
    raise Exception.Create('Dialog4D: parent form is required.');

  LShowNow := False;
  LDiscard := False;

  FCrit.Acquire;
  try
    LState := GetOrCreateStateLocked(AReq.ParentForm);

    if LState.OwnerDestroying then
      LDiscard := True
    else if LState.Active then
    begin
      LState.Queue.Enqueue(AReq);
      Exit;
    end
    else
    begin
      LState.Active := True;
      LShowNow := True;
    end;
  finally
    FCrit.Release;
  end;

  if LDiscard then
  begin
    AReq.Free;
    Exit;
  end;

  if LShowNow then
    ShowRequestOnUI(AReq);
end;

procedure TDialog4DRegistry.OnDialogFinished(const AForm: TCommonCustomForm);
(*
  FIFO drain after a dialog completes.

  Strategy
  - Decide under FCrit, dispatch outside the lock.
  - Do not drain the FIFO for a form state that has entered owner-destroying
    mode. OnFormDestroyed will remove the state and discard pending requests.
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

    if LState.OwnerDestroying then
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

class procedure TDialog4D.SafeEmitTelemetry(const AData: TDialog4DTelemetry;
  const AProc: TDialog4DTelemetryProc);
begin
  if not Assigned(AProc) then
    Exit;

  try
    AProc(AData);
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

{ ========================= }
{ == Unit-scoped helpers == }
{ ========================= }

function CountMsgDlgButtons(const AButtons: TMsgDlgButtons): Integer;
var
  LBtn: TMsgDlgBtn;
begin
  Result := 0;
  for LBtn := Low(TMsgDlgBtn) to High(TMsgDlgBtn) do
    if LBtn in AButtons then
      Inc(Result);
end;

function HasStandardCancelButton(const AButtons: TMsgDlgButtons;
  const ATheme: TDialog4DTheme): Boolean;
begin
  Result := (TMsgDlgBtn.mbCancel in AButtons) or
    (ATheme.TreatCloseAsCancel and (TMsgDlgBtn.mbClose in AButtons));
end;

function ResolveStandardDefaultResult(const AButtons: TMsgDlgButtons;
  const ADefaultButton: TMsgDlgBtn): TModalResult;
var
  LBtn: TMsgDlgBtn;
begin
  if ADefaultButton in AButtons then
    Exit(TDialog4D.BtnToModalResult(ADefaultButton));

  for LBtn := Low(TMsgDlgBtn) to High(TMsgDlgBtn) do
    if LBtn in AButtons then
      Exit(TDialog4D.BtnToModalResult(LBtn));

  Result := mrNone;
end;

procedure ValidateCustomButtons(const AButtons: TArray<TDialog4DCustomButton>);
var
  I: Integer;
begin
  if Length(AButtons) = 0 then
    raise Exception.Create('Dialog4D: at least one button is required.');

  for I := 0 to High(AButtons) do
    if AButtons[I].ModalResult = mrNone then
      raise Exception.Create
        ('Dialog4D: custom buttons cannot use mrNone as ModalResult.');
end;

function HasCustomCancelButton(const AButtons: TArray<TDialog4DCustomButton>;
  const ATheme: TDialog4DTheme): Boolean;
var
  I: Integer;
begin
  Result := False;

  for I := 0 to High(AButtons) do
    if (AButtons[I].ModalResult = mrCancel) or
      (ATheme.TreatCloseAsCancel and (AButtons[I].ModalResult = mrClose)) then
      Exit(True);
end;

function ResolveCustomDefaultResult
  (const AButtons: TArray<TDialog4DCustomButton>): TModalResult;
var
  I: Integer;
begin
  for I := 0 to High(AButtons) do
    if AButtons[I].IsDefault then
      Exit(AButtons[I].ModalResult);

  if Length(AButtons) > 0 then
    Result := AButtons[0].ModalResult
  else
    Result := mrNone;
end;

procedure InitShowRequestedTelemetry(out AData: TDialog4DTelemetry;
  const ADialogType: TMsgDlgType; const ATitle: string;
  const AMessage: string);
begin
  AData := Default(TDialog4DTelemetry);
  AData.Kind := tkShowRequested;
  AData.DialogType := ADialogType;
  AData.Title := ATitle;
  AData.MessageLen := Length(AMessage);
  AData.Result := mrNone;
  AData.CloseReason := crNone;
  AData.Tick := TDialog4D.TickMs;
  AData.ElapsedMs := 0;
  AData.EventDateTime := Now;
end;

procedure RunOnMainThreadOrQueue(const AProc: TDialog4DProc);
begin
  if not Assigned(AProc) then
    Exit;

  if IsMainThreadSafe then
    AProc
  else
    QueueOnMainThread(AProc);
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
  - Validate thread-independent inputs immediately.
  - Capture configuration snapshots at call time:
      • theme
      • text provider
      • telemetry sink
      • callback
  - Execute parent-form resolution and registry handoff on the main thread.
  - Emit ShowRequested telemetry using the captured telemetry sink.

  Invariants
  - No Screen/Application fallback access is performed on a worker thread.
  - AButtons must contain at least one button.
*)
var
  LTheme: TDialog4DTheme;
  LProvider: IDialog4DTextProvider;
  LTelemetry: TDialog4DTelemetryProc;
  LOnResult: TDialog4DResultProc;
begin
  if AButtons = [] then
    raise Exception.Create('Dialog4D: at least one button is required.');

  LTheme := FTheme;
  LProvider := FTextProvider;
  if not Assigned(LProvider) then
    LProvider := TDialog4DDefaultTextProvider.Create;

  LTelemetry := FTelemetry;
  LOnResult := AOnResult;

  RunOnMainThreadOrQueue(
    procedure
    var
      LParentForm: TCommonCustomForm;
      LRequest: TDialog4DRequest;
      LData: TDialog4DTelemetry;
    begin
      LParentForm := ResolveParentForm(AParent);
      if not Assigned(LParentForm) then
        raise Exception.Create('Dialog4D: no parent form available.');

      LRequest := TDialog4DRequest.Create(LParentForm, AMessage, ADialogType,
        AButtons, ADefaultButton, LOnResult, ATitle, ACancelable, LTheme,
        LProvider, LTelemetry);

      InitShowRequestedTelemetry(LData, ADialogType, ATitle, AMessage);
      LData.ButtonsCount := CountMsgDlgButtons(AButtons);
      LData.HasCancelButton := HasStandardCancelButton(AButtons, LTheme);
      LData.DefaultResult := ResolveStandardDefaultResult(AButtons,
        ADefaultButton);

      SafeEmitTelemetry(LData, LTelemetry);

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
  - Copy the custom-button array immediately so later caller-side mutations
    cannot affect the queued request.
  - Validate the copied array, including rejecting mrNone.
  - Capture configuration snapshots at call time.
  - Execute parent-form resolution and registry handoff on the main thread.

  Invariants
  - No Screen/Application fallback access is performed on a worker thread.
  - The custom button array stored in the request is independent from the
    caller's local dynamic array after this method returns.
*)
var
  LTheme: TDialog4DTheme;
  LProvider: IDialog4DTextProvider;
  LTelemetry: TDialog4DTelemetryProc;
  LOnResult: TDialog4DResultProc;
  LButtons: TArray<TDialog4DCustomButton>;
begin
  LButtons := Copy(AButtons);
  ValidateCustomButtons(LButtons);

  LTheme := FTheme;
  LProvider := FTextProvider;
  if not Assigned(LProvider) then
    LProvider := TDialog4DDefaultTextProvider.Create;

  LTelemetry := FTelemetry;
  LOnResult := AOnResult;

  RunOnMainThreadOrQueue(
    procedure
    var
      LParentForm: TCommonCustomForm;
      LRequest: TDialog4DRequest;
      LData: TDialog4DTelemetry;
    begin
      LParentForm := ResolveParentForm(AParent);
      if not Assigned(LParentForm) then
        raise Exception.Create('Dialog4D: no parent form available.');

      LRequest := TDialog4DRequest.CreateCustom(LParentForm, AMessage,
        ADialogType, LButtons, LOnResult, ATitle, ACancelable, LTheme,
        LProvider, LTelemetry);

      InitShowRequestedTelemetry(LData, ADialogType, ATitle, AMessage);
      LData.ButtonsCount := Length(LButtons);
      LData.HasCancelButton := HasCustomCancelButton(LButtons, LTheme);
      LData.DefaultResult := ResolveCustomDefaultResult(LButtons);

      SafeEmitTelemetry(LData, LTelemetry);

      if Assigned(GRegistry) then
        GRegistry.EnqueueOrShow(LRequest)
      else
        LRequest.Free;
    end);
end;

class procedure TDialog4D.CloseDialog(const AForm: TCommonCustomForm;
const AResult: TModalResult);
begin
  RunOnMainThreadOrQueue(
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

