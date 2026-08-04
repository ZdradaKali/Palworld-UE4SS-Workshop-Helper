@echo off
setlocal
title Palworld UE4SS Workshop Helper
:menu
cls
set "helperArgs="
echo.
echo Palworld UE4SS Workshop Helper
echo.
echo 1. Show current status
echo 2. Preview GitHub UE4SS setup
echo 3. Apply GitHub UE4SS setup
echo 4. Preview enabled.txt synchronization
echo 5. Apply enabled.txt synchronization
echo 6. Preview restoration of Workshop UE4SS
echo 7. Apply restoration of Workshop UE4SS
echo 8. Cancel
echo.
choice /C 12345678 /N /M "Choose an action: "
set "selection=%ERRORLEVEL%"
if "%selection%"=="8" exit /b 0
if "%selection%"=="7" set "helperArgs=-Action Restore -Apply"
if "%selection%"=="6" set "helperArgs=-Action Restore"
if "%selection%"=="5" set "helperArgs=-Action Sync -Apply"
if "%selection%"=="4" set "helperArgs=-Action Sync"
if "%selection%"=="3" set "helperArgs=-Action Setup -Apply"
if "%selection%"=="2" set "helperArgs=-Action Setup"
if "%selection%"=="1" set "helperArgs=-Action Status"
echo.
if "%selection%"=="3" call :confirm || goto :menu
if "%selection%"=="5" call :confirm || goto :menu
if "%selection%"=="7" call :confirm || goto :menu
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Palworld-UE4SS-Workshop-Helper.ps1" %helperArgs%
set "helperExit=%ERRORLEVEL%"
echo.
echo Exit code: %helperExit%
echo.
echo Press any key to return to the main menu.
pause >nul
goto :menu

:confirm
echo This action can change files. Close Palworld and review the preview first.
choice /C YN /N /M "Continue? [Y/N]: "
if errorlevel 2 exit /b 1
exit /b 0
