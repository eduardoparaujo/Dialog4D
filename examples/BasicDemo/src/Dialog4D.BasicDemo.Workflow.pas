// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Eduardo P. Araujo

{*
  Unit   : UnitDialog4D_Demo.Workflow
  Purpose: UI-agnostic support types and demo service used by UnitDialog4D_Demo
           to illustrate dialog-driven business actions with dependency
           injection.

           This unit exists to keep the demonstration of business flow
           separate from the FMX form. It defines:
             - a small action enum describing the logical operation performed
             - a structured result record returned by the workflow service
             - a demo service contract (IDocumentWorkflow)
             - a configurable fake implementation (TDemoDocumentWorkflow)

           Important design rule:
             - this unit must remain UI-free
             - no form access
             - no dialogs
             - no logs
             - no FMX dependencies

           The form is responsible for presenting results. This unit is
           responsible only for representing and executing demo workflow
           actions.

  Notes:
    - Demo/support unit only. Not part of the Dialog4D runtime library.
    - Used by example 5.6 to demonstrate that Dialog4D can drive business
      decisions without coupling the decision handler to UI code.
    - The demo workflow can simulate success or failure for selected actions.

  Author        : Eduardo P. Araujo
  Created       : 2026-04-26
  Last modified : 2026-04-26
  Version       : 1.0.0
*}

unit Dialog4D.BasicDemo.Workflow;

interface

type
  /// <summary>
  /// Logical action performed by the injected workflow service.
  /// </summary>
  TDocumentWorkflowAction = (
    dwaNone,
    dwaSaveDocument,
    dwaCloseDocument,
    dwaDiscardChanges,
    dwaReturnToEditor
  );

  /// <summary>
  /// Structured result returned by the workflow service.
  /// </summary>
  /// <remarks>
  /// <para>
  /// This record is intentionally UI-agnostic. It carries only outcome data
  /// that the caller may later present in the UI.
  /// </para>
  /// </remarks>
  TDocumentWorkflowResult = record
    Success: Boolean;
    Action: TDocumentWorkflowAction;
    MessageText: string;

    /// <summary>
    /// Builds a successful workflow result.
    /// </summary>
    class function Ok(
      const AAction: TDocumentWorkflowAction;
      const AMessageText: string): TDocumentWorkflowResult; static;

    /// <summary>
    /// Builds a failed workflow result.
    /// </summary>
    class function Fail(
      const AAction: TDocumentWorkflowAction;
      const AMessageText: string): TDocumentWorkflowResult; static;
  end;

  /// <summary>
  /// Example service contract used by the <c>Dialog4D</c> demo.
  /// </summary>
  /// <remarks>
  /// <para>
  /// Implementations must not touch the UI. They should only execute or
  /// simulate business actions and return structured results.
  /// </para>
  /// </remarks>
  IDocumentWorkflow = interface
    ['{A7E6AC9C-7A8C-4EC7-9D2F-8C0FA7F2D511}']
    function SaveDocument: TDocumentWorkflowResult;
    function CloseDocument: TDocumentWorkflowResult;
    function DiscardChanges: TDocumentWorkflowResult;
    function ReturnToEditor: TDocumentWorkflowResult;
  end;

  /// <summary>
  /// Demo implementation used to illustrate dependency injection.
  /// </summary>
  /// <remarks>
  /// <para>
  /// This implementation is deliberately simple and deterministic. It does
  /// not access files, databases, services, or UI elements. Its purpose is
  /// only to support the <c>Dialog4D</c> demo scenarios.
  /// </para>
  /// <para>
  /// It can be configured to simulate failures in specific actions so the
  /// demo can show both success and failure branches without changing UI code.
  /// </para>
  /// </remarks>
  TDemoDocumentWorkflow = class(TInterfacedObject, IDocumentWorkflow)
  private
    FFailOnSave: Boolean;
    FFailOnClose: Boolean;
    FFailOnDiscard: Boolean;
    FFailOnReturnToEditor: Boolean;
  public
    constructor Create(
      const AFailOnSave: Boolean = False;
      const AFailOnClose: Boolean = False;
      const AFailOnDiscard: Boolean = False;
      const AFailOnReturnToEditor: Boolean = False
    );

    function SaveDocument: TDocumentWorkflowResult;
    function CloseDocument: TDocumentWorkflowResult;
    function DiscardChanges: TDocumentWorkflowResult;
    function ReturnToEditor: TDocumentWorkflowResult;
  end;

implementation

{ == TDocumentWorkflowResult == }

class function TDocumentWorkflowResult.Ok(
  const AAction: TDocumentWorkflowAction;
  const AMessageText: string): TDocumentWorkflowResult;
begin
  Result.Success := True;
  Result.Action := AAction;
  Result.MessageText := AMessageText;
end;

class function TDocumentWorkflowResult.Fail(
  const AAction: TDocumentWorkflowAction;
  const AMessageText: string): TDocumentWorkflowResult;
begin
  Result.Success := False;
  Result.Action := AAction;
  Result.MessageText := AMessageText;
end;

{ == TDemoDocumentWorkflow == }

constructor TDemoDocumentWorkflow.Create(
  const AFailOnSave: Boolean;
  const AFailOnClose: Boolean;
  const AFailOnDiscard: Boolean;
  const AFailOnReturnToEditor: Boolean);
begin
  inherited Create;
  FFailOnSave := AFailOnSave;
  FFailOnClose := AFailOnClose;
  FFailOnDiscard := AFailOnDiscard;
  FFailOnReturnToEditor := AFailOnReturnToEditor;
end;

function TDemoDocumentWorkflow.SaveDocument: TDocumentWorkflowResult;
begin
  if FFailOnSave then
    Exit(TDocumentWorkflowResult.Fail(
      dwaSaveDocument,
      'DocumentWorkflow.SaveDocument failed.'
    ));

  Result := TDocumentWorkflowResult.Ok(
    dwaSaveDocument,
    'DocumentWorkflow.SaveDocument executed successfully.'
  );
end;

function TDemoDocumentWorkflow.CloseDocument: TDocumentWorkflowResult;
begin
  if FFailOnClose then
    Exit(TDocumentWorkflowResult.Fail(
      dwaCloseDocument,
      'DocumentWorkflow.CloseDocument failed.'
    ));

  Result := TDocumentWorkflowResult.Ok(
    dwaCloseDocument,
    'DocumentWorkflow.CloseDocument executed successfully.'
  );
end;

function TDemoDocumentWorkflow.DiscardChanges: TDocumentWorkflowResult;
begin
  if FFailOnDiscard then
    Exit(TDocumentWorkflowResult.Fail(
      dwaDiscardChanges,
      'DocumentWorkflow.DiscardChanges failed.'
    ));

  Result := TDocumentWorkflowResult.Ok(
    dwaDiscardChanges,
    'DocumentWorkflow.DiscardChanges executed successfully.'
  );
end;

function TDemoDocumentWorkflow.ReturnToEditor: TDocumentWorkflowResult;
begin
  if FFailOnReturnToEditor then
    Exit(TDocumentWorkflowResult.Fail(
      dwaReturnToEditor,
      'DocumentWorkflow.ReturnToEditor failed.'
    ));

  Result := TDocumentWorkflowResult.Ok(
    dwaReturnToEditor,
    'DocumentWorkflow.ReturnToEditor executed successfully.'
  );
end;

end.

