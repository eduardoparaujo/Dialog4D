// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Eduardo P. Araujo
// https://github.com/eduardoparaujo/Dialog4D

{*
  Unit   : Dialog4D.Tests.Internal.Queue
  Purpose: Validation tests for Dialog4D.Internal.Queue.

           This fixture verifies the behavior of QueueOnMainThread, the shared
           internal helper used to dispatch anonymous procedures to the main
           thread. The covered contract includes:
             - queued procedures are eventually executed
             - nil procedures are safely ignored
             - queued calls preserve submission order
             - calls made from the main thread are not executed inline

           These tests exercise the public observable behavior of the helper.
           They do not attempt to inspect the internal wrapper implementation.

  Part of the Dialog4D automated test suite.

  Author        : Eduardo P. Araujo
  Created       : 2026-04-26
  Last modified : 2026-05-01
  Version       : 1.0.1

  Notes:
    - Uses Dialog4D.Tests.Support.WaitUntil to pump the main thread and wait
      deterministically for queued work to execute.
    - Timing values are intentionally conservative to reduce flakiness in
      slower local or CI environments.
    - The inline-execution test protects the intended TThread.ForceQueue
      behavior: even when called from the main thread, the procedure must
      execute asynchronously after the queue is pumped.

  History:
    1.0.1 — 2026-05-01 — Queue dispatch regression coverage.
      • Added QueueOnMainThread_CalledFromMainThread_DoesNotExecuteInline
        to protect the asynchronous ForceQueue contract introduced in
        Dialog4D.Internal.Queue 1.0.1.

    1.0.0 — 2026-04-26 — Initial public release.
      • Added tests for queued execution, nil handling, and execution order.
*}

unit Dialog4D.Tests.Internal.Queue;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TDialog4DInternalQueueTests = class
  public
    [Test]
    procedure QueueOnMainThread_ExecutesQueuedProc;

    [Test]
    procedure QueueOnMainThread_IgnoresNil;

    [Test]
    procedure QueueOnMainThread_PreservesExecutionOrder;

    [Test]
    procedure QueueOnMainThread_CalledFromMainThread_DoesNotExecuteInline;
  end;

implementation

uses
  Dialog4D.Internal.Queue,
  Dialog4D.Tests.Support;

procedure TDialog4DInternalQueueTests.QueueOnMainThread_ExecutesQueuedProc;
var
  LExecuted: Boolean;
begin
  LExecuted := False;

  QueueOnMainThread(
    procedure
    begin
      LExecuted := True;
    end
  );

  Assert.IsTrue(
    TDialog4DTestSupport.WaitUntil(
      function: Boolean
      begin
        Result := LExecuted;
      end,
      2000,
      10
    ),
    'The queued procedure was not executed on the main thread.'
  );
end;

procedure TDialog4DInternalQueueTests.QueueOnMainThread_IgnoresNil;
begin
  QueueOnMainThread(nil);
  Assert.Pass;
end;

procedure TDialog4DInternalQueueTests.QueueOnMainThread_PreservesExecutionOrder;
var
  LTrace: string;
begin
  LTrace := '';

  QueueOnMainThread(
    procedure
    begin
      LTrace := LTrace + 'A';
    end
  );

  QueueOnMainThread(
    procedure
    begin
      LTrace := LTrace + 'B';
    end
  );

  QueueOnMainThread(
    procedure
    begin
      LTrace := LTrace + 'C';
    end
  );

  Assert.IsTrue(
    TDialog4DTestSupport.WaitUntil(
      function: Boolean
      begin
        Result := LTrace = 'ABC';
      end,
      2000,
      10
    ),
    'Queued procedures were not executed in the expected order.'
  );
end;

procedure TDialog4DInternalQueueTests.QueueOnMainThread_CalledFromMainThread_DoesNotExecuteInline;
var
  LExecuted: Boolean;
begin
  LExecuted := False;

  QueueOnMainThread(
    procedure
    begin
      LExecuted := True;
    end
  );

  Assert.IsFalse(
    LExecuted,
    'QueueOnMainThread executed inline. Expected asynchronous ForceQueue behavior.'
  );

  Assert.IsTrue(
    TDialog4DTestSupport.WaitUntil(
      function: Boolean
      begin
        Result := LExecuted;
      end,
      2000,
      10
    ),
    'The queued procedure was not executed after pumping the main thread.'
  );
end;

initialization
  TDUnitX.RegisterTestFixture(TDialog4DInternalQueueTests);

end.
