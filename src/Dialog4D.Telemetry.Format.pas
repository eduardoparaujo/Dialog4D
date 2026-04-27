// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Eduardo P. Araujo
// https://github.com/eduardoparaujo/Dialog4D

{*
  Unit   : Dialog4D.Telemetry.Format
  Purpose: Formatting helpers for TDialog4DTelemetry records. Converts
           telemetry snapshots into human-readable strings suitable for
           logging, debug output, console display, or demo instrumentation.

  Part of the Dialog4D framework - see Dialog4D.Types for the overview.

  Author        : Eduardo P. Araujo
  Created       : 2026-04-26
  Last modified : 2026-04-26
  Version       : 1.0.0

  Notes:
    - This unit is optional. Dialog4D itself does not require it at runtime
      unless the application chooses to format telemetry using the built-in
      text helpers.

    - Design notes:
        * Formatting is intentionally simple and log-friendly — single-line
          output with stable field ordering.
        * Standard Delphi modal result constants (mrNone..mrClose) are
          mapped to symbolic names.
        * Any non-standard modal result is formatted as Custom(N), where N
          is the raw integer value.
        * When a title is not present in telemetry, an optional text
          provider may supply a fallback title for better readability.
        * ErrorMessage, when present, is appended to the formatted line as
          an optional diagnostic field.

  Important:
    - Exceptions raised inside FormatTelemetry would propagate to the
      caller, but no public method here is expected to raise under normal
      use.

    - ModalResultToText uses exhaustive matching on standard modal result
      constants. Values outside that set are always formatted as Custom(N),
      regardless of numeric range.
*}

unit Dialog4D.Telemetry.Format;

interface

uses
  System.SysUtils,
  System.UITypes,

  Dialog4D.Types;

type
  { ========================= }
  { == Telemetry formatter == }
  { ========================= }

  /// <summary>
  /// Utility formatter for <c>Dialog4D</c> telemetry data.
  /// </summary>
  /// <remarks>
  /// <para><b>Purpose:</b></para>
  /// <para>• Convert telemetry enums into readable text.</para>
  /// <para>• Provide a stable single-line textual representation for telemetry events, suitable for logs and debug output.</para>
  /// <para>All methods are class functions and have no internal state.</para>
  /// </remarks>
  TDialog4DTelemetryFormat = class
  public
    /// <summary>
    /// Converts a telemetry kind (<c>TDialog4DTelemetryKind</c>) into readable text.
    /// </summary>
    class function TelemetryKindToText(const AKind: TDialog4DTelemetryKind)
      : string; static;

    /// <summary>
    /// Converts a close reason (<c>TDialog4DCloseReason</c>) into readable text.
    /// </summary>
    class function CloseReasonToText(const AReason: TDialog4DCloseReason)
      : string; static;

    /// <summary>
    /// Converts a dialog type (<c>TMsgDlgType</c>) into readable text.
    /// </summary>
    class function MsgDlgTypeToText(const ADlgType: TMsgDlgType)
      : string; static;

    /// <summary>
    /// Converts a modal result (<c>TModalResult</c>) into readable text.
    /// </summary>
    /// <remarks>
    /// <para>
    /// Standard Delphi modal result constants (<c>mrNone</c>..<c>mrClose</c>) are
    /// mapped to their symbolic names.
    /// </para>
    /// <para>
    /// Any other value is formatted as <c>Custom(N)</c> where <c>N</c> is the raw
    /// integer — this includes application-defined results regardless of their
    /// numeric range.
    /// </para>
    /// </remarks>
    class function ModalResultToText(const AResult: TModalResult)
      : string; static;

    /// <summary>
    /// Converts a dialog button kind (<c>TMsgDlgBtn</c>) into readable text.
    /// </summary>
    class function MsgDlgBtnToText(const ABtn: TMsgDlgBtn): string; static;

    /// <summary>
    /// Formats a telemetry record as a single-line text entry suitable for logs.
    /// </summary>
    /// <param name="AData">
    /// Telemetry record to format.
    /// </param>
    /// <param name="AProvider">
    /// Optional text provider used to resolve fallback titles when the telemetry
    /// record's <c>Title</c> field is empty.
    /// </param>
    /// <returns>
    /// A formatted string containing the event data with stable field ordering.
    /// </returns>
    class function FormatTelemetry(const AData: TDialog4DTelemetry;
      const AProvider: IDialog4DTextProvider = nil): string; static;
  end;

