@echo off
setlocal
setlocal EnableDelayedExpansion

set "ROOT=%~dp0"
cd /d "%ROOT%"

where erl >nul 2>&1
if errorlevel 1 (
    echo [ERROR] erl.exe not found in PATH.
    exit /b 1
)

where rebar3 >nul 2>&1
if errorlevel 1 (
    echo [ERROR] rebar3 not found in PATH.
    exit /b 1
)

echo [1/3] Compiling project modules...
call rebar3 compile
if errorlevel 1 goto :compile_error

echo [2/3] Compiling test profile modules...
call rebar3 as test compile
if errorlevel 1 goto :compile_error

rem rebar3 test profile compiles test/*.erl in-place; remove stray beams from source tree
del /q "%ROOT%test\*.beam" 2>nul
if exist "%ROOT%test\schema" del /q "%ROOT%test\schema\*.beam" 2>nul

echo [3/3] Starting Erlang shell with src and test code paths...
echo.
echo Available examples after startup:
echo   pgdb_test_helper:start().
echo   pgdb_bench_tests:run_all().
echo   pgdb_bench_tests:run_all(5000).
echo   pgdb_crud_tests:module_info().
echo   ePgdb:schema(players).
echo.

set "ERL_PA_ARGS="
for /d %%D in ("%ROOT%_build\default\lib\*") do (
    if exist "%%~fD\ebin" (
        set "ERL_PA_ARGS=!ERL_PA_ARGS! -pa "%%~fD\ebin""
    )
)
for /d %%D in ("%ROOT%_build\test\lib\*") do (
    if exist "%%~fD\ebin" (
        set "ERL_PA_ARGS=!ERL_PA_ARGS! -pa "%%~fD\ebin""
    )
)

call erl !ERL_PA_ARGS! %*
set "ERL_EXIT=%ERRORLEVEL%"
exit /b %ERL_EXIT%

:compile_error
echo [ERROR] Compile failed. Shell not started.
exit /b 1