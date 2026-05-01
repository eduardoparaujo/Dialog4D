// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Eduardo P. Araujo
// https://github.com/eduardoparaujo/Dialog4D

{*
  Unit   : DialogService4D
  Purpose: Migration-friendly adapter facade over Dialog4D. Provides a
           TDialogService-style surface for common asynchronous dialog calls
           so existing FMX codebases can adopt Dialog4D with minimal source
           changes.

  Part of the Dialog4D migration facade layer.

  Author        : Eduardo P. Araujo
  Created       : 2026-04-26
  Last modified : 2026-05-01
  Version       : 1.0.1

  Notes:
    - Migration recipe for common asynchronous dialog calls:
        * Add DialogService4D to the uses clause.
        * Replace TDialogService. with TDialogService4D. where appropriate.
        * Use MessageDialogAsync for Dialog4D-backed asynchronous dialogs.

    - This unit is intentionally thin. It forwards calls to TDialog4D and
      exists only to reduce migration friction.

    - For new code, prefer using TDialog4D directly. This facade exists
      primarily for source-level migration convenience, not as a full clone
      of FMX.DialogService.

    - DialogService4D does not attempt to reproduce every overload,
      behavioral detail, or platform-specific nuance of FMX.DialogService.
      Its purpose is to expose the Dialog4D asynchronous dialog pipeline
      through a familiar adapter surface.

  Important:
    - CloseDialog has no equivalent in FMX.DialogService. It is provided
      here as a Dialog4D extension and forwards directly to
      TDialog4D.CloseDialog.

    - Callback execution semantics are inherited from TDialog4D. This adapter
      only wraps the callback type and does not introduce a separate dispatch
      or lifetime model.

  History:
    1.0.1 — 2026-05-01 — Documentation hardening and adapter cleanup.
      • Replaced "drop-in replacement" language with a more precise
        migration-friendly adapter contract.
      • Clarified that the facade is not a full behavioral clone of
        FMX.DialogService.
      • Added a small WrapOnClose helper to avoid duplicated callback wrapper
        code in the standard and custom overloads.
      • Updated comments to make clear that callback dispatch/lifetime
        semantics are inherited from TDialog4D.

    1.0.0 — 2026-04-26 — Initial public release.
      • Introduced TDialogService4D as a thin adapter over TDialog4D.
      • Added standard-button and custom-button asynchronous dialog overloads.
      • Added CloseDialog as a Dialog4D-specific extension.
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
  /// compatibility with <c>TDialogService</c>-style asynchronous code.
  /// </summary>
  /// <remarks>
  /// <para>
  /// Functionally identical to <c>TDialog4DResultProc</c> — kept as a separate
  /// alias so callers migrating from <c>FMX.DialogService</c> can preserve the
  /// original parameter naming (<c>OnClose</c>) without renaming variables.
  /// </para>
  /// <para>
  /// Dispatch and lifetime semantics are inherited from <c>TDialog4D</c>.
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
  /// Provides a familiar <c>TDialogService</c>-style surface for common
  /// asynchronous dialog calls while delegating behavior to <c>TDialog4D</c>.
  /// </para>
  /// <para>
  /// This class is a migration helper, not a full replacement for every
  /// <c>FMX.DialogService</c> overload or platform-specific behavior.
  /// </para>
  /// </remarks>
  TDialogService4D = class
  public

    { =============================================== }
    { == Standard button overload (TMsgDlgButtons) == }
    { =============================================== }

    /// <summary>
    /// Shows a Dialog4D dialog using standard <c>TMsgDlgBtn</c> buttons.
    /// </summary>
    /// <remarks>
    /// <para>
    /// Migration-friendly adapter for common asynchronous
    /// <c>TDialogService</c>-style calls.
    /// </para>
    /// <para>
    /// The call is forwarded to
    /// <c>TDialog4D.MessageDialogAsync(TMsgDlgButtons)</c>.
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
    /// Shows a Dialog4D dialog using fully custom buttons.
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
    /// <para>
    /// May be called from worker code; the actual close semantics are provided
    /// by <c>TDialog4D.CloseDialog</c>.
    /// </para>
    /// <para>Silently ignored if no dialog is active.</para>
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

{ ======================= }
{ == Unit-scope helper == }
{ ======================= }

function WrapOnClose(const AOnClose: TDialogService4DOnClose)
  : TDialog4DResultProc;
begin
  Result :=
    procedure(const R: TModalResult)
    begin
      if Assigned(AOnClose) then
        AOnClose(R);
    end;
end;

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
  // TDialog4DResultProc closure. The actual dialog lifecycle, queueing,
  // callback dispatch and telemetry behavior are owned by TDialog4D.
  TDialog4D.MessageDialogAsync(AMessage, ADialogType, AButtons, ADefaultButton,
    WrapOnClose(AOnClose), ATitle, AParent, ACancelable);
end;

class procedure TDialogService4D.MessageDialogAsync(const AMessage: string;
  const ADialogType: TMsgDlgType; const AButtons: TArray<TDialog4DCustomButton>;
  const AOnClose: TDialogService4DOnClose; const ATitle: string;
  const AParent: TCommonCustomForm; const ACancelable: Boolean);
begin
  // Same adapter pattern as the standard overload — see comment there.
  TDialog4D.MessageDialogAsync(AMessage, ADialogType, AButtons,
    WrapOnClose(AOnClose), ATitle, AParent, ACancelable);
end;

class procedure TDialogService4D.CloseDialog(const AForm: TCommonCustomForm;
  const AResult: TModalResult);
begin
  TDialog4D.CloseDialog(AForm, AResult);
end;

end.

