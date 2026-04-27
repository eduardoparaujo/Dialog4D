// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Eduardo P. Araujo
// https://github.com/eduardoparaujo/Dialog4D

{*
  Unit   : Dialog4D.Host.FMX
  Purpose: Internal FMX visual host for Dialog4D. Renders and manages a
           single dialog instance inside a parent form, including visual
           tree creation, layout recalculation, open/close animation,
           button layout, keyboard and back-button handling, lifecycle-safe
           cleanup, and structured telemetry emission.

  Part of the Dialog4D framework - see Dialog4D.Types for the overview.

  Author        : Eduardo P. Araujo
  Created       : 2026-04-26
  Last modified : 2026-04-26
  Version       : 1.0.0

  Notes:
    - This unit is part of the internal rendering pipeline and is not
      intended for direct use by application code. Public entry points are
      exposed through Dialog4D.pas.

    - Visual tree:
        * TLayout overlay
        * TRectangle backdrop
        * TRectangle card
        * TLayout header (icon wrap + title)
        * TVertScrollBox
        * TLayout content
        * TText message
        * TLayout button bar
        * TLayout buttons

    - Lifecycle:
        * dgsClosed → ShowDialog → dgsOpening → OnOpenFinished → dgsOpen
        * dgsOpen → CloseWithResult → dgsClosing → OnCloseFinished
        * OnCloseFinished → FinalizeCloseNow / FinalizeCloseAsync → dgsClosed

    - Platform notes:
        * Windows reserves a fixed-width strip on the right side of the
          content area so the scrollbar does not overlap the message text.
        * Android skips open/close animations to reduce touch-lifecycle
          timing issues; destruction is always deferred to the main loop via
          FinalizeCloseAsync.
        * Android back button (vkHardwareBack) is intercepted on OnKeyUp and
          always consumed (Key := 0) to prevent the OS from interpreting it
          as a navigation back and closing the activity.
        * Desktop (Windows/macOS): Enter triggers the default button, Esc
          triggers the cancel button when present and the dialog is
          cancelable.

  Important:
    - This host owns and drives the FMX visual tree of a single Dialog4D
      instance. It is created and destroyed by the public facade in
      Dialog4D.pas.

    - Cleanup is lifecycle-sensitive:
        * FinalizeCloseNow captures the effective close reason before
          Cleanup resets internal state.
        * TDialog4DFormHook is owned by the parent form and triggers safe
          async cleanup when the form is destroyed.

    - Telemetry is best-effort:
        * SafeEmitTelemetry emits all lifecycle events.
        * Exceptions raised by the telemetry sink are silently swallowed and
          must never affect dialog flow.

    - The default-button highlight is rendered as an inset TRectangle child
      of the button and is fully controlled by the active theme.
*}

unit Dialog4D.Host.FMX;

interface

uses
  System.Classes,
  System.Math,
  System.SysUtils,
  System.Types,
  System.UITypes,

  FMX.Ani,
  FMX.Controls,
  FMX.Forms,
  FMX.Graphics,
  FMX.Layouts,
  FMX.Objects,
  FMX.StdCtrls,
  FMX.Text,
  FMX.TextLayout,
  FMX.Types,

  Dialog4D.Types;

type
  { ======================= }
  { == Visual host class == }
  { ======================= }

  /// <summary>
  /// Internal visual host that owns and drives the FMX visual tree of a
  /// single <c>Dialog4D</c> instance. Created and destroyed by the public
  /// facade in <c>Dialog4D.pas</c>.
  /// </summary>
  TDialog4DHostFMX = class
  private type
    /// <summary>
    /// Internal lifecycle state of the host.
    /// </summary>
    TDialogState = (dgsClosed, dgsOpening, dgsOpen, dgsClosing);

    /// <summary>
    /// How buttons are laid out inside the button bar.
    /// </summary>
    TDialogButtonLayoutMode = (blmHorizontal, blmVertical);

  private
    { == Lifecycle / runtime flags == }
    FState: TDialogState;
    FFinalizing: Boolean;
    FHandlingResize: Boolean;
    FRebuildingButtons: Boolean;
    FButtonLayoutMode: TDialogButtonLayoutMode;

    { == Configuration == }
    FTheme: TDialog4DTheme;
    FParentForm: TCommonCustomForm;

    { == Telemetry == }
    FTelemetry: TDialog4DTelemetryProc;
    FOpenTick: UInt64;
    FCloseReason: TDialog4DCloseReason;

    { == Telemetry snapshots == }
    FTitleSnapshot: string;
    FMessageLenSnapshot: Integer;
    FButtonsCountSnapshot: Integer;
    FDefaultResultSnapshot: TModalResult;

    { == Triggered button (the one that produced the close) == }
    FTriggeredButtonKind: TMsgDlgBtn;
    FTriggeredButtonCaption: string;
    FTriggeredButtonWasDefault: Boolean;

    { == Button specs (normalized) == }
    FButtonSpecs: TArray<TDialog4DButtonConfiguration>;

    function TickMs: UInt64;
    function ElapsedMs: UInt64;

    procedure SafeEmitTelemetry(const AKind: TDialog4DTelemetryKind;
      const AResult: TModalResult = mrNone;
      const AReason: TDialog4DCloseReason = crNone;
      const AElapsedOverrideMs: UInt64 = 0; const AErrorMessage: string = '');

    procedure ResetTriggeredButtonInfo;
    procedure CaptureTriggeredButtonFromMeta(const AMeta: TObject);
    procedure CaptureTriggeredButtonFromIndex(const AIndex: Integer);

    function IsCancelLikeResult(const AResult: TModalResult): Boolean;
    function IndexOfFirstCancelableButton(const AButtonSpecs
      : TArray<TDialog4DButtonConfiguration>): Integer;
    function IndexOfFirstDefaultButton(const AButtonSpecs
      : TArray<TDialog4DButtonConfiguration>): Integer;
    function IndexOfFirstValidButton(const AButtonSpecs
      : TArray<TDialog4DButtonConfiguration>): Integer;
    function NormalizeButtonSpecs(const AButtonSpecs
      : TArray<TDialog4DButtonConfiguration>)
      : TArray<TDialog4DButtonConfiguration>;

    /// <summary>
    /// Converts TDialog4DTextAlign to FMX TTextAlign.
    /// </summary>
    function ToFMXTextAlign(const AAlign: TDialog4DTextAlign): TTextAlign;

    /// <summary>
    /// Attempts to focus the overlay so it can receive keyboard input on
    /// desktop and hardware back-button events on Android. Called for all
    /// platforms in <c>OnOpenFinished</c>.
    /// </summary>
    procedure TryFocusOverlay;

{$IF DEFINED(MSWINDOWS) OR DEFINED(MACOS)}
    procedure OverlayKeyDown(Sender: TObject; var Key: Word; var KeyChar: Char;
      Shift: TShiftState);
    procedure HandleDialogKey(var Key: Word; var KeyChar: Char;
      Shift: TShiftState);
    function ResolveDefaultResult(out AResult: TModalResult;
      out AIndex: Integer): Boolean;
    function ResolveCancelResult(out AResult: TModalResult;
      out AIndex: Integer): Boolean;
{$ENDIF}
{$IFDEF ANDROID}
    /// <summary>
    /// Intercepts the Android hardware back button (<c>vkHardwareBack</c>).
    /// </summary>
    /// <remarks>
    /// <para>
    /// Always consumes the key event (<c>Key := 0</c>) to prevent the OS from
    /// interpreting it as a navigation back and closing the activity.
    /// </para>
    /// <para>
    /// When the dialog is cancelable and a cancel-like button is present, also
    /// closes the dialog with that result (<c>crKeyEsc</c>).
    /// </para>
    /// </remarks>
    procedure OverlayKeyUpAndroid(Sender: TObject; var Key: Word;
      var KeyChar: Char; Shift: TShiftState);
{$ENDIF}
  private
    { == Form hook (owner-form lifecycle) == }
    FFormHook: TComponent;
    FOwnerDestroying: Boolean;

  private
    { == Visual tree == }
    FOverlay: TLayout;
    FBackdrop: TRectangle;
    FCard: TRectangle;
    FHeader: TLayout;
    FScrollBox: TVertScrollBox;
    FContent: TLayout;
    FIconWrap: TLayout;
    FIconCircle: TCircle;
    FIconGlyph: TLabel;
    FXBar1: TRectangle;
    FXBar2: TRectangle;
    FTitle: TLabel;
    FMessage: TText;
    FButtonBar: TLayout;
    FButtons: TLayout;

  private
    { == Result handling == }
    FOnResult: TDialog4DResultProc;
    FCancelable: Boolean;
    FHasCancelButton: Boolean;
    FClosingResult: TModalResult;
    FDialogType: TMsgDlgType;

  private
    { == Animations == }
    FAnimOpen: TFloatAnimation;
    FAnimClose: TFloatAnimation;

  private
    { == Layout cache == }
    FLastButtonsLayoutWidth: Single;

  private
    { == Visual tree construction and layout == }
    procedure EnsureUI(const AParent: TCommonCustomForm);
    procedure ApplyTheme;
    procedure ApplyIconForType(const ADlgType: TMsgDlgType);
    procedure SetupErrorIcon(const AIconSize: Single);
    procedure OverlayResized(Sender: TObject);

    function ResolveButtonLayoutMode(const AButtonSpecs
      : TArray<TDialog4DButtonConfiguration>): TDialogButtonLayoutMode;
    function CalculateHorizontalButtonWidth(const AButtonCount
      : Integer): Single;

    procedure BuildButtons(const AButtonSpecs
      : TArray<TDialog4DButtonConfiguration>);
    procedure BuildButtonsHorizontal(const AButtonSpecs
      : TArray<TDialog4DButtonConfiguration>);
    procedure BuildButtonsVertical(const AButtonSpecs
      : TArray<TDialog4DButtonConfiguration>);
    function CreateButtonControl(const AParent: TFmxObject;
      const ASpec: TDialog4DButtonConfiguration): TControl;
    procedure ApplyDefaultHighlight(const AButtonRect: TRectangle;
      const ASpec: TDialog4DButtonConfiguration);
    procedure ClearButtons;
    procedure RebuildButtonsIfNeeded;

    function MeasureTextHeight(const AText: string; const AMaxWidth: Single;
      const AFont: TFont; const AFontSize: Single): Single;
    procedure RecalcLayoutHeights;

  private
    { == Input handlers == }
    procedure BackdropTap(Sender: TObject; const Point: TPointF);
    procedure BackdropClick(Sender: TObject);
    procedure ButtonTap(Sender: TObject; const Point: TPointF);
    procedure ButtonClick(Sender: TObject);
    procedure ButtonMouseDown(Sender: TObject; AButton: TMouseButton;
      AShift: TShiftState; X, Y: Single);
    procedure ButtonMouseUp(Sender: TObject; AButton: TMouseButton;
      AShift: TShiftState; X, Y: Single);

  private
    { == Close pipeline == }
    procedure CloseWithResult(const AResult: TModalResult);
    procedure AnimateOpen;
    procedure AnimateClose;
    procedure OnOpenFinished(Sender: TObject);
    procedure OnCloseFinished(Sender: TObject);
    procedure DetachHook;
    procedure FinalizeCloseNow;
    procedure FinalizeCloseAsync;
    procedure Cleanup;

  public
    constructor Create(const ATheme: TDialog4DTheme);
    destructor Destroy; override;

    /// <summary>
    /// Telemetry sink for this host. Set by the public facade before
    /// <c>ShowDialog</c>.
    /// </summary>
    property Telemetry: TDialog4DTelemetryProc read FTelemetry write FTelemetry;

    /// <summary>
    /// Called by the form hook when the parent form starts destruction.
    /// </summary>
    /// <remarks>
    /// <para>
    /// Suppresses user callbacks and emits an <c>OwnerDestroying</c> telemetry
    /// event.
    /// </para>
    /// </remarks>
    procedure NotifyOwnerDestroying;

    /// <summary>
    /// Closes the dialog programmatically.
    /// </summary>
    /// <remarks>
    /// <para>Must be called on the main thread.</para>
    /// <para>Silently ignored when the dialog is not open.</para>
    /// <para>Recorded as <c>crProgrammatic</c>.</para>
    /// </remarks>
    procedure CloseProgram(const AResult: TModalResult);

    /// <summary>
    /// Builds the visual tree, applies the theme, lays out the buttons and
    /// starts the open animation.
    /// </summary>
    /// <remarks>
    /// <para>Must be called on the main thread.</para>
    /// </remarks>
    procedure ShowDialog(const AParent: TCommonCustomForm; const ATitle: string;
      const AMessage: string;
      const AButtons: TArray<TDialog4DButtonConfiguration>;
      const ACancelable: Boolean; const AOnResult: TDialog4DResultProc;
      const ADlgType: TMsgDlgType = TMsgDlgType.mtCustom);

    /// <summary>
    /// Returns the available width inside the button bar for laying out buttons.
    /// </summary>
    /// <remarks>
    /// <para>Used both by the layout engine and by external callers.</para>
    /// </remarks>
    function ButtonsAvailableWidth: Single;
  end;