implementation

{ ============================== }
{ == TDialog4DTelemetryFormat == }
{ ============================== }

class function TDialog4DTelemetryFormat.TelemetryKindToText
  (const AKind: TDialog4DTelemetryKind): string;
begin
  case AKind of
    tkShowRequested:
      Result := 'ShowRequested';
    tkShowDisplayed:
      Result := 'ShowDisplayed';
    tkCloseRequested:
      Result := 'CloseRequested';
    tkClosed:
      Result := 'Closed';
    tkCallbackInvoked:
      Result := 'CallbackInvoked';
    tkCallbackSuppressed:
      Result := 'CallbackSuppressed';
    tkOwnerDestroying:
      Result := 'OwnerDestroying';
  else
    // Defensive fallback for future enum values.
    Result := 'Unknown';
  end;
end;

class function TDialog4DTelemetryFormat.CloseReasonToText
  (const AReason: TDialog4DCloseReason): string;
begin
  case AReason of
    crNone:
      Result := 'None';
    crButton:
      Result := 'Button';
    crBackdrop:
      Result := 'Backdrop';
    crKeyEsc:
      Result := 'KeyEsc';
    crKeyEnter:
      Result := 'KeyEnter';
    crOwnerDestroying:
      Result := 'OwnerDestroying';
    crProgrammatic:
      Result := 'Programmatic';
  else
    // Defensive fallback for future enum values.
    Result := 'Unknown';
  end;
end;

class function TDialog4DTelemetryFormat.MsgDlgTypeToText(const ADlgType
  : TMsgDlgType): string;
begin
  case ADlgType of
    TMsgDlgType.mtWarning:
      Result := 'Warning';
    TMsgDlgType.mtError:
      Result := 'Error';
    TMsgDlgType.mtInformation:
      Result := 'Information';
    TMsgDlgType.mtConfirmation:
      Result := 'Confirmation';
    TMsgDlgType.mtCustom:
      Result := 'Custom';
  else
    // Defensive fallback for future enum values.
    Result := 'Unknown';
  end;
end;

class function TDialog4DTelemetryFormat.ModalResultToText
  (const AResult: TModalResult): string;
begin
  // Standard Delphi modal result constants are mapped to symbolic names.
  // Any value not in this set is an application-defined result and is
  // formatted as Custom(N) regardless of its numeric range.
  case AResult of
    mrNone:
      Exit('None');
    mrOk:
      Exit('OK');
    mrCancel:
      Exit('Cancel');
    mrYes:
      Exit('Yes');
    mrNo:
      Exit('No');
    mrAbort:
      Exit('Abort');
    mrRetry:
      Exit('Retry');
    mrIgnore:
      Exit('Ignore');
    mrAll:
      Exit('All');
    mrNoToAll:
      Exit('NoToAll');
    mrYesToAll:
      Exit('YesToAll');
    mrHelp:
      Exit('Help');
    mrClose:
      Exit('Close');
  end;

  Result := 'Custom(' + IntToStr(Ord(AResult)) + ')';
end;

class function TDialog4DTelemetryFormat.MsgDlgBtnToText
  (const ABtn: TMsgDlgBtn): string;
