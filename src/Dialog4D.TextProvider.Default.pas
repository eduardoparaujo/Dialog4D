// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Eduardo P. Araujo
// https://github.com/eduardoparaujo/Dialog4D

{*
  Unit   : Dialog4D.TextProvider.Default
  Purpose: Built-in English implementation of IDialog4DTextProvider.
           Supplies the baseline button captions and default dialog titles
           used when no custom text provider has been registered via
           TDialog4D.ConfigureTextProvider.

  Part of the Dialog4D framework - see Dialog4D.Types for the overview.

  Author        : Eduardo P. Araujo
  Created       : 2026-04-26
  Last modified : 2026-04-26
  Version       : 1.0.0

  Notes:
    - This unit is intentionally simple and predictable. It serves as the
      default English text layer for Dialog4D and may be replaced or
      complemented by custom i18n providers.

    - Behavior:
        * ButtonText covers all 12 TMsgDlgBtn values with English captions.
        * An unrecognized button value falls back to the literal string
          'Button' — a defensive fallback that should never trigger in
          practice.
        * TitleForType returns localized titles for mtInformation,
          mtWarning, mtError and mtConfirmation.
        * mtCustom intentionally returns an empty string so the caller can
          supply an explicit title or show no title at all.
        * An unknown TMsgDlgType also returns an empty string.

  Important:
    - The provider is registered automatically as the global default in the
      TDialog4D class constructor and can be replaced at any time via
      TDialog4D.ConfigureTextProvider.
*}

unit Dialog4D.TextProvider.Default;

interface

uses
  System.UITypes,

  Dialog4D.Types;

type
  { =================================== }
  { == Default English text provider == }
  { =================================== }

  /// <summary>
  /// Default English text provider used by <c>Dialog4D</c> when no custom
  /// <c>IDialog4DTextProvider</c> is configured.
  /// </summary>
  /// <remarks>
  /// <para>• Provides English captions for all standard <c>TMsgDlgBtn</c> values.</para>
  /// <para>• Provides English titles for the four built-in dialog types (<c>mtInformation</c>, <c>mtWarning</c>, <c>mtError</c>, <c>mtConfirmation</c>).</para>
  /// <para>• <c>mtCustom</c> intentionally returns an empty title so the caller can provide an explicit title or show no title at all.</para>
  /// <para>
  /// This provider is deliberately simple and predictable, serving as the
  /// baseline text behavior for <c>Dialog4D</c>.
  /// </para>
  /// </remarks>
  TDialog4DDefaultTextProvider = class(TInterfacedObject, IDialog4DTextProvider)
  public
    /// <summary>
    /// Returns the default English caption for a standard dialog button.
    /// </summary>
    /// <param name="ABtn">
    /// The dialog button kind (<c>TMsgDlgBtn</c>).
    /// </param>
    /// <returns>
    /// The text string corresponding to the button. Returns <c>'Button'</c> for
    /// any value not explicitly covered (defensive fallback).
    /// </returns>
    function ButtonText(const ABtn: TMsgDlgBtn): string;

    /// <summary>
    /// Returns the default English title for a built-in dialog type.
    /// </summary>
    /// <param name="ADlgType">
    /// The message dialog type (<c>TMsgDlgType</c>).
    /// </param>
    /// <returns>
    /// The title text string. Returns an empty string for <c>mtCustom</c> and
    /// for any unrecognized type.
    /// </returns>
    function TitleForType(const ADlgType: TMsgDlgType): string;
  end;

implementation

{ ================================== }
{ == TDialog4DDefaultTextProvider == }
{ ================================== }

function TDialog4DDefaultTextProvider.ButtonText
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
      Result := 'No to All';
    TMsgDlgBtn.mbYesToAll:
      Result := 'Yes to All';
    TMsgDlgBtn.mbHelp:
      Result := 'Help';
    TMsgDlgBtn.mbClose:
      Result := 'Close';
  else
    // Defensive fallback for unexpected values — should not occur in
    // practice because all current TMsgDlgBtn values are covered above.
    Result := 'Button';
  end;
end;

function TDialog4DDefaultTextProvider.TitleForType(const ADlgType
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
      Result := '';
  else
    // Unknown type — no default title.
    Result := '';
  end;
end;

end.
