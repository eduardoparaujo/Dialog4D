// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Eduardo P. Araujo
// https://github.com/eduardoparaujo/dialog4D

{*
  Unit   : Dialog4D.Tests.Types
  Purpose: Validation tests for Dialog4D.Types.

           This fixture verifies the core public value types exposed by
           Dialog4D.Types, with focus on:
             - TDialog4DCustomButton factory helpers
             - TDialog4DTheme.Default baseline values
             - record copy behavior for TDialog4DTheme

           These tests help protect the public contract relied on by the rest
           of the framework, especially default configuration values and custom
           button construction semantics.

  Notes:
    - The fixture validates both convenience constructors
      (Default / Destructive / Cancel) and the base Make constructor.
    - Theme tests intentionally assert concrete default values so regressions
      in the public baseline theme are detected immediately.

  Author        : Eduardo P. Araujo
  Created       : 2026-04-26
  Last modified : 2026-04-26
  Version       : 1.0.0
*}

unit Dialog4D.Tests.Types;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TDialog4DTypesTests = class
  public
    { == TDialog4DCustomButton == }
    [Test] procedure CustomButton_Make_PreservesCaption;
    [Test] procedure CustomButton_Make_PreservesModalResult;
    [Test] procedure CustomButton_Make_PreservesIsDefault;
    [Test] procedure CustomButton_Make_PreservesIsDestructive;

    [Test] procedure CustomButton_Default_SetsPrimaryFlags;
    [Test] procedure CustomButton_Destructive_SetsDestructiveFlags;
    [Test] procedure CustomButton_Cancel_UsesMrCancel;
    [Test] procedure CustomButton_Cancel_IsNeutralAndNotDefault;

    { == TDialog4DTheme.Default == }
    [Test] procedure Theme_Default_HasExpectedGeometry;
    [Test] procedure Theme_Default_HasExpectedOverlay;
    [Test] procedure Theme_Default_HasExpectedTypography;
    [Test] procedure Theme_Default_HasExpectedButtons;
    [Test] procedure Theme_Default_HasExpectedSemanticFlags;
    [Test] procedure Theme_Default_HasExpectedHighlight;
    [Test] procedure Theme_Default_HasExpectedKeyColors;

    { == TDialog4DTheme record copy == }
    [Test] procedure Theme_Copy_PreservesAssignedValues;
  end;

implementation

uses
  System.UITypes,
  Dialog4D.Types;

{ TDialog4DCustomButton }

procedure TDialog4DTypesTests.CustomButton_Make_PreservesCaption;
var
  LButton: TDialog4DCustomButton;
begin
  LButton := TDialog4DCustomButton.Make('Stay Logged In', mrOk, True, False);

  Assert.AreEqual('Stay Logged In', LButton.Caption);
end;

procedure TDialog4DTypesTests.CustomButton_Make_PreservesModalResult;
var
  LButton: TDialog4DCustomButton;
begin
  LButton := TDialog4DCustomButton.Make('Close', mrClose, False, False);

  Assert.AreEqual(Integer(mrClose), Integer(LButton.ModalResult));
end;

procedure TDialog4DTypesTests.CustomButton_Make_PreservesIsDefault;
var
  LButton: TDialog4DCustomButton;
begin
  LButton := TDialog4DCustomButton.Make('Primary', mrOk, True, False);

  Assert.IsTrue(LButton.IsDefault);
end;

procedure TDialog4DTypesTests.CustomButton_Make_PreservesIsDestructive;
var
  LButton: TDialog4DCustomButton;
begin
  LButton := TDialog4DCustomButton.Make('Delete', mrAbort, False, True);

  Assert.IsTrue(LButton.IsDestructive);
end;

procedure TDialog4DTypesTests.CustomButton_Default_SetsPrimaryFlags;
var
  LButton: TDialog4DCustomButton;
begin
  LButton := TDialog4DCustomButton.Default('OK', mrOk);

  Assert.AreEqual('OK', LButton.Caption);
  Assert.AreEqual(Integer(mrOk), Integer(LButton.ModalResult));
  Assert.IsTrue(LButton.IsDefault);
  Assert.IsFalse(LButton.IsDestructive);
end;

procedure TDialog4DTypesTests.CustomButton_Destructive_SetsDestructiveFlags;
var
  LButton: TDialog4DCustomButton;
begin
  LButton := TDialog4DCustomButton.Destructive('Delete', mrAbort);

  Assert.AreEqual('Delete', LButton.Caption);
  Assert.AreEqual(Integer(mrAbort), Integer(LButton.ModalResult));
  Assert.IsFalse(LButton.IsDefault);
  Assert.IsTrue(LButton.IsDestructive);
end;

procedure TDialog4DTypesTests.CustomButton_Cancel_UsesMrCancel;
var
  LButton: TDialog4DCustomButton;
begin
  LButton := TDialog4DCustomButton.Cancel('Cancel');

  Assert.AreEqual(Integer(mrCancel), Integer(LButton.ModalResult));
  Assert.AreEqual('Cancel', LButton.Caption);
end;

procedure TDialog4DTypesTests.CustomButton_Cancel_IsNeutralAndNotDefault;
var
  LButton: TDialog4DCustomButton;
begin
  LButton := TDialog4DCustomButton.Cancel('Cancel');

  Assert.IsFalse(LButton.IsDefault);
  Assert.IsFalse(LButton.IsDestructive);
end;

{ TDialog4DTheme.Default }

procedure TDialog4DTypesTests.Theme_Default_HasExpectedGeometry;
var
  LTheme: TDialog4DTheme;