implementation

uses
  Dialog4D.Internal.Queue;

{ ====================== }
{ == Layout constants == }
{ ====================== }

const
  DefaultOverlayOpenDuration = 0.18;
  DefaultOverlayCloseDuration = 0.14;
  DefaultCardHeight = 260;

  DefaultCardPaddingLeft = 16;
  DefaultCardPaddingTop = 16;
  DefaultCardPaddingRight = 16;
  DefaultCardPaddingBottom = 12;

  DefaultButtonBarVerticalPad = 10;
  DefaultButtonBarHorizontalPad = 12;

  DefaultButtonGap = 6;
  DefaultVerticalButtonGap = 8;
  DefaultMinButtonWidth = 80;
  DefaultVerticalLayoutMinButtonWidth = 110;

  DefaultDefaultButtonWidth = 100;
  DefaultButtonCornerRadius = 10;
  DefaultButtonBorderThickness = 1;

  DefaultIconWrapHeight = 72;
  DefaultIconWrapBottomMargin = 12;
  DefaultIconCircleSize = 56;
  DefaultGlyphFontSize = 45;

  DefaultDefaultContentHeight = 160;

  DefaultButtonPressedOpacity = 0.82;
  DefaultButtonNormalOpacity = 1.0;

  DefaultTextMeasureMaxHeight = 10_000;

  DefaultTitleHeightPadding = 2;
  DefaultMessageHeightPadding = 2;
  DefaultSpacingAfterMessage = 10;
  DefaultTitleBottomMargin = 8;

  // Scrollbar reservation — Windows only.
  // FContent.Margins.Right = DefaultScrollbarReservedWidth reserves a strip
  // at the right of FContent so the Windows scrollbar renders there instead
  // of overlapping FMessage. On other platforms the value is 0 (no-op).
{$IFDEF MSWINDOWS}
  DefaultScrollbarReservedWidth = 18;
{$ELSE}
  DefaultScrollbarReservedWidth = 0;
{$ENDIF}
  DefaultScrollTextWidthCompensation = 4;

  DefaultCardWidthPhoneRatio = 0.92;
  DefaultCardWidthDesktopRatio = 0.78;
  DefaultCardMinWidth = 260;
  DefaultCardMaxWidth = 520;

  { ================================= }
  { == Internal supporting classes == }
  { ================================= }

type
  /// <summary>
  /// Metadata attached to each rendered button rectangle.
  /// </summary>
  /// <remarks>
  /// <para>
  /// Carries the information needed to populate telemetry when the button
  /// triggers a close.
  /// </para>
  /// <para>
  /// Lifetime is tied to the button rectangle (see <c>TDialog4DButtonRect</c>).
  /// </para>
  /// </remarks>
  TDialog4DButtonMeta = class
  public
    Btn: TMsgDlgBtn;
    ModalResult: TModalResult;
    Caption: string;
    IsDefault: Boolean;
  end;

  /// <summary>
  /// Rectangle subclass used for button rendering.
  /// </summary>
  /// <remarks>
  /// <para>
  /// Owns its <c>TagObject</c> (the <c>TDialog4DButtonMeta</c> instance) and
  /// frees it on destruction.
  /// </para>
  /// </remarks>
  TDialog4DButtonRect = class(TRectangle)
  public
    destructor Destroy; override;
  end;

  /// <summary>
  /// <c>TComponent</c> owned by the parent form.
  /// </summary>
  /// <remarks>
  /// <para>
  /// When the parent form is destroyed, this hook's destructor notifies the
  /// host so it can run safe async cleanup before the form's visual tree
  /// disappears.
  /// </para>
  /// </remarks>
  TDialog4DFormHook = class(TComponent)
  private
    FHost: TDialog4DHostFMX;
  public
    constructor Create(AOwner: TComponent; AHost: TDialog4DHostFMX);
      reintroduce;
    destructor Destroy; override;
    procedure Detach;
  end;

destructor TDialog4DButtonRect.Destroy;
(*
  Ownership invariant.

  Each button rect owns the TDialog4DButtonMeta instance attached via
  TagObject. The destructor frees the meta first and then nulls TagObject
  so any subsequent FMX teardown access does not double-free.

  Ordering rule: meta first, TagObject := nil second, inherited last.
*)
begin
  TagObject.Free;
  TagObject := nil;
  inherited;
end;

constructor TDialog4DFormHook.Create(AOwner: TComponent;
  AHost: TDialog4DHostFMX);
begin
  inherited Create(AOwner);
  FHost := AHost;
end;

procedure TDialog4DFormHook.Detach;
begin
  FHost := nil;
end;

destructor TDialog4DFormHook.Destroy;
(*
  Owner-destroying notification path.

  Strategy
  - Capture FHost into a local variable and clear the field atomically
    against any reentry triggered by the host calling DetachHook from
    inside NotifyOwnerDestroying.
  - If a host was attached, notify it so user callbacks are suppressed,
    detach the back-reference, and free the host before the parent form's
    visual tree disappears.

  Invariants
  - FHost may already be nil when an explicit Detach happened earlier.
  - The local LHost is the only safe reference to use after FHost := nil.
*)
var
  LHost: TDialog4DHostFMX;
begin
  LHost := FHost;
  FHost := nil;

  if Assigned(LHost) then
  begin
    LHost.NotifyOwnerDestroying;
    LHost.DetachHook;
    LHost.Free;
  end;

  inherited;
end;

{ ====================== }
{ == TDialog4DHostFMX == }
{ ====================== }

constructor TDialog4DHostFMX.Create(const ATheme: TDialog4DTheme);
begin
  inherited Create;
  FTheme := ATheme;
  FState := dgsClosed;
  FDialogType := TMsgDlgType.mtCustom;
  FButtonLayoutMode := blmHorizontal;
  FOwnerDestroying := False;
  FFinalizing := False;
  FHandlingResize := False;
  FRebuildingButtons := False;
  FTelemetry := nil;
  FOpenTick := 0;
  FCloseReason := crNone;
  FTitleSnapshot := '';
  FMessageLenSnapshot := 0;
  FButtonsCountSnapshot := 0;
  FDefaultResultSnapshot := mrNone;
  FLastButtonsLayoutWidth := 0;
  SetLength(FButtonSpecs, 0);
  ResetTriggeredButtonInfo;
end;

destructor TDialog4DHostFMX.Destroy;
begin
  Cleanup;
  inherited;
end;

{ == Timing helpers == }

function TDialog4DHostFMX.TickMs: UInt64;
begin
  Result := TThread.GetTickCount64;
end;

function TDialog4DHostFMX.ElapsedMs: UInt64;
begin
  if FOpenTick = 0 then
    Exit(0);

  Result := TickMs - FOpenTick;
end;

{ == Triggered-button bookkeeping == }

procedure TDialog4DHostFMX.ResetTriggeredButtonInfo;
begin
  FTriggeredButtonKind := TMsgDlgBtn.mbOK;
  FTriggeredButtonCaption := '';
  FTriggeredButtonWasDefault := False;
end;

procedure TDialog4DHostFMX.CaptureTriggeredButtonFromMeta(const AMeta: TObject);
var
  LMeta: TDialog4DButtonMeta;
begin
  if not Assigned(AMeta) or not(AMeta is TDialog4DButtonMeta) then
  begin
    ResetTriggeredButtonInfo;
    Exit;
  end;

  LMeta := TDialog4DButtonMeta(AMeta);
  FTriggeredButtonKind := LMeta.Btn;
  FTriggeredButtonCaption := LMeta.Caption;
  FTriggeredButtonWasDefault := LMeta.IsDefault;
end;

procedure TDialog4DHostFMX.CaptureTriggeredButtonFromIndex
  (const AIndex: Integer);
