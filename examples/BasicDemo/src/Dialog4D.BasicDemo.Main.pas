// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Eduardo P. Araujo
// https://github.com/eduardoparaujo/Dialog4D

{*
  Unit   : Dialog4D.BasicDemo.Main
  Purpose: Scenario-driven demonstration and manual validation harness for
           Dialog4D. Covers the public API through practical examples:
           visual consistency, theme/provider customization, telemetry,
           behavioral checks, per-form FIFO queueing, worker-thread await,
           FMX.DialogService comparison, custom-button workflows, and
           dialog-driven business actions via an injected demo service.

  Part of the Dialog4D demo application; not part of the runtime library.

  Author        : Eduardo P. Araujo
  Created       : 2026-04-26
  Last modified : 2026-05-01
  Version       : 1.0.1

  Sections:
    1  - Basic dialog types
    2  - Theme / provider / telemetry
    3  - UX / behavioral checks
    4  - Extra button combinations
    5  - Queue, stress and flow orchestration
    6  - Programmatic close
    7  - DialogService4D facade
    8  - Await family
    9  - FMX.DialogService comparison
    10 - Custom buttons (TDialog4DCustomButton)

  Notes:
    - This unit is a demo and validation surface, not part of the Dialog4D
      runtime library.

    - Supporting workflow abstractions used by the examples are isolated in
      Dialog4D.BasicDemo.Workflow to keep UI orchestration separate from
      demo business actions.

    - Queue and async examples intentionally demonstrate Dialog4D behavior
      under delayed callback execution. Loop values used inside anonymous
      callbacks must be captured through stable method parameters or local
      immutable snapshots, not through the mutable loop variable itself.

  History:
    1.0.1 — 2026-05-01 — Demo wording and queue callback correction.
      • Fixed example 5.1 (Queue burst from TTask) so each dialog callback logs
        the correct dialog index.
      • Moved per-dialog creation to a helper method, preventing anonymous
        callbacks from capturing the mutable loop variable used by the TTask
        for-loop.
      • Clarified example 7.1 wording: DialogService4D is presented as a
        migration-friendly facade, not as a full drop-in clone of
        FMX.DialogService.
      • Restored the previous FMX.DialogService PreferredMode after example
        9.1 so the demo does not leave global DialogService state changed.
      • No Dialog4D runtime behavior was changed by these demo corrections.

    1.0.0 — 2026-04-26 — Initial public demo release.
      • Added scenario-driven examples covering basic dialogs, themes,
        providers, telemetry, queueing, programmatic close, DialogService4D,
        Await, FMX.DialogService comparison and custom buttons.
      • Added workflow-service based examples to demonstrate dialog-driven
        business actions without coupling demo UI code directly to simulated
        business logic.
*}

unit Dialog4D.BasicDemo.Main;

interface

uses
  System.SysUtils,
  System.Classes,
  System.UITypes,
  System.Threading,

  FMX.Types,
  FMX.Controls,
  FMX.Dialogs,
  FMX.Forms,
  FMX.StdCtrls,
  FMX.Layouts,
  FMX.Memo,
  FMX.Memo.Types,
  FMX.ScrollBox,
  FMX.Controls.Presentation,
  FMX.DialogService,

  Dialog4D,
  Dialog4D.Types,
  Dialog4D.Telemetry.Format,
  Dialog4D.Await,
  Dialog4D.TextProvider.Default,
  DialogService4D,
  Dialog4D.BasicDemo.Workflow;

type
  /// <summary>
  /// Demo Japanese text provider.
  /// </summary>
  /// <remarks>
  /// <para>Replace with your own i18n infrastructure in production.</para>
  /// </remarks>
  TJPProvider = class(TInterfacedObject, IDialog4DTextProvider)
  public
    function ButtonText(const ABtn: TMsgDlgBtn): string;
    function TitleForType(const ADlgType: TMsgDlgType): string;
  end;

  /// <summary>
  /// Defines the workflow scenario simulated by the injected demo service.
  /// </summary>
  /// <remarks>
  /// <para>
  /// Used by example 5.6 to switch between success and controlled failure
  /// paths without changing the UI orchestration code.
  /// </para>
  /// </remarks>
  TInjectedWorkflowScenario = (
    iwsSuccess,
    iwsFailOnSave,
    iwsFailOnClose
  );

  TFormMain = class(TForm)
    MemoLog: TMemo;
    ScrollButtons: TVertScrollBox;

    { == Section 1 — Basic dialog types == }
    ButtonInfoOk:                   TButton;
    ButtonConfirmYesNo:             TButton;
    ButtonWarningYesNoCancel:       TButton;
    ButtonErrorRetryCancel:         TButton;
    ButtonNoCancelTapOutside:       TButton;

    { == Section 2 — Theme / provider / telemetry == }
    ButtonCustomTheme:              TButton;
    ButtonDarkTheme:                TButton;
    ButtonCyberpunkTheme:           TButton;
    ButtonTreatCloseAsCancel:       TButton;
    ButtonJPProvider:               TButton;
    ButtonRestoreDefaultProvider:   TButton;
    ButtonTelemetryEnable:          TButton;

    { == Section 3 — UX / behavioral checks == }
    ButtonEnterDefaultDemo:         TButton;
    ButtonEscCancelDemo:            TButton;
    ButtonEscWithoutCancelDemo:     TButton;
    ButtonInvalidDefaultDemo:       TButton;

    { == Section 4 — Extra button combinations == }
    ButtonAbortRetryIgnore:         TButton;
    ButtonAllCancel:                TButton;
    ButtonAllNoToAllYesToAll:       TButton;
    ButtonHelpClose:                TButton;
    ButtonIgnoreClose:              TButton;

    { == Section 5 — Queue and stress == }
    ButtonQueueDemo:                TButton;
    ButtonTestLongCancel:           TButton;
    ButtonThemeSwapDemo:            TButton;
    ButtonDecisionFlowDemo:         TButton;
    ButtonDecisionFlowCustom:       TButton;
    ButtonInjectedWorkflowDemo:     TButton;

    { == Section 6 — Programmatic close == }
    ButtonCloseProgrammatic: TButton;

    { == Section 7 — DialogService4D facade == }
    ButtonDialogService4D: TButton;

    { == Section 8 — Await family == }
    ButtonAwaitOnWorker:            TButton;
    ButtonAwaitSmart:               TButton;
    ButtonAwaitSmartCallbackOnMain: TButton;
    ButtonAwaitTimeout:             TButton;
    ButtonAwaitErrorOnMainThread:   TButton;

    { == Section 9 — FMX.DialogService comparison == }
    ButtonDialogServiceSyncRealityCheck: TButton;

    { == Section 10 — Custom buttons == }
    ButtonCustomSimple:             TButton;
    ButtonCustomDestructive:        TButton;
    ButtonCustomAllRoles:           TButton;
    ButtonCustomSessionExpiry:      TButton;
    ButtonCustomAwaitWorker:        TButton;

    procedure FormCreate(Sender: TObject);

    { == Section 1 == }
    procedure ButtonInfoOkClick(Sender: TObject);
    procedure ButtonConfirmYesNoClick(Sender: TObject);
    procedure ButtonWarningYesNoCancelClick(Sender: TObject);
    procedure ButtonErrorRetryCancelClick(Sender: TObject);
    procedure ButtonNoCancelTapOutsideClick(Sender: TObject);

    { == Section 2 == }
    procedure ButtonCustomThemeClick(Sender: TObject);
    procedure ButtonDarkThemeClick(Sender: TObject);
    procedure ButtonCyberpunkThemeClick(Sender: TObject);
    procedure ButtonTreatCloseAsCancelClick(Sender: TObject);
    procedure ButtonJPProviderClick(Sender: TObject);
    procedure ButtonRestoreDefaultProviderClick(Sender: TObject);
    procedure ButtonTelemetryEnableClick(Sender: TObject);

    { == Section 3 == }
    procedure ButtonEnterDefaultDemoClick(Sender: TObject);
    procedure ButtonEscCancelDemoClick(Sender: TObject);
    procedure ButtonEscWithoutCancelDemoClick(Sender: TObject);
    procedure ButtonInvalidDefaultDemoClick(Sender: TObject);

    { == Section 4 == }
    procedure ButtonAbortRetryIgnoreClick(Sender: TObject);
    procedure ButtonAllCancelClick(Sender: TObject);
    procedure ButtonAllNoToAllYesToAllClick(Sender: TObject);
    procedure ButtonHelpCloseClick(Sender: TObject);
    procedure ButtonIgnoreCloseClick(Sender: TObject);

    { == Section 5 == }
    procedure QueueDemoDialogFromTask(const AIndex, ATotal: Integer);
    procedure ButtonQueueDemoClick(Sender: TObject);
    procedure ButtonTestLongCancelClick(Sender: TObject);
    procedure ButtonThemeSwapDemoClick(Sender: TObject);
    procedure ButtonDecisionFlowDemoClick(Sender: TObject);
    procedure ButtonDecisionFlowCustomClick(Sender: TObject);
    procedure ButtonInjectedWorkflowDemoClick(Sender: TObject);

    { == Section 6 == }
    procedure ButtonCloseProgrammaticClick(Sender: TObject);

    { == Section 7 == }
    procedure ButtonDialogService4DClick(Sender: TObject);

    { == Section 8 == }
    procedure ButtonAwaitOnWorkerClick(Sender: TObject);
    procedure ButtonAwaitSmartClick(Sender: TObject);
    procedure ButtonAwaitSmartCallbackOnMainClick(Sender: TObject);
    procedure ButtonAwaitTimeoutClick(Sender: TObject);
    procedure ButtonAwaitErrorOnMainThreadClick(Sender: TObject);

    { == Section 9 == }
    procedure ButtonDialogServiceSyncRealityCheckClick(Sender: TObject);

    { == Section 10 == }
    procedure ButtonCustomSimpleClick(Sender: TObject);
    procedure ButtonCustomDestructiveClick(Sender: TObject);
    procedure ButtonCustomAllRolesClick(Sender: TObject);
    procedure ButtonCustomSessionExpiryClick(Sender: TObject);
    procedure ButtonCustomAwaitWorkerClick(Sender: TObject);

  private
    FTelemetryEnabled: Boolean;
    FProgrammaticCloseTimer: TTimer;

    { == Logging == }
    procedure LogLine(const S: string);
    procedure LogResult(const ACaption: string; const AResult: TModalResult);
    procedure LogSeparator(const ATitle: string);
    procedure LogWorkflowResult(const ACaption: string;
      const AResult: TDocumentWorkflowResult);

    { == Theme helpers == }
    procedure ApplyDefaultTheme;
    procedure ApplyCustomTheme;
    procedure ApplyDarkTheme;
    procedure ApplyDemoTheme_Cyberpunk;
    procedure ApplyCompactSizing(var ATheme: TDialog4DTheme);
    procedure ApplyTallSizing(var ATheme: TDialog4DTheme);

    { == Provider helpers == }
    procedure ApplyDefaultProvider;
    procedure ApplyJPProvider;

    { == Telemetry == }
    procedure SetTelemetryEnabled(const AEnabled: Boolean);
    procedure UpdateTelemetryButtonUI;

    { == Timer helpers == }
    procedure ProgrammaticCloseTimer(Sender: TObject);

    { == Misc helpers == }
    function BuildLongMessage: string;
    function NowStr: string;
  end;