begin
  LTheme := TDialog4DTheme.Default;

  Assert.AreEqual(Single(320.0), LTheme.DialogWidth);
  Assert.AreEqual(Single(170.0), LTheme.DialogMinHeight);
  Assert.AreEqual(Single(0.85), LTheme.DialogMaxHeightRatio);
  Assert.AreEqual(Single(50.0), LTheme.ContentMinHeight);
  Assert.AreEqual(Single(14.0), LTheme.CornerRadius);
end;

procedure TDialog4DTypesTests.Theme_Default_HasExpectedOverlay;
var
  LTheme: TDialog4DTheme;
begin
  LTheme := TDialog4DTheme.Default;

  Assert.AreEqual(Single(0.45), LTheme.OverlayOpacity);
  Assert.AreEqual(Cardinal($FF000000), Cardinal(LTheme.OverlayColor));
end;

procedure TDialog4DTypesTests.Theme_Default_HasExpectedTypography;
var
  LTheme: TDialog4DTheme;
begin
  LTheme := TDialog4DTheme.Default;

  Assert.AreEqual(Single(16.0), LTheme.TitleFontSize);
  Assert.AreEqual(Single(14.0), LTheme.MessageFontSize);
  Assert.AreEqual(Integer(dtaCenter), Integer(LTheme.MessageTextAlign));
end;

procedure TDialog4DTypesTests.Theme_Default_HasExpectedButtons;
var
  LTheme: TDialog4DTheme;
begin
  LTheme := TDialog4DTheme.Default;

  Assert.AreEqual(Single(44.0), LTheme.ButtonHeight);
  Assert.AreEqual(Single(14.0), LTheme.ButtonFontSize);
  Assert.AreEqual(Cardinal($FFF3F3F3), Cardinal(LTheme.ButtonNeutralFillColor));
  Assert.AreEqual(Cardinal($FF2C2C2C), Cardinal(LTheme.ButtonNeutralTextColor));
  Assert.AreEqual(Cardinal($FFCECECE), Cardinal(LTheme.ButtonNeutralBorderColor));
end;

procedure TDialog4DTypesTests.Theme_Default_HasExpectedSemanticFlags;
var
  LTheme: TDialog4DTheme;
begin
  LTheme := TDialog4DTheme.Default;

  Assert.IsFalse(LTheme.TreatCloseAsCancel);
  Assert.AreEqual(Integer(dtaCenter), Integer(LTheme.MessageTextAlign));
end;

procedure TDialog4DTypesTests.Theme_Default_HasExpectedHighlight;
var
  LTheme: TDialog4DTheme;
begin
  LTheme := TDialog4DTheme.Default;

  Assert.IsTrue(LTheme.ShowDefaultButtonHighlight);
  Assert.AreEqual(Cardinal(TAlphaColorRec.White), Cardinal(LTheme.DefaultButtonHighlightColor));
  Assert.AreEqual(Single(1.0), LTheme.DefaultButtonHighlightThickness);
  Assert.AreEqual(Single(0.95), LTheme.DefaultButtonHighlightOpacity);
  Assert.AreEqual(Single(1.0), LTheme.DefaultButtonHighlightInset);
end;

procedure TDialog4DTypesTests.Theme_Default_HasExpectedKeyColors;
var
  LTheme: TDialog4DTheme;
begin
  LTheme := TDialog4DTheme.Default;

  Assert.AreEqual(Cardinal(TAlphaColorRec.White), Cardinal(LTheme.SurfaceColor));
  Assert.AreEqual(Cardinal($FF2C2C2C), Cardinal(LTheme.TextTitleColor));
  Assert.AreEqual(Cardinal($FF848484), Cardinal(LTheme.TextMessageColor));

  Assert.AreEqual(Cardinal($FF3085D6), Cardinal(LTheme.AccentInfoColor));
  Assert.AreEqual(Cardinal($FFF3A867), Cardinal(LTheme.AccentWarningColor));
  Assert.AreEqual(Cardinal($FFE64D4D), Cardinal(LTheme.AccentErrorColor));
  Assert.AreEqual(Cardinal($FF9E9E9E), Cardinal(LTheme.AccentConfirmColor));
  Assert.AreEqual(Cardinal($FFEFEFEF), Cardinal(LTheme.AccentNeutralColor));
end;

{ TDialog4DTheme record copy }

procedure TDialog4DTypesTests.Theme_Copy_PreservesAssignedValues;
var
  LSourceTheme: TDialog4DTheme;
  LCopiedTheme: TDialog4DTheme;
begin
  LSourceTheme := TDialog4DTheme.Default;
  LSourceTheme.DialogWidth := 420;
  LSourceTheme.ButtonHeight := 50;
  LSourceTheme.OverlayOpacity := 0.60;
  LSourceTheme.MessageTextAlign := dtaLeading;
  LSourceTheme.TreatCloseAsCancel := True;
  LSourceTheme.AccentInfoColor := $FF112233;

  LCopiedTheme := LSourceTheme;

  Assert.AreEqual(Single(420.0), LCopiedTheme.DialogWidth);
  Assert.AreEqual(Single(50.0), LCopiedTheme.ButtonHeight);
  Assert.AreEqual(Single(0.60), LCopiedTheme.OverlayOpacity);
  Assert.AreEqual(Integer(dtaLeading), Integer(LCopiedTheme.MessageTextAlign));
  Assert.IsTrue(LCopiedTheme.TreatCloseAsCancel);
  Assert.AreEqual(Cardinal($FF112233), Cardinal(LCopiedTheme.AccentInfoColor));
end;

initialization
  TDUnitX.RegisterTestFixture(TDialog4DTypesTests);

end.
