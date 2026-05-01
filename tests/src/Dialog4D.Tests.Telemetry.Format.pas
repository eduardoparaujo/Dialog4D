// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Eduardo P. Araujo
// https://github.com/eduardoparaujo/Dialog4D

{*
  Unit   : Dialog4D.Tests.Telemetry.Format
  Purpose: Validation tests for Dialog4D.Telemetry.Format.

           This fixture verifies the public text-formatting contract exposed by
           TDialog4DTelemetryFormat, including:
             - enum/value to text conversion helpers
             - formatting of a complete telemetry record into a single-line log
               entry
             - fallback behavior for missing title and missing button caption
             - quote escaping in quoted text fields
             - CR/LF/TAB normalization to preserve single-line log output

           These tests focus on stable textual output that external logging,
           diagnostics, and demos may depend on.

  Part of the Dialog4D automated test suite.

  Author        : Eduardo P. Araujo
  Created       : 2026-04-26
  Last modified : 2026-05-01
  Version       : 1.0.1

  Notes:
    - The fixture uses a small test text provider to validate provider-based
      title fallback behavior.
    - Assertions are intentionally granular so formatting regressions are easier
      to identify.
    - Text escaping tests protect the 1.0.1 formatter hardening: Title,
      ButtonCaption and ErrorMessage must use the same escaping and
      single-line normalization rules.

  History:
    1.0.1 — 2026-05-01 — Formatter hardening coverage.
      • Added tests for quote escaping in Title, ButtonCaption and ErrorMessage.
      • Added tests for CR/LF/TAB normalization to visible escape sequences.
      • Added assertions that formatted telemetry remains a single physical line.

    1.0.0 — 2026-04-26 — Initial public release.
      • Added enum/value conversion tests.
      • Added complete telemetry formatting tests.
      • Added fallback tests for missing title and missing button caption.
*}

unit Dialog4D.Tests.Telemetry.Format;

interface

uses
  DUnitX.TestFramework,
  Dialog4D.Types;

type
  [TestFixture]
  TDialog4DTelemetryFormatTests = class
  private
    function CreateBasicTelemetry: TDialog4DTelemetry;
    function FormatBasicTelemetry: string;
    procedure AssertContains(
      const AExpectedFragment: string;
      const AActualText: string;
      const AFailureMessage: string
    );
  public
    [Test] procedure TelemetryKindToText_ShowRequested_ReturnsShowRequested;
    [Test] procedure TelemetryKindToText_CallbackInvoked_ReturnsCallbackInvoked;

    [Test] procedure CloseReasonToText_Programmatic_ReturnsProgrammatic;
    [Test] procedure CloseReasonToText_KeyEsc_ReturnsKeyEsc;

    [Test] procedure MsgDlgTypeToText_Information_ReturnsInformation;
    [Test] procedure MsgDlgTypeToText_Custom_ReturnsCustom;

    [Test] procedure ModalResultToText_Ok_ReturnsOK;
    [Test] procedure ModalResultToText_CustomValue_ReturnsCustomFormat;

    [Test] procedure MsgDlgBtnToText_Ok_ReturnsOK;
    [Test] procedure MsgDlgBtnToText_Close_ReturnsClose;

    [Test] procedure FormatTelemetry_BasicRecord_ContainsIdentificationFields;
    [Test] procedure FormatTelemetry_BasicRecord_ContainsResultFields;
    [Test] procedure FormatTelemetry_BasicRecord_ContainsStateFields;
    [Test] procedure FormatTelemetry_BasicRecord_ContainsButtonFields;
    [Test] procedure FormatTelemetry_BasicRecord_ContainsMetricsFields;
    [Test] procedure FormatTelemetry_BasicRecord_ContainsTitleField;

    [Test] procedure FormatTelemetry_UsesProviderTitleWhenTitleEmpty;
    [Test] procedure FormatTelemetry_UsesDashWhenButtonCaptionEmpty;

    [Test] procedure FormatTelemetry_EscapesQuotesInTextFields;
    [Test] procedure FormatTelemetry_NormalizesControlCharactersToSingleLine;
  end;

implementation