var
  FormMain: TFormMain;

implementation

{$R *.fmx}

{ ================= }
{ == TJPProvider == }
{ ================= }

function TJPProvider.ButtonText(const ABtn: TMsgDlgBtn): string;
begin
  case ABtn of
    TMsgDlgBtn.mbOK:       Result := 'OK';
    TMsgDlgBtn.mbCancel:   Result := 'キャンセル';
    TMsgDlgBtn.mbYes:      Result := 'はい';
    TMsgDlgBtn.mbNo:       Result := 'いいえ';
    TMsgDlgBtn.mbRetry:    Result := '再試行';
    TMsgDlgBtn.mbAbort:    Result := '中止';
    TMsgDlgBtn.mbIgnore:   Result := '無視';
    TMsgDlgBtn.mbClose:    Result := '閉じる';
    TMsgDlgBtn.mbHelp:     Result := 'ヘルプ';
    TMsgDlgBtn.mbAll:      Result := 'すべて';
    TMsgDlgBtn.mbYesToAll: Result := 'すべてはい';
    TMsgDlgBtn.mbNoToAll:  Result := 'すべていいえ';
  else
    Result := 'ボタン';
  end;
end;

function TJPProvider.TitleForType(const ADlgType: TMsgDlgType): string;
begin
  case ADlgType of
    TMsgDlgType.mtInformation:  Result := '情報';
    TMsgDlgType.mtConfirmation: Result := '確認';
    TMsgDlgType.mtWarning:      Result := '警告';
    TMsgDlgType.mtError:        Result := 'エラー';
  else
    Result := '';
  end;
end;

{ ==================== }
{ == Form lifecycle == }
{ ==================== }

procedure TFormMain.FormCreate(Sender: TObject);
begin
  MemoLog.Lines.Clear;
  LogLine('Dialog4D demo ready.');
  LogLine('');

  { -- Telemetry -- }
  ButtonTelemetryEnable.Text := '2.7  Telemetry: OFF  (click to enable)';

  { -- Section 1 — Basic dialog types -- }
  ButtonInfoOk.Text                   := '1.1  Information (OK)';
  ButtonConfirmYesNo.Text             := '1.2  Confirmation (Yes / No)';
  ButtonWarningYesNoCancel.Text       := '1.3  Warning (Yes / No / Cancel)';
  ButtonErrorRetryCancel.Text         := '1.4  Error (Retry / Cancel)';
  ButtonNoCancelTapOutside.Text       := '1.5  No cancel button';

  { -- Section 2 — Theme / provider / telemetry -- }
  ButtonCustomTheme.Text              := '2.1  Custom theme';
  ButtonDarkTheme.Text                := '2.2  Dark theme';
  ButtonCyberpunkTheme.Text           := '2.3  Cyberpunk theme';
  ButtonTreatCloseAsCancel.Text       := '2.4  TreatCloseAsCancel';
  ButtonJPProvider.Text               := '2.5  Japanese provider';
  ButtonRestoreDefaultProvider.Text   := '2.6  Restore provider';

  { -- Section 3 — UX / behavioral checks -- }
  ButtonEnterDefaultDemo.Text         := '3.1  Enter → default button';
  ButtonEscCancelDemo.Text            := '3.2  Esc → cancel button';
  ButtonEscWithoutCancelDemo.Text     := '3.3  Esc/backdrop no-op';
  ButtonInvalidDefaultDemo.Text       := '3.4  Invalid default';

  { -- Section 4 — Extra button combinations -- }
  ButtonAbortRetryIgnore.Text         := '4.1  Abort / Retry / Ignore';
  ButtonAllCancel.Text                := '4.2  All / Cancel';
  ButtonAllNoToAllYesToAll.Text       := '4.3  All / NoToAll / YesToAll';
  ButtonHelpClose.Text                := '4.4  Help / Close';
  ButtonIgnoreClose.Text              := '4.5  Ignore / Close';

  { -- Section 5 — Queue and stress -- }
  ButtonQueueDemo.Text                := '5.1  Queue burst';
  ButtonTestLongCancel.Text           := '5.2  Long message';
  ButtonThemeSwapDemo.Text            := '5.3  Theme snapshot';
  ButtonDecisionFlowDemo.Text         := '5.4  Sequential decision flow';
  ButtonDecisionFlowCustom.Text       := '5.5  Decision flow — custom';
  ButtonInjectedWorkflowDemo.Text     := '5.6  Business action';

  { -- Section 6 — Programmatic close -- }
  ButtonCloseProgrammatic.Text        := '6.1  Programmatic close';

  { -- Section 7 — DialogService4D facade -- }
  ButtonDialogService4D.Text          := '7.1  DialogService4D facade';

  { -- Section 8 — Await family -- }
  ButtonAwaitOnWorker.Text            := '8.1  Worker await';
  ButtonAwaitSmart.Text               := '8.2  Smart message';
  ButtonAwaitSmartCallbackOnMain.Text := '8.3  Callback on main';
  ButtonAwaitTimeout.Text             := '8.4  Worker timeout';
  ButtonAwaitErrorOnMainThread.Text   := '8.5  Intentional await error';

  { -- Section 9 — FMX.DialogService comparison -- }
  ButtonDialogServiceSyncRealityCheck.Text := '9.1  FMX.DialogService comparison';

  { -- Section 10 — Custom buttons -- }
  ButtonCustomSimple.Text            := '10.1  Custom buttons';
  ButtonCustomDestructive.Text       := '10.2  Destructive button';
  ButtonCustomAllRoles.Text          := '10.3  Custom roles';
  ButtonCustomSessionExpiry.Text     := '10.4  Session example';
  ButtonCustomAwaitWorker.Text       := '10.5  Custom worker await';

  ApplyDefaultProvider;
  ApplyDefaultTheme;
  FTelemetryEnabled := False;
end;

{ ===================== }
{ == Logging helpers == }
{ ===================== }

function TFormMain.NowStr: string;
begin
  Result := FormatDateTime('hh:nn:ss.zzz', Now);
end;

procedure TFormMain.LogLine(const S: string);
begin
  MemoLog.Lines.Add(S);
end;

procedure TFormMain.LogResult(const ACaption: string;
  const AResult: TModalResult);
begin
  LogLine(Format('%s  %s -> %s',
    [NowStr, ACaption, TDialog4DTelemetryFormat.ModalResultToText(AResult)]));
end;

procedure TFormMain.LogSeparator(const ATitle: string);
begin
  LogLine('');
  LogLine('--- ' + ATitle + ' ---');
end;

{ =================== }
{ == Timer helpers == }
{ =================== }

procedure TFormMain.ProgrammaticCloseTimer(Sender: TObject);
begin
  if Assigned(FProgrammaticCloseTimer) then
    FProgrammaticCloseTimer.Enabled := False;

  TDialog4D.CloseDialog(Self, mrCancel);
