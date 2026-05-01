// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Eduardo P. Araujo
// https://github.com/eduardoparaujo/Dialog4D

{*
  Unit   : Dialog4D.Tests.Await.Core
  Purpose: Core validation tests for Dialog4D.Await.

           This test fixture focuses on the basic contract of the await helper:
             - worker-only APIs must reject usage from the main thread
             - invalid async input must still be validated on the main thread
             - worker timeout must not invoke the smart overload callback

           These tests do not validate visual interaction. They verify the core
           guardrails and error paths that define correct usage of
           TDialog4DAwait.

  Part of the Dialog4D automated test suite.

  Author        : Eduardo P. Araujo
  Created       : 2026-04-26
  Last modified : 2026-05-01
  Version       : 1.0.1

  Notes:
    - Uses TForm.CreateNew(nil) to avoid any dependency on FMX form resources
      where a form is explicitly required.
    - Keeps assertions explicit and deterministic, especially for exception
      message validation.
    - The timeout callback test intentionally avoids showing a real dialog:
      it allows the worker to time out before the queued main-thread show
      attempt is pumped, then drains the queue using a failing text provider
      so no visual host remains active after the test.

  History:
    1.0.1 — 2026-05-01 — Await timeout regression coverage.
      • Added MessageDialog_WorkerTimeout_DoesNotInvokeCallback to protect
        the documented timeout contract: on dasTimedOut, the smart overload
        must not invoke the user callback.
      • Added deterministic queue draining after timeout so the queued
        main-thread show attempt does not remain pending after the test.

    1.0.0 — 2026-04-26 — Initial public release.
      • Added main-thread guard tests for MessageDialogOnWorker.
      • Added validation test for empty button sets through the smart overload.
*}

unit Dialog4D.Tests.Await.Core;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TDialog4DAwaitCoreTests = class
  public
    [Test]
    procedure MessageDialogOnWorker_CalledFromMainThread_Raises;

    [Test]
    procedure MessageDialog_CalledFromMainThread_WithEmptyButtons_RaisesAsyncValidation;

    [Test]
    procedure MessageDialog_WorkerTimeout_DoesNotInvokeCallback;
  end;

implementation

uses
  System.Classes,
  System.SyncObjs,
  System.SysUtils,
  System.UITypes,

  FMX.Forms,

  Dialog4D,
  Dialog4D.Await,
  Dialog4D.Internal.Queue,
  Dialog4D.Tests.Support,
  Dialog4D.TextProvider.Default,
  Dialog4D.Types;

type
  /// <summary>
  /// Text provider used by the timeout test to make any delayed show attempt
  /// fail before a visual dialog host is created.
  /// </summary>
  TFailingTextProvider = class(TInterfacedObject, IDialog4DTextProvider)
  private
    FOnButtonText: TProc;
  public
    constructor Create(const AOnButtonText: TProc);
    function ButtonText(const ABtn: TMsgDlgBtn): string;
    function TitleForType(const ADlgType: TMsgDlgType): string;
  end;

constructor TFailingTextProvider.Create(const AOnButtonText: TProc);
begin
  inherited Create;
  FOnButtonText := AOnButtonText;
end;

function TFailingTextProvider.ButtonText(const ABtn: TMsgDlgBtn): string;
begin
  if Assigned(FOnButtonText) then
    FOnButtonText;

  raise Exception.Create('Intentional text provider failure for await timeout test.');
end;

function TFailingTextProvider.TitleForType(const ADlgType: TMsgDlgType): string;
begin
  Result := 'Await Timeout Test';
end;

procedure TDialog4DAwaitCoreTests.MessageDialogOnWorker_CalledFromMainThread_Raises;
var
  LStatus: TDialog4DAwaitStatus;
