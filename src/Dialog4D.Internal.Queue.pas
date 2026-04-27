// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Eduardo P. Araujo
// https://github.com/eduardoparaujo/Dialog4D

{*
  Unit   : Dialog4D.Internal.Queue
  Purpose: Internal queue helper for Dialog4D. Schedules anonymous
           procedures for execution on the main thread via TThread.Queue.

  Part of the Dialog4D framework.

  Author        : Eduardo P. Araujo
  Created       : 2026-04-26
  Last modified : 2026-04-26
  Version       : 1.0.0

  Notes:
    - This unit centralizes the "queue work onto the main thread" pattern so
      it is not duplicated across Dialog4D, Dialog4D.Host.FMX and
      Dialog4D.Await.

    - Design notes:
        * Safe to call from any thread, including the main thread itself.
        * Execution is asynchronous and fire-and-forget — there is no return
          value and no completion signal.
        * Nil procedures are silently ignored — callers do not need to guard
          Assigned() before calling QueueOnMainThread.

  Important:
    - This is an internal utility unit and should not be used directly from
      application code.
    - A self-freeing wrapper (TDialog4DQueuedCall) carries the anonymous
      procedure across the thread boundary. The wrapper is always freed,
      even if the procedure raises. Any exception is re-raised only after
      the wrapper has already been disposed of.
*}

unit Dialog4D.Internal.Queue;

interface

type
  /// <summary>
  /// Anonymous procedure reference used to queue work onto the main thread.
  /// </summary>
  TDialog4DProc = reference to procedure;

  /// <summary>
  /// Schedules the execution of an anonymous procedure on the main thread
  /// using <c>TThread.Queue</c>.
  /// </summary>
  /// <remarks>
  /// <para>• Safe to call from any thread, including the main thread itself.</para>
  /// <para>• If <c>AProc</c> is <c>nil</c> the call is silently ignored.</para>
  /// <para>• Execution is asynchronous and fire-and-forget.</para>
  /// <para>
  /// • The internal wrapper object is always freed, even if <c>AProc</c> raises
  /// an exception (the exception is re-raised after the wrapper is freed).
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
  /// thread via <c>TThread.Queue</c>.
  /// </summary>
  /// <remarks>
  /// <para>
  /// The <c>Execute</c> method is used directly as a <c>TThreadProcedure</c>
  /// by <c>TThread.Queue</c>.
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
    /// <para>Used as a <c>TThreadProcedure</c> by <c>TThread.Queue</c>.</para>
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
    keep a strong reference to the closure while the closure runs (which
    could matter if the closure indirectly references this wrapper).
  - Run the procedure inside a try/finally so the wrapper is always freed,
    even if the procedure raises.

  Outcomes
  - On success: the procedure ran and the wrapper is freed.
  - On exception: the wrapper is freed first, then the exception
    propagates out (TThread.Queue will surface it on the main thread).

  Invariants
  - This method runs exactly once per wrapper instance. After Free, the
    instance must not be touched.
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
  TThread.Queue(nil, LCall.Execute);
end;

end.