end;

{ ================== }
{ == Misc helpers == }
{ ================== }

function TFormMain.BuildLongMessage: string;
var
  I: Integer;
begin
  Result :=
    'Long message scroll test.' + sLineBreak + sLineBreak +
    'Objectives:' + sLineBreak +
    '  - Validate ScrollBox behavior' + sLineBreak +
    '  - Validate Cancel button click after scrolling' + sLineBreak +
    '  - Validate dialog stability throughout' + sLineBreak + sLineBreak;

  for I := 1 to 60 do
    Result := Result +
      Format(
        'Line %d: intentionally long text to force ScrollBox usage. ' +
        'Scroll to the middle, the end, then click Cancel to verify stability.',
        [I]
      ) + sLineBreak + sLineBreak;

  Result := Result + 'End of test message. Click Cancel to close.';
end;

{ ====================== }
{ == Provider helpers == }
{ ====================== }

procedure TFormMain.ApplyDefaultProvider;
begin
  TDialog4D.ConfigureTextProvider(TDialog4DDefaultTextProvider.Create);
  LogLine(NowStr + '  Provider: default (English) restored.');
end;

procedure TFormMain.ApplyJPProvider;
begin
  TDialog4D.ConfigureTextProvider(TJPProvider.Create);
  LogLine(NowStr + '  Provider: Japanese applied. Use 2.6 to revert.');
end;

{ =================== }
{ == Theme helpers == }
{ =================== }

procedure TFormMain.ApplyDefaultTheme;
var
  LTheme: TDialog4DTheme;
begin
  LTheme := TDialog4DTheme.Default;
  LTheme.ShowDefaultButtonHighlight := False;
  LTheme.ContentMinHeight           := 50;
  LTheme.DialogMinHeight            := 170;
  LTheme.DialogMaxHeightRatio       := 0.85;
  LTheme.DialogWidth                := 320;
  LTheme.OverlayOpacity             := 0.45;
  TDialog4D.ConfigureTheme(LTheme);
end;

procedure TFormMain.ApplyCompactSizing(var ATheme: TDialog4DTheme);
begin
  ATheme.ContentMinHeight     := 30;
  ATheme.DialogMinHeight      := 150;
  ATheme.DialogMaxHeightRatio := 0.80;
  ATheme.DialogWidth          := 300;
end;

procedure TFormMain.ApplyTallSizing(var ATheme: TDialog4DTheme);
begin
  ATheme.ContentMinHeight     := 90;
  ATheme.DialogMinHeight      := 220;
  ATheme.DialogMaxHeightRatio := 0.90;
  ATheme.DialogWidth          := 360;
end;

procedure TFormMain.ApplyCustomTheme;
var
  LTheme: TDialog4DTheme;
begin
  LTheme := TDialog4DTheme.Default;
  ApplyTallSizing(LTheme);
  LTheme.CornerRadius       := 16;
  LTheme.TitleFontSize      := 17;
  LTheme.MessageFontSize    := 14;
  LTheme.ButtonHeight       := 46;
  LTheme.OverlayOpacity     := 0.50;
  LTheme.AccentInfoColor    := $FF00A0E1;
  LTheme.AccentWarningColor := $FFF0B44C;
  LTheme.AccentErrorColor   := $FFE64D4D;
  LTheme.AccentConfirmColor := $FF8C8C8C;
  LTheme.AccentNeutralColor := $FFEFEFEF;
  TDialog4D.ConfigureTheme(LTheme);
end;

procedure TFormMain.ApplyDarkTheme;
var
  LTheme: TDialog4DTheme;
begin
  LTheme := TDialog4DTheme.Default;
  LTheme.SurfaceColor             := $FF1E1E2E;
  LTheme.TextTitleColor           := $FFCDD6F4;
  LTheme.TextMessageColor         := $FF9399B2;
  LTheme.OverlayColor             := $FF000000;
  LTheme.OverlayOpacity           := 0.65;
  LTheme.AccentInfoColor          := $FF89B4FA;
  LTheme.AccentWarningColor       := $FFFAB387;
  LTheme.AccentErrorColor         := $FFF38BA8;
  LTheme.AccentConfirmColor       := $FFA6E3A1;
  LTheme.AccentNeutralColor       := $FF313244;
  LTheme.ButtonNeutralFillColor   := $FF313244;
  LTheme.ButtonNeutralTextColor   := $FFCDD6F4;
  LTheme.ButtonNeutralBorderColor := $FF45475A;
  TDialog4D.ConfigureTheme(LTheme);
end;

procedure TFormMain.ApplyDemoTheme_Cyberpunk;
var
  LTheme: TDialog4DTheme;
begin
  LTheme := TDialog4DTheme.Default;
  LTheme.DialogWidth                     := 380;
  LTheme.DialogMinHeight                 := 200;
  LTheme.DialogMaxHeightRatio            := 0.90;
  LTheme.ContentMinHeight                := 80;
  LTheme.OverlayColor                    := $FF05060A;
  LTheme.OverlayOpacity                  := 0.70;
  LTheme.SurfaceColor                    := $FF10121A;
  LTheme.TextTitleColor                  := $FFEDEDED;
  LTheme.TextMessageColor                := $FFB8C0FF;
  LTheme.AccentInfoColor                 := $FF00D1FF;
  LTheme.AccentWarningColor              := $FFFFC247;
  LTheme.AccentErrorColor                := $FFFF4D6D;
  LTheme.AccentConfirmColor              := $FF8A5CFF;
  LTheme.AccentNeutralColor              := $FF2A2D3A;
  LTheme.CornerRadius                    := 22;
  LTheme.TitleFontSize                   := 18;
  LTheme.MessageFontSize                 := 14;
  LTheme.ButtonHeight                    := 48;
  LTheme.ButtonFontSize                  := 14;
  LTheme.ButtonNeutralFillColor          := $FFFFFFFF;
  LTheme.ButtonNeutralTextColor          := $FF000000;
  LTheme.ButtonNeutralBorderColor        := $FF000000;
  LTheme.ShowDefaultButtonHighlight      := True;
  LTheme.DefaultButtonHighlightColor     := TAlphaColors.White;
  LTheme.DefaultButtonHighlightThickness := 1;
  LTheme.DefaultButtonHighlightOpacity   := 1.0;
  LTheme.DefaultButtonHighlightInset     := 1;
  TDialog4D.ConfigureTheme(LTheme);
end;

{ ====================== }
{ == Telemetry toggle == }
{ ====================== }

procedure TFormMain.UpdateTelemetryButtonUI;
begin
  if FTelemetryEnabled then
    ButtonTelemetryEnable.Text := '2.7  Telemetry: ON  (click to disable)'
  else
    ButtonTelemetryEnable.Text := '2.7  Telemetry: OFF  (click to enable)';
end;

procedure TFormMain.SetTelemetryEnabled(const AEnabled: Boolean);
begin
  FTelemetryEnabled := AEnabled;

  if not FTelemetryEnabled then
  begin
    TDialog4D.ConfigureTelemetry(nil);
    LogLine(NowStr + '  Telemetry disabled.');
    UpdateTelemetryButtonUI;
    Exit;
  end;

  TDialog4D.ConfigureTelemetry(
    procedure(const D: TDialog4DTelemetry)
    begin
      TThread.Queue(nil, procedure
      begin
        LogLine(TDialog4DTelemetryFormat.FormatTelemetry(D));
      end);
    end);

  LogLine(NowStr + '  Telemetry enabled.');
  UpdateTelemetryButtonUI;
end;

procedure TFormMain.ButtonTelemetryEnableClick(Sender: TObject);
begin
  SetTelemetryEnabled(not FTelemetryEnabled);
end;

{ ==================================== }
{ == Section 1 — Basic dialog types == }
{ ==================================== }

procedure TFormMain.ButtonInfoOkClick(Sender: TObject);
var
  LTheme: TDialog4DTheme;
begin
  LTheme := TDialog4DTheme.Default;
  ApplyCompactSizing(LTheme);
  TDialog4D.ConfigureTheme(LTheme);

  TDialog4D.MessageDialogAsync(
    'Your file has been saved successfully.',
    TMsgDlgType.mtInformation,
    [TMsgDlgBtn.mbOK],
    TMsgDlgBtn.mbOK,
    procedure(const AResult: TModalResult)
    begin
      LogResult('1.1 Info(OK) Compact', AResult);
      ApplyDefaultTheme;
    end,
    '', Self, False
  );
end;

procedure TFormMain.LogWorkflowResult(
  const ACaption: string;
  const AResult: TDocumentWorkflowResult);
begin
  LogLine(Format(
    '%s  %s -> Success=%s, Message=%s',
    [
      NowStr,
      ACaption,
      BoolToStr(AResult.Success, True),
      AResult.MessageText
    ]
  ));
end;

