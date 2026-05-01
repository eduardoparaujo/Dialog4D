// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Eduardo P. Araujo
// https://github.com/eduardoparaujo/Dialog4D

{*
  Unit   : Dialog4D.Tests.TextProvider.Default
  Purpose: Validation tests for Dialog4D.TextProvider.Default.

           This fixture verifies the behavior of the built-in English
           IDialog4DTextProvider implementation used by Dialog4D when no custom
           provider is configured.

           Covered contract:
             - standard button kinds return the expected English captions
             - built-in dialog types return the expected default English titles
             - mtCustom returns an empty title

           These tests intentionally validate the provider as a stable baseline
           text source for the library.

  Part of the Dialog4D automated test suite.

  Author        : Eduardo P. Araujo
  Created       : 2026-04-26
  Last modified : 2026-04-26
  Version       : 1.0.0

  Notes:
    - Uses a concrete TDialog4DDefaultTextProvider instance created in Setup.
    - Keeps assertions explicit to make regressions easy to identify.

  History:
    1.0.0 — 2026-04-26 — Initial default text-provider test release.
      • Added tests for all standard TMsgDlgBtn button captions exposed by
        TDialog4DDefaultTextProvider.
      • Added tests for default titles returned for mtInformation, mtWarning,
        mtError and mtConfirmation.
      • Added test coverage confirming that mtCustom returns an empty title.
*}

unit Dialog4D.Tests.TextProvider.Default;

interface

uses
  DUnitX.TestFramework,
  System.UITypes,
  Dialog4D.TextProvider.Default;

type
  [TestFixture]
  TDialog4DDefaultTextProviderTests = class
  private
    FProvider: TDialog4DDefaultTextProvider;

    procedure AssertButtonText(
      const ABtn: TMsgDlgBtn;
      const AExpected: string
    );

    procedure AssertTitleText(
      const ADlgType: TMsgDlgType;
      const AExpected: string
    );
  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test] procedure ButtonText_Ok_ReturnsOK;
    [Test] procedure ButtonText_Cancel_ReturnsCancel;
    [Test] procedure ButtonText_Yes_ReturnsYes;
    [Test] procedure ButtonText_No_ReturnsNo;
    [Test] procedure ButtonText_Abort_ReturnsAbort;
    [Test] procedure ButtonText_Retry_ReturnsRetry;
    [Test] procedure ButtonText_Ignore_ReturnsIgnore;
    [Test] procedure ButtonText_All_ReturnsAll;
    [Test] procedure ButtonText_NoToAll_ReturnsNoToAll;
    [Test] procedure ButtonText_YesToAll_ReturnsYesToAll;
    [Test] procedure ButtonText_Help_ReturnsHelp;
    [Test] procedure ButtonText_Close_ReturnsClose;

    [Test] procedure TitleForType_Information_ReturnsInformation;
    [Test] procedure TitleForType_Warning_ReturnsWarning;
    [Test] procedure TitleForType_Error_ReturnsError;
    [Test] procedure TitleForType_Confirmation_ReturnsConfirmation;
    [Test] procedure TitleForType_Custom_ReturnsEmpty;
  end;

implementation

procedure TDialog4DDefaultTextProviderTests.Setup;
begin
  FProvider := TDialog4DDefaultTextProvider.Create;
end;

procedure TDialog4DDefaultTextProviderTests.TearDown;
begin
  FProvider := nil;
end;

procedure TDialog4DDefaultTextProviderTests.AssertButtonText(
  const ABtn: TMsgDlgBtn;
  const AExpected: string);
begin
  Assert.AreEqual(AExpected, FProvider.ButtonText(ABtn));
end;

procedure TDialog4DDefaultTextProviderTests.AssertTitleText(
  const ADlgType: TMsgDlgType;
  const AExpected: string);
begin
  Assert.AreEqual(AExpected, FProvider.TitleForType(ADlgType));
end;

procedure TDialog4DDefaultTextProviderTests.ButtonText_Ok_ReturnsOK;
begin
  AssertButtonText(TMsgDlgBtn.mbOK, 'OK');
end;

procedure TDialog4DDefaultTextProviderTests.ButtonText_Cancel_ReturnsCancel;
begin
  AssertButtonText(TMsgDlgBtn.mbCancel, 'Cancel');
end;

procedure TDialog4DDefaultTextProviderTests.ButtonText_Yes_ReturnsYes;
begin
  AssertButtonText(TMsgDlgBtn.mbYes, 'Yes');
end;

procedure TDialog4DDefaultTextProviderTests.ButtonText_No_ReturnsNo;
begin
  AssertButtonText(TMsgDlgBtn.mbNo, 'No');
end;

procedure TDialog4DDefaultTextProviderTests.ButtonText_Abort_ReturnsAbort;
begin
  AssertButtonText(TMsgDlgBtn.mbAbort, 'Abort');
end;

procedure TDialog4DDefaultTextProviderTests.ButtonText_Retry_ReturnsRetry;
begin
  AssertButtonText(TMsgDlgBtn.mbRetry, 'Retry');
end;

procedure TDialog4DDefaultTextProviderTests.ButtonText_Ignore_ReturnsIgnore;
begin
  AssertButtonText(TMsgDlgBtn.mbIgnore, 'Ignore');
end;

procedure TDialog4DDefaultTextProviderTests.ButtonText_All_ReturnsAll;
begin
  AssertButtonText(TMsgDlgBtn.mbAll, 'All');
end;

procedure TDialog4DDefaultTextProviderTests.ButtonText_NoToAll_ReturnsNoToAll;
begin
  AssertButtonText(TMsgDlgBtn.mbNoToAll, 'No to All');
end;

procedure TDialog4DDefaultTextProviderTests.ButtonText_YesToAll_ReturnsYesToAll;
begin
  AssertButtonText(TMsgDlgBtn.mbYesToAll, 'Yes to All');
end;

procedure TDialog4DDefaultTextProviderTests.ButtonText_Help_ReturnsHelp;
begin
  AssertButtonText(TMsgDlgBtn.mbHelp, 'Help');
end;

procedure TDialog4DDefaultTextProviderTests.ButtonText_Close_ReturnsClose;
begin
  AssertButtonText(TMsgDlgBtn.mbClose, 'Close');
end;

procedure TDialog4DDefaultTextProviderTests.TitleForType_Information_ReturnsInformation;
begin
  AssertTitleText(TMsgDlgType.mtInformation, 'Information');
end;

procedure TDialog4DDefaultTextProviderTests.TitleForType_Warning_ReturnsWarning;
begin
  AssertTitleText(TMsgDlgType.mtWarning, 'Warning');
end;

procedure TDialog4DDefaultTextProviderTests.TitleForType_Error_ReturnsError;
begin
  AssertTitleText(TMsgDlgType.mtError, 'Error');
end;

procedure TDialog4DDefaultTextProviderTests.TitleForType_Confirmation_ReturnsConfirmation;
begin
  AssertTitleText(TMsgDlgType.mtConfirmation, 'Confirmation');
end;

procedure TDialog4DDefaultTextProviderTests.TitleForType_Custom_ReturnsEmpty;
begin
  AssertTitleText(TMsgDlgType.mtCustom, '');
end;

initialization
  TDUnitX.RegisterTestFixture(TDialog4DDefaultTextProviderTests);

end.