begin
  if (AIndex < Low(FButtonSpecs)) or (AIndex > High(FButtonSpecs)) then
  begin
    ResetTriggeredButtonInfo;
    Exit;
  end;

  FTriggeredButtonKind := FButtonSpecs[AIndex].Btn;
  FTriggeredButtonCaption := FButtonSpecs[AIndex].Caption;
  FTriggeredButtonWasDefault := FButtonSpecs[AIndex].IsDefault;
end;

{ == Telemetry emission == }

procedure TDialog4DHostFMX.SafeEmitTelemetry(const AKind
  : TDialog4DTelemetryKind; const AResult: TModalResult;
  const AReason: TDialog4DCloseReason; const AElapsedOverrideMs: UInt64;
  const AErrorMessage: string);
var
  LProc: TDialog4DTelemetryProc;
  LData: TDialog4DTelemetry;
begin
  LProc := FTelemetry;
  if not Assigned(LProc) then
    Exit;

  LData.Kind := AKind;
  LData.DialogType := FDialogType;
  LData.Title := FTitleSnapshot;
  LData.MessageLen := FMessageLenSnapshot;
  LData.ButtonsCount := FButtonsCountSnapshot;
  LData.HasCancelButton := FHasCancelButton;
  LData.DefaultResult := FDefaultResultSnapshot;
  LData.Result := AResult;
  LData.CloseReason := AReason;
  LData.ButtonKind := FTriggeredButtonKind;
  LData.ButtonCaption := FTriggeredButtonCaption;
  LData.ButtonWasDefault := FTriggeredButtonWasDefault;
  LData.Tick := TickMs;
  LData.ElapsedMs := IfThen(AElapsedOverrideMs <> 0, AElapsedOverrideMs,
    ElapsedMs);
  LData.EventDateTime := Now;
  LData.ErrorMessage := AErrorMessage;

  try
    LProc(LData);
  except
    // Telemetry must never affect dialog flow — exceptions in the sink are
    // silently swallowed.
  end;
end;

{ == Button helpers == }

function TDialog4DHostFMX.IsCancelLikeResult(const AResult
  : TModalResult): Boolean;
begin
  Result := (AResult = mrCancel) or
    (FTheme.TreatCloseAsCancel and (AResult = mrClose));
end;

function TDialog4DHostFMX.IndexOfFirstCancelableButton(const AButtonSpecs
  : TArray<TDialog4DButtonConfiguration>): Integer;
var
  I: Integer;
begin
  for I := 0 to High(AButtonSpecs) do
    if IsCancelLikeResult(AButtonSpecs[I].ModalResult) then
      Exit(I);

  Result := -1;
end;

function TDialog4DHostFMX.IndexOfFirstDefaultButton(const AButtonSpecs
  : TArray<TDialog4DButtonConfiguration>): Integer;
var
  I: Integer;
begin
  for I := 0 to High(AButtonSpecs) do
    if AButtonSpecs[I].IsDefault then
      Exit(I);

  Result := -1;
end;

function TDialog4DHostFMX.IndexOfFirstValidButton(const AButtonSpecs
  : TArray<TDialog4DButtonConfiguration>): Integer;
var
  I: Integer;
begin
  for I := 0 to High(AButtonSpecs) do
    if AButtonSpecs[I].ModalResult <> mrNone then
      Exit(I);

  Result := -1;
end;

function TDialog4DHostFMX.NormalizeButtonSpecs(const AButtonSpecs
  : TArray<TDialog4DButtonConfiguration>): TArray<TDialog4DButtonConfiguration>;
(*
  Default-button normalization.

  Strategy
  - Copy the input array so the caller's data is not mutated.
  - Resolve the canonical default index: the first button explicitly marked
    IsDefault, or, if none is marked, the first button with a valid
    ModalResult.
  - Enforce the single-default invariant: only the resolved index keeps
    IsDefault := True; every other button has IsDefault := False.

  Outcomes
  - Returns the normalized copy.
  - When the input has no valid default (and no valid result), the result
    array still contains the buttons but with all IsDefault flags False.

  Invariants
  - At most one button in the returned array has IsDefault := True.
*)
var
  I, LDefaultIndex: Integer;
begin
  Result := Copy(AButtonSpecs);
  if Length(Result) = 0 then
    Exit;

  LDefaultIndex := IndexOfFirstDefaultButton(Result);
  if LDefaultIndex < 0 then
    LDefaultIndex := IndexOfFirstValidButton(Result);

  for I := 0 to High(Result) do
    Result[I].IsDefault := (I = LDefaultIndex);
end;

function TDialog4DHostFMX.ToFMXTextAlign(const AAlign: TDialog4DTextAlign)
  : TTextAlign;
begin
  case AAlign of
    dtaLeading:
      Result := TTextAlign.Leading;
    dtaTrailing:
      Result := TTextAlign.Trailing;
  else
    Result := TTextAlign.Center;
  end;
end;

procedure TDialog4DHostFMX.TryFocusOverlay;
begin
  // Called on all platforms after the dialog becomes visible.
  // Desktop: enables Enter/Esc keyboard navigation.
  // Android: enables OnKeyUp to receive vkHardwareBack.
  if not Assigned(FOverlay) then
    Exit;

  try
    FOverlay.SetFocus;
  except
    // Best effort only — focus can fail silently on platforms with
    // restricted focus models or during transient lifecycle states.
  end;
end;

{$IF DEFINED(MSWINDOWS) OR DEFINED(MACOS)}

procedure TDialog4DHostFMX.OverlayKeyDown(Sender: TObject; var Key: Word;
  var KeyChar: Char; Shift: TShiftState);
begin
  HandleDialogKey(Key, KeyChar, Shift);
end;

procedure TDialog4DHostFMX.HandleDialogKey(var Key: Word; var KeyChar: Char;
  Shift: TShiftState);
(*
  Desktop keyboard dispatch (Windows / macOS).

  Strategy
  - Only act while the dialog is fully open and not in any teardown phase.
  - Enter resolves the default button; Esc resolves the first cancel-like
    button when one is present.
  - When a key triggers a close, both Key and KeyChar are zeroed so the
    event does not leak to the parent form (which could process it as a
    second navigation action).

  Outcomes
  - Enter on a dialog with a valid default closes with that result and
    records crKeyEnter.
  - Esc on a dialog with a cancel-like button closes with that result and
    records crKeyEsc.
  - Any other key, or a key when no matching button exists, is ignored.
*)
var
  LResult: TModalResult;
  LIndex: Integer;
begin
  if (FState <> dgsOpen) or FFinalizing or FOwnerDestroying then
    Exit;

  case Key of
    vkReturn:
      if ResolveDefaultResult(LResult, LIndex) then
      begin
        CaptureTriggeredButtonFromIndex(LIndex);
        Key := 0;
        KeyChar := #0;
        FCloseReason := crKeyEnter;
        CloseWithResult(LResult);
      end;

    vkEscape:
      if ResolveCancelResult(LResult, LIndex) then
      begin
        CaptureTriggeredButtonFromIndex(LIndex);
        Key := 0;
        KeyChar := #0;
        FCloseReason := crKeyEsc;
        CloseWithResult(LResult);
      end;
  end;
end;

function TDialog4DHostFMX.ResolveDefaultResult(out AResult: TModalResult;
  out AIndex: Integer): Boolean;
begin
  AIndex := IndexOfFirstDefaultButton(FButtonSpecs);
  if AIndex < 0 then
    AIndex := IndexOfFirstValidButton(FButtonSpecs);

  if AIndex >= 0 then
  begin
    AResult := FButtonSpecs[AIndex].ModalResult;
    Exit(AResult <> mrNone);
  end;

  AResult := mrNone;
  Result := False;
end;

function TDialog4DHostFMX.ResolveCancelResult(out AResult: TModalResult;
  out AIndex: Integer): Boolean;
begin
  AIndex := IndexOfFirstCancelableButton(FButtonSpecs);

  if AIndex >= 0 then
  begin
    AResult := FButtonSpecs[AIndex].ModalResult;
    Exit(True);
  end;

  AResult := mrNone;
  Result := False;
end;
{$ENDIF}
{$IFDEF ANDROID}

procedure TDialog4DHostFMX.OverlayKeyUpAndroid(Sender: TObject; var Key: Word;
  var KeyChar: Char; Shift: TShiftState);
(*
  Android hardware back-button interception.

  Strategy
  - Filter on vkHardwareBack only; any other key is ignored.
  - Always consume the event by setting Key := 0 BEFORE any further state
    check. This is the critical invariant: without it the OS treats the
    back key as activity-level navigation and may close the activity.
  - When the dialog is open, cancelable, and has a cancel-like button,
    treat the back key like Esc on desktop: close with that button's
    modal result and record crKeyEsc.

  Outcomes
  - On a cancelable dialog with a cancel button: dialog closes, activity
    stays alive.
  - On a non-cancelable dialog or one without a cancel button: dialog
    stays open, activity stays alive.

  Invariants
  - Key := 0 happens unconditionally on vkHardwareBack — even when the
    dialog refuses to close.
*)
var
  LCancelIndex: Integer;
begin
  if Key <> vkHardwareBack then
    Exit;

  // Always consume the back key. Without Key := 0 the event propagates to
  // the parent form and the OS interprets it as a navigation back.
  Key := 0;

  if (FState <> dgsOpen) or FFinalizing or FOwnerDestroying then
    Exit;

  if FCancelable then
  begin
    LCancelIndex := IndexOfFirstCancelableButton(FButtonSpecs);
    if LCancelIndex >= 0 then
    begin
      FCloseReason := crKeyEsc;
      CaptureTriggeredButtonFromIndex(LCancelIndex);
      CloseWithResult(FButtonSpecs[LCancelIndex].ModalResult);
    end;
  end;
end;
{$ENDIF}
{ == Hook / owner lifecycle == }

procedure TDialog4DHostFMX.DetachHook;
begin
  FFormHook := nil;
end;

procedure TDialog4DHostFMX.NotifyOwnerDestroying;
begin
  FOwnerDestroying := True;
  FOnResult := nil;
  FCloseReason := crOwnerDestroying;
  SafeEmitTelemetry(tkOwnerDestroying, mrNone, crOwnerDestroying);

  // Detach any pending animation finish callbacks — the visual tree is
  // about to disappear with the parent form.
  if Assigned(FAnimOpen) then
    FAnimOpen.OnFinish := nil;
  if Assigned(FAnimClose) then
    FAnimClose.OnFinish := nil;
end;