procedure TFormMain.ButtonConfirmYesNoClick(Sender: TObject);
begin
  ApplyDefaultTheme;

  TDialog4D.MessageDialogAsync(
    'Do you want to continue with the operation?',
    TMsgDlgType.mtConfirmation,
    [TMsgDlgBtn.mbYes, TMsgDlgBtn.mbNo],
    TMsgDlgBtn.mbYes,
    procedure(const AResult: TModalResult)
    begin
      LogResult('1.2 Confirm(Yes/No)', AResult);
    end,
    '', Self, False
  );
end;

procedure TFormMain.ButtonWarningYesNoCancelClick(Sender: TObject);
begin
  ApplyDefaultTheme;

  TDialog4D.MessageDialogAsync(
    'This dialog shows Yes / No / Cancel with distinct callback actions per button.',
    TMsgDlgType.mtWarning,
    [TMsgDlgBtn.mbYes, TMsgDlgBtn.mbNo, TMsgDlgBtn.mbCancel],
    TMsgDlgBtn.mbNo,
    procedure(const AResult: TModalResult)
    begin
      LogResult('1.3 Warning(Yes/No/Cancel)', AResult);
      case AResult of
        mrYes:    LogLine('  Action: YES — proceed.');
        mrNo:     LogLine('  Action: NO — do not proceed.');
        mrCancel: LogLine('  Action: CANCEL — dismiss.');
      end;
    end,
    '', Self, True
  );
end;

procedure TFormMain.ButtonErrorRetryCancelClick(Sender: TObject);
begin
  ApplyDefaultTheme;

  TDialog4D.MessageDialogAsync(
    'The network request failed. Do you want to retry?',
    TMsgDlgType.mtError,
    [TMsgDlgBtn.mbRetry, TMsgDlgBtn.mbCancel],
    TMsgDlgBtn.mbRetry,
    procedure(const AResult: TModalResult)
    begin
      LogResult('1.4 Error(Retry/Cancel)', AResult);
    end,
    'Network Error', Self, True
  );
end;

procedure TFormMain.ButtonNoCancelTapOutsideClick(Sender: TObject);
var
  LTheme: TDialog4DTheme;
begin
  LTheme := TDialog4DTheme.Default;
  ApplyCompactSizing(LTheme);
  TDialog4D.ConfigureTheme(LTheme);

  TDialog4D.MessageDialogAsync(
    'ACancelable is True but there is no Cancel button.' + sLineBreak + sLineBreak +
    'Expected: tapping the backdrop does nothing.' + sLineBreak +
    'Only the OK button can close this dialog.',
    TMsgDlgType.mtInformation,
    [TMsgDlgBtn.mbOK],
    TMsgDlgBtn.mbOK,
    procedure(const AResult: TModalResult)
    begin
      LogResult('1.5 NoCancelButton+BackdropTap', AResult);
      ApplyDefaultTheme;
    end,
    'No-Cancel Guarantee', Self, True
  );
end;

{ ============================================== }
{ == Section 2 — Theme / provider / telemetry == }
{ ============================================== }

procedure TFormMain.ButtonCustomThemeClick(Sender: TObject);
begin
  ApplyCustomTheme;

  TDialog4D.MessageDialogAsync(
    'Custom theme: adjusted sizing, corner radius, accent palette, and overlay opacity.',
    TMsgDlgType.mtInformation,
    [TMsgDlgBtn.mbOK, TMsgDlgBtn.mbClose],
    TMsgDlgBtn.mbOK,
    procedure(const AResult: TModalResult)
    begin
      LogResult('2.1 CustomTheme', AResult);
      ApplyDefaultTheme;
    end,
    'Custom Theme Demo', Self, False
  );
end;

procedure TFormMain.ButtonDarkThemeClick(Sender: TObject);
begin
  ApplyDarkTheme;

  TDialog4D.MessageDialogAsync(
    'Dark theme: deep surface, muted message text, soft accent palette.' + sLineBreak + sLineBreak +
    'Input fields also respect the dark palette (InputFillColor, InputTextColor, InputBorderColor).',
    TMsgDlgType.mtInformation,
    [TMsgDlgBtn.mbOK, TMsgDlgBtn.mbClose],
    TMsgDlgBtn.mbOK,
    procedure(const AResult: TModalResult)
    begin
      LogResult('2.2 DarkTheme', AResult);
      ApplyDefaultTheme;
    end,
    'Dark Theme Demo', Self, False
  );
end;

procedure TFormMain.ButtonCyberpunkThemeClick(Sender: TObject);
begin
  ApplyDemoTheme_Cyberpunk;

  TDialog4D.MessageDialogAsync(
    'Cyberpunk theme: dark surface, neon accents, wide card, white neutral buttons.',
    TMsgDlgType.mtInformation,
    [TMsgDlgBtn.mbOK, TMsgDlgBtn.mbClose],
    TMsgDlgBtn.mbOK,
    procedure(const AResult: TModalResult)
    begin
      LogResult('2.3 CyberpunkTheme', AResult);
      ApplyDefaultTheme;
    end,
    'Cyberpunk Theme Demo', Self, False
  );
end;

procedure TFormMain.ButtonTreatCloseAsCancelClick(Sender: TObject);
var
  LTheme: TDialog4DTheme;
begin
  LTheme := TDialog4DTheme.Default;
  LTheme.TreatCloseAsCancel := True;
  TDialog4D.ConfigureTheme(LTheme);

  LogSeparator('2.4  TreatCloseAsCancel = True');
  LogLine(NowStr + '  Tap the backdrop — expected: closes with mrClose.');

  TDialog4D.MessageDialogAsync(
    'TreatCloseAsCancel is True and a Close button is present.' + sLineBreak + sLineBreak +
    'Expected: tapping the backdrop closes the dialog with mrClose.',
    TMsgDlgType.mtInformation,
    [TMsgDlgBtn.mbOK, TMsgDlgBtn.mbClose],
    TMsgDlgBtn.mbOK,
    procedure(const AResult: TModalResult)
    begin
      LogResult('2.4 TreatCloseAsCancel', AResult);
      if AResult = mrClose then
        LogLine('  Confirmed: backdrop triggered mrClose.')
      else
        LogLine('  User clicked a button directly.');
      ApplyDefaultTheme;
    end,
    'TreatCloseAsCancel Demo', Self, True
  );
end;

procedure TFormMain.ButtonJPProviderClick(Sender: TObject);
begin
  ApplyJPProvider;
  ApplyDefaultTheme;

  TDialog4D.MessageDialogAsync(
    'ボタンとタイトルは IDialog4DTextProvider で制御できます。',
    TMsgDlgType.mtConfirmation,
    [TMsgDlgBtn.mbYes, TMsgDlgBtn.mbNo, TMsgDlgBtn.mbCancel],
    TMsgDlgBtn.mbYes,
    procedure(const AResult: TModalResult)
    begin
      LogResult('2.5 JPProvider', AResult);
    end,
    '', Self, True
  );
end;

procedure TFormMain.ButtonRestoreDefaultProviderClick(Sender: TObject);
begin
  ApplyDefaultProvider;
end;

{ ======================================== }
{ == Section 3 — UX / behavioral checks == }
{ ======================================== }

procedure TFormMain.ButtonEnterDefaultDemoClick(Sender: TObject);
begin
  ApplyDefaultTheme;
  LogSeparator('3.1  Enter = default button');
  LogLine(NowStr + '  Press Enter. Expected: mrYes.');

  TDialog4D.MessageDialogAsync(
    'Press Enter on the keyboard.' + sLineBreak + sLineBreak +
    'Expected: dialog closes with Yes (the default button).',
    TMsgDlgType.mtConfirmation,
    [TMsgDlgBtn.mbYes, TMsgDlgBtn.mbNo, TMsgDlgBtn.mbCancel],
    TMsgDlgBtn.mbYes,
    procedure(const R: TModalResult)
    begin
      LogResult('3.1 Enter→Default', R);
      if R = mrYes then
        LogLine('  Confirmed: Enter triggered the default button.')
      else
        LogLine('  User chose a different button.');
    end,
    'Enter Key Demo', Self, True
  );
end;

procedure TFormMain.ButtonEscCancelDemoClick(Sender: TObject);
begin
  ApplyDefaultTheme;
  LogSeparator('3.2  Esc = cancel button');
  LogLine(NowStr + '  Press Esc. Expected: mrCancel.');

  TDialog4D.MessageDialogAsync(
    'Press Esc on the keyboard.' + sLineBreak + sLineBreak +
    'Expected: dialog closes with Cancel.',
    TMsgDlgType.mtConfirmation,
    [TMsgDlgBtn.mbYes, TMsgDlgBtn.mbNo, TMsgDlgBtn.mbCancel],
    TMsgDlgBtn.mbNo,
    procedure(const R: TModalResult)
    begin
      LogResult('3.2 Esc→Cancel', R);
      if R = mrCancel then
        LogLine('  Confirmed: Esc triggered the Cancel button.')
      else
        LogLine('  User chose a different button.');
    end,
    'Esc Key Demo', Self, True
  );
end;

