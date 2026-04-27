// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Eduardo P. Araujo
// https://github.com/eduardoparaujo/Dialog4D

{*
  Unit   : Dialog4D.Await
  Purpose: Worker-thread await helper for Dialog4D. Allows a background
           thread to wait for a dialog result while keeping dialog
           presentation on the main thread.

  Part of the Dialog4D framework - see Dialog4D.Types for the overview.

  Author        : Eduardo P. Araujo
  Created       : 2026-04-26
  Last modified : 2026-04-26
  Version       : 1.0.0

  Notes:
    - TDialog4DAwait provides two API flavors for each button shape:
      (1) smart overloads (MessageDialog), which work in any thread context;
      (2) OnWorker overloads (MessageDialogOnWorker), which are worker-thread
      only and block until completion or timeout.

    - Smart overloads:
      * Main thread  -> delegate to MessageDialogAsync (non-blocking)
      * Worker thread -> delegate to MessageDialogOnWorker (blocking)

    - OnWorker overloads:
      * Must NOT be called from the main thread
      * Raise EDialog4DAwait if used on the main thread
      * Return dasCompleted when the user responds
      * Return dasTimedOut when the wait expires before completion

    - Timeout semantics:
      * Default timeout is 5 minutes (300_000 ms)
      * Timeout does NOT close the dialog
      * The worker simply gives up waiting
      * On dasTimedOut the worker receives mrNone and the callback is not called

  Internal design:
    - An IDialog4DAwaitState carries a TEvent, result, error string and
      completed flag across the thread boundary.
    - The visual dialog is created by MessageDialogAsync on the main thread,
      queued through QueueOnMainThread.
    - The worker thread waits on the event with the requested timeout.
*}

unit Dialog4D.Await;

interface

uses
  System.Classes,
  System.SyncObjs,
  System.SysUtils,
  System.UITypes,

  FMX.Forms,

  Dialog4D.Types;

