// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Eduardo P. Araujo
// https://github.com/eduardoparaujo/Dialog4D

{*
  Program: Dialog4D.Tests
  Purpose: Console test runner for the Dialog4D automated test suite.

           This project is the entry point for all DUnitX-based tests in the
           Dialog4D test set. It registers the available test units, configures
           console and NUnit XML loggers, executes the suite, and returns a
           process exit code suitable for local runs and CI environments.

           Exit code policy:
             - 0 = all tests passed
             - 1 = one or more tests failed, errored, or an unhandled exception
                   occurred during test execution

  Part of the Dialog4D automated test suite.

  Author        : Eduardo P. Araujo
  Created       : 2026-04-26
  Last modified : 2026-05-01
  Version       : 1.0.1

  Notes:
    - Uses RTTI-based test discovery via DUnitX.
    - Console logger is enabled for interactive local execution.
    - NUnit XML logger is enabled for CI/reporting integration.
    - Keeps the console window open at the end of execution for convenience
      in manual runs.

  History:
    1.0.1 - 2026-05-01 - Test suite coverage update.
      - Added Dialog4D.Tests.Facade.Core to the console runner.
      - Included facade-level validation tests for custom-button arrays and
        manually constructed mrNone button results.
      - Updated the runner to execute the expanded Dialog4D 1.0.1 regression
        test set.

    1.0.0 - 2026-04-26 - Initial automated test runner release.
      - Added the DUnitX console runner for the Dialog4D automated test suite.
      - Enabled RTTI-based test discovery.
      - Enabled console and NUnit XML loggers.
      - Added process exit code handling for local runs and CI environments.
*}

program Dialog4D.Tests;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  DUnitX.TestFramework,
  DUnitX.Loggers.Console,
  DUnitX.Loggers.Xml.NUnit,
  Dialog4D.Tests.Await.Core in '..\src\Dialog4D.Tests.Await.Core.pas',
  Dialog4D.Tests.Internal.Queue in '..\src\Dialog4D.Tests.Internal.Queue.pas',
  Dialog4D.Tests.Support in '..\src\Dialog4D.Tests.Support.pas',
  Dialog4D.Tests.Telemetry.Format in '..\src\Dialog4D.Tests.Telemetry.Format.pas',
  Dialog4D.Tests.TextProvider.Default in '..\src\Dialog4D.Tests.TextProvider.Default.pas',
  Dialog4D.Tests.Types in '..\src\Dialog4D.Tests.Types.pas',
  Dialog4D.Tests.Facade.Core in '..\src\Dialog4D.Tests.Facade.Core.pas';

var
  LRunner: ITestRunner;
  LResults: IRunResults;

begin
  try
    TDUnitX.CheckCommandLine;

    LRunner := TDUnitX.CreateRunner;
    LRunner.UseRTTI := True;
    LRunner.FailsOnNoAsserts := False;

    LRunner.AddLogger(TDUnitXConsoleLogger.Create(True));
    LRunner.AddLogger(TDUnitXXMLNUnitFileLogger.Create);

    LResults := LRunner.Execute;

    if Assigned(LResults) and LResults.AllPassed then
      ExitCode := 0
    else
      ExitCode := 1;

    Writeln;
    Writeln('Press ENTER to exit...');
    Readln;
  except
    on E: Exception do
    begin
      Writeln(E.ClassName + ': ' + E.Message);
      Writeln;
      Writeln('Press ENTER to exit...');
      Readln;
      ExitCode := 1;
    end;
  end;
end.