procedure TFormMain.ButtonEscWithoutCancelDemoClick(Sender: TObject);
begin
  ApplyDefaultTheme;
  LogSeparator('3.3  Esc + Backdrop no-op (no cancel button)');
  LogLine(NowStr + '  No cancel button — Esc and backdrop must be no-ops.');

  TDialog4D.MessageDialogAsync(
    'This dialog has only an OK button. ACancelable = True.' + sLineBreak + sLineBreak +
    'Expected:' + sLineBreak +
    '  - Esc key     → nothing happens' + sLineBreak +
    '  - Backdrop tap → nothing happens' + sLineBreak +
    '  - Only OK can close this dialog.',
    TMsgDlgType.mtInformation,
    [TMsgDlgBtn.mbOK],
    TMsgDlgBtn.mbOK,
    procedure(const R: TModalResult)
    begin
      LogResult('3.3 Esc/BackdropNoOp', R);
    end,
    'No Cancel Demo', Self, True
  );
end;

procedure TFormMain.ButtonInvalidDefaultDemoClick(Sender: TObject);
begin
  ApplyDefaultTheme;
  LogSeparator('3.4  Invalid default button normalization');
  LogLine(NowStr + '  Buttons=[Yes,No,Cancel], Default=Help (not in set). Must normalize.');

  TDialog4D.MessageDialogAsync(
    'Buttons: Yes / No / Cancel. Requested default: Help (not in the set).' + sLineBreak + sLineBreak +
    'Expected:' + sLineBreak +
    '  - Dialog opens normally' + sLineBreak +
    '  - A valid button is promoted as default automatically' + sLineBreak +
    '  - Enter closes with that fallback default' + sLineBreak +
    '  - Esc still closes with Cancel',
    TMsgDlgType.mtConfirmation,
    [TMsgDlgBtn.mbYes, TMsgDlgBtn.mbNo, TMsgDlgBtn.mbCancel],
    TMsgDlgBtn.mbHelp, // Intentionally invalid.
    procedure(const R: TModalResult)
    begin
      LogResult('3.4 InvalidDefaultNormalization', R);
    end,
    'Invalid Default Demo', Self, True
  );
end;

{ =========================================== }
{ == Section 4 — Extra button combinations == }
{ =========================================== }

procedure TFormMain.ButtonAbortRetryIgnoreClick(Sender: TObject);
begin
  ApplyDefaultTheme;

  TDialog4D.MessageDialogAsync(
    'An unrecoverable operation may be in progress. Choose: Abort / Retry / Ignore.' + sLineBreak + sLineBreak +
    'Note: Abort is marked as destructive (red).',
    TMsgDlgType.mtError,
    [TMsgDlgBtn.mbAbort, TMsgDlgBtn.mbRetry, TMsgDlgBtn.mbIgnore],
    TMsgDlgBtn.mbRetry,
    procedure(const R: TModalResult)
    begin
      LogResult('4.1 Abort/Retry/Ignore', R);
    end,
    'Advanced Error', Self, True
  );
end;

procedure TFormMain.ButtonAllCancelClick(Sender: TObject);
begin
  ApplyDefaultTheme;

  TDialog4D.MessageDialogAsync(
    'Apply to all items or cancel?',
    TMsgDlgType.mtConfirmation,
    [TMsgDlgBtn.mbAll, TMsgDlgBtn.mbCancel],
    TMsgDlgBtn.mbAll,
    procedure(const R: TModalResult)
    begin
      LogResult('4.2 All/Cancel', R);
    end,
    'Batch Operation', Self, True
  );
end;

procedure TFormMain.ButtonAllNoToAllYesToAllClick(Sender: TObject);
begin
  ApplyDefaultTheme;

  TDialog4D.MessageDialogAsync(
    'Batch decision: choose how to apply the operation to all items.',
    TMsgDlgType.mtConfirmation,
    [TMsgDlgBtn.mbAll, TMsgDlgBtn.mbNoToAll, TMsgDlgBtn.mbYesToAll, TMsgDlgBtn.mbCancel],
    TMsgDlgBtn.mbYesToAll,
    procedure(const R: TModalResult)
    begin
      LogResult('4.3 All/NoToAll/YesToAll/Cancel', R);
    end,
    'Batch Decision', Self, True
  );
end;

procedure TFormMain.ButtonHelpCloseClick(Sender: TObject);
begin
  ApplyDefaultTheme;

  TDialog4D.MessageDialogAsync(
    'Need more information? Open the help screen or close this message.',
    TMsgDlgType.mtInformation,
    [TMsgDlgBtn.mbHelp, TMsgDlgBtn.mbClose],
    TMsgDlgBtn.mbClose,
    procedure(const R: TModalResult)
    begin
      LogResult('4.4 Help/Close', R);
      if R = mrHelp then
        LogLine('  Action: open docs / help screen.');
    end,
    'Help Example', Self, False
  );
end;

procedure TFormMain.ButtonIgnoreCloseClick(Sender: TObject);
begin
  ApplyDefaultTheme;

  TDialog4D.MessageDialogAsync(
    'Non-critical warning. Ignore it or close this message.',
    TMsgDlgType.mtWarning,
    [TMsgDlgBtn.mbIgnore, TMsgDlgBtn.mbClose],
    TMsgDlgBtn.mbClose,
    procedure(const R: TModalResult)
    begin
      LogResult('4.5 Ignore/Close', R);
      if R = mrIgnore then
        LogLine('  Action: suppress this warning in future sessions.');
    end,
    'Warning Choice', Self, True
  );
end;

{ =================================== }
{ == Section 5 — Queue and stress  == }
{ =================================== }

procedure TFormMain.QueueDemoDialogFromTask(const AIndex, ATotal: Integer);
begin
  TDialog4D.MessageDialogAsync(
    Format('Dialog %d / %d — queued from TTask.Run.', [AIndex, ATotal]),
    TMsgDlgType.mtInformation,
    [TMsgDlgBtn.mbOK],
    TMsgDlgBtn.mbOK,
    procedure(const R: TModalResult)
    begin
      LogLine(NowStr + Format('  Queue callback %d/%d → %s',
        [AIndex, ATotal, TDialog4DTelemetryFormat.ModalResultToText(R)]));
    end,
    'Queue Demo',
    Self,
    False
  );
end;

procedure TFormMain.ButtonQueueDemoClick(Sender: TObject);
const
  N = 6;
begin
  ApplyDefaultTheme;

  LogSeparator('5.1  Queue burst — ' + N.ToString + ' dialogs from TTask');
  LogLine(NowStr + '  Scheduling ' + N.ToString + ' dialogs from a background task...');

  TTask.Run(
    procedure
    var
      I: Integer;
    begin
      for I := 1 to N do
        QueueDemoDialogFromTask(I, N);
    end
  );
end;

procedure TFormMain.ButtonTestLongCancelClick(Sender: TObject);
var
  LTheme: TDialog4DTheme;
begin
  LTheme := TDialog4DTheme.Default;
  LTheme.DialogWidth          := 340;
  LTheme.DialogMinHeight      := 170;
  LTheme.ContentMinHeight     := 50;
  LTheme.DialogMaxHeightRatio := 0.65; // Constrained height forces scroll.
  TDialog4D.ConfigureTheme(LTheme);

  LogSeparator('5.2  Long message — scroll + Cancel stability');

  TDialog4D.MessageDialogAsync(
    BuildLongMessage,
    TMsgDlgType.mtWarning,
    [TMsgDlgBtn.mbCancel],
    TMsgDlgBtn.mbCancel,
    procedure(const AResult: TModalResult)
    begin
      LogResult('5.2 LongMessage(CancelOnly)', AResult);
      ApplyDefaultTheme;
    end,
    'Long Message Test', Self, True
  );
end;

procedure TFormMain.ButtonThemeSwapDemoClick(Sender: TObject);
begin
  ApplyDefaultTheme;
  LogSeparator('5.3  Theme snapshot during queue');

  TDialog4D.MessageDialogAsync(
    'Step 1 — Default theme.' + sLineBreak + sLineBreak +
    'Click OK. The global theme will be switched before the second dialog is queued.' + sLineBreak +
    'The second dialog will reflect the new theme.',
    TMsgDlgType.mtInformation,
    [TMsgDlgBtn.mbOK],
    TMsgDlgBtn.mbOK,
    procedure(const AResult: TModalResult)
    begin
      LogResult('5.3 ThemeSwap-Step1(Default)', AResult);
      ApplyDemoTheme_Cyberpunk;
      LogLine(NowStr + '  Global theme switched to Cyberpunk.');

      TDialog4D.MessageDialogAsync(
        'Step 2 — Cyberpunk theme.' + sLineBreak + sLineBreak +
        'The theme was swapped after Step 1 closed.' + sLineBreak +
        'This dialog was queued after the swap, so it uses the new theme.',
        TMsgDlgType.mtInformation,
        [TMsgDlgBtn.mbOK, TMsgDlgBtn.mbClose],
        TMsgDlgBtn.mbOK,
        procedure(const AResult2: TModalResult)
        begin
          LogResult('5.3 ThemeSwap-Step2(Cyberpunk)', AResult2);
          ApplyDefaultTheme;
          LogLine(NowStr + '  Default theme restored.');
        end,
        'Theme Swap — Step 2', Self, False
      );
    end,
    'Theme Swap — Step 1', Self, False
  );