procedure TDialog4DHostFMX.CloseProgram(const AResult: TModalResult);
begin
  if (FState <> dgsOpen) and (FState <> dgsOpening) then
    Exit;
  if FFinalizing or FOwnerDestroying then
    Exit;

  FCloseReason := crProgrammatic;
  ResetTriggeredButtonInfo;
  CloseWithResult(AResult);
end;

{ == Visual tree construction == }

procedure TDialog4DHostFMX.EnsureUI(const AParent: TCommonCustomForm);
(*
  Visual tree construction.

  Strategy
  - Attach the form-destruction hook so cleanup is triggered if the parent
    form disappears while the dialog is alive.
  - Build the visual tree top-down: overlay → backdrop → card → header
    (icon + title) → scroll box → content → message → button bar →
    buttons. Each container is created and parented before its children.
  - Wire platform-specific input handlers:
    * Desktop (Windows/macOS): OnKeyDown for Enter/Esc.
    * Android: OnKeyUp for vkHardwareBack.
  - Build the open and close animations and bind their finish handlers.

  Invariants
  - All controls are created with no FMX owner (Create(nil)) and parented
    explicitly. Cleanup is responsible for disposing them.
  - FOverlay.CanFocus must remain True on every platform — TryFocusOverlay
    relies on it for desktop keyboard input and Android back-button events.
*)
begin
  FParentForm := AParent;

  if Assigned(FParentForm) and (FFormHook = nil) then
    FFormHook := TDialog4DFormHook.Create(FParentForm, Self);

  { -- Overlay -- }
  FOverlay := TLayout.Create(nil);
  FOverlay.Parent := FParentForm;
  FOverlay.Align := TAlignLayout.Contents;
  FOverlay.HitTest := True;
  FOverlay.Stored := False;
  FOverlay.Opacity := 0;
  FOverlay.Visible := True;
  FOverlay.CanFocus := True; // Required on every platform for TryFocusOverlay.
  FOverlay.OnResize := OverlayResized;
  FOverlay.BringToFront;

{$IF DEFINED(MSWINDOWS) OR DEFINED(MACOS)}
  // Desktop: Enter and Esc keyboard navigation.
  FOverlay.OnKeyDown := OverlayKeyDown;
{$ENDIF}
{$IFDEF ANDROID}
  // Android: intercept the hardware back button via OnKeyUp.
  // OnKeyUp is used (not OnKeyDown) because FMX delivers vkHardwareBack on
  // key-up on Android, consistent with the platform's back navigation model.
  FOverlay.OnKeyUp := OverlayKeyUpAndroid;
{$ENDIF}
  { -- Backdrop -- }
  FBackdrop := TRectangle.Create(nil);
  FBackdrop.Parent := FOverlay;
  FBackdrop.Align := TAlignLayout.Contents;
  FBackdrop.Fill.Kind := TBrushKind.Solid;
  FBackdrop.Fill.Color := FTheme.OverlayColor;
  FBackdrop.Stroke.Kind := TBrushKind.None;
  FBackdrop.Opacity := FTheme.OverlayOpacity;
  FBackdrop.HitTest := True;
{$IFDEF ANDROID}
  FBackdrop.OnTap := BackdropTap;
{$ELSE}
  FBackdrop.OnClick := BackdropClick;
{$ENDIF}
  { -- Card -- }
  FCard := TRectangle.Create(nil);
  FCard.Parent := FOverlay;
  FCard.Align := TAlignLayout.Center;
  FCard.Width := FTheme.DialogWidth;
  FCard.Height := DefaultCardHeight;
  FCard.Fill.Kind := TBrushKind.Solid;
  FCard.Fill.Color := FTheme.SurfaceColor;
  FCard.Stroke.Kind := TBrushKind.None;
  FCard.XRadius := FTheme.CornerRadius;
  FCard.YRadius := FTheme.CornerRadius;
  FCard.Padding.Rect := RectF(DefaultCardPaddingLeft, DefaultCardPaddingTop,
    DefaultCardPaddingRight, DefaultCardPaddingBottom);
  FCard.HitTest := True;

  { -- Button bar -- }
  FButtonBar := TLayout.Create(nil);
  FButtonBar.Parent := FCard;
  FButtonBar.Align := TAlignLayout.Bottom;
  FButtonBar.Height := FTheme.ButtonHeight + (2 * DefaultButtonBarVerticalPad);
  FButtonBar.Padding.Rect := RectF(DefaultButtonBarHorizontalPad,
    DefaultButtonBarVerticalPad, DefaultButtonBarHorizontalPad,
    DefaultButtonBarVerticalPad);
  FButtonBar.Stored := False;
  FButtonBar.HitTest := True;

  FButtons := TLayout.Create(nil);
  FButtons.Parent := FButtonBar;
  FButtons.Align := TAlignLayout.Client;
  FButtons.Stored := False;
  FButtons.HitTest := True;

  { -- Header -- }
  FHeader := TLayout.Create(nil);
  FHeader.Parent := FCard;
  FHeader.Align := TAlignLayout.Top;
  FHeader.Stored := False;
  FHeader.HitTest := False;
  FHeader.Height := 0;

  { -- Icon wrap + circle + glyph -- }
  FIconWrap := TLayout.Create(nil);
  FIconWrap.Parent := FHeader;
  FIconWrap.Align := TAlignLayout.Top;
  FIconWrap.Stored := False;
  FIconWrap.Height := DefaultIconWrapHeight;
  FIconWrap.Margins.Bottom := DefaultIconWrapBottomMargin;
  FIconWrap.HitTest := False;

  FIconCircle := TCircle.Create(nil);
  FIconCircle.Parent := FIconWrap;
  FIconCircle.Align := TAlignLayout.Center;
  FIconCircle.Width := DefaultIconCircleSize;
  FIconCircle.Height := DefaultIconCircleSize;
  FIconCircle.Fill.Kind := TBrushKind.Solid;
  FIconCircle.Fill.Color := FTheme.AccentNeutralColor;
  FIconCircle.Stroke.Kind := TBrushKind.None;
  FIconCircle.HitTest := False;

  FIconGlyph := TLabel.Create(nil);
  FIconGlyph.Parent := FIconCircle;
  FIconGlyph.Align := TAlignLayout.Contents;
  FIconGlyph.TextSettings.HorzAlign := TTextAlign.Center;
  FIconGlyph.TextSettings.VertAlign := TTextAlign.Center;
  FIconGlyph.TextSettings.Font.Size := DefaultGlyphFontSize;
  FIconGlyph.TextSettings.Font.Style := [TFontStyle.fsBold];
  FIconGlyph.StyledSettings := [TStyledSetting.Style, TStyledSetting.Family];
  FIconGlyph.HitTest := False;
  FIconGlyph.Text := '';
  FIconGlyph.Visible := False;

  // Error icon: built from two crossed bars (rotated rounded rectangles).
  FXBar1 := TRectangle.Create(nil);
  FXBar1.Parent := FIconCircle;
  FXBar1.Stored := False;
  FXBar1.HitTest := False;
  FXBar1.Stroke.Kind := TBrushKind.None;
  FXBar1.Fill.Kind := TBrushKind.Solid;
  FXBar1.Fill.Color := TAlphaColorRec.White;
  FXBar1.Visible := False;

  FXBar2 := TRectangle.Create(nil);
  FXBar2.Parent := FIconCircle;
  FXBar2.Stored := False;
  FXBar2.HitTest := False;
  FXBar2.Stroke.Kind := TBrushKind.None;
  FXBar2.Fill.Kind := TBrushKind.Solid;
  FXBar2.Fill.Color := TAlphaColorRec.White;
  FXBar2.Visible := False;

  { -- Title -- }
  FTitle := TLabel.Create(nil);
  FTitle.Parent := FHeader;
  FTitle.Align := TAlignLayout.Top;
  FTitle.Margins.Bottom := DefaultTitleBottomMargin;
  FTitle.TextSettings.Font.Size := FTheme.TitleFontSize;
  FTitle.TextSettings.Font.Style := [TFontStyle.fsBold];
  FTitle.TextSettings.FontColor := FTheme.TextTitleColor;
  FTitle.TextSettings.HorzAlign := TTextAlign.Center;
  // Title is always centered.
  FTitle.WordWrap := True;
  FTitle.StyledSettings := [TStyledSetting.Style, TStyledSetting.Family];
  FTitle.HitTest := False;

  { -- Scroll box + content -- }
  FScrollBox := TVertScrollBox.Create(nil);
  FScrollBox.Parent := FCard;
  FScrollBox.Align := TAlignLayout.Client;
  FScrollBox.Stored := False;
  FScrollBox.HitTest := True;
  FScrollBox.Padding.Rect := RectF(0, 0, 0, 0);
  FScrollBox.AniCalculations.Animation := False;
  FScrollBox.AniCalculations.BoundsAnimation := False;
  FScrollBox.AniCalculations.TouchTracking := [ttVertical];

  FContent := TLayout.Create(nil);
  FContent.Parent := FScrollBox;
  FContent.Align := TAlignLayout.Top;
  FContent.Stored := False;
  FContent.Height := DefaultDefaultContentHeight;
  FContent.HitTest := False;

  // Reserve the right strip for the Windows scrollbar.
  // FContent (Align=Top) Margins.Right reduces FContent.Width, so FMessage
  // (Client in FContent) is narrower than FScrollBox by this amount.
  // The scrollbar renders in the freed strip without overlapping the text.
  // On other platforms DefaultScrollbarReservedWidth = 0 (no-op).
  FContent.Margins.Right := DefaultScrollbarReservedWidth;

  { -- Message -- }
  FMessage := TText.Create(nil);
  FMessage.Parent := FContent;
  FMessage.Align := TAlignLayout.Client;
  FMessage.Stored := False;
  FMessage.HitTest := False;
  FMessage.WordWrap := True;

  // AutoSize intentionally NOT set (defaults to False).
  // AutoSize=True with Align=Client conflicts: for short single-line text
  // the control may not fill the full parent width, making HorzAlign=Center
  // appear as left-aligned. With AutoSize=False, Align=Client always
  // assigns the full FContent width to FMessage and HorzAlign is applied
  // consistently.
  FMessage.TextSettings.Font.Size := FTheme.MessageFontSize;
  FMessage.TextSettings.FontColor := FTheme.TextMessageColor;
  FMessage.TextSettings.HorzAlign := ToFMXTextAlign(FTheme.MessageTextAlign);
  FMessage.TextSettings.VertAlign := TTextAlign.Leading;

  { -- Animations -- }
  FAnimOpen := TFloatAnimation.Create(nil);
  FAnimOpen.Parent := FOverlay;
  FAnimOpen.Stored := False;
  FAnimOpen.PropertyName := 'Opacity';
  FAnimOpen.StartValue := 0;
  FAnimOpen.StopValue := 1;
  FAnimOpen.Duration := DefaultOverlayOpenDuration;
  FAnimOpen.AnimationType := TAnimationType.&In;
  FAnimOpen.Interpolation := TInterpolationType.Circular;
  FAnimOpen.OnFinish := OnOpenFinished;

  FAnimClose := TFloatAnimation.Create(nil);
  FAnimClose.Parent := FOverlay;
  FAnimClose.Stored := False;
  FAnimClose.PropertyName := 'Opacity';
  FAnimClose.StartValue := 1;
  FAnimClose.StopValue := 0;
  FAnimClose.Duration := DefaultOverlayCloseDuration;
  FAnimClose.AnimationType := TAnimationType.&In;
  FAnimClose.Interpolation := TInterpolationType.Circular;
  FAnimClose.OnFinish := OnCloseFinished;
