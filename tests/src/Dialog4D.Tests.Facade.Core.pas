// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Eduardo P. Araujo
// https://github.com/eduardoparaujo/Dialog4D

{*
  Unit   : Dialog4D.Tests.Facade.Core
  Purpose: Core validation tests for the public Dialog4D facade.

           This fixture verifies facade-level guardrails that belong to
           TDialog4D itself rather than to lower-level units. The current focus
           is custom-button validation:
             - empty custom button arrays are rejected
             - manually constructed custom buttons using mrNone are rejected

           These tests protect the public API against invalid input even when
           callers bypass TDialog4DCustomButton helper constructors and fill
           the record manually.

  Part of the Dialog4D automated test suite.

  Author        : Eduardo P. Araujo
  Created       : 2026-05-01
  Last modified : 2026-05-01
  Version       : 1.0.0

  Notes:
    - These tests intentionally exercise validation paths that occur before
      any visual dialog is created.
    - No FMX form is required because the tested failures happen before parent
      form resolution and before registry enqueue/show logic.
    - The tests assert exact messages where the message is part of the public
      diagnostic contract.

  History:
    1.0.0 — 2026-05-01 — Initial public release.
      • Added facade-level validation tests for custom-button arrays.
      • Added regression coverage for manually constructed mrNone buttons.
*}

unit Dialog4D.Tests.Facade.Core;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TDialog4DFacadeCoreTests = class
  public
    [Test]
    procedure MessageDialogAsync_CustomButtons_EmptyArray_Raises;

    [Test]
    procedure MessageDialogAsync_CustomButtonWithMrNone_Raises;
  end;

implementation

uses
  System.SysUtils,
  System.UITypes,

  Dialog4D,
  Dialog4D.Types;

procedure TDialog4DFacadeCoreTests.MessageDialogAsync_CustomButtons_EmptyArray_Raises;
var
  LButtons: TArray<TDialog4DCustomButton>;
begin
  SetLength(LButtons, 0);

  try
    TDialog4D.MessageDialogAsync(
      'Invalid custom button array',
      TMsgDlgType.mtInformation,
      LButtons,
      nil
    );

    Assert.Fail('Expected exception was not raised.');
  except
    on E: Exception do
      Assert.AreEqual(
        'Dialog4D: at least one button is required.',
        E.Message
      );
  end;
end;

procedure TDialog4DFacadeCoreTests.MessageDialogAsync_CustomButtonWithMrNone_Raises;
var
  LButton: TDialog4DCustomButton;
  LButtons: TArray<TDialog4DCustomButton>;
begin
  // Deliberately bypass TDialog4DCustomButton.Make so this test verifies
  // facade-level validation, not helper-level validation.
  LButton.Caption := 'Invalid';
  LButton.ModalResult := mrNone;
  LButton.IsDefault := False;
  LButton.IsDestructive := False;

  SetLength(LButtons, 1);
  LButtons[0] := LButton;

  try
    TDialog4D.MessageDialogAsync(
      'Invalid custom button',
      TMsgDlgType.mtInformation,
      LButtons,
      nil
    );

    Assert.Fail('Expected exception was not raised.');
  except
    on E: Exception do
      Assert.AreEqual(
        'Dialog4D: custom buttons cannot use mrNone as ModalResult.',
        E.Message
      );
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TDialog4DFacadeCoreTests);

end.