end;

procedure TFormMain.ButtonDecisionFlowDemoClick(Sender: TObject);
begin
  ApplyDefaultTheme;
  LogSeparator('5.4  Sequential decision flow');
  LogLine(NowStr + '  Step 1 decides what Step 2 will be.');

  TDialog4D.MessageDialogAsync(
    'You are about to close the document.' + sLineBreak + sLineBreak +
    'Do you want to save changes first?',
    TMsgDlgType.mtConfirmation,
    [TMsgDlgBtn.mbYes, TMsgDlgBtn.mbNo, TMsgDlgBtn.mbCancel],
    TMsgDlgBtn.mbYes,
    procedure(const R1: TModalResult)
    begin
      LogResult('5.4 Step1 SaveChanges?', R1);

      case R1 of
        mrYes:
          begin
            LogLine('  Branch selected: YES -> open save confirmation.');

            TDialog4D.MessageDialogAsync(
              'Changes were saved successfully.' + sLineBreak + sLineBreak +
              'Do you want to close the document now?',
              TMsgDlgType.mtInformation,
              [TMsgDlgBtn.mbOK, TMsgDlgBtn.mbCancel],
              TMsgDlgBtn.mbOK,
              procedure(const R2: TModalResult)
              begin
                LogResult('5.4 Step2 AfterSave', R2);

                if R2 = mrOk then
                  LogLine('  Final action: close document after save.')
                else
                  LogLine('  Final action: keep document open after save.');
              end,
              'Step 2 — Save completed', Self, True
            );
          end;

        mrNo:
          begin
            LogLine('  Branch selected: NO -> open discard confirmation.');

            TDialog4D.MessageDialogAsync(
              'The changes will be discarded.' + sLineBreak + sLineBreak +
              'Do you want to close the document without saving?',
              TMsgDlgType.mtWarning,
              [TMsgDlgBtn.mbYes, TMsgDlgBtn.mbCancel],
              TMsgDlgBtn.mbCancel,
              procedure(const R2: TModalResult)
              begin
                LogResult('5.4 Step2 DiscardChanges', R2);

                if R2 = mrYes then
                  LogLine('  Final action: discard changes and close document.')
                else
                  LogLine('  Final action: cancel close, keep document open.');
              end,
              'Step 2 — Discard confirmation', Self, True
            );
          end;

        mrCancel:
          begin
            LogLine('  Branch selected: CANCEL -> no second dialog.');
            LogLine('  Final action: flow aborted by user at Step 1.');
          end;
      end;
    end,
    'Step 1 — Save before closing?', Self, True
  );
end;

procedure TFormMain.ButtonDecisionFlowCustomClick(Sender: TObject);
begin
  ApplyDefaultTheme;
  LogSeparator('5.5  Sequential decision flow — custom buttons');
  LogLine(NowStr + '  Step 1 decides the entire next path.');

  TDialog4D.MessageDialogAsync(
    'This document has unsaved changes.' + sLineBreak + sLineBreak +
    'Choose how you want to proceed:',
    TMsgDlgType.mtWarning,
    [
      TDialog4DCustomButton.Default('Save and Close', mrYes),
      TDialog4DCustomButton.Destructive('Close Without Saving', mrNo),
      TDialog4DCustomButton.Cancel('Review Changes')
    ],
    procedure(const R1: TModalResult)
    begin
      LogResult('5.5 Step1 UnsavedChanges', R1);

      case R1 of
        mrYes:
          begin
            LogLine('  Branch selected: Save and Close.');

            TDialog4D.MessageDialogAsync(
              'The document was saved successfully.' + sLineBreak + sLineBreak +
              'Do you want to close it now?',
              TMsgDlgType.mtInformation,
              [
                TDialog4DCustomButton.Default('Close Document', mrOk),
                TDialog4DCustomButton.Cancel('Keep Open')
              ],
              procedure(const R2: TModalResult)
              begin
                LogResult('5.5 Step2 AfterSave', R2);

                if R2 = mrOk then
                  LogLine('  Final action: document closed after save.')
                else
                  LogLine('  Final action: document remains open after save.');
              end,
              'Save Completed', Self, True
            );
          end;

        mrNo:
          begin
            LogLine('  Branch selected: Close Without Saving.');

            TDialog4D.MessageDialogAsync(
              'All unsaved changes will be lost.' + sLineBreak + sLineBreak +
              'Are you sure you want to close without saving?',
              TMsgDlgType.mtError,
              [
                TDialog4DCustomButton.Destructive('Discard and Close', mrAbort),
                TDialog4DCustomButton.Cancel('Go Back')
              ],
              procedure(const R2: TModalResult)
              begin
                LogResult('5.5 Step2 DiscardConfirm', R2);

                if R2 = mrAbort then
                  LogLine('  Final action: changes discarded, document closed.')
                else
                  LogLine('  Final action: discard canceled, document remains open.');
              end,
              'Discard Confirmation', Self, True
            );
          end;

        mrCancel:
          begin
            LogLine('  Branch selected: Review Changes.');
            LogLine('  Final action: user returns to the document editor.');
          end;
      end;
    end,
    'Unsaved Changes', Self, True
  );
end;

procedure TFormMain.ButtonInjectedWorkflowDemoClick(Sender: TObject);
const
  // Change this single line to switch the demo scenario:
  CurrentScenario = iwsSuccess; // iwsSuccess, iwsFailOnSave, iwsFailOnClose.
var
  LWorkflow: IDocumentWorkflow;
  LScenarioText: string;
begin
  case CurrentScenario of
    iwsSuccess:
      begin
        LWorkflow := TDemoDocumentWorkflow.Create(False, False, False, False);
        LScenarioText := 'Success';
      end;

    iwsFailOnSave:
      begin
        LWorkflow := TDemoDocumentWorkflow.Create(True, False, False, False);
        LScenarioText := 'FailOnSave';
      end;

    iwsFailOnClose:
      begin
        LWorkflow := TDemoDocumentWorkflow.Create(False, True, False, False);
        LScenarioText := 'FailOnClose';
      end;
  else
    LWorkflow := TDemoDocumentWorkflow.Create(False, False, False, False);
    LScenarioText := 'Success';
  end;

  ApplyDefaultTheme;
  LogSeparator('5.6  Dialog-driven business action');
  LogLine(NowStr + '  Scenario: ' + LScenarioText);
  LogLine(NowStr + '  Dialog decides which injected service method will run.');
  LogLine('  Important: the service does NOT touch the UI.');

  TDialog4D.MessageDialogAsync(
    'This document has unsaved changes.' + sLineBreak + sLineBreak +
    'Choose how you want to proceed:',
    TMsgDlgType.mtWarning,
    [
      TDialog4DCustomButton.Default('Save and Close', mrYes),
      TDialog4DCustomButton.Destructive('Close Without Saving', mrNo),
      TDialog4DCustomButton.Cancel('Review Changes')
    ],
    procedure(const R1: TModalResult)
    var
      LResult: TDocumentWorkflowResult;
    begin
      LogResult('5.6 Step1 UnsavedChanges', R1);

      case R1 of
        mrYes:
          begin
            LResult := LWorkflow.SaveDocument;
            LogWorkflowResult('5.6 Service.SaveDocument', LResult);

            if not LResult.Success then
            begin
              LogLine('  Save failed. Flow stopped.');
              Exit;
            end;

            TDialog4D.MessageDialogAsync(
              'The document was saved successfully.' + sLineBreak + sLineBreak +
              'Do you want to close it now?',
              TMsgDlgType.mtInformation,
              [
                TDialog4DCustomButton.Default('Close Document', mrOk),
                TDialog4DCustomButton.Cancel('Keep Open')
              ],
              procedure(const R2: TModalResult)
              begin
                LogResult('5.6 Step2 AfterSave', R2);

                if R2 = mrOk then
                begin
                  LResult := LWorkflow.CloseDocument;
                  LogWorkflowResult('5.6 Service.CloseDocument', LResult);

                  if LResult.Success then
                    LogLine('  Final action: document closed after save.')
                  else
                    LogLine('  Final action: close failed.');
                end
                else
                  LogLine('  Final action: document remains open after save.');
              end,
              'Save Completed',
              Self,
              True
            );
          end;

        mrNo:
          begin
            TDialog4D.MessageDialogAsync(
              'All unsaved changes will be lost.' + sLineBreak + sLineBreak +
              'Are you sure you want to close without saving?',
              TMsgDlgType.mtError,
              [
                TDialog4DCustomButton.Destructive('Discard and Close', mrAbort),
                TDialog4DCustomButton.Cancel('Go Back')
              ],
              procedure(const R2: TModalResult)
              begin
                LogResult('5.6 Step2 DiscardConfirm', R2);

                if R2 = mrAbort then
                begin
                  LResult := LWorkflow.DiscardChanges;
                  LogWorkflowResult('5.6 Service.DiscardChanges', LResult);

                  if not LResult.Success then
                  begin
                    LogLine('  Final action: discard failed.');
                    Exit;
                  end;

                  LResult := LWorkflow.CloseDocument;
                  LogWorkflowResult('5.6 Service.CloseDocument', LResult);

                  if LResult.Success then
                    LogLine('  Final action: changes discarded, document closed.')
                  else
                    LogLine('  Final action: close failed after discard.');
                end
                else
                  LogLine('  Final action: discard canceled, document remains open.');
              end,
              'Discard Confirmation',
              Self,
              True
            );
          end;

        mrCancel:
          begin
            LResult := LWorkflow.ReturnToEditor;
            LogWorkflowResult('5.6 Service.ReturnToEditor', LResult);

            if LResult.Success then
              LogLine('  Final action: user returns to the editor.')
            else
              LogLine('  Final action: return-to-editor flow failed.');
          end;
      end;
    end,
    'Unsaved Changes',
    Self,
    True
  );