end;

procedure TDialog4DHostFMX.ApplyTheme;
begin
  if not Assigned(FBackdrop) then
    Exit;

  FBackdrop.Fill.Color := FTheme.OverlayColor;
  FBackdrop.Opacity := FTheme.OverlayOpacity;

  FCard.Fill.Color := FTheme.SurfaceColor;
  FCard.XRadius := FTheme.CornerRadius;
  FCard.YRadius := FTheme.CornerRadius;

  FTitle.TextSettings.Font.Size := FTheme.TitleFontSize;
  FTitle.TextSettings.FontColor := FTheme.TextTitleColor;
  // Title is always centered — MessageTextAlign does not affect it.

  FMessage.TextSettings.Font.Size := FTheme.MessageFontSize;
  FMessage.TextSettings.FontColor := FTheme.TextMessageColor;
  FMessage.TextSettings.HorzAlign := ToFMXTextAlign(FTheme.MessageTextAlign);
end;

procedure TDialog4DHostFMX.SetupErrorIcon(const AIconSize: Single);
const
  DefaultStrokeLengthFactor = 0.60;
  DefaultStrokeThicknessFactor = 0.075;
  DefaultMinStrokeThickness = 3;
var
  LLen, LThick, LLeft, LTop: Single;
begin
  // Geometry: bar length and thickness scale with the icon size; both bars
  // share the same bounds and are rotated 45° / 135° to form the X.
  LLen := Round(AIconSize * DefaultStrokeLengthFactor);
  LThick := Max(DefaultMinStrokeThickness,
    Round(AIconSize * DefaultStrokeThicknessFactor));
  LLeft := (AIconSize - LLen) / 2;
  LTop := (AIconSize - LThick) / 2;

  FXBar1.SetBounds(LLeft, LTop, LLen, LThick);
  FXBar1.XRadius := LThick / 2;
  FXBar1.YRadius := LThick / 2;
  FXBar1.RotationAngle := 45;
  FXBar1.Visible := True;

  FXBar2.SetBounds(LLeft, LTop, LLen, LThick);
  FXBar2.XRadius := LThick / 2;
  FXBar2.YRadius := LThick / 2;
  FXBar2.RotationAngle := 135;
  FXBar2.Visible := True;
end;

procedure TDialog4DHostFMX.ApplyIconForType(const ADlgType: TMsgDlgType);
var
  LIconChar: string;
  LCircleColor: TAlphaColor;
begin
  // Reset all icon visuals first; only the elements relevant to the
  // resolved dialog type are turned back on below.
  FIconGlyph.Text := '';
  FIconGlyph.Visible := False;
  FXBar1.Visible := False;
  FXBar2.Visible := False;

  LIconChar := '';
  LCircleColor := FTheme.AccentNeutralColor;

  case ADlgType of
    TMsgDlgType.mtInformation:
      begin
        LIconChar := 'i';
        LCircleColor := FTheme.AccentInfoColor;
      end;
    TMsgDlgType.mtWarning:
      begin
        LIconChar := '!';
        LCircleColor := FTheme.AccentWarningColor;
      end;
    TMsgDlgType.mtError:
      begin
        LIconChar := '';
        LCircleColor := FTheme.AccentErrorColor;
      end;
    TMsgDlgType.mtConfirmation:
      begin
        LIconChar := '?';
        LCircleColor := FTheme.AccentConfirmColor;
      end;
    TMsgDlgType.mtCustom:
      begin
        LIconChar := '';
        LCircleColor := FTheme.AccentNeutralColor;
      end;
  end;

  FIconWrap.Visible := (ADlgType <> TMsgDlgType.mtCustom);
  if not FIconWrap.Visible then
    Exit;

  FIconCircle.Fill.Color := LCircleColor;

  if ADlgType = TMsgDlgType.mtError then
    SetupErrorIcon(FIconCircle.Width)
  else
  begin
    FIconGlyph.TextSettings.Font.Size := DefaultGlyphFontSize;
    FIconGlyph.TextSettings.FontColor := TAlphaColorRec.White;
    FIconGlyph.Text := LIconChar;
    FIconGlyph.Visible := (LIconChar <> '');
  end;
end;

procedure TDialog4DHostFMX.OverlayResized(Sender: TObject);
begin
  if (FState = dgsClosed) or FFinalizing or FOwnerDestroying then
    Exit;
  if FHandlingResize then
    Exit;
  if not Assigned(FCard) then
    Exit;

  // Reentrancy guard: RecalcLayoutHeights may indirectly trigger another
  // resize (e.g. via RealignContent on the scroll box).
  FHandlingResize := True;
  try
    RecalcLayoutHeights;
  finally
    FHandlingResize := False;
  end;
end;

{ == Button layout engine == }

function TDialog4DHostFMX.CalculateHorizontalButtonWidth(const AButtonCount
  : Integer): Single;
begin
  if AButtonCount <= 0 then
    Exit(0);

  Result := (ButtonsAvailableWidth - (DefaultButtonGap * (AButtonCount - 1))) /
    AButtonCount;
end;

function TDialog4DHostFMX.ResolveButtonLayoutMode(const AButtonSpecs
  : TArray<TDialog4DButtonConfiguration>): TDialogButtonLayoutMode;
var
  LButtonWidth: Single;
begin
  // 3+ buttons always go vertical for readability and tap targets.
  if Length(AButtonSpecs) >= 3 then
    Exit(blmVertical);

  // 1–2 buttons go horizontal unless the resulting width would be too
  // narrow to fit a comfortable label.
  LButtonWidth := CalculateHorizontalButtonWidth(Length(AButtonSpecs));
  if LButtonWidth < DefaultVerticalLayoutMinButtonWidth then
    Result := blmVertical
  else
    Result := blmHorizontal;
end;

procedure TDialog4DHostFMX.BuildButtons(const AButtonSpecs
  : TArray<TDialog4DButtonConfiguration>);
(*
  Top-level button construction.

  Strategy
  - Clear any previously rendered buttons from the bar.
  - Validate that at least one button was supplied (raises otherwise).
  - Normalize the spec array (single-default invariant) and store it as
    FButtonSpecs for later layout recalculations.
  - Refresh telemetry snapshots (count, has-cancel, default result).
  - Resolve the layout mode (horizontal vs vertical) from the current bar
    width and dispatch to the matching builder.

  Outcomes
  - On return, FButtons is populated with the rendered button rectangles
    and FButtonLayoutMode reflects the chosen mode.
*)
var
  LSpecs: TArray<TDialog4DButtonConfiguration>;
  LDefaultIndex: Integer;
begin
  ClearButtons;
  if Length(AButtonSpecs) = 0 then
    raise Exception.Create('Dialog4D: at least one button is required.');

  LSpecs := NormalizeButtonSpecs(AButtonSpecs);
  FButtonSpecs := Copy(LSpecs);

  FHasCancelButton := (IndexOfFirstCancelableButton(FButtonSpecs) >= 0);
  FButtonsCountSnapshot := Length(FButtonSpecs);

  LDefaultIndex := IndexOfFirstDefaultButton(FButtonSpecs);
  FDefaultResultSnapshot := IfThen(LDefaultIndex >= 0,
    FButtonSpecs[LDefaultIndex].ModalResult, mrNone);

  FButtonLayoutMode := ResolveButtonLayoutMode(FButtonSpecs);
  case FButtonLayoutMode of
    blmHorizontal:
      BuildButtonsHorizontal(FButtonSpecs);
    blmVertical:
      BuildButtonsVertical(FButtonSpecs);
  end;
end;

procedure TDialog4DHostFMX.BuildButtonsHorizontal(const AButtonSpecs
  : TArray<TDialog4DButtonConfiguration>);
(*
  Horizontal layout builder.

  Strategy
  - Compute the per-button width from the available bar width and the
    fixed inter-button gap.
  - Clamp to DefaultMinButtonWidth so labels remain legible even when many
    buttons share the row.
  - If the resulting row would overflow the available bar (typically after
    a window resize between mode resolution and rendering), fall back to
    vertical layout instead of clipping.

  Outcomes
  - On success: each button is positioned at a deterministic X within a
    centered row.
  - On overflow: defers entirely to BuildButtonsVertical and exits.

  Invariants
  - FLastButtonsLayoutWidth reflects the bar width that produced the
    current layout, so RebuildButtonsIfNeeded can detect drift.
*)
var
  I: Integer;
  LButtonWidth, LButtonsRowWidth: Single;
  LAvailableBarWidth, LRowStartX: Single;
  LButtonCtrl: TControl;
begin
  LAvailableBarWidth := ButtonsAvailableWidth;
  LButtonWidth := CalculateHorizontalButtonWidth(Length(AButtonSpecs));

  if LButtonWidth < DefaultMinButtonWidth then
    LButtonWidth := DefaultMinButtonWidth;

  LButtonsRowWidth := (LButtonWidth * Length(AButtonSpecs)) +
    (DefaultButtonGap * (Length(AButtonSpecs) - 1));

  if LButtonsRowWidth > LAvailableBarWidth then
  begin
    BuildButtonsVertical(AButtonSpecs);
    Exit;
  end;

  FButtonLayoutMode := blmHorizontal;
  FButtonBar.Height := FTheme.ButtonHeight + (2 * DefaultButtonBarVerticalPad);
  FLastButtonsLayoutWidth := LAvailableBarWidth;
  LRowStartX := Max(0, (LAvailableBarWidth - LButtonsRowWidth) / 2);

  for I := 0 to High(AButtonSpecs) do
  begin
    LButtonCtrl := CreateButtonControl(FButtons, AButtonSpecs[I]);
    LButtonCtrl.Width := Round(LButtonWidth);
    LButtonCtrl.Position.X :=
      Round(LRowStartX + (I * (LButtonWidth + DefaultButtonGap)));
    LButtonCtrl.Position.Y := 0;
  end;
