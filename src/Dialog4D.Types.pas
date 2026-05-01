// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Eduardo P. Araujo
// https://github.com/eduardoparaujo/Dialog4D

{*
  Unit   : Dialog4D.Types
  Purpose: Core public type definitions for Dialog4D — enums, records,
           interfaces, callbacks and normalized button descriptors used
           across the library.

  Part of the Dialog4D public type system.

  Author        : Eduardo P. Araujo
  Created       : 2026-04-26
  Last modified : 2026-05-01
  Version       : 1.0.1

  Notes:
    - This unit defines the common language shared by configuration,
      telemetry, visual hosting, await helpers and custom button flows.

    - Dialog4D is a lightweight, no-third-party-dependency asynchronous
      dialog library for Delphi FMX. It provides a complementary FMX-rendered
      dialog layer alongside FMX.DialogService for applications that need
      themed presentation, per-form queueing, request-time configuration
      snapshots, structured telemetry, and worker-thread integration across
      Windows, macOS, iOS and Android.

    - Key features reflected in this unit:
        * Per-form FIFO queue — dialogs for the same form do not overlap.
        * Worker-thread await — TDialog4DAwait can block a background thread
          without blocking the main thread.
        * Custom buttons — arbitrary captions and TModalResult values, except
          mrNone, which is reserved as the internal "no result" value.
        * Structured telemetry — lifecycle events with close-reason and
          triggered-button tracking.
        * Theme snapshots — visual/behavioral theme values are copied by
          value at request time.

  Important:
    - TDialog4DTheme is intended to behave as a true snapshot copied by
      value at request time. Keep its fields limited to value types so
      queued dialogs remain isolated from later configuration changes.

    - TDialog4DButtonConfiguration is an internal-normalized shape used by
      the visual host. It may be built either from standard TMsgDlgBtn
      values or from TDialog4DCustomButton records.

    - Telemetry callback events describe Dialog4D's close-callback pipeline.
      In the public facade, the visual host invokes an internal close callback
      that queues the application OnResult dispatch onto the main loop.
      The final OnResult dispatch is skipped when the parent form enters
      destruction before that queued dispatch runs. Telemetry should therefore
      be interpreted as Dialog4D lifecycle observability, not as proof that
      application code completed.

  History:
    1.0.1 — 2026-05-01 — Contract wording and custom-button validation hardening.
      • Aligned positioning wording with the rest of the project: Dialog4D is
        presented as a complementary FMX-rendered dialog layer alongside
        FMX.DialogService, scoped to specific coordination needs (theming,
        per-form queueing, snapshots, telemetry, worker-thread integration).
      • Clarified that Dialog4D has no third-party dependency rather than no
        dependency at all, because it intentionally depends on FMX.
      • Clarified telemetry callback semantics: the host's internal close
        callback queues the application OnResult dispatch onto the main loop,
        and that final dispatch is skipped when parent-form destruction begins
        before the queued dispatch runs.
      • Documented mrNone as a reserved result and added helper-constructor
        validation in TDialog4DCustomButton.Make.
      • Kept TDialog4DTheme snapshot guidance explicit: value fields only.

    1.0.0 — 2026-04-26 — Initial public release.
      • Introduced shared public types for theme, text providers, callbacks,
        telemetry, custom buttons and normalized host button configuration.
*}

unit Dialog4D.Types;

interface

uses
  System.SysUtils,
  System.UITypes;