type
  { ================== }
  { == Public types == }
  { ================== }

  /// <summary>
  /// Result status of a worker-thread await.
  /// </summary>
  /// <remarks>
  /// <para>
  /// • <c>dasCompleted</c> — the user closed the dialog and the result is valid.
  /// </para>
  /// <para>
  /// • <c>dasTimedOut</c> — the configured timeout elapsed before the user closed
  /// the dialog. The dialog is left on screen; only the worker stopped waiting.
  /// </para>
  /// </remarks>
  TDialog4DAwaitStatus = (dasCompleted, dasTimedOut);

  /// <summary>
  /// Exception type raised by <c>Dialog4D.Await</c> for invariant violations
  /// (calling <c>MessageDialogOnWorker</c> from the main thread, empty button
  /// set, internal show errors).
  /// </summary>
  EDialog4DAwait = class(Exception);

  { ================== }
  { == Facade class == }
  { ================== }

  /// <summary>
  /// Helper API that allows a background thread to wait for the result of
  /// a <c>Dialog4D</c> dialog without blocking the UI thread.
  /// </summary>
  TDialog4DAwait = class
  public

    { ================================================ }
    { == Standard button overloads (TMsgDlgButtons) == }
    { ================================================ }

    /// <summary>
    /// Smart method — works in any thread context.
    /// </summary>
    /// <remarks>
    /// <para><b>Main thread:</b> async, non-blocking.</para>
    /// <para><b>Worker thread:</b> blocks until result.</para>
    /// <para><b>ACallbackOnMain:</b> when <c>True</c> and called from a worker thread, the callback is re-dispatched to the main thread automatically.</para>
    /// </remarks>
    class procedure MessageDialog(const AMessage: string;
      const ADialogType: TMsgDlgType; const AButtons: TMsgDlgButtons;
      const ADefaultButton: TMsgDlgBtn; const AOnResult: TDialog4DResultProc;
      const ATitle: string = ''; const AParent: TCommonCustomForm = nil;
      const ACancelable: Boolean = True; const ACallbackOnMain: Boolean = False;
      const ATimeoutMs: Cardinal = 300_000); overload; static;

    /// <summary>
    /// Low-level worker-thread only. Blocks the calling thread.
    /// </summary>
    /// <remarks>
    /// <para>Must <b>NOT</b> be called from the main thread (raises <c>EDialog4DAwait</c>).</para>
    /// </remarks>
    /// <exception cref="EDialog4DAwait">
    /// Raised when called from the main thread, when the button set is empty,
    /// or when an internal show error occurs.
    /// </exception>
    class function MessageDialogOnWorker(const AMessage: string;
      const ADialogType: TMsgDlgType; const AButtons: TMsgDlgButtons;
      const ADefaultButton: TMsgDlgBtn; out AStatus: TDialog4DAwaitStatus;
      const ATitle: string = ''; const AParent: TCommonCustomForm = nil;
      const ACancelable: Boolean = True; const ATimeoutMs: Cardinal = 300_000)
      : TModalResult; overload; static;

    { ============================================================= }
    { == Custom button overloads (TArray<TDialog4DCustomButton>) == }
    { ============================================================= }

    /// <summary>
    /// Smart method — works in any thread context — using custom buttons.
    /// </summary>
    /// <remarks>
    /// <para><b>Main thread:</b> async, non-blocking.</para>
    /// <para><b>Worker thread:</b> blocks until result.</para>
    /// <para><b>ACallbackOnMain:</b> when <c>True</c> and called from a worker thread, the callback is re-dispatched to the main thread automatically.</para>
    /// <para><b>Example from a worker thread:</b></para>
    /// <code>
    /// TDialog4DAwait.MessageDialog(
    ///   'File already exists. What should we do?',
    ///   TMsgDlgType.mtWarning,
    ///   [
    ///     TDialog4DCustomButton.Default('Replace',   mrYes),
    ///     TDialog4DCustomButton.Make('Keep Both',    mrNo),
    ///     TDialog4DCustomButton.Cancel('Cancel')
    ///   ],
    ///   procedure(const R: TModalResult)
    ///   begin
    ///     case R of
    ///       mrYes: ReplaceFile;
    ///       mrNo:  KeepBoth;
    ///     end;
    ///   end
    /// );
    /// </code>
    /// </remarks>
    class procedure MessageDialog(const AMessage: string;
      const ADialogType: TMsgDlgType;
      const AButtons: TArray<TDialog4DCustomButton>;
      const AOnResult: TDialog4DResultProc; const ATitle: string = '';
      const AParent: TCommonCustomForm = nil; const ACancelable: Boolean = True;
      const ACallbackOnMain: Boolean = False;
      const ATimeoutMs: Cardinal = 300_000); overload; static;

    /// <summary>
    /// Low-level worker-thread only — using custom buttons.
    /// Blocks the calling thread until the user responds or timeout expires.
    /// </summary>
    /// <remarks>
    /// <para>Must <b>NOT</b> be called from the main thread (raises <c>EDialog4DAwait</c>).</para>
    /// </remarks>
    /// <exception cref="EDialog4DAwait">
    /// Raised when called from the main thread, when the button set is empty,
    /// or when an internal show error occurs.
    /// </exception>
    class function MessageDialogOnWorker(const AMessage: string;
      const ADialogType: TMsgDlgType;
      const AButtons: TArray<TDialog4DCustomButton>;
      out AStatus: TDialog4DAwaitStatus; const ATitle: string = '';
      const AParent: TCommonCustomForm = nil; const ACancelable: Boolean = True;
      const ATimeoutMs: Cardinal = 300_000): TModalResult; overload; static;

  end;

implementation

uses
  Dialog4D,
  Dialog4D.Internal.Queue;

{ ==================================== }
{ == Internal helpers (unit-scoped) == }
{ ==================================== }

/// <summary>
/// Returns <c>True</c> when the caller is on the main thread.
/// </summary>
/// <remarks>
/// <para>
/// Uses <c>TThread.CurrentThread.ThreadID</c> directly rather than going
/// through <c>TThread.Current</c>, which can return <c>nil</c> for native
/// callbacks. This makes the result reliable for all execution contexts.
/// </para>
/// </remarks>
function IsMainThreadSafe: Boolean;
begin
  Result := TThread.CurrentThread.ThreadID = MainThreadID;
end;

{ ============================================== }
{ == Internal await-state interface and class == }
{ ============================================== }