end;

procedure TDialog4DHostFMX.BuildButtonsVertical(const AButtonSpecs
  : TArray<TDialog4DButtonConfiguration>);
(*
  Vertical layout builder.

  Strategy
  - Width: each button takes the full bar width, except when the bar is
    narrower than DefaultVerticalLayoutMinButtonWidth — in that edge case
    the bar width is used as-is to avoid negative or zero widths.
  - Height: stack each button top-down at FTheme.ButtonHeight, adding
    DefaultVerticalButtonGap between siblings.
  - Final bar height: padding + (n × button height) + (n−1 × gap).

  Outcomes
  - On return, FButtonBar.Height reflects the total vertical extent of
    the stacked buttons including padding.

  Invariants
  - FLastButtonsLayoutWidth tracks the bar width that produced the
    current layout, used by RebuildButtonsIfNeeded to detect drift.
*)
var
  I: Integer;
  LButtonCtrl: TControl;
  LAvailableBarWidth, LButtonWidth, LButtonTop: Single;
begin
  FButtonLayoutMode := blmVertical;
  LAvailableBarWidth := ButtonsAvailableWidth;
  LButtonWidth := IfThen(LAvailableBarWidth <
    DefaultVerticalLayoutMinButtonWidth, Max(0, LAvailableBarWidth),
    LAvailableBarWidth);
  FLastButtonsLayoutWidth := LAvailableBarWidth;
  LButtonTop := 0;

  for I := 0 to High(AButtonSpecs) do
  begin
    LButtonCtrl := CreateButtonControl(FButtons, AButtonSpecs[I]);
    LButtonCtrl.Width := Round(LButtonWidth);
    LButtonCtrl.Position.X := 0;
    LButtonCtrl.Position.Y := Round(LButtonTop);
    LButtonTop := LButtonTop + FTheme.ButtonHeight + DefaultVerticalButtonGap;
  end;

  if Length(AButtonSpecs) > 0 then
    FButtonBar.Height := (2 * DefaultButtonBarVerticalPad) +
      (Length(AButtonSpecs) * FTheme.ButtonHeight) +
      ((Length(AButtonSpecs) - 1) * DefaultVerticalButtonGap)
  else
    FButtonBar.Height := FTheme.ButtonHeight +
      (2 * DefaultButtonBarVerticalPad);
end;

function TDialog4DHostFMX.CreateButtonControl(const AParent: TFmxObject;
  const ASpec: TDialog4DButtonConfiguration): TControl;
(*
  Single-button control factory.

  Strategy
  - Resolve the color triple (fill / text / border) by button role, with
    mutually exclusive precedence: destructive > default > neutral.
  - Build the button as a TDialog4DButtonRect (subclass that owns its
    metadata) and attach a TDialog4DButtonMeta carrying everything needed
    for telemetry on close.
  - Wire platform-appropriate input handlers:
    * Android: OnTap.
    * Desktop: OnClick + OnMouseDown / OnMouseUp for the press feedback.
  - Build the inner caption label as a contents-aligned, non-hit-tested
    TLabel so the button rect itself receives all input.
  - If this button is the default and the active theme requests a
    highlight, apply the inset ring on top.

  Invariants
  - The returned control is the rectangle. The label and any highlight
    are children and will be destroyed with it.
  - Ownership of the meta object is transferred to TDialog4DButtonRect,
    whose destructor frees it.
*)
var
  LButtonRect: TDialog4DButtonRect;
  LButtonLabel: TLabel;
  LFillColor, LTextColor, LBorderColor: TAlphaColor;
  LMeta: TDialog4DButtonMeta;
begin
  if ASpec.IsDestructive then
  begin
    LFillColor := FTheme.AccentErrorColor;
    LTextColor := TAlphaColorRec.White;
    LBorderColor := LFillColor;
  end
  else if ASpec.IsDefault then
  begin
    LFillColor := FTheme.AccentInfoColor;
    LTextColor := TAlphaColorRec.White;
    LBorderColor := LFillColor;
  end
  else
  begin
    LFillColor := FTheme.ButtonNeutralFillColor;
    LTextColor := FTheme.ButtonNeutralTextColor;
    LBorderColor := FTheme.ButtonNeutralBorderColor;
  end;

  LButtonRect := TDialog4DButtonRect.Create(nil);
  LButtonRect.Parent := AParent;
  LButtonRect.Stored := False;
  LButtonRect.Width := DefaultDefaultButtonWidth;
  LButtonRect.Height := FTheme.ButtonHeight;
  LButtonRect.XRadius := DefaultButtonCornerRadius;
  LButtonRect.YRadius := DefaultButtonCornerRadius;
  LButtonRect.Fill.Kind := TBrushKind.Solid;
  LButtonRect.Fill.Color := LFillColor;
  LButtonRect.Stroke.Kind := TBrushKind.Solid;
  LButtonRect.Stroke.Color := LBorderColor;
  LButtonRect.Stroke.Thickness := DefaultButtonBorderThickness;
  LButtonRect.HitTest := True;
  LButtonRect.Opacity := DefaultButtonNormalOpacity;
  LButtonRect.Tag := Ord(ASpec.ModalResult);

  // Attach metadata via TagObject. Ownership is transferred to the rect —
  // TDialog4DButtonRect.Destroy frees it.
  LMeta := TDialog4DButtonMeta.Create;
  LMeta.Btn := ASpec.Btn;
  LMeta.ModalResult := ASpec.ModalResult;
  LMeta.Caption := ASpec.Caption;
  LMeta.IsDefault := ASpec.IsDefault;
  LButtonRect.TagObject := LMeta;

{$IFDEF ANDROID}
  LButtonRect.OnTap := ButtonTap;
{$ELSE}
  LButtonRect.OnClick := ButtonClick;
  LButtonRect.OnMouseDown := ButtonMouseDown;
  LButtonRect.OnMouseUp := ButtonMouseUp;
{$ENDIF}
  LButtonLabel := TLabel.Create(nil);
  LButtonLabel.Parent := LButtonRect;
  LButtonLabel.Align := TAlignLayout.Contents;
  LButtonLabel.Stored := False;
  LButtonLabel.Text := ASpec.Caption;
  LButtonLabel.TextSettings.HorzAlign := TTextAlign.Center;
  LButtonLabel.TextSettings.VertAlign := TTextAlign.Center;
  LButtonLabel.TextSettings.Font.Size := FTheme.ButtonFontSize;
  LButtonLabel.TextSettings.Font.Style := [TFontStyle.fsBold];
  LButtonLabel.TextSettings.FontColor := LTextColor;
  LButtonLabel.StyledSettings := [TStyledSetting.Style, TStyledSetting.Family];
  LButtonLabel.HitTest := False;

  ApplyDefaultHighlight(LButtonRect, ASpec);
  LButtonLabel.BringToFront;
  Result := LButtonRect;
end;

procedure TDialog4DHostFMX.ApplyDefaultHighlight(const AButtonRect: TRectangle;
  const ASpec: TDialog4DButtonConfiguration);
var
  LRing: TRectangle;
  LThickness, LOpacity, LInset: Single;
begin
  if not Assigned(AButtonRect) then
    Exit;
  if not ASpec.IsDefault then
    Exit;
  if not FTheme.ShowDefaultButtonHighlight then
    Exit;

  LThickness := IfThen(FTheme.DefaultButtonHighlightThickness > 0,
    FTheme.DefaultButtonHighlightThickness, 2);
  LOpacity := Min(1, Max(0.01, FTheme.DefaultButtonHighlightOpacity));
  LInset := Max(0, FTheme.DefaultButtonHighlightInset);

  LRing := TRectangle.Create(nil);
  LRing.Parent := AButtonRect;
  LRing.Align := TAlignLayout.Contents;
  LRing.Stored := False;
  LRing.Margins.Left := LInset;
  LRing.Margins.Top := LInset;
  LRing.Margins.Right := LInset;
  LRing.Margins.Bottom := LInset;
  LRing.Fill.Kind := TBrushKind.None;
  LRing.Stroke.Kind := TBrushKind.Solid;
  LRing.Stroke.Color := FTheme.DefaultButtonHighlightColor;
  LRing.Stroke.Thickness := LThickness;
  LRing.XRadius := Max(0, DefaultButtonCornerRadius - LInset);
  LRing.YRadius := Max(0, DefaultButtonCornerRadius - LInset);
  LRing.HitTest := False;
  LRing.Opacity := LOpacity;
end;

procedure TDialog4DHostFMX.ClearButtons;
begin
  while Assigned(FButtons) and (FButtons.ControlsCount > 0) do
    FButtons.Controls[0].DisposeOf;
end;

procedure TDialog4DHostFMX.RebuildButtonsIfNeeded;
var
  LNewMode: TDialogButtonLayoutMode;
  LCurrentWidth: Single;
begin
  if Length(FButtonSpecs) = 0 then
    Exit;
  if FRebuildingButtons then
    Exit;

  LNewMode := ResolveButtonLayoutMode(FButtonSpecs);
  LCurrentWidth := ButtonsAvailableWidth;

  // Rebuild only when the layout actually needs to change: no buttons yet,
  // mode flipped, or the available width drifted by more than 1 px.
  if (FButtons.ControlsCount = 0) or (LNewMode <> FButtonLayoutMode) or
    (Abs(LCurrentWidth - FLastButtonsLayoutWidth) > 1.0) then
  begin
    FRebuildingButtons := True;
    try
      BuildButtons(FButtonSpecs);
    finally
      FRebuildingButtons := False;
    end;
  end;
end;

{ == Text measurement and layout recalculation == }

function TDialog4DHostFMX.MeasureTextHeight(const AText: string;
  const AMaxWidth: Single; const AFont: TFont; const AFontSize: Single): Single;
var
  LTextLayout: TTextLayout;
begin
  if (AText.Trim = '') or (AMaxWidth <= 0) then
    Exit(0);

  LTextLayout := TTextLayoutManager.DefaultTextLayout.Create;
  try
    LTextLayout.BeginUpdate;
    LTextLayout.Font.Assign(AFont);
    LTextLayout.Font.Size := AFontSize;
    LTextLayout.WordWrap := True;
    LTextLayout.MaxSize := TSizeF.Create(AMaxWidth,
      DefaultTextMeasureMaxHeight);
    LTextLayout.Text := AText;
    LTextLayout.EndUpdate;
    Result := Ceil(LTextLayout.TextHeight);
  finally
    LTextLayout.Free;
  end;