uses
  System.UITypes,

  Dialog4D.Telemetry.Format;

type
  /// <summary>
  /// Minimal text provider used by fallback-formatting tests.
  /// </summary>
  TTestTextProvider = class(TInterfacedObject, IDialog4DTextProvider)
  public
    function ButtonText(const ABtn: TMsgDlgBtn): string;
    function TitleForType(const ADlgType: TMsgDlgType): string;
  end;

function TTestTextProvider.ButtonText(const ABtn: TMsgDlgBtn): string;
begin
  case ABtn of
    TMsgDlgBtn.mbOK:     Result := 'OK';
    TMsgDlgBtn.mbCancel: Result := 'Cancel';
    TMsgDlgBtn.mbYes:    Result := 'Yes';
    TMsgDlgBtn.mbNo:     Result := 'No';
    TMsgDlgBtn.mbClose:  Result := 'Close';
  else
    Result := 'Button';
  end;
end;

function TTestTextProvider.TitleForType(const ADlgType: TMsgDlgType): string;
begin
  case ADlgType of
    TMsgDlgType.mtInformation:  Result := 'InfoTitle';
    TMsgDlgType.mtWarning:      Result := 'WarningTitle';
    TMsgDlgType.mtError:        Result := 'ErrorTitle';
    TMsgDlgType.mtConfirmation: Result := 'ConfirmationTitle';
    TMsgDlgType.mtCustom:       Result := 'CustomTitle';
  else
    Result := 'UnknownTitle';
  end;
end;

procedure TDialog4DTelemetryFormatTests.AssertContains(
  const AExpectedFragment: string;
  const AActualText: string;
  const AFailureMessage: string);
begin
  Assert.IsTrue(
    Pos(AExpectedFragment, AActualText) > 0,
    AFailureMessage
  );
end;

function TDialog4DTelemetryFormatTests.CreateBasicTelemetry: TDialog4DTelemetry;
begin
  Result := Default(TDialog4DTelemetry);
  Result.Kind := tkShowRequested;
  Result.DialogType := TMsgDlgType.mtInformation;
  Result.CloseReason := crProgrammatic;
  Result.Result := mrCancel;
  Result.DefaultResult := mrOk;
  Result.HasCancelButton := True;
  Result.ButtonsCount := 2;
  Result.MessageLen := 42;
  Result.ButtonKind := TMsgDlgBtn.mbOK;
  Result.ButtonCaption := 'Cancel now';
  Result.ButtonWasDefault := False;
  Result.ElapsedMs := 123;
  Result.Title := 'My Title';
end;

function TDialog4DTelemetryFormatTests.FormatBasicTelemetry: string;
begin
  Result := TDialog4DTelemetryFormat.FormatTelemetry(CreateBasicTelemetry);
end;

procedure TDialog4DTelemetryFormatTests.TelemetryKindToText_ShowRequested_ReturnsShowRequested;
begin
  Assert.AreEqual(
    'ShowRequested',
    TDialog4DTelemetryFormat.TelemetryKindToText(tkShowRequested)
  );
end;

procedure TDialog4DTelemetryFormatTests.TelemetryKindToText_CallbackInvoked_ReturnsCallbackInvoked;
begin
  Assert.AreEqual(
    'CallbackInvoked',
    TDialog4DTelemetryFormat.TelemetryKindToText(tkCallbackInvoked)
  );
end;

procedure TDialog4DTelemetryFormatTests.CloseReasonToText_Programmatic_ReturnsProgrammatic;
begin
  Assert.AreEqual(
    'Programmatic',
    TDialog4DTelemetryFormat.CloseReasonToText(crProgrammatic)
  );
end;

procedure TDialog4DTelemetryFormatTests.CloseReasonToText_KeyEsc_ReturnsKeyEsc;
begin
  Assert.AreEqual(
    'KeyEsc',
    TDialog4DTelemetryFormat.CloseReasonToText(crKeyEsc)
  );
end;

procedure TDialog4DTelemetryFormatTests.MsgDlgTypeToText_Information_ReturnsInformation;
begin
  Assert.AreEqual(
    'Information',
    TDialog4DTelemetryFormat.MsgDlgTypeToText(TMsgDlgType.mtInformation)
  );
