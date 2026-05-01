// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Eduardo P. Araujo
// https://github.com/eduardoparaujo/Dialog4D

{*
  Unit   : Dialog4D.Internal.Queue
  Purpose: Internal queue helper for Dialog4D. Schedules anonymous
           procedures for asynchronous execution on the main thread via
           TThread.ForceQueue.

  Internal unit of the Dialog4D runtime library.

  Author        : Eduardo P. Araujo
  Created       : 2026-04-26
  Last modified : 2026-05-01
  Version       : 1.0.1

  Notes:
    - This unit centralizes the "queue work onto the main thread" pattern so
      it is not duplicated across Dialog4D, Dialog4D.Host.FMX and
      Dialog4D.Await.

    - Design notes:
        • Safe to call from any thread, including the main thread itself.
        • Execution is asynchronous and fire-and-forget — there is no return
          value and no completion signal.
        • TThread.ForceQueue is intentionally used instead of TThread.Queue so
          calls made from the main thread are still queued asynchronously.
        • Nil procedures are silently ignored — callers do not need to guard
          Assigned() before calling QueueOnMainThread.

  Important:
    - This is an internal utility unit and should not be used directly from
      application code.

    - A self-freeing wrapper (TDialog4DQueuedCall) carries the anonymous
      procedure across the thread boundary. The wrapper is freed after the
      procedure runs, even if the procedure raises. Any exception is re-raised
      only after the wrapper has already been disposed of.

    - If the queue operation itself fails, the wrapper is freed immediately
      before the exception is re-raised, avoiding a leak on enqueue failure.

  History:
    1.0.1 — 2026-05-01 — Queue semantics correction.
      • Replaced TThread.Queue with TThread.ForceQueue to make the helper
        consistently asynchronous, including when called from the main thread.
      • Added exception protection around the queue operation so the internal
        wrapper is freed if the enqueue operation fails.
      • Updated the unit documentation to remove ambiguity around asynchronous
        execution semantics.
      • Centralized IsMainThreadSafe in this unit so the public facade
        (Dialog4D.pas) and the await helper (Dialog4D.Await.pas) share a
        single thread-decision primitive.

    1.0.0 — 2026-04-26 — Initial public release.
      • Introduced QueueOnMainThread as the shared internal helper for
        main-thread dispatch.
      • Added a self-freeing wrapper to safely carry anonymous procedures
        across the thread boundary.
*}

unit Dialog4D.Internal.Queue;

interface

type
  /// <summary>
  /// Anonymous procedure reference used to queue work onto the main thread.
  /// </summary>
  TDialog4DProc = reference to procedure;

  /// <summary>
  /// Returns <c>True</c> when the calling thread is the application main
  /// thread.
  /// </summary>
  /// <remarks>
  /// <para>
  /// Used by Dialog4D internal marshaling decisions: when the caller is already
  /// on the main thread, some handoff work can run inline; otherwise it must be
  /// queued via <c>QueueOnMainThread</c>.
  /// </para>
  /// </remarks>
  function IsMainThreadSafe: Boolean;

  /// <summary>
  /// Schedules the execution of an anonymous procedure asynchronously on the
  /// main thread using <c>TThread.ForceQueue</c>.
  /// </summary>
  /// <remarks>
  /// <para>
  /// • Safe to call from any thread, including the main thread itself.
  /// </para>
  /// <para>
  /// • If <c>AProc</c> is <c>nil</c> the call is silently ignored.
  /// </para>
  /// <para>
  /// • Execution is asynchronous and fire-and-forget.
  /// </para>
  /// <para>
  /// • <c>TThread.ForceQueue</c> is used intentionally so calls made from the
  /// main thread are still queued instead of being executed inline.
  /// </para>
  /// <para>
  /// • The internal wrapper object is always freed after execution, even if
  /// <c>AProc</c> raises an exception. If the queue operation itself fails,
  /// the wrapper is freed immediately before the exception is re-raised.
  /// </para>
  /// </remarks>
  procedure QueueOnMainThread(const AProc: TDialog4DProc);

implementation

uses
  System.Classes;

{ ========================================================= }
{ == Internal wrapper — self-freeing main-thread carrier == }
{ ========================================================= }

type
  /// <summary>
  /// Self-freeing wrapper that carries an anonymous procedure to the main
  /// thread via <c>TThread.ForceQueue</c>.
  /// </summary>
  /// <remarks>
  /// <para>
  /// The <c>Execute</c> method is used directly as a <c>TThreadProcedure</c>
  /// by <c>TThread.ForceQueue</c>.
  /// </para>
  /// </remarks>
  TDialog4DQueuedCall = class
  private
    FProc: TDialog4DProc;
  public
    constructor Create(const AProc: TDialog4DProc);

    /// <summary>
    /// Executes the stored procedure and frees this object.
    /// </summary>
    /// <remarks>
    /// <para>Used as a <c>TThreadProcedure</c> by <c>TThread.ForceQueue</c>.</para>
    /// </remarks>
    procedure Execute;
  end;

constructor TDialog4DQueuedCall.Create(const AProc: TDialog4DProc);
begin
  inherited Create;
  FProc := AProc;
end;

procedure TDialog4DQueuedCall.Execute;
(*
  Self-freeing main-thread execution.

  Strategy
  - Move the procedure reference to a local variable and clear the field
    BEFORE running the procedure. This guarantees the wrapper does not
    keep a strong reference to the closure while the closure runs.
  - Run the procedure inside a try/finally so the wrapper is always freed,
    even if the procedure raises.

  Outcomes
  - On success: the procedure ran and the wrapper is freed.
  - On exception: the wrapper is freed first, then the exception propagates
    out of the queued call and is surfaced by the main-thread queue
    processing mechanism.

  Invariants
  - This method runs exactly once per wrapper instance.
  - After Free, the instance must not be touched.
*)
var
  LProc: TDialog4DProc;
begin
  LProc := FProc;
  FProc := nil;

  try
    if Assigned(LProc) then
      LProc;
  finally
    Free;
  end;
end;

function IsMainThreadSafe: Boolean;
begin
  Result := TThread.CurrentThread.ThreadID = MainThreadID;
end;

{ =================== }
{ == Public helper == }
{ =================== }

procedure QueueOnMainThread(const AProc: TDialog4DProc);
var
  LCall: TDialog4DQueuedCall;
begin
  if not Assigned(AProc) then
    Exit;

  LCall := TDialog4DQueuedCall.Create(AProc);
  try
    TThread.ForceQueue(nil, LCall.Execute);
  except
    LCall.Free;
    raise;
  end;
end;

end.
