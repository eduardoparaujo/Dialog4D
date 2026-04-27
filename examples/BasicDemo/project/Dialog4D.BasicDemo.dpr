program Dialog4D.BasicDemo;

uses
  System.StartUpCopy,
  FMX.Forms,
  Dialog4D.BasicDemo.Main in '..\src\Dialog4D.BasicDemo.Main.pas' {FormMain},
  Dialog4D.BasicDemo.Workflow in '..\src\Dialog4D.BasicDemo.Workflow.pas';

{$R *.res}

begin
  ReportMemoryLeaksOnShutdown := True;
  Application.Initialize;
  Application.CreateForm(TFormMain, FormMain);
  Application.Run;
end.