end;

procedure TDialog4DHostFMX.RecalcLayoutHeights;
(*
  Layout recalculation pipeline.

  Strategy
  - Resolve the responsive card width: phone form factor (≤480 px parent
    width) uses a wider ratio, desktop uses a narrower ratio. The result
    is clamped to [DefaultCardMinWidth, DefaultCardMaxWidth] and then
    capped by FTheme.DialogWidth when set.
  - Rebuild the button row if the available bar width drifted enough to
    change the chosen layout mode.
  - Measure the title and message heights against the actual render
    width — this means matching FMessage's effective width by subtracting
    DefaultScrollbarReservedWidth (Windows) and a small text compensation.
  - Compose the final card height from header + content + button bar +
    paddings, clamping to [LMinCardHeight, parent × DialogMaxHeightRatio].

  Outcomes
  - FCard.Width and FCard.Height reflect the recalculated values.
  - FScrollBox is realigned and scrolled to the top so the text starts at
    a known position after every recalculation.

  Invariants
  - FMessage's measurement width MUST match its actual render width;
    otherwise the bottom safety margin (one extra line) becomes
    insufficient and the last line clips on Windows at certain DPI
    settings.
*)
var
  LTextMaxWidth: Single;
  LTitleHeight, LMessageHeight: Single;
  LContentHeight: Single;
  LDesiredCardHeight, LMaxCardHeight: Single;
  LTitleVisible: Boolean;
  LMinContentHeight, LMinCardHeight: Single;
  LMaxCardHeightRatio: Single;
  LHeaderHeight, LHeaderBottomSpacing: Single;
  LFormWidth, LWidthRatio, LTargetCardWidth: Single;
begin
  LMinContentHeight := IfThen(FTheme.ContentMinHeight > 0,
    FTheme.ContentMinHeight, 50);
  LMinCardHeight := IfThen(FTheme.DialogMinHeight > 0,
    FTheme.DialogMinHeight, 170);

  LMaxCardHeightRatio := FTheme.DialogMaxHeightRatio;
  if (LMaxCardHeightRatio <= 0) or (LMaxCardHeightRatio > 1.0) then
    LMaxCardHeightRatio := 0.85;

  LFormWidth := IfThen(Assigned(FParentForm) and (FParentForm.Width > 0),
    FParentForm.Width, FTheme.DialogWidth);

  // Phone form factor (≤480 px) gets a wider ratio so the dialog uses more
  // of the screen; desktop uses a narrower ratio for visual balance.
  LWidthRatio := IfThen(LFormWidth <= 480, DefaultCardWidthPhoneRatio,
    DefaultCardWidthDesktopRatio);
  LTargetCardWidth := Min(DefaultCardMaxWidth, Max(DefaultCardMinWidth,
    LFormWidth * LWidthRatio));

  if FTheme.DialogWidth > 0 then
    LTargetCardWidth := Min(LTargetCardWidth, FTheme.DialogWidth);

  FCard.Width := LTargetCardWidth;
  RebuildButtonsIfNeeded;

  // Text measurement width must match FMessage's actual render width.
  // FMessage (Client in FContent) = FContent.Width.
  // FContent.Margins.Right = DefaultScrollbarReservedWidth on Windows,
  // so FContent.Width = FScrollBox.Width - DefaultScrollbarReservedWidth.
  // Subtract the same amount here so the height estimate is accurate.
  if Assigned(FScrollBox) and (FScrollBox.Width > 0) then
    LTextMaxWidth := FScrollBox.Width - DefaultScrollbarReservedWidth -
      DefaultScrollTextWidthCompensation
  else
    LTextMaxWidth := FCard.Width - FCard.Padding.Left - FCard.Padding.Right -
      DefaultScrollbarReservedWidth - DefaultScrollTextWidthCompensation;

  if LTextMaxWidth < 40 then
    LTextMaxWidth := 40;

  LTitleVisible := FTitle.Visible and (FTitle.Text.Trim <> '');

  FTitle.Height := IfThen(LTitleVisible, MeasureTextHeight(FTitle.Text,
    FCard.Width - FCard.Padding.Left - FCard.Padding.Right,
    FTitle.TextSettings.Font, FTheme.TitleFontSize) +
    DefaultTitleHeightPadding, 0);

  LHeaderHeight := 0;
  if FIconWrap.Visible then
    LHeaderHeight := LHeaderHeight + FIconWrap.Height +
      FIconWrap.Margins.Bottom;
  if LTitleVisible then
    LHeaderHeight := LHeaderHeight + FTitle.Height + FTitle.Margins.Bottom;

  LHeaderBottomSpacing := IfThen(FIconWrap.Visible or LTitleVisible, 4, 0);
  FHeader.Height := Ceil(LHeaderHeight + LHeaderBottomSpacing);

  // Height source: TTextLayout explicit measurement.
  // AutoSize is disabled on FMessage so FMessage.Height = FContent.Height,
  // which is not a valid text height at this point.
  //
  // Bottom safety margin: add Ceil(FTheme.MessageFontSize) to LContentHeight.
  // TTextLayout.TextHeight returns a tight bounding box. FMX adds line
  // leading and descender padding when rendering, which is not reflected in
  // TextHeight. Without this margin the last visible line can be clipped by
  // approximately half its height, especially on Windows with certain DPI
  // settings. One font size worth of extra space (≈ one line height) is
  // sufficient to guarantee the last line is always fully visible.
  LMessageHeight := MeasureTextHeight(FMessage.Text, LTextMaxWidth,
    FMessage.TextSettings.Font, FTheme.MessageFontSize) +
    DefaultMessageHeightPadding;

  LContentHeight := Ceil(LMessageHeight + DefaultSpacingAfterMessage +
    FTheme.MessageFontSize); // Bottom safety margin (≈ one line height).
  if LContentHeight < LMinContentHeight then
    LContentHeight := LMinContentHeight;

  FContent.Height := LContentHeight;

  if Assigned(FScrollBox) then
  begin
    FScrollBox.RealignContent;
    FScrollBox.ViewportPosition := PointF(0, 0);
  end;

  LDesiredCardHeight := FCard.Padding.Top + FHeader.Height + LContentHeight +
    FButtonBar.Height + FCard.Padding.Bottom;
  if LDesiredCardHeight < LMinCardHeight then
    LDesiredCardHeight := LMinCardHeight;

  LMaxCardHeight := IfThen(Assigned(FParentForm) and (FParentForm.Height > 0),
    Floor(FParentForm.Height * LMaxCardHeightRatio), LDesiredCardHeight);
  if LMaxCardHeight < LMinCardHeight then
    LMaxCardHeight := LMinCardHeight;

  FCard.Height := IfThen(LDesiredCardHeight > LMaxCardHeight, LMaxCardHeight,
    LDesiredCardHeight);
end;

{ == Input handlers == }

procedure TDialog4DHostFMX.BackdropClick(Sender: TObject);
var
  LCancelIndex: Integer;
begin
  if not FCancelable then
    Exit;

  LCancelIndex := IndexOfFirstCancelableButton(FButtonSpecs);
  if LCancelIndex < 0 then
    Exit;

  FCloseReason := crBackdrop;
  CaptureTriggeredButtonFromIndex(LCancelIndex);
  CloseWithResult(FButtonSpecs[LCancelIndex].ModalResult);
end;

procedure TDialog4DHostFMX.BackdropTap(Sender: TObject; const Point: TPointF);
begin
  BackdropClick(Sender);
end;

procedure TDialog4DHostFMX.ButtonMouseDown(Sender: TObject;
  AButton: TMouseButton; AShift: TShiftState; X, Y: Single);
begin
  if Sender is TRectangle then
    TRectangle(Sender).Opacity := DefaultButtonPressedOpacity;
end;

procedure TDialog4DHostFMX.ButtonMouseUp(Sender: TObject; AButton: TMouseButton;
  AShift: TShiftState; X, Y: Single);
begin
  if Sender is TRectangle then
    TRectangle(Sender).Opacity := DefaultButtonNormalOpacity;
end;

function TDialog4DHostFMX.ButtonsAvailableWidth: Single;
begin
  // Resolve the available width by walking up the layout hierarchy until
  // we find a control with a known width. Order: FButtons → FButtonBar
  // (minus padding) → FCard (minus padding × 2) → FTheme.DialogWidth.
  if Assigned(FButtons) and (FButtons.Width > 0) then
    Exit(FButtons.Width);

  if Assigned(FButtonBar) and (FButtonBar.Width > 0) then
    Exit(FButtonBar.Width - (FButtonBar.Padding.Left +
      FButtonBar.Padding.Right));

  if Assigned(FCard) then
    Exit(FCard.Width - FCard.Padding.Left - FCard.Padding.Right -
      (FButtonBar.Padding.Left + FButtonBar.Padding.Right));

  Result := FTheme.DialogWidth;
end;

procedure TDialog4DHostFMX.ButtonClick(Sender: TObject);
var
  LButtonRect: TRectangle;
begin
  if not(Sender is TRectangle) then
    Exit;

  FCloseReason := crButton;
  LButtonRect := TRectangle(Sender);
  CaptureTriggeredButtonFromMeta(LButtonRect.TagObject);
  CloseWithResult(TModalResult(LButtonRect.Tag));
end;

procedure TDialog4DHostFMX.ButtonTap(Sender: TObject; const Point: TPointF);
begin
  ButtonClick(Sender);
end;

{ == Close pipeline == }

procedure TDialog4DHostFMX.CloseWithResult(const AResult: TModalResult);
begin
  if (FState = dgsClosing) or (FState = dgsClosed) then
    Exit;

  // Disable hit-testing across the whole tree as soon as a close is
  // requested so the user cannot trigger a second close mid-animation.
  if Assigned(FOverlay) then
    FOverlay.HitTest := False;
  if Assigned(FBackdrop) then
    FBackdrop.HitTest := False;
  if Assigned(FCard) then
    FCard.HitTest := False;

  FClosingResult := AResult;
  SafeEmitTelemetry(tkCloseRequested, FClosingResult, FCloseReason);
  AnimateClose;
end;

