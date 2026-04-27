// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Eduardo P. Araujo
// https://github.com/eduardoparaujo/Dialog4D

{*
  Unit   : DialogService4D
  Purpose: Migration and compatibility facade over Dialog4D. Provides a
           TDialogService-style surface so existing codebases can adopt
           Dialog4D with minimal source changes.

  Part of the Dialog4D framework - see Dialog4D.Types for the overview.

  Author        : Eduardo P. Araujo
  Created       : 2026-04-26
  Last modified : 2026-04-26
  Version       : 1.0.0

  Notes:
    - Migration recipe:
        * Replace FMX.DialogService with DialogService4D in the uses clause.
        * Replace TDialogService. with TDialogService4D.
        * Existing code calling TDialogService.MessageDialog continues to
          compile against TDialogService4D.MessageDialogAsync with the same
          signature.

    - This unit is intentionally thin. It forwards calls to TDialog4D and
      exists only to reduce migration friction.

    - For new code, prefer using TDialog4D directly. This facade exists
      primarily for source-level compatibility with TDialogService callers.

  Important:
    - CloseDialog has no equivalent in FMX.DialogService. It is provided
      here as a Dialog4D extension and forwards directly to
      TDialog4D.CloseDialog.
*}

unit DialogService4D;

interface

uses
  System.UITypes,

  FMX.Forms,

  Dialog4D.Types;

type
  { ======================== }
  { == Migration callback == }
  { ======================== }

  /// <summary>
  /// Callback signature used by <c>DialogService4D</c> for migration-friendly
  /// compatibility with <c>TDialogService</c>-style code.
  /// </summary>
  /// <remarks>
  /// <para>
  /// Functionally identical to <c>TDialog4DResultProc</c> — kept as a separate
  /// alias so callers migrating from <c>FMX.DialogService</c> can preserve the
  /// original parameter naming (<c>OnClose</c>) without renaming variables.
  /// </para>
  /// </remarks>
  TDialogService4DOnClose = reference to procedure(const AResult: TModalResult);

  { =================== }
  { == Facade class == }
  { =================== }

  /// <summary>
  /// Lightweight adapter facade over <c>Dialog4D</c>.
  /// </summary>
  /// <remarks>
  /// <para>
  /// Reduces migration friction when moving from <c>FMX.DialogService</c>
  /// to <c>Dialog4D</c>.
  /// </para>
  /// </remarks>
  TDialogService4D = class
  public

    { =============================================== }
    { == Standard button overload (TMsgDlgButtons) == }
    { =============================================== }

    /// <summary>
    /// Shows a dialog using standard <c>TMsgDlgBtn</c> buttons.
    /// </summary>
    /// <remarks>
    /// <para>
    /// Drop-in replacement for <c>TDialogService.MessageDialog</c>.
    /// </para>
    /// </remarks>
    class procedure MessageDialogAsync(const AMessage: string;
      const ADialogType: TMsgDlgType; const AButtons: TMsgDlgButtons;
      const ADefaultButton: TMsgDlgBtn; const AOnClose: TDialogService4DOnClose;
      const ATitle: string = ''; const AParent: TCommonCustomForm = nil;
      const ACancelable: Boolean = True); overload; static;

    { ============================================================ }
    { == Custom button overload (TArray<TDialog4DCustomButton>) == }
    { ============================================================ }

    /// <summary>
    /// Shows a dialog using fully custom buttons.
    /// </summary>
    /// <remarks>
    /// <para>
    /// Forwards to
    /// <c>TDialog4D.MessageDialogAsync(TArray&lt;TDialog4DCustomButton&gt;)</c>.
    /// </para>
    /// <para><b>Example:</b></para>
    /// <code>
    /// TDialogService4D.MessageDialogAsync(
    ///   'Do you want to save before closing?',
    ///   TMsgDlgType.mtConfirmation,
    ///   [
    ///     TDialog4DCustomButton.Default('Save and Close',       mrYes),
    ///     TDialog4DCustomButton.Make   ('Close Without Saving', mrNo),
    ///     TDialog4DCustomButton.Cancel ('Cancel')
    ///   ],
    ///   procedure(const R: TModalResult)
    ///   begin
    ///     case R of
    ///       mrYes: SaveAndClose;
    ///       mrNo:  CloseWithoutSaving;
    ///     end;
    ///   end
    /// );
    /// </code>
    /// </remarks>
    class procedure MessageDialogAsync(const AMessage: string;
      const ADialogType: TMsgDlgType;
      const AButtons: TArray<TDialog4DCustomButton>;
      const AOnClose: TDialogService4DOnClose; const ATitle: string = '';
      const AParent: TCommonCustomForm = nil;
      const ACancelable: Boolean = True); overload; static;

    { ======================== }
    { == Programmatic close == }
    { ======================== }

    /// <summary>
    /// Programmatically closes the currently visible dialog for the given form.
    /// </summary>
    /// <remarks>
    /// <para>Thread-safe. Silently ignored if no dialog is active.</para>
    /// <para>
    /// This method has no equivalent in <c>FMX.DialogService</c> — it is
    /// provided here as a <c>Dialog4D</c> extension and forwards directly to
    /// <c>TDialog4D.CloseDialog</c>.
    /// </para>
    /// </remarks>
    class procedure CloseDialog(const AForm: TCommonCustomForm = nil;
      const AResult: TModalResult = mrCancel); static;
  end;

implementation

uses
  Dialog4D;

{ ====================== }
{ == TDialogService4D == }
{ ====================== }

class procedure TDialogService4D.MessageDialogAsync(const AMessage: string;
  const ADialogType: TMsgDlgType; const AButtons: TMsgDlgButtons;
  const ADefaultButton: TMsgDlgBtn; const AOnClose: TDialogService4DOnClose;
  const ATitle: string; const AParent: TCommonCustomForm;
  const ACancelable: Boolean);
begin
  // Adapter wrapper: convert TDialogService4DOnClose into a
  // TDialog4DResultProc closure. Functionally identical, but the indirection
  // keeps the public callback type stable for migration callers.
  TDialog4D.MessageDialogAsync(AMessage, ADialogType, AButtons, ADefaultButton,
    procedure(const R: TModalResult)
    begin
      if Assigned(AOnClose) then
        AOnClose(R);
    end, ATitle, AParent, ACancelable);
end;

class procedure TDialogService4D.MessageDialogAsync(const AMessage: string;
  const ADialogType: TMsgDlgType; const AButtons: TArray<TDialog4DCustomButton>;
  const AOnClose: TDialogService4DOnClose; const ATitle: string;
  const AParent: TCommonCustomForm; const ACancelable: Boolean);
begin
  // Same adapter pattern as the standard overload — see comment there.
  TDialog4D.MessageDialogAsync(AMessage, ADialogType, AButtons,
    procedure(const R: TModalResult)
    begin
      if Assigned(AOnClose) then
        AOnClose(R);
    end, ATitle, AParent, ACancelable);
end;

class procedure TDialogService4D.CloseDialog(const AForm: TCommonCustomForm;
const AResult: TModalResult);
begin
  TDialog4D.CloseDialog(AForm, AResult);
end;

end.