type
  /// <summary>
  /// Internal carrier interface used to ferry the dialog result, error and
  /// completion signal across the thread boundary between the worker and the
  /// main-thread show callback.
  /// </summary>
  IDialog4DAwaitState = interface
    ['{D18D4D1C-13C9-4F9F-9844-2A4A5B6D8F41}']
    function GetEvent: TEvent;
    function GetResultValue: TModalResult;
    procedure SetResultValue(const Value: TModalResult);
    function GetShowError: string;
    procedure SetShowError(const Value: string);
    function GetCompleted: Boolean;
    procedure SetCompleted(const Value: Boolean);

    property Event: TEvent read GetEvent;
    property ResultValue: TModalResult read GetResultValue write SetResultValue;
    property ShowError: string read GetShowError write SetShowError;
    property Completed: Boolean read GetCompleted write SetCompleted;
  end;

  /// <summary>
  /// Default <c>IDialog4DAwaitState</c> implementation.
  /// Owns a manual-reset <c>TEvent</c> created in the unsignaled state.
  /// </summary>
  /// <remarks>
  /// <para>
  /// This class is not thread-safe in the strict sense — readers and writers
  /// do not synchronize via locks.
  /// </para>
  /// <para>
  /// Safety relies on the happens-before guarantee of <c>TEvent.SetEvent</c>:
  /// the worker only reads the <c>result</c>, <c>error</c> and <c>completed</c>
  /// fields <b>after</b> <c>WaitFor</c> returns, by which point the writer
  /// has already issued <c>SetEvent</c>.
  /// </para>
  /// </remarks>
  TDialog4DAwaitState = class(TInterfacedObject, IDialog4DAwaitState)
  private
    FEvent: TEvent;
    FResultValue: TModalResult;
    FShowError: string;
    FCompleted: Boolean;

    function GetEvent: TEvent;
    function GetResultValue: TModalResult;
    procedure SetResultValue(const Value: TModalResult);
    function GetShowError: string;
    procedure SetShowError(const Value: string);
    function GetCompleted: Boolean;
    procedure SetCompleted(const Value: Boolean);
  public
    constructor Create;
    destructor Destroy; override;
  end;

constructor TDialog4DAwaitState.Create;
begin
  inherited Create;
  // Manual reset, initial state unsignaled — the worker will wait on this
  // event until the show callback signals completion (or an error occurs
  // while scheduling the dialog).
  FEvent := TEvent.Create(nil, True, False, '');
  FResultValue := mrNone;
  FShowError := '';
  FCompleted := False;
end;

destructor TDialog4DAwaitState.Destroy;
begin
  FEvent.Free;
  inherited;
end;

function TDialog4DAwaitState.GetEvent: TEvent;
begin
  Result := FEvent;
end;

function TDialog4DAwaitState.GetResultValue: TModalResult;
begin
  Result := FResultValue;
end;

function TDialog4DAwaitState.GetShowError: string;
begin
  Result := FShowError;
end;

function TDialog4DAwaitState.GetCompleted: Boolean;
begin
  Result := FCompleted;
end;

procedure TDialog4DAwaitState.SetResultValue(const Value: TModalResult);
begin
  FResultValue := Value;
end;

procedure TDialog4DAwaitState.SetShowError(const Value: string);
begin
  FShowError := Value;
end;

procedure TDialog4DAwaitState.SetCompleted(const Value: Boolean);
begin
  FCompleted := Value;
end;

{ ================================================ }
{ == TDialog4DAwait — standard button overloads == }
{ ================================================ }

class procedure TDialog4DAwait.MessageDialog(const AMessage: string;
  const ADialogType: TMsgDlgType; const AButtons: TMsgDlgButtons;
  const ADefaultButton: TMsgDlgBtn; const AOnResult: TDialog4DResultProc;
  const ATitle: string; const AParent: TCommonCustomForm;
  const ACancelable: Boolean; const ACallbackOnMain: Boolean;
  const ATimeoutMs: Cardinal);
var
  LResult: TModalResult;
  LStatus: TDialog4DAwaitStatus;