type
  { ================= }
  { == Result type == }
  { ================= }

  /// <summary>
  /// Callback invoked when a dialog finishes and produces a modal result.
  /// </summary>
  /// <remarks>
  /// <para>
  /// The callback is dispatched by the public Dialog4D facade after the visual
  /// host has produced a result. It should return quickly and avoid long
  /// blocking work on the main thread.
  /// </para>
  /// </remarks>
  TDialog4DResultProc = reference to procedure(const AResult: TModalResult);

  { ====================== }
  { == Text abstraction == }
  { ====================== }

  /// <summary>
  /// Abstraction responsible for providing localized/default button captions
  /// and default titles for dialog types.
  /// </summary>
  /// <remarks>
  /// <para>
  /// Implementations are registered globally via
  /// <c>TDialog4D.ConfigureTextProvider</c>.
  /// </para>
  /// <para>
  /// The default implementation (<c>TDialog4DDefaultTextProvider</c>) supplies
  /// English captions and titles.
  /// </para>
  /// </remarks>
  IDialog4DTextProvider = interface
    ['{9D2F8E7A-0D3D-4A86-9B3E-6A9E4F2E1B11}']
    function ButtonText(const ABtn: TMsgDlgBtn): string;
    function TitleForType(const ADlgType: TMsgDlgType): string;
  end;

  { ============================ }
  { == Message text alignment == }
  { ============================ }

  /// <summary>
  /// Horizontal alignment of the dialog message body text.
  /// </summary>
  /// <remarks>
  /// <para>
  /// • <c>dtaCenter</c> — centered text, suitable for short messages.
  /// </para>
  /// <para>
  /// • <c>dtaLeading</c> — left-aligned text, recommended for longer or
  /// multi-line messages.
  /// </para>
  /// <para>
  /// • <c>dtaTrailing</c> — right-aligned text, useful for RTL layouts or
  /// specific design needs.
  /// </para>
  /// <para>
  /// The title is always centered regardless of this setting.
  /// </para>
  /// </remarks>
  TDialog4DTextAlign = (dtaCenter, dtaLeading, dtaTrailing);

  { =============== }
  { == Telemetry == }
  { =============== }

  /// <summary>
  /// Lifecycle events emitted by <c>Dialog4D</c> telemetry.
  /// </summary>
  /// <remarks>
  /// <para>
  /// • <c>tkShowRequested</c> — request accepted by the public API.
  /// </para>
  /// <para>
  /// • <c>tkShowDisplayed</c> — dialog became visible to the user.
  /// </para>
  /// <para>
  /// • <c>tkCloseRequested</c> — close was triggered by a button, key,
  /// backdrop, programmatic close, or owner destruction.
  /// </para>
  /// <para>
  /// • <c>tkClosed</c> — visual host completed its close finalization.
  /// </para>
  /// <para>
  /// • <c>tkCallbackInvoked</c> — Dialog4D's close-callback pipeline was
  /// invoked.
  /// </para>
  /// <para>
  /// • <c>tkCallbackSuppressed</c> — close callback was skipped, usually
  /// because the parent form was destroying.
  /// </para>
  /// <para>
  /// • <c>tkOwnerDestroying</c> — parent form began destruction while the
  /// dialog was active.
  /// </para>
  /// </remarks>
  TDialog4DTelemetryKind = (tkShowRequested, tkShowDisplayed, tkCloseRequested,
    tkClosed, tkCallbackInvoked, tkCallbackSuppressed, tkOwnerDestroying);

  /// <summary>
  /// Logical reason why a dialog was closed.
  /// </summary>
  /// <remarks>
  /// <para>
  /// <c>crProgrammatic</c> is set when the caller explicitly closes the dialog
  /// via <c>TDialog4D.CloseDialog</c>.
  /// </para>
  /// <para>
  /// <c>crOwnerDestroying</c> is set when the parent form is being destroyed
  /// while the dialog is still active — in that case user-result delivery is
  /// suppressed.
  /// </para>
  /// </remarks>
  TDialog4DCloseReason = (crNone, crButton, crBackdrop, crKeyEsc, crKeyEnter,
    crOwnerDestroying, crProgrammatic);

  /// <summary>
  /// Immutable telemetry snapshot emitted during the dialog lifecycle.
  /// </summary>
  /// <remarks>
  /// <para>
  /// This record is a snapshot — it is safe to consume even after the dialog
  /// visual tree has been destroyed.
  /// </para>
  /// <para>
  /// Dialog4D initializes the record before emission. Consumers should still
  /// treat unknown future enum values defensively when formatting telemetry.
  /// </para>
  /// </remarks>
  TDialog4DTelemetry = record
    Kind: TDialog4DTelemetryKind;

    DialogType: TMsgDlgType;
    Title: string;
    MessageLen: Integer;

    ButtonsCount: Integer;
    HasCancelButton: Boolean;
    DefaultResult: TModalResult;

    Result: TModalResult;
    CloseReason: TDialog4DCloseReason;

    ButtonKind: TMsgDlgBtn;
    ButtonCaption: string;
    ButtonWasDefault: Boolean;

    Tick: UInt64;
    ElapsedMs: UInt64;
    EventDateTime: TDateTime;

    /// <summary>
    /// Optional diagnostic text associated with the event.
    /// </summary>
    /// <remarks>
    /// <para>Empty on normal paths.</para>
    /// </remarks>
    ErrorMessage: string;
  end;

  /// <summary>
  /// Telemetry sink callback.
  /// </summary>
  /// <remarks>
  /// <para><b>Contract:</b></para>
  /// <para>Must be non-blocking.</para>
  /// <para>Should not raise exceptions.</para>
  /// <para>
  /// Exceptions raised inside the sink are silently swallowed by Dialog4D
  /// telemetry emitters so diagnostic code cannot break the dialog lifecycle.
  /// </para>
  /// </remarks>
  TDialog4DTelemetryProc = reference to procedure
    (const AData: TDialog4DTelemetry);

  { =========== }
  { == Theme == }
  { =========== }

  /// <summary>
  /// Visual and behavioral configuration snapshot for a <c>Dialog4D</c>
  /// instance.
  /// </summary>
  /// <remarks>
  /// <para>
  /// The theme is captured at request time, so later global changes via
  /// <c>TDialog4D.ConfigureTheme</c> do not affect dialogs that are already
  /// queued or visible.
  /// </para>
  /// <para>
  /// Keep this record limited to value-type fields. Adding object references,
  /// interfaces, dynamic arrays or other managed state would weaken the
  /// snapshot guarantee unless the facade also performs a deep copy.
  /// </para>
  /// <para>
  /// Use <c>TDialog4DTheme.Default</c> as a starting point and override only
  /// the fields you want to customize.
  /// </para>
  /// </remarks>
  TDialog4DTheme = record
  public
    { == Geometry == }
    DialogWidth: Single;
    DialogMinHeight: Single;
    DialogMaxHeightRatio: Single;
    ContentMinHeight: Single;
    CornerRadius: Single;

    { == Overlay == }
    OverlayOpacity: Single;
    OverlayColor: TAlphaColor;

    { == Typography == }
    TitleFontSize: Single;
    MessageFontSize: Single;

    /// <summary>
    /// Horizontal alignment of the message body text.
    /// </summary>
    /// <remarks>
    /// <para>
    /// Default: <c>dtaCenter</c>. Use <c>dtaLeading</c> for long or multi-line
    /// messages.
    /// </para>
    /// <para>The title is always centered regardless of this setting.</para>
    /// </remarks>
    MessageTextAlign: TDialog4DTextAlign;

    { == Buttons == }
    ButtonHeight: Single;
    ButtonFontSize: Single;

    ButtonNeutralFillColor: TAlphaColor;
    ButtonNeutralTextColor: TAlphaColor;
    ButtonNeutralBorderColor: TAlphaColor;

    { == Surface / text colors == }
    SurfaceColor: TAlphaColor;
    TextTitleColor: TAlphaColor;
    TextMessageColor: TAlphaColor;

    { == Accent colors by semantic role == }
    AccentInfoColor: TAlphaColor;
    AccentWarningColor: TAlphaColor;
    AccentErrorColor: TAlphaColor;
    AccentConfirmColor: TAlphaColor;
    AccentNeutralColor: TAlphaColor;

    { == Semantics == }

    /// <summary>
    /// When <c>True</c>, <c>mrClose</c> is treated the same as <c>mrCancel</c>
    /// for cancel-like actions (Esc key, backdrop tap, hardware back button on
    /// Android).
    /// </summary>
    TreatCloseAsCancel: Boolean;

    { == Default button highlight == }
    ShowDefaultButtonHighlight: Boolean;
    DefaultButtonHighlightColor: TAlphaColor;
    DefaultButtonHighlightThickness: Single;
    DefaultButtonHighlightOpacity: Single;
    DefaultButtonHighlightInset: Single;

    /// <summary>
    /// Returns a fully-populated theme with deterministic defaults.
    /// </summary>
    class function Default: TDialog4DTheme; static;
  end;

  { ==================== }
  { == Custom buttons == }
  { ==================== }

  /// <summary>
  /// Defines a fully custom dialog button with an arbitrary caption and a
  /// non-<c>mrNone</c> <c>TModalResult</c> value.
  /// </summary>
  /// <remarks>
  /// <para>
  /// Use this type with the <c>TDialog4D.MessageDialogAsync</c> overload that
  /// accepts <c>TArray&lt;TDialog4DCustomButton&gt;</c> instead of
  /// <c>TMsgDlgButtons</c>. Custom buttons bypass the <c>TMsgDlgBtn</c> /
  /// <c>IDialog4DTextProvider</c> pipeline entirely — the <c>Caption</c> you
  /// provide is used exactly as given.
  /// </para>
  /// <para><b>ModalResult values:</b></para>
  /// <para>
  /// You may use any <c>TModalResult</c> value, including application-defined
  /// ones above the standard range. The only reserved value is <c>mrNone</c>
  /// (<c>0</c>), which Dialog4D uses internally to signal "no result".
  /// Helper constructors reject <c>mrNone</c>, and the public facade also
  /// validates custom-button arrays before showing a dialog.
  /// </para>
  /// <para><b>Cancel detection:</b></para>
  /// <para>
  /// A button with <c>ModalResult = mrCancel</c> is treated as a cancel-like
  /// button (backdrop tap, Esc key). If <c>TreatCloseAsCancel</c> is
  /// <c>True</c> in the theme, <c>mrClose</c> is also treated as cancel.
  /// </para>
  /// <para><b>Telemetry:</b></para>
  /// <para>
  /// The <c>ButtonKind</c> field in <c>TDialog4DTelemetry</c> will show
  /// <c>mbOK</c> for all custom buttons (it is a placeholder — <c>TMsgDlgBtn</c>
  /// has no custom value). Use <c>ButtonCaption</c> to identify which button
  /// was clicked in telemetry.
  /// </para>
  /// <para><b>Construction:</b></para>
  /// <para>
  /// Use <c>TDialog4DCustomButton.Make(...)</c> or one of the convenience
  /// shortcuts <c>Default</c> / <c>Destructive</c> / <c>Cancel</c>.
  /// </para>
  /// <para><b>Example:</b></para>
  /// <code>
  /// TDialog4D.MessageDialogAsync(
  ///   'Your session is about to expire.',
  ///   TMsgDlgType.mtWarning,
  ///   [
  ///     TDialog4DCustomButton.Make('Stay Logged In', mrOk, True),
  ///     TDialog4DCustomButton.Make('Log Out Now',    mrCancel)
  ///   ],
  ///   procedure(const R: TModalResult)
  ///   begin
  ///     if R = mrOk then
  ///       RenewSession;
  ///   end
  /// );
  /// </code>
  /// </remarks>
  TDialog4DCustomButton = record
    /// <summary>Text displayed on the button face.</summary>
    Caption: string;

    /// <summary>
    /// Result delivered to OnResult when this button is clicked.
    /// Must not be <c>mrNone</c>.
    /// </summary>
    ModalResult: TModalResult;

    /// <summary>
    /// When <c>True</c>, this button is rendered as the primary action and is
    /// triggered by the Enter key on desktop.
    /// </summary>
    /// <remarks>
    /// <para>
    /// At most one button in the set should have <c>IsDefault = True</c>.
    /// </para>
    /// <para>
    /// If none is <c>True</c>, the first valid button is promoted automatically
    /// by the visual host.
    /// </para>
    /// </remarks>
    IsDefault: Boolean;

    /// <summary>
    /// When <c>True</c>, this button is rendered as a destructive action.
    /// Suitable for Delete, Remove, Discard, etc.
    /// </summary>
    IsDestructive: Boolean;

    /// <summary>
    /// Creates a <c>TDialog4DCustomButton</c> with all fields explicitly set.
    /// </summary>
    /// <exception cref="EArgumentException">
    /// Raised when <c>AModalResult = mrNone</c>.
    /// </exception>
    class function Make(const ACaption: string;
      const AModalResult: TModalResult; const AIsDefault: Boolean = False;
      const AIsDestructive: Boolean = False): TDialog4DCustomButton; static;

    /// <summary>
    /// Shortcut for a default (primary) action button.
    /// </summary>
    /// <remarks>
    /// <para>
    /// Equivalent to <c>Make(ACaption, AModalResult, True, False)</c>.
    /// </para>
    /// </remarks>
    class function Default(const ACaption: string;
      const AModalResult: TModalResult): TDialog4DCustomButton; static;

    /// <summary>
    /// Shortcut for a destructive action button.
    /// </summary>
    /// <remarks>
    /// <para>
    /// Equivalent to <c>Make(ACaption, AModalResult, False, True)</c>.
    /// </para>
    /// </remarks>
    class function Destructive(const ACaption: string;
      const AModalResult: TModalResult): TDialog4DCustomButton; static;

    /// <summary>
    /// Shortcut for a cancel button (<c>ModalResult = mrCancel</c>).
    /// </summary>
    /// <remarks>
    /// <para>
    /// Equivalent to <c>Make(ACaption, mrCancel, False, False)</c>.
    /// </para>
    /// <para>This button acts as the Esc / backdrop-tap target.</para>
    /// </remarks>
    class function Cancel(const ACaption: string)
      : TDialog4DCustomButton; static;
  end;

  { ============================== }
  { == Normalized button config == }
  { ============================== }

  /// <summary>
  /// Normalized button configuration consumed by the visual host.
  /// </summary>
  /// <remarks>
  /// <para>
  /// Built from either <c>TMsgDlgBtn</c> (standard path) or
  /// <c>TDialog4DCustomButton</c> (custom path). The visual host receives this
  /// normalized shape and does not need to know which public overload created
  /// the button.
  /// </para>
  /// <para>
  /// For custom buttons, <c>Btn</c> is set to <c>mbOK</c> as a placeholder —
  /// telemetry consumers should use <c>Caption</c> to identify the button.
  /// </para>
  /// </remarks>
  TDialog4DButtonConfiguration = record
    /// <summary>
    /// Standard button kind. For custom buttons this is <c>mbOK</c> as a
    /// placeholder.
    /// </summary>
    Btn: TMsgDlgBtn;

    /// <summary>Modal result produced by the button.</summary>
    ModalResult: TModalResult;

    /// <summary>Text displayed on the rendered button.</summary>
    Caption: string;

    /// <summary>Whether this button is the default/Enter target.</summary>
    IsDefault: Boolean;

    /// <summary>Whether this button is rendered as destructive.</summary>
    IsDestructive: Boolean;
  end;