end;


{ ==================================== }
{ == Section 6 — Programmatic close == }
{ ==================================== }

procedure TFormMain.ButtonCloseProgrammaticClick(Sender: TObject);
begin
  ApplyDefaultTheme;
  LogSeparator('6.1  Programmatic close — TDialog4D.CloseDialog');
  LogLine(NowStr + '  Dialog will auto-close with mrCancel in ~3 s.');
  LogLine(NowStr + '  A form-owned TTimer is used so the demo stays safe if the form closes.');

  TDialog4D.MessageDialogAsync(
    'This dialog has no cancel button and will be closed programmatically' + sLineBreak +
    'in approximately 3 seconds via a form-owned TTimer and TDialog4D.CloseDialog(Self, mrCancel).' + sLineBreak + sLineBreak +
    'Check the telemetry log for CloseReason = Programmatic.',
    TMsgDlgType.mtInformation,
    [TMsgDlgBtn.mbOK],
    TMsgDlgBtn.mbOK,
    procedure(const AResult: TModalResult)
    begin
      LogResult('6.1 CloseDialog(Programmatic)', AResult);
      if AResult = mrCancel then
        LogLine('  Confirmed: closed programmatically with mrCancel.')
      else
        LogLine('  User clicked OK before the programmatic close fired.');
    end,
    'Programmatic Close Demo', Self, False
  );

  FreeAndNil(FProgrammaticCloseTimer);
  FProgrammaticCloseTimer := TTimer.Create(Self);
  FProgrammaticCloseTimer.Interval := 3000;
  FProgrammaticCloseTimer.OnTimer := ProgrammaticCloseTimer;
  FProgrammaticCloseTimer.Enabled := True;
end;

{ ======================================== }
{ == Section 7 — DialogService4D facade == }
{ ======================================== }

procedure TFormMain.ButtonDialogService4DClick(Sender: TObject);
begin
  ApplyDefaultTheme;
  LogSeparator('7.1  DialogService4D — migration-friendly facade');

  TDialogService4D.MessageDialogAsync(
    'This dialog was opened via TDialogService4D — a migration-friendly facade' + sLineBreak +
    'for common FMX.DialogService-style asynchronous calls.' + sLineBreak + sLineBreak +
    'Migration steps for common cases:' + sLineBreak +
    '  uses FMX.DialogService  →  uses DialogService4D' + sLineBreak +
    '  TDialogService          →  TDialogService4D' + sLineBreak +
    '  Remove the HelpCtx (0) argument' + sLineBreak + sLineBreak +
    'Note: DialogService4D is not intended to be a full behavioral clone of' + sLineBreak +
    'every FMX.DialogService overload or platform-specific behavior.',
    TMsgDlgType.mtInformation,
    [TMsgDlgBtn.mbOK],
    TMsgDlgBtn.mbOK,
    procedure(const R: TModalResult)
    begin
      LogResult('7.1 DialogService4D migration facade', R);
    end,
    'DialogService4D Demo', Self, False
  );
end;

{ ============================== }
{ == Section 8 — Await family == }
{ ============================== }

procedure TFormMain.ButtonAwaitOnWorkerClick(Sender: TObject);
begin
  LogSeparator('8.1  MessageDialogOnWorker — blocking');
  LogLine(NowStr + '  Starting worker thread. It will BLOCK on the dialog.');

  TTask.Run(procedure
  var
    LStatus: TDialog4DAwaitStatus;
    LResult: TModalResult;
  begin
    TThread.Queue(nil, procedure begin
      LogLine(NowStr + '  Worker: calling MessageDialogOnWorker...');
    end);

    LResult := TDialog4DAwait.MessageDialogOnWorker(
      'The worker thread is blocked waiting for your answer.' + sLineBreak + sLineBreak +
      'The main thread (UI) remains fully responsive while you decide.',
      TMsgDlgType.mtConfirmation,
      [TMsgDlgBtn.mbYes, TMsgDlgBtn.mbNo, TMsgDlgBtn.mbCancel],
      TMsgDlgBtn.mbYes,
      LStatus,
      'Worker Await', Self
    );

    TThread.Queue(nil, procedure
    begin
      case LStatus of
        dasCompleted:
          LogLine(NowStr + Format('  8.1 Worker unblocked. Status=Completed, Result=%s',
            [TDialog4DTelemetryFormat.ModalResultToText(LResult)]));
        dasTimedOut:
          LogLine(NowStr + '  8.1 Worker unblocked. Status=TimedOut.');
      end;
    end);
  end);
end;

procedure TFormMain.ButtonAwaitSmartClick(Sender: TObject);
begin
  LogSeparator('8.2  MessageDialog — smart (main thread path)');
  LogLine(NowStr + '  Calling from main thread — behaves like MessageDialogAsync (non-blocking).');

  TDialog4DAwait.MessageDialog(
    'This dialog was opened via TDialog4DAwait.MessageDialog from the main thread.' + sLineBreak + sLineBreak +
    'Behavior: same as MessageDialogAsync — the UI is not blocked.',
    TMsgDlgType.mtInformation,
    [TMsgDlgBtn.mbYes, TMsgDlgBtn.mbNo],
    TMsgDlgBtn.mbYes,
    procedure(const AResult: TModalResult)
    begin
      LogResult('8.2 SmartMethod(MainThread)', AResult);
    end,
    'Smart — Main Thread', Self
  );
end;

procedure TFormMain.ButtonAwaitSmartCallbackOnMainClick(Sender: TObject);
begin
  LogSeparator('8.3  MessageDialog — ACallbackOnMain=True');
  LogLine(NowStr + '  Worker will block. Callback will arrive on the main thread.');

  TTask.Run(procedure
  begin
    TThread.Queue(nil, procedure begin
      LogLine(NowStr + '  Worker: blocking (ACallbackOnMain=True)...');
    end);

    TDialog4DAwait.MessageDialog(
      'The worker thread is blocked.' + sLineBreak + sLineBreak +
      'ACallbackOnMain = True.' + sLineBreak + sLineBreak +
      'After you answer, the callback will be re-dispatched to the main thread.' + sLineBreak +
      'No TThread.Queue is needed inside the callback.',
      TMsgDlgType.mtConfirmation,
      [TMsgDlgBtn.mbYes, TMsgDlgBtn.mbNo],
      TMsgDlgBtn.mbYes,
      procedure(const AResult: TModalResult)
      begin
        // Main thread — direct UI access is safe.
        LogResult('8.3 SmartMethod(ACallbackOnMain=True)', AResult);
        LogLine('  Confirmed: callback is on the main thread.');
      end,
      'Smart — ACallbackOnMain', Self,
      True, // ACancelable.
      True  // ACallbackOnMain.
    );

    TThread.Queue(nil, procedure begin
      LogLine(NowStr + '  Worker thread resumed after dialog closed.');
    end);
  end);
end;

procedure TFormMain.ButtonAwaitTimeoutClick(Sender: TObject);
begin
  LogSeparator('8.4  MessageDialogOnWorker — timeout (4 s)');
  LogLine(NowStr + '  Worker will time out in 4 s if you do not click any button.');

  TTask.Run(procedure
  var
    LStatus: TDialog4DAwaitStatus;
    LResult: TModalResult;
  begin
    LResult := TDialog4DAwait.MessageDialogOnWorker(
      'The worker thread will time out in 4 seconds.' + sLineBreak + sLineBreak +
      'To see the timeout: do NOT click any button and wait.' + sLineBreak + sLineBreak +
      'Note: the timeout ends the worker wait only.' + sLineBreak +
      'This demo then closes the still-visible dialog programmatically.',
      TMsgDlgType.mtWarning,
      [TMsgDlgBtn.mbOK, TMsgDlgBtn.mbCancel],
      TMsgDlgBtn.mbOK,
      LStatus,
      'Await Timeout Demo', Self,
      True,
      4000 // 4-second timeout for easy observation.
    );

    TThread.Queue(nil, procedure
    begin
      case LStatus of
        dasCompleted:
          LogLine(NowStr + Format('  8.4 Status=Completed. Result=%s',
            [TDialog4DTelemetryFormat.ModalResultToText(LResult)]));
        dasTimedOut:
          begin
            LogLine(NowStr + '  8.4 Status=TimedOut. Result=None.');
            LogLine('  Timeout reached. Closing the still-visible dialog programmatically.');
            TDialog4D.CloseDialog(Self, mrCancel);
          end;
      end;
    end);
  end);