begin
  if IsMainThreadSafe then
  begin
    // Main-thread path: there is no thread to block, so just dispatch the
    // standard async call. ACallbackOnMain is irrelevant here — the
    // callback already fires on the main thread.
    TDialog4D.MessageDialogAsync(AMessage, ADialogType, AButtons,
      ADefaultButton, AOnResult, ATitle, AParent, ACancelable);
  end
  else
  begin
    // Worker-thread path: block on the OnWorker variant, then deliver the
    // callback either inline (worker) or re-dispatched to the main thread.
    LResult := MessageDialogOnWorker(AMessage, ADialogType, AButtons,
      ADefaultButton, LStatus, ATitle, AParent, ACancelable, ATimeoutMs);

    if Assigned(AOnResult) then
    begin
      if ACallbackOnMain then
        QueueOnMainThread(
          procedure
          begin
            AOnResult(LResult);
          end)
      else
        AOnResult(LResult);
    end;
  end;
end;

class function TDialog4DAwait.MessageDialogOnWorker(const AMessage: string;
  const ADialogType: TMsgDlgType; const AButtons: TMsgDlgButtons;
  const ADefaultButton: TMsgDlgBtn; out AStatus: TDialog4DAwaitStatus;
  const ATitle: string; const AParent: TCommonCustomForm;
  const ACancelable: Boolean; const ATimeoutMs: Cardinal): TModalResult;
(*
  Worker-thread blocking call (standard buttons).

  Strategy
  - Build a shared IDialog4DAwaitState that ferries result, error and
    completion flag across the thread boundary.
  - Schedule the actual dialog presentation on the main thread via
    QueueOnMainThread, so the UI work stays where it belongs.
  - Block the worker on LState.Event.WaitFor with the requested timeout.

  Outcomes
  - WaitFor returns wrSignaled with no error: dialog completed normally,
    return the user's TModalResult and dasCompleted.
  - WaitFor returns wrSignaled with ShowError set: scheduling the dialog
    raised on the main thread, re-raise as EDialog4DAwait.
  - WaitFor times out: the dialog is still on screen and remains visible
    for the user; only the worker gives up. Return mrNone and dasTimedOut.

  Invariants
  - This method must not be called from the main thread (raises).
  - At least one button must be supplied (raises).
  - LState lives until the show callback (or its error path) signals the
    event; the closure holds a strong interface reference for that purpose.
*)
var
  LState: IDialog4DAwaitState;
  LWaitResult: TWaitResult;
begin
  AStatus := dasTimedOut;

  if IsMainThreadSafe then
    raise EDialog4DAwait.Create
      ('Dialog4D.Await: MessageDialogOnWorker cannot be called on the main thread. '
      + 'Use MessageDialog for automatic compatibility.');

  if AButtons = [] then
    raise EDialog4DAwait.Create
      ('Dialog4D.Await: At least one button is required.');

  LState := TDialog4DAwaitState.Create;

  // Schedule dialog presentation on the main thread. The closure captures
  // LState as a strong interface reference so the state object stays alive
  // until the show callback (or its error path) signals the event.
  QueueOnMainThread(
    procedure
    var
      LAsyncState: IDialog4DAwaitState;
    begin
      LAsyncState := LState;
      try
        TDialog4D.MessageDialogAsync(AMessage, ADialogType, AButtons,
          ADefaultButton,
          procedure(const AResult: TModalResult)
          begin
            LAsyncState.ResultValue := AResult;
            LAsyncState.Completed := True;
            LAsyncState.Event.SetEvent;
          end, ATitle, AParent, ACancelable);
      except
        on E: Exception do
        begin
          // Capture the show error and unblock the worker; the worker will
          // re-raise as EDialog4DAwait below.
          LAsyncState.ShowError := E.Message;
          LAsyncState.Event.SetEvent;
        end;
      end;
    end);

  LWaitResult := LState.Event.WaitFor(ATimeoutMs);

  // Timeout: the dialog is still on screen — only the worker gave up.
  if LWaitResult <> TWaitResult.wrSignaled then
    Exit(mrNone);

  if LState.ShowError <> '' then
    raise EDialog4DAwait.Create('Dialog4D.Await: Failed to show dialog. ' +
      LState.ShowError);

  // Defensive: signaled but not completed should not happen unless the
  // show error path raced. Fall through as mrNone / dasTimedOut.
  if not LState.Completed then
    Exit(mrNone);

  AStatus := dasCompleted;
  Result := LState.ResultValue;
end;

{ ============================================== }
{ == TDialog4DAwait — custom button overloads == }
{ ============================================== }