begin
  case ABtn of
    TMsgDlgBtn.mbOK:
      Result := 'OK';
    TMsgDlgBtn.mbCancel:
      Result := 'Cancel';
    TMsgDlgBtn.mbYes:
      Result := 'Yes';
    TMsgDlgBtn.mbNo:
      Result := 'No';
    TMsgDlgBtn.mbAbort:
      Result := 'Abort';
    TMsgDlgBtn.mbRetry:
      Result := 'Retry';
    TMsgDlgBtn.mbIgnore:
      Result := 'Ignore';
    TMsgDlgBtn.mbAll:
      Result := 'All';
    TMsgDlgBtn.mbNoToAll:
      Result := 'NoToAll';
    TMsgDlgBtn.mbYesToAll:
      Result := 'YesToAll';
    TMsgDlgBtn.mbHelp:
      Result := 'Help';
    TMsgDlgBtn.mbClose:
      Result := 'Close';
  else
    // Defensive fallback for future enum values.
    Result := 'Unknown';
  end;
end;

class function TDialog4DTelemetryFormat.FormatTelemetry
  (const AData: TDialog4DTelemetry;
  const AProvider: IDialog4DTextProvider): string;
(*
  Single-line telemetry formatter.

  Strategy
  - Resolve four optional fields with explicit fallbacks:
    * Title: prefer AData.Title; if empty, ask the optional provider
      for a default title for the dialog type.
    * ButtonCaption: prefer AData.ButtonCaption; if empty, render '-'
      so the field stays visible and aligned in log output.
    * EventDateTime: prefer the snapshot's own timestamp; fall back to
      Now only on legacy paths where the snapshot does not carry one.
    * ErrorMessage: appended as an optional final field, with embedded
      quotes escaped (" → "").
  - Concatenate all fields into a single line with stable ordering. The
    visual alignment of the '+' operators is intentional: it lets a reader
    see at a glance which prefix pairs with which value.

  Outcomes
  - Returns a self-contained string suitable for direct logging, console
    output, or demo instrumentation. Never raises under normal use.

  Invariants
  - The output is single-line: no embedded line breaks come from the
    formatter itself (caller-supplied strings are not sanitized for
    newlines beyond quote-escaping the ErrorMessage).
  - Field ordering is stable across calls so log lines remain comparable.
*)
var
  LTitle: string;
  LButtonCaption: string;
  LEventText: string;
  LErrorText: string;
begin
  LTitle := AData.Title;
  if (LTitle.Trim = '') and Assigned(AProvider) then
    LTitle := AProvider.TitleForType(AData.DialogType);

  LButtonCaption := AData.ButtonCaption;
  if LButtonCaption.Trim = '' then
    LButtonCaption := '-';

  if AData.EventDateTime > 0 then
    LEventText := FormatDateTime('hh:nn:ss.zzz', AData.EventDateTime)
  else
    LEventText := FormatDateTime('hh:nn:ss.zzz', Now);

  if AData.ErrorMessage.Trim <> '' then
    LErrorText := '  Error="' + AData.ErrorMessage.Replace('"', '""') + '"'
  else
    LErrorText := '';

  Result := LEventText + '  ' + TelemetryKindToText(AData.Kind) + '  Type=' +
    MsgDlgTypeToText(AData.DialogType) + '  Reason=' +
    CloseReasonToText(AData.CloseReason) + '  Result=' +
    ModalResultToText(AData.Result) + '  Default=' +
    ModalResultToText(AData.DefaultResult) + '  Cancel=' +
    BoolToStr(AData.HasCancelButton, True) + '  Buttons=' +
    IntToStr(AData.ButtonsCount) + '  Len=' + IntToStr(AData.MessageLen) +
    '  ButtonKind=' + MsgDlgBtnToText(AData.ButtonKind) + '  ButtonCaption=' +
    '"' + LButtonCaption + '"' + '  ButtonDefault=' +
    BoolToStr(AData.ButtonWasDefault, True) + '  ElapsedMs=' +
    AData.ElapsedMs.ToString + '  Title=' + '"' + LTitle + '"' + LErrorText;
end;

end.