end;

procedure TFormMain.ButtonAwaitErrorOnMainThreadClick(Sender: TObject);
begin
  LogSeparator('8.5  EDialog4DAwait — intentional error');
  LogLine(NowStr + '  Calling MessageDialogOnWorker from the main thread (wrong). Must raise EDialog4DAwait.');

  try
    var LStatus: TDialog4DAwaitStatus;
    TDialog4DAwait.MessageDialogOnWorker(
      'This will never be shown.',
      TMsgDlgType.mtError,
      [TMsgDlgBtn.mbOK],
      TMsgDlgBtn.mbOK,
      LStatus,
      'Error', Self
    );
  except
    on E: EDialog4DAwait do
    begin
      LogLine(NowStr + '  EDialog4DAwait caught (expected): ' + E.Message);
      ShowMessage('EDialog4DAwait raised and caught successfully.' + sLineBreak + sLineBreak + E.Message);
    end;
    on E: Exception do
      LogLine(NowStr + '  Unexpected exception: ' + E.ClassName + ': ' + E.Message);
  end;
end;

{ ============================================== }
{ == Section 9 — FMX.DialogService comparison == }
{ ============================================== }

procedure TFormMain.ButtonDialogServiceSyncRealityCheckClick(Sender: TObject);
var
  LOldPreferredMode: TDialogService.TPreferredMode;
begin
  LogSeparator('9.1  FMX.DialogService callback ordering comparison');

{$IFDEF ANDROID}
  LogLine(NowStr + '  Sync PreferredMode is not supported on Android. Run this comparison on desktop.');
  Exit;
{$ENDIF}

  LOldPreferredMode := TDialogService.PreferredMode;
  TDialogService.PreferredMode := TDialogService.TPreferredMode.Sync;
  try
    TDialogService.MessageDialog(
      'FMX.DialogService callback ordering comparison.' + sLineBreak + sLineBreak +
      'Click OK and observe the log:' + sLineBreak +
      '"OUTSIDE" appears BEFORE "INSIDE" because the line after this call' + sLineBreak +
      'runs synchronously, before the callback fires.',
      TMsgDlgType.mtInformation,
      [TMsgDlgBtn.mbOK],
      TMsgDlgBtn.mbOK,
      0,
      procedure(const AResult: TModalResult)
      begin
        if AResult = mrOk then
          TThread.Queue(nil,
            procedure
            begin
              LogLine(NowStr + '  <- INSIDE  callback: user clicked OK.');
            end);
      end
    );

    // This line runs before the callback — intentional demonstration.
    LogLine(NowStr + '  <- OUTSIDE callback: logged synchronously BEFORE user decision.');
  finally
    TDialogService.PreferredMode := LOldPreferredMode;
  end;
end;

{ ========================================================= }
{ == Section 10 — Custom buttons (TDialog4DCustomButton) == }
{ ========================================================= }

procedure TFormMain.ButtonCustomSimpleClick(Sender: TObject);
begin
  ApplyDefaultTheme;
  LogSeparator('10.1  Custom buttons — minimal (2 buttons)');

  TDialog4D.MessageDialogAsync(
    'Would you like to check for updates now?',
    TMsgDlgType.mtInformation,
    [
      TDialog4DCustomButton.Default('Check for Updates', mrOk),
      TDialog4DCustomButton.Cancel ('Not Now')
    ],
    procedure(const R: TModalResult)
    begin
      case R of
        mrOk:     LogLine(NowStr + '  10.1 → "Check for Updates" (mrOk).');
        mrCancel: LogLine(NowStr + '  10.1 → "Not Now" (mrCancel).');
      end;
    end,
    'Software Update', Self, True
  );
end;

procedure TFormMain.ButtonCustomDestructiveClick(Sender: TObject);
begin
  ApplyDefaultTheme;
  LogSeparator('10.2  Custom buttons — destructive action');

  TDialog4D.MessageDialogAsync(
    'Delete "Q4 2025 Report.xlsx"?' + sLineBreak + sLineBreak +
    'This file will be permanently removed and cannot be recovered.',
    TMsgDlgType.mtConfirmation,
    [
      TDialog4DCustomButton.Destructive('Delete Permanently', mrYes),
      TDialog4DCustomButton.Cancel     ('Keep File')
    ],
    procedure(const R: TModalResult)
    begin
      case R of
        mrYes:    LogLine(NowStr + '  10.2 → "Delete Permanently" — file would be deleted.');
        mrCancel: LogLine(NowStr + '  10.2 → "Keep File" — operation cancelled.');
      end;
    end,
    'Confirm Deletion', Self, True
  );
end;

procedure TFormMain.ButtonCustomAllRolesClick(Sender: TObject);
const
  mrSaveAndClose = TModalResult(100);
  mrCloseNoSave  = TModalResult(101);
begin
  ApplyDefaultTheme;
  LogSeparator('10.3  Custom buttons — all four visual roles');

  TDialog4D.MessageDialogAsync(
    'You have unsaved changes.' + sLineBreak + sLineBreak +
    'What would you like to do before closing?',
    TMsgDlgType.mtConfirmation,
    [
      TDialog4DCustomButton.Default    ('Save and Close',       mrSaveAndClose),
      TDialog4DCustomButton.Make       ('Close Without Saving', mrCloseNoSave),
      TDialog4DCustomButton.Destructive('Discard All Changes',  mrAbort),
      TDialog4DCustomButton.Cancel     ('Stay Here')
    ],
    procedure(const R: TModalResult)
    begin
      case R of
        mrSaveAndClose: LogLine(NowStr + '  10.3 → "Save and Close" (custom=100).');
        mrCloseNoSave:  LogLine(NowStr + '  10.3 → "Close Without Saving" (custom=101).');
        mrAbort:        LogLine(NowStr + '  10.3 → "Discard All Changes" (mrAbort, destructive).');
        mrCancel:       LogLine(NowStr + '  10.3 → "Stay Here" (mrCancel).');
      end;
    end,
    'Unsaved Changes', Self, True
  );
end;

procedure TFormMain.ButtonCustomSessionExpiryClick(Sender: TObject);
begin
  ApplyDemoTheme_Cyberpunk;
  LogSeparator('10.4  Custom buttons — real-world (session expiry)');

  TDialog4D.MessageDialogAsync(
    'Your session will expire in 2 minutes due to inactivity.' + sLineBreak + sLineBreak +
    'Do you want to continue working or sign out now?',
    TMsgDlgType.mtWarning,
    [
      TDialog4DCustomButton.Default('Keep Me Signed In', mrOk),
      TDialog4DCustomButton.Make   ('Sign Out Now',      mrClose),
      TDialog4DCustomButton.Cancel ('Remind Me Later')
    ],
    procedure(const R: TModalResult)
    begin
      case R of
        mrOk:     LogLine(NowStr + '  10.4 → Session renewed. Timer reset.');
        mrClose:  LogLine(NowStr + '  10.4 → Signing out immediately.');
        mrCancel: LogLine(NowStr + '  10.4 → Reminder scheduled in 60 s.');
      end;
      ApplyDefaultTheme;
    end,
    'Session Expiring Soon', Self, True
  );
end;

procedure TFormMain.ButtonCustomAwaitWorkerClick(Sender: TObject);
begin
  ApplyDefaultTheme;
  LogSeparator('10.5  Custom buttons — worker-thread await');
  LogLine(NowStr + '  Starting worker. It will BLOCK on a custom-button dialog.');

  TTask.Run(procedure
  var
    LStatus: TDialog4DAwaitStatus;
    LResult: TModalResult;
  begin
    TThread.Queue(nil, procedure begin
      LogLine(NowStr + '  Worker: calling MessageDialogOnWorker with custom buttons...');
    end);

    LResult := TDialog4DAwait.MessageDialogOnWorker(
      'A large file transfer is in progress.' + sLineBreak + sLineBreak +
      'The worker thread is blocked waiting for your choice.',
      TMsgDlgType.mtWarning,
      [
        TDialog4DCustomButton.Default    ('Continue Transfer', mrOk),
        TDialog4DCustomButton.Make       ('Pause Transfer',    mrRetry),
        TDialog4DCustomButton.Destructive('Cancel Transfer',   mrAbort)
      ],
      LStatus,
      'File Transfer', Self
    );

    TThread.Queue(nil, procedure
    begin
      case LStatus of
        dasCompleted:
          begin
            LogLine(NowStr + '  10.5 Worker unblocked. Status=Completed.');
            case LResult of
              mrOk:    LogLine('  → "Continue Transfer" — resuming upload.');
              mrRetry: LogLine('  → "Pause Transfer" — transfer paused.');
              mrAbort: LogLine('  → "Cancel Transfer" — transfer aborted.');
            end;
          end;
        dasTimedOut:
          LogLine(NowStr + '  10.5 Worker unblocked. Status=TimedOut.');
      end;
    end);
  end);
end;

end.

