// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Eduardo P. Araujo
// https://github.com/eduardoparaujo/Dialog4D

{*
  Unit   : Dialog4D.Tests.Await.Core
  Purpose: Core validation tests for Dialog4D.Await.

           This test fixture focuses on the basic contract of the await helper:
             - worker-only APIs must reject usage from the main thread
             - invalid async input must still be validated on the main thread

           These tests do not validate timing, worker-thread blocking behavior,
           or visual interaction. They verify the core guardrails and error
           paths that define correct usage of TDialog4DAwait.

  Notes:
    - Uses TForm.CreateNew(nil) to avoid any dependency on FMX form resources.
    - Keeps assertions explicit and deterministic, especially for exception
      message validation.

  Author        : Eduardo P. Araujo
  Created       : 2026-04-26
  Last modified : 2026-04-26
  Version       : 1.0.0
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
  end;

implementation

uses
  System.SysUtils,
  System.UITypes,
  FMX.Forms,
  Dialog4D.Await;

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

initialization
  TDUnitX.RegisterTestFixture(TDialog4DAwaitCoreTests);

end.
