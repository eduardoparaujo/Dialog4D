// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Eduardo P. Araujo
// https://github.com/eduardoparaujo/Dialog4D

{*
  Unit   : Dialog4D.Tests.Support
  Purpose: Shared support helpers for Dialog4D automated tests.

           This unit provides small deterministic utilities used across the
           Dialog4D test suite, especially for tests that depend on queued
           main-thread execution or asynchronous state changes.

           Current helpers:
             - PumpMainThread : processes queued synchronized work
             - WaitUntil      : repeatedly pumps the main thread and polls a
                                condition until it becomes True or a timeout
                                expires

           This unit does not define test cases. It exists only to support the
           execution of test fixtures.

  Notes:
    - Designed for simple and predictable use in DUnitX tests.
    - Uses CheckSynchronize to process queued work on the main thread.
    - WaitUntil is intended for test scenarios only and should not be reused
      as a production waiting primitive.

  Author        : Eduardo P. Araujo
  Created       : 2026-04-26
  Last modified : 2026-04-26
  Version       : 1.0.0
*}

unit Dialog4D.Tests.Support;

interface

uses
  System.SysUtils,
  System.Classes;

type
  TDialog4DTestSupport = class
  public
    /// <summary>
    /// Pumps the main thread by processing pending synchronized/queued work.
    /// </summary>
    class procedure PumpMainThread(const ATimeoutMs: Cardinal = 1); static;

    /// <summary>
    /// Waits until <c>ACondition</c> returns <c>True</c> or the timeout expires.
    /// </summary>
    /// <remarks>
    /// <para>
    /// During the wait loop, the main thread is pumped via
    /// <c>CheckSynchronize</c> so queued work can be executed deterministically
    /// in tests.
    /// </para>
    /// </remarks>
    class function WaitUntil(
      const ACondition: TFunc<Boolean>;
      const ATimeoutMs: Cardinal = 2000;
      const APollMs: Cardinal = 10
    ): Boolean; static;
  end;

implementation

class procedure TDialog4DTestSupport.PumpMainThread(const ATimeoutMs: Cardinal);
begin
  CheckSynchronize(ATimeoutMs);
end;

class function TDialog4DTestSupport.WaitUntil(
  const ACondition: TFunc<Boolean>;
  const ATimeoutMs: Cardinal;
  const APollMs: Cardinal
): Boolean;
var
  LStart: Cardinal;
begin
  LStart := TThread.GetTickCount;

  repeat
    PumpMainThread(APollMs);

    if Assigned(ACondition) and ACondition() then
      Exit(True);

    Sleep(APollMs);
  until (TThread.GetTickCount - LStart) >= ATimeoutMs;

  Result := Assigned(ACondition) and ACondition();
end;

end.