procedure TDialog4DHostFMX.AnimateOpen;
begin
  if FState <> dgsClosed then
    Exit;
  if Assigned(FAnimClose) then
    FAnimClose.Stop;

  FState := dgsOpening;
  FOverlay.Visible := True;
  FOverlay.HitTest := True;
  FOverlay.BringToFront;

{$IFDEF ANDROID}
  // Android: skip open animation to reduce touch-lifecycle timing issues.
  FOverlay.Opacity := 1;
  OnOpenFinished(nil);
{$ELSE}
  FOverlay.Opacity := 0;
  if Assigned(FAnimOpen) then
    FAnimOpen.Start;
{$ENDIF}
end;

procedure TDialog4DHostFMX.AnimateClose;
begin
  if (FState = dgsClosing) or (FState = dgsClosed) then
    Exit;
  if Assigned(FAnimOpen) then
    FAnimOpen.Stop;

  FState := dgsClosing;

{$IFDEF ANDROID}
  // Android: defer destruction to the main loop (see FinalizeCloseAsync).
  FOverlay.Opacity := 0;
  OnCloseFinished(nil);
{$ELSE}
  if Assigned(FAnimClose) then
  begin
    FAnimClose.StartValue := FOverlay.Opacity;
    FAnimClose.StopValue := 0;
    FAnimClose.Start;
  end
  else
    OnCloseFinished(nil);
{$ENDIF}
end;

procedure TDialog4DHostFMX.OnOpenFinished(Sender: TObject);
begin
  if FState = dgsOpening then
    FState := dgsOpen;

  // Focus the overlay on all platforms.
  // Desktop: enables Enter/Esc keyboard navigation.
  // Android: enables OnKeyUp to receive vkHardwareBack.
  TryFocusOverlay;

  SafeEmitTelemetry(tkShowDisplayed, mrNone, crNone);
end;

procedure TDialog4DHostFMX.FinalizeCloseNow;
(*
  Synchronous close finalization.

  Strategy
  - Reentrancy guard: FFinalizing prevents a second pass even if a finish
    handler fires twice.
  - Owner-destroying path: emit Closed + CallbackSuppressed telemetry, run
    Cleanup, set state to dgsClosed and bail out without invoking the user
    callback (the host is being torn down with the parent form).
  - Normal path: capture LProc, LRes and LReason BEFORE Cleanup, because
    Cleanup resets FCloseReason and the snapshot fields. After Cleanup,
    invoke the user callback wrapped in try/except so a faulty callback
    cannot leave the close pipeline in a partial state — the exception
    message is preserved in telemetry for diagnostics.

  Outcomes
  - User callback assigned and ran cleanly: tkCallbackInvoked telemetry.
  - User callback raised: tkCallbackInvoked telemetry with ErrorMessage.
  - User callback not assigned: tkCallbackSuppressed telemetry.
*)
var
  LProc: TDialog4DResultProc;
  LRes: TModalResult;
  LReason: TDialog4DCloseReason;
begin
  if FFinalizing then
    Exit;
  FFinalizing := True;

  if FOwnerDestroying then
  begin
    SafeEmitTelemetry(tkClosed, mrNone, crOwnerDestroying);
    SafeEmitTelemetry(tkCallbackSuppressed, mrNone, crOwnerDestroying);
    Cleanup;
    FState := dgsClosed;
    Exit;
  end;

  // Capture all values BEFORE Cleanup — Cleanup resets FCloseReason
  // (and other snapshot fields) to defaults.
  LProc := FOnResult;
  LRes := FClosingResult;
  LReason := FCloseReason;

  SafeEmitTelemetry(tkClosed, LRes, LReason);
  Cleanup;
  FState := dgsClosed;

  if Assigned(LProc) then
  begin
    try
      LProc(LRes);
      SafeEmitTelemetry(tkCallbackInvoked, LRes, LReason);
    except
      on E: Exception do
      begin
        // Keep the close pipeline deterministic, but preserve the callback
        // failure message in telemetry for diagnostics.
        SafeEmitTelemetry(tkCallbackInvoked, LRes, LReason, 0, E.Message);
      end;
    end;
  end
  else
    SafeEmitTelemetry(tkCallbackSuppressed, LRes, LReason);
end;

procedure TDialog4DHostFMX.FinalizeCloseAsync;
begin
  QueueOnMainThread(
    procedure
    begin
      FinalizeCloseNow;
    end);
end;

procedure TDialog4DHostFMX.OnCloseFinished(Sender: TObject);
begin
  if FState <> dgsClosing then
    Exit;

{$IFDEF ANDROID}
  // Android: always defer destruction to avoid destroying the visual tree
  // inline during touch/gesture processing.
  FinalizeCloseAsync;
{$ELSE}
  FinalizeCloseNow;
{$ENDIF}
end;

procedure TDialog4DHostFMX.Cleanup;
(*
  Per-dialog state and visual-tree teardown.

  Strategy
  - Reset all per-dialog state fields (callbacks, snapshots, flags, layout
    cache) to their post-construction defaults so the host is ready for
    a future ShowDialog cycle.
  - Stop and detach both animations.
  - Branch by FOwnerDestroying:
    * Owner destroying: do NOT touch the visual tree. The parent form is
      already disposing of its own children. Just neutralize handlers
      and let the form take care of the overlay.
    * Normal close: actively dispose of the overlay (which cascades to
      the entire tree) after clearing buttons.
  - Detach the form hook on a normal close. On owner-destroying the hook
    is already running its destructor — touching it here would be a UAF.
  - Null all visual-tree references; DisposeOf above already triggered
    their destruction.

  Invariants
  - After this method returns, FState is unchanged — the caller decides
    when to set FState := dgsClosed (FinalizeCloseNow does this after
    Cleanup so the user callback runs after the state transition).
*)
begin
  FOnResult := nil;
  FCancelable := False;
  FHasCancelButton := False;
  FClosingResult := mrNone;
  FDialogType := TMsgDlgType.mtCustom;
  FOpenTick := 0;
  FCloseReason := crNone;

  FTitleSnapshot := '';
  FMessageLenSnapshot := 0;
  FButtonsCountSnapshot := 0;
  FDefaultResultSnapshot := mrNone;

  SetLength(FButtonSpecs, 0);
  ResetTriggeredButtonInfo;

  FHandlingResize := False;
  FRebuildingButtons := False;
  FButtonLayoutMode := blmHorizontal;

  if Assigned(FAnimOpen) then
  begin
    FAnimOpen.Stop;
    FAnimOpen.OnFinish := nil;
  end;
  if Assigned(FAnimClose) then
  begin
    FAnimClose.Stop;
    FAnimClose.OnFinish := nil;
  end;

  if FOwnerDestroying then
  begin
    if Assigned(FOverlay) then
    begin
{$IF DEFINED(MSWINDOWS) OR DEFINED(MACOS)}
      FOverlay.OnKeyDown := nil;
{$ENDIF}
{$IFDEF ANDROID}
      FOverlay.OnKeyUp := nil;
{$ENDIF}
      FOverlay.OnResize := nil;
      FOverlay.HitTest := False;
      FOverlay.Visible := False;
      FOverlay.Opacity := 0;
    end;
  end
  else
  begin
    if Assigned(FButtons) then
      ClearButtons;
    if Assigned(FOverlay) then
    begin
{$IF DEFINED(MSWINDOWS) OR DEFINED(MACOS)}
      FOverlay.OnKeyDown := nil;
{$ENDIF}
{$IFDEF ANDROID}
      FOverlay.OnKeyUp := nil;
{$ENDIF}
      FOverlay.OnResize := nil;
      FOverlay.HitTest := False;
      FOverlay.Visible := False;
      FOverlay.Opacity := 0;
      FOverlay.Parent := nil;
      FOverlay.DisposeOf;
    end;
  end;

  if not FOwnerDestroying then
  begin
    if Assigned(FFormHook) and (FFormHook is TDialog4DFormHook) then
      TDialog4DFormHook(FFormHook).Detach;
    FreeAndNil(FFormHook);
  end;

  // Null all visual-tree references — DisposeOf above already triggered
  // their destruction.
  FOverlay := nil;
  FBackdrop := nil;
  FCard := nil;
  FHeader := nil;
  FScrollBox := nil;
  FContent := nil;
  FIconWrap := nil;
  FIconCircle := nil;
  FIconGlyph := nil;
  FXBar1 := nil;
  FXBar2 := nil;
  FTitle := nil;
  FMessage := nil;
  FButtonBar := nil;
  FButtons := nil;
  FAnimOpen := nil;
  FAnimClose := nil;
  FParentForm := nil;
  FFinalizing := False;
end;

{ == Public entry == }

procedure TDialog4DHostFMX.ShowDialog(const AParent: TCommonCustomForm;
const ATitle, AMessage: string;
const AButtons: TArray<TDialog4DButtonConfiguration>;
const ACancelable: Boolean; const AOnResult: TDialog4DResultProc;
const ADlgType: TMsgDlgType);
(*
  Public entry point for showing a dialog.

  Strategy
  - Reject reentrancy: an active visual tree or a non-closed state means a
    dialog is already running on this host.
  - Validate the parent form (raises if missing).
  - Capture telemetry snapshots BEFORE building the visual tree, so any
    failure during EnsureUI or BuildButtons still produces meaningful
    diagnostic output.
  - Build the visual tree (EnsureUI), apply the active theme, configure
    the icon, title and message, build the button row, and run the layout
    recalculation pipeline.
  - Bring the overlay to front and start the open animation.

  Invariants
  - Must run on the main thread (the public facade enforces this; this
    method assumes it).
  - On entry, FState must be dgsClosed and FOverlay must be nil.
*)
begin
  if Assigned(FOverlay) or (FState <> dgsClosed) then
    raise Exception.Create
      ('Dialog4D: a dialog is already active on this host.');

  if not Assigned(AParent) then
    raise Exception.Create('Dialog4D: parent form is required.');

  FDialogType := ADlgType;
  FTitleSnapshot := ATitle;
  FMessageLenSnapshot := Length(AMessage);
  FButtonsCountSnapshot := Length(AButtons);
  FCloseReason := crNone;
  FOpenTick := TickMs;
  ResetTriggeredButtonInfo;

  EnsureUI(AParent);
  ApplyTheme;

  FCancelable := ACancelable;
  FOnResult := AOnResult;

  ApplyIconForType(ADlgType);

  FTitle.Text := ATitle;
  FTitle.Visible := (ATitle.Trim <> '');
  FMessage.Text := AMessage;

  BuildButtons(AButtons);
  RecalcLayoutHeights;

  FOverlay.BringToFront;
  AnimateOpen;
end;

end.