begin
  try
    TDialog4DAwait.MessageDialogOnWorker(
      'Test',
      TMsgDlgType.mtInformation,
      [TMsgDlgBtn.mbOK],
      TMsgDlgBtn.mbOK,
      LStatus
    );

    Assert.Fail('Expected exception was not raised.');
  except
    on E: EDialog4DAwait do
      Assert.IsTrue(
        Pos('cannot be called on the main thread', E.Message) > 0,
        'Unexpected exception message: ' + E.Message
      );
    on E: Exception do
      Assert.Fail(
        'Expected EDialog4DAwait, but got ' + E.ClassName + ': ' + E.Message
      );
  end;
end;

procedure TDialog4DAwaitCoreTests.MessageDialog_CalledFromMainThread_WithEmptyButtons_RaisesAsyncValidation;
var
  LForm: TForm;
begin
  LForm := TForm.CreateNew(nil);
  try
    try
      TDialog4DAwait.MessageDialog(
        'Test',
        TMsgDlgType.mtInformation,
        [],
        TMsgDlgBtn.mbOK,
        nil,
        '',
        LForm,
        True
      );

      Assert.Fail('Expected exception was not raised.');
    except
      on E: Exception do
        Assert.AreEqual(
          'Dialog4D: at least one button is required.',
          E.Message
        );
    end;
  finally
    LForm.Free;
  end;
end;

procedure TDialog4DAwaitCoreTests.MessageDialog_WorkerTimeout_DoesNotInvokeCallback;
var
  LThread: TThread;
  LDone: TEvent;
  LWaitResult: TWaitResult;
  LCallbackInvoked: Boolean;
  LWorkerError: string;
  LQueueDrained: Boolean;
begin
  LThread := nil;
  LCallbackInvoked := False;
  LWorkerError := '';
  LQueueDrained := False;

  TDialog4D.ConfigureTextProvider(
    TFailingTextProvider.Create(
      procedure
      begin
        // Intentionally empty.
        // If the delayed show attempt reaches the text provider,
        // ButtonText will raise before any visual host is created.
      end
    )
  );

  LDone := TEvent.Create(nil, True, False, '');
  try
    LThread := TThread.CreateAnonymousThread(
      procedure
      begin
        try
          try
            TDialog4DAwait.MessageDialog(
              'Timeout test',
              TMsgDlgType.mtInformation,
              [TMsgDlgBtn.mbOK],
              TMsgDlgBtn.mbOK,
              procedure(const AResult: TModalResult)
              begin
                LCallbackInvoked := True;
              end,
              '',
              nil,
              True,
              False,
              1
            );
          except
            on E: Exception do
              LWorkerError := E.ClassName + ': ' + E.Message;
          end;
        finally
          LDone.SetEvent;
        end;
      end
    );

    // Critical for deterministic tests:
    // keep ownership of the TThread object so WaitFor/Free below are safe.
    LThread.FreeOnTerminate := False;

    LThread.Start;

    // Do not pump the main thread here. The worker must time out before the
    // queued show attempt is processed.
    LWaitResult := LDone.WaitFor(2000);

    Assert.AreEqual(
      Integer(TWaitResult.wrSignaled),
      Integer(LWaitResult),
      'The worker did not finish after the await timeout.'
    );

    LThread.WaitFor;

    Assert.AreEqual(
      '',
      LWorkerError,
      'The worker raised an unexpected exception.'
    );

    Assert.IsFalse(
      LCallbackInvoked,
      'The smart await callback was invoked even though the worker timed out.'
    );

    // Drain the queued show attempt so the internal queue wrapper and await
    // state are released before the test ends. The sentinel is queued after
    // the await show attempt, so reaching it means the earlier queued work
    // has already run.
    QueueOnMainThread(
      procedure
      begin
        LQueueDrained := True;
      end
    );

    Assert.IsTrue(
      TDialog4DTestSupport.WaitUntil(
        function: Boolean
        begin
          Result := LQueueDrained;
        end,
        2000,
        10
      ),
      'The queued await show attempt was not drained.'
    );
  finally
    TDialog4D.ConfigureTextProvider(TDialog4DDefaultTextProvider.Create);

    LThread.Free;
    LDone.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TDialog4DAwaitCoreTests);

end.