end;

procedure TDialog4DTelemetryFormatTests.MsgDlgTypeToText_Custom_ReturnsCustom;
begin
  Assert.AreEqual(
    'Custom',
    TDialog4DTelemetryFormat.MsgDlgTypeToText(TMsgDlgType.mtCustom)
  );
end;

procedure TDialog4DTelemetryFormatTests.ModalResultToText_Ok_ReturnsOK;
begin
  Assert.AreEqual(
    'OK',
    TDialog4DTelemetryFormat.ModalResultToText(mrOk)
  );
end;

procedure TDialog4DTelemetryFormatTests.ModalResultToText_CustomValue_ReturnsCustomFormat;
begin
  Assert.AreEqual(
    'Custom(100)',
    TDialog4DTelemetryFormat.ModalResultToText(TModalResult(100))
  );
end;

procedure TDialog4DTelemetryFormatTests.MsgDlgBtnToText_Ok_ReturnsOK;
begin
  Assert.AreEqual(
    'OK',
    TDialog4DTelemetryFormat.MsgDlgBtnToText(TMsgDlgBtn.mbOK)
  );
end;

procedure TDialog4DTelemetryFormatTests.MsgDlgBtnToText_Close_ReturnsClose;
begin
  Assert.AreEqual(
    'Close',
    TDialog4DTelemetryFormat.MsgDlgBtnToText(TMsgDlgBtn.mbClose)
  );
end;

procedure TDialog4DTelemetryFormatTests.FormatTelemetry_BasicRecord_ContainsIdentificationFields;
var
  LText: string;
begin
  LText := FormatBasicTelemetry;

  AssertContains('ShowRequested', LText, 'Kind was not found.');
  AssertContains('Type=Information', LText, 'DialogType was not found.');
  AssertContains('Reason=Programmatic', LText, 'CloseReason was not found.');
end;

procedure TDialog4DTelemetryFormatTests.FormatTelemetry_BasicRecord_ContainsResultFields;
var
  LText: string;
begin
  LText := FormatBasicTelemetry;

  AssertContains('Result=Cancel', LText, 'Result was not found.');
  AssertContains('Default=OK', LText, 'DefaultResult was not found.');
end;

procedure TDialog4DTelemetryFormatTests.FormatTelemetry_BasicRecord_ContainsStateFields;
var
  LText: string;
begin
  LText := FormatBasicTelemetry;

  AssertContains('Cancel=True', LText, 'HasCancelButton was not found.');
  AssertContains('Buttons=2', LText, 'ButtonsCount was not found.');
end;

procedure TDialog4DTelemetryFormatTests.FormatTelemetry_BasicRecord_ContainsButtonFields;
var
  LText: string;
begin
  LText := FormatBasicTelemetry;

  AssertContains('ButtonKind=OK', LText, 'ButtonKind was not found.');
  AssertContains('ButtonCaption="Cancel now"', LText, 'ButtonCaption was not found.');
  AssertContains('ButtonDefault=False', LText, 'ButtonWasDefault was not found.');
end;

procedure TDialog4DTelemetryFormatTests.FormatTelemetry_BasicRecord_ContainsMetricsFields;
var
  LText: string;
begin
  LText := FormatBasicTelemetry;

  AssertContains('Len=42', LText, 'MessageLen was not found.');
  AssertContains('ElapsedMs=123', LText, 'ElapsedMs was not found.');
end;

procedure TDialog4DTelemetryFormatTests.FormatTelemetry_BasicRecord_ContainsTitleField;
var
  LText: string;
begin
  LText := FormatBasicTelemetry;

  AssertContains('Title="My Title"', LText, 'Title was not found.');
end;

procedure TDialog4DTelemetryFormatTests.FormatTelemetry_UsesProviderTitleWhenTitleEmpty;
var
  LTelemetry: TDialog4DTelemetry;
  LText: string;
  LProvider: IDialog4DTextProvider;