implementation

{ ============================ }
{ == TDialog4DTheme.Default == }
{ ============================ }

class function TDialog4DTheme.Default: TDialog4DTheme;
begin
  // Zero the entire record first so any field not explicitly set below
  // (including future additions) starts from a deterministic default.
  FillChar(Result, SizeOf(Result), 0);

  { -- Geometry -- }
  Result.DialogWidth := 320;
  Result.DialogMinHeight := 170;
  Result.DialogMaxHeightRatio := 0.85;
  Result.ContentMinHeight := 50;
  Result.CornerRadius := 14;

  { -- Overlay -- }
  Result.OverlayOpacity := 0.45;
  Result.OverlayColor := $FF000000;

  { -- Typography -- }
  Result.TitleFontSize := 16;
  Result.MessageFontSize := 14;
  Result.MessageTextAlign := dtaCenter;

  { -- Buttons -- }
  Result.ButtonHeight := 44;
  Result.ButtonFontSize := 14;

  Result.ButtonNeutralFillColor := $FFF3F3F3;
  Result.ButtonNeutralTextColor := $FF2C2C2C;
  Result.ButtonNeutralBorderColor := $FFCECECE;

  { -- Surface / text colors -- }
  Result.SurfaceColor := TAlphaColorRec.White;
  Result.TextTitleColor := $FF2C2C2C;
  Result.TextMessageColor := $FF848484;

  { -- Accent colors by semantic role -- }
  Result.AccentInfoColor := $FF3085D6;
  Result.AccentWarningColor := $FFF3A867;
  Result.AccentErrorColor := $FFE64D4D;
  Result.AccentConfirmColor := $FF9E9E9E;
  Result.AccentNeutralColor := $FFEFEFEF;

  { -- Semantics -- }
  Result.TreatCloseAsCancel := False;

  { -- Default button highlight -- }
  Result.ShowDefaultButtonHighlight := True;
  Result.DefaultButtonHighlightColor := TAlphaColorRec.White;
  Result.DefaultButtonHighlightThickness := 1;
  Result.DefaultButtonHighlightOpacity := 0.95;
  Result.DefaultButtonHighlightInset := 1;
end;

{ =========================== }
{ == TDialog4DCustomButton == }
{ =========================== }

class function TDialog4DCustomButton.Make(const ACaption: string;
  const AModalResult: TModalResult; const AIsDefault: Boolean;
  const AIsDestructive: Boolean): TDialog4DCustomButton;
begin
  if AModalResult = mrNone then
    raise EArgumentException.Create
      ('Dialog4D: custom button ModalResult cannot be mrNone.');

  Result.Caption := ACaption;
  Result.ModalResult := AModalResult;
  Result.IsDefault := AIsDefault;
  Result.IsDestructive := AIsDestructive;
end;

class function TDialog4DCustomButton.Default(const ACaption: string;
  const AModalResult: TModalResult): TDialog4DCustomButton;
begin
  Result := Make(ACaption, AModalResult, True, False);
end;

class function TDialog4DCustomButton.Destructive(const ACaption: string;
  const AModalResult: TModalResult): TDialog4DCustomButton;
begin
  Result := Make(ACaption, AModalResult, False, True);
end;

class function TDialog4DCustomButton.Cancel(const ACaption: string)
  : TDialog4DCustomButton;
begin
  Result := Make(ACaption, mrCancel, False, False);
end;

end.