class procedure TDialog4DAwait.MessageDialog(const AMessage: string;
  const ADialogType: TMsgDlgType; const AButtons: TArray<TDialog4DCustomButton>;
  const AOnResult: TDialog4DResultProc; const ATitle: string;
  const AParent: TCommonCustomForm; const ACancelable: Boolean;
  const ACallbackOnMain: Boolean; const ATimeoutMs: Cardinal);
var
  LResult: TModalResult;
  LStatus: TDialog4DAwaitStatus;
begin
  if IsMainThreadSafe then
  begin
    // Main-thread path: dispatch the standard async call directly.
    TDialog4D.MessageDialogAsync(AMessage, ADialogType, AButtons, AOnResult,
      ATitle, AParent, ACancelable);
  end
  else
  begin
    // Worker-thread path: block on the OnWorker variant.
    LResult := MessageDialogOnWorker(AMessage, ADialogType, AButtons, LStatus,
      ATitle, AParent, ACancelable, ATimeoutMs);

    if Assigned(AOnResult) then
    begin
      if ACallbackOnMain then
        QueueOnMainThread(
          procedure
          begin
            AOnResult(LResult);
          end)
      else
        AOnResult(LResult);
    end;
  end;
end;

class function TDialog4DAwait.MessageDialogOnWorker(const AMessage: string;
  const ADialogType: TMsgDlgType; const AButtons: TArray<TDialog4DCustomButton>;
  out AStatus: TDialog4DAwaitStatus; const ATitle: string;
  const AParent: TCommonCustomForm; const ACancelable: Boolean;
  const ATimeoutMs: Cardinal): TModalResult;
(*
  Worker-thread blocking call (custom buttons).

  Strategy
  - Same pattern as the standard-buttons overload: a shared
    IDialog4DAwaitState carries result, error and completion flag across
    the thread boundary, and the dialog is presented on the main thread
    via QueueOnMainThread. The worker blocks on LState.Event.WaitFor with
    the requested timeout.

  Outcomes
  - wrSignaled with no error: dialog completed normally, return the
    selected TModalResult and dasCompleted.
  - wrSignaled with ShowError: scheduling the dialog raised on the main
    thread, re-raise as EDialog4DAwait.
  - WaitFor times out: the dialog stays on screen, the worker returns
    mrNone and dasTimedOut.

  Invariants
  - This method must not be called from the main thread (raises).
  - At least one custom button must be supplied (raises).
  - LState lives until the show callback (or its error path) signals the
    event; the closure holds a strong interface reference for that purpose.
*)
var
  LState: IDialog4DAwaitState;
  LWaitResult: TWaitResult;
begin
  AStatus := dasTimedOut;

  if IsMainThreadSafe then
    raise EDialog4DAwait.Create
      ('Dialog4D.Await: MessageDialogOnWorker cannot be called on the main thread. '
      + 'Use MessageDialog for automatic compatibility.');

  if Length(AButtons) = 0 then
    raise EDialog4DAwait.Create
      ('Dialog4D.Await: At least one button is required.');

  LState := TDialog4DAwaitState.Create;

  // Schedule custom-button dialog on the main thread. Same closure pattern
  // as the standard overload — see comment there for ownership details.
  QueueOnMainThread(
    procedure
    var
      LAsyncState: IDialog4DAwaitState;
    begin
      LAsyncState := LState;
      try
        TDialog4D.MessageDialogAsync(AMessage, ADialogType, AButtons,
          procedure(const AResult: TModalResult)
          begin
            LAsyncState.ResultValue := AResult;
            LAsyncState.Completed := True;
            LAsyncState.Event.SetEvent;
          end, ATitle, AParent, ACancelable);
      except
        on E: Exception do
        begin
          LAsyncState.ShowError := E.Message;
          LAsyncState.Event.SetEvent;
        end;
      end;
    end);

  LWaitResult := LState.Event.WaitFor(ATimeoutMs);

  if LWaitResult <> TWaitResult.wrSignaled then
    Exit(mrNone);

  if LState.ShowError <> '' then
    raise EDialog4DAwait.Create('Dialog4D.Await: Failed to show dialog. ' +
      LState.ShowError);

  if not LState.Completed then
    Exit(mrNone);

  AStatus := dasCompleted;
  Result := LState.ResultValue;
end;

end.