begin
  LTelemetry := CreateBasicTelemetry;
  LTelemetry.Kind := tkClosed;
  LTelemetry.DialogType := TMsgDlgType.mtWarning;
  LTelemetry.CloseReason := crButton;
  LTelemetry.Result := mrOk;
  LTelemetry.DefaultResult := mrOk;
  LTelemetry.ButtonKind := TMsgDlgBtn.mbOK;
  LTelemetry.ButtonCaption := 'OK';
  LTelemetry.Title := '';

  LProvider := TTestTextProvider.Create;
  LText := TDialog4DTelemetryFormat.FormatTelemetry(LTelemetry, LProvider);

  AssertContains(
    'Title="WarningTitle"',
    LText,
    'When Title is empty, the formatter should use the provider''s title.'
  );
end;

procedure TDialog4DTelemetryFormatTests.FormatTelemetry_UsesDashWhenButtonCaptionEmpty;
var
  LTelemetry: TDialog4DTelemetry;
  LText: string;
begin
  LTelemetry := CreateBasicTelemetry;
  LTelemetry.Kind := tkClosed;
  LTelemetry.DialogType := TMsgDlgType.mtInformation;
  LTelemetry.CloseReason := crButton;
  LTelemetry.Result := mrOk;
  LTelemetry.DefaultResult := mrOk;
  LTelemetry.ButtonKind := TMsgDlgBtn.mbOK;
  LTelemetry.ButtonCaption := '';
  LTelemetry.Title := 'X';

  LText := TDialog4DTelemetryFormat.FormatTelemetry(LTelemetry);

  AssertContains(
    'ButtonCaption="-"',
    LText,
    'When ButtonCaption is empty, the formatter should use "-".'
  );
end;

procedure TDialog4DTelemetryFormatTests.FormatTelemetry_EscapesQuotesInTextFields;
var
  LTelemetry: TDialog4DTelemetry;
  LText: string;
begin
  LTelemetry := CreateBasicTelemetry;
  LTelemetry.Title := 'Title "A"';
  LTelemetry.ButtonCaption := 'Button "B"';
  LTelemetry.ErrorMessage := 'Error "C"';

  LText := TDialog4DTelemetryFormat.FormatTelemetry(LTelemetry);

  AssertContains(
    'Title="Title ""A"""',
    LText,
    'Title quotes were not escaped correctly.'
  );

  AssertContains(
    'ButtonCaption="Button ""B"""',
    LText,
    'ButtonCaption quotes were not escaped correctly.'
  );

  AssertContains(
    'Error="Error ""C"""',
    LText,
    'ErrorMessage quotes were not escaped correctly.'
  );
end;

procedure TDialog4DTelemetryFormatTests.FormatTelemetry_NormalizesControlCharactersToSingleLine;
var
  LTelemetry: TDialog4DTelemetry;
  LText: string;
begin
  LTelemetry := CreateBasicTelemetry;
  LTelemetry.Title := 'Line1' + #13 + #10 + 'Line2';
  LTelemetry.ButtonCaption := 'Button' + #9 + 'Caption';
  LTelemetry.ErrorMessage := 'A' + #13 + 'B' + #10 + 'C' + #9 + 'D';

  LText := TDialog4DTelemetryFormat.FormatTelemetry(LTelemetry);

  AssertContains(
    'Title="Line1\r\nLine2"',
    LText,
    'Title CR/LF characters were not normalized.'
  );

  AssertContains(
    'ButtonCaption="Button\tCaption"',
    LText,
    'ButtonCaption TAB character was not normalized.'
  );

  AssertContains(
    'Error="A\rB\nC\tD"',
    LText,
    'ErrorMessage control characters were not normalized.'
  );

  Assert.AreEqual(
    0,
    Pos(#13, LText),
    'Formatted telemetry contains a physical carriage return.'
  );

  Assert.AreEqual(
    0,
    Pos(#10, LText),
    'Formatted telemetry contains a physical line feed.'
  );

  Assert.AreEqual(
    0,
    Pos(#9, LText),
    'Formatted telemetry contains a physical tab.'
  );
end;

initialization
  TDUnitX.RegisterTestFixture(TDialog4DTelemetryFormatTests);

end.
