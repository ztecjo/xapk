@echo off
setlocal EnableExtensions DisableDelayedExpansion

REM ============================================================================
REM  ZTEC XAPK Installer
REM  Copyright (c) 2026 ZTEC JO
REM  Licensed under the MIT License. See LICENSE for details.
REM
REM  Supported platform: Windows only (Windows 10 / 11).
REM  macOS, Linux, and other systems are not supported.
REM
REM  Usage:
REM    Double-click install.bat
REM      - lists .xapk packages next to this script and installs the one you pick
REM
REM    install.bat "package.xapk"
REM      - installs the specified package
REM ============================================================================

set "SCRIPT_DIR=%~dp0"
set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
set "TARGET_XAPK="
set "WORK_DIR="
set "XAPK_BASENAME="
set "INSTALLER_NAME=ZTEC XAPK Installer"
set "INSTALLER_VER=1.1"
set "COPYRIGHT=Copyright (c) 2026 ZTEC JO — MIT License"
set "PLATFORM=Windows only"

REM Guard: this installer is Windows-only (.bat + PowerShell + adb on PATH).
if /I not "%OS%"=="Windows_NT" goto :ERR_NOT_WINDOWS
ver | findstr /I /C:"Windows" >nul
if errorlevel 1 goto :ERR_NOT_WINDOWS

title %INSTALLER_NAME%
color 0A
cls

echo.
echo  ============================================================
echo   %INSTALLER_NAME%  v%INSTALLER_VER%
echo   Platform: %PLATFORM%
echo   %COPYRIGHT%
echo  ============================================================
echo.

where adb >nul 2>&1
if errorlevel 1 goto :ERR_NO_ADB

call :CHECK_DEVICE
if errorlevel 1 goto :ERR_NO_DEVICE

if not "%~1"=="" goto :ARG_MODE

call :SELECT_XAPK
if errorlevel 1 goto :ERR_SELECT
goto :CONFIRM

:ARG_MODE
if /I "%~1"=="/?" goto :SHOW_HELP
if /I "%~1"=="-h" goto :SHOW_HELP
if /I "%~1"=="--help" goto :SHOW_HELP
if not exist "%~1" goto :ERR_FILE_NOT_FOUND
set "TARGET_XAPK=%~f1"
goto :CONFIRM

:CONFIRM
for %%Z in ("%TARGET_XAPK%") do set "XAPK_BASENAME=%%~nxZ"
echo  Package : %XAPK_BASENAME%
echo  Device  : connected via ADB
echo.
set /p CONFIRM=  Install this package now? [Y/N]: 
if /I not "%CONFIRM%"=="Y" if /I not "%CONFIRM%"=="YES" goto :CANCELLED

:START_INSTALL
set "WORK_DIR=%TEMP%\ztec_xapk_%RANDOM%_%RANDOM%"
mkdir "%WORK_DIR%" >nul 2>&1
if not exist "%WORK_DIR%" goto :ERR_TEMP

echo.
echo  ------------------------------------------------------------
echo   Installing "%XAPK_BASENAME%"
echo  ------------------------------------------------------------
echo.

echo  [1/3] Extracting package...
call :EXTRACT_XAPK
if errorlevel 1 goto :ERR_EXTRACT
echo        Done.
echo.

echo  [2/3] Installing application...
call :INSTALL_APKS
if errorlevel 1 goto :FAIL
echo        Done.
echo.

echo  [3/3] Copying game data (OBB), if any...
call :PUSH_OBB
echo.

echo  ============================================================
echo   SUCCESS
echo   "%XAPK_BASENAME%" was installed.
echo   %COPYRIGHT%
echo  ============================================================
goto :CLEAN_EXIT

:SELECT_XAPK
setlocal EnableDelayedExpansion
set /a COUNT=0

REM Prefer packages next to this script (double-click safe), then current folder.
pushd "%SCRIPT_DIR%" >nul 2>&1
for %%F in ("*.xapk") do (
    set /a COUNT+=1
    set "XAPK[!COUNT!]=%%~fF"
    set "XAPKNAME[!COUNT!]=%%~nxF"
)
popd >nul 2>&1

if /I not "%CD%"=="%SCRIPT_DIR%" (
    for %%F in ("%CD%\*.xapk") do (
        set "ALREADY=0"
        for /L %%I in (1,1,!COUNT!) do (
            if /I "!XAPKNAME[%%I]!"=="%%~nxF" set "ALREADY=1"
        )
        if "!ALREADY!"=="0" if exist "%%~fF" (
            set /a COUNT+=1
            set "XAPK[!COUNT!]=%%~fF"
            set "XAPKNAME[!COUNT!]=%%~nxF"
        )
    )
)

if !COUNT! EQU 0 (
    echo  [ERROR] No .xapk files found.
    echo.
    echo  Place your .xapk file in this folder and run again:
    echo    %SCRIPT_DIR%
    endlocal & exit /b 1
)

if !COUNT! EQU 1 (
    echo  Found 1 package:
    echo    1^) !XAPKNAME[1]!
    echo.
    for %%S in ("!XAPK[1]!") do endlocal & set "TARGET_XAPK=%%~fS" & exit /b 0
)

echo  Available packages:
echo.
for /L %%I in (1,1,!COUNT!) do echo    %%I^) !XAPKNAME[%%I]!
echo.
set /p PICK=  Select number ^(1-!COUNT!^): 

for /f "delims=0123456789" %%A in ("!PICK!") do set "PICK="
if "!PICK!"=="" goto :SELECT_BAD
if !PICK! LSS 1 goto :SELECT_BAD
if !PICK! GTR !COUNT! goto :SELECT_BAD

for %%S in ("!XAPK[%PICK%]!") do endlocal & set "TARGET_XAPK=%%~fS" & exit /b 0

:SELECT_BAD
echo.
echo  [ERROR] Invalid selection.
endlocal & exit /b 1

:EXTRACT_XAPK
if not exist "%SCRIPT_DIR%\extract_xapk.ps1" (
    echo  [ERROR] Missing helper script: extract_xapk.ps1
    echo          Keep install.bat and extract_xapk.ps1 in the same folder.
    exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%\extract_xapk.ps1" -Source "%TARGET_XAPK%" -Destination "%WORK_DIR%"
if errorlevel 1 exit /b 1
exit /b 0

:INSTALL_APKS
setlocal EnableDelayedExpansion
set "APK_COUNT=0"
set "APK_LIST="
set "SINGLE_APK="

for /f "delims=" %%A in ('dir /b /s /a:-d "%WORK_DIR%\*.apk" 2^>nul') do (
    set /a APK_COUNT+=1
    set "SINGLE_APK=%%~fA"
    set "APK_LIST=!APK_LIST! "%%~fA""
)

if "!APK_COUNT!"=="0" (
    echo  [ERROR] No APK files found inside the package.
    endlocal & exit /b 1
)

if "!APK_COUNT!"=="1" (
    adb install -r "!SINGLE_APK!"
    goto :INSTALL_DONE
)

echo        Installing !APK_COUNT! split APKs...
adb install-multiple -r !APK_LIST!

:INSTALL_DONE
if errorlevel 1 (
    echo  [ERROR] Installation failed.
    echo  [TIP]  Uninstall the old app first if signatures differ,
    echo         or confirm this package matches your device ABI.
    endlocal & exit /b 1
)

endlocal & exit /b 0

:PUSH_OBB
if not exist "%WORK_DIR%\Android\obb" (
    echo        No OBB data in this package.
    exit /b 0
)

echo        Pushing OBB data to device...
adb shell mkdir -p /sdcard/Android/obb >nul 2>&1
adb push "%WORK_DIR%\Android\obb" "/sdcard/Android/" >nul
if errorlevel 1 (
    echo  [WARN] OBB copy failed. The app may still be installed.
    echo  [TIP]  Grant file access / storage permission and try again.
    exit /b 0
)
echo        OBB data copied.
exit /b 0

:CHECK_DEVICE
adb get-state >nul 2>&1
if not errorlevel 1 exit /b 0

REM Distinguish "unauthorized" USB debugging from no device.
adb devices 2>nul | findstr /I /C:"unauthorized" >nul
if not errorlevel 1 exit /b 2
exit /b 1

:SHOW_HELP
echo  %INSTALLER_NAME%  v%INSTALLER_VER%
echo  Platform: %PLATFORM%
echo  %COPYRIGHT%
echo.
echo  Usage:
echo    install.bat
echo    install.bat "C:\path\to\package.xapk"
echo.
echo  Requirements: Windows 10/11, adb in PATH, USB debugging enabled.
echo.
goto :CLEAN_EXIT

:CANCELLED
echo.
echo  Install cancelled.
goto :CLEAN_EXIT

:ERR_NOT_WINDOWS
echo  [ERROR] This installer supports Windows only.
echo          macOS, Linux, and other systems are not supported.
goto :FAIL_PAUSE

:ERR_NO_ADB
echo  [ERROR] Android Debug Bridge (adb) was not found.
echo.
echo  Install Android platform-tools and add adb to your PATH, then try again.
echo  https://developer.android.com/tools/releases/platform-tools
goto :FAIL_PAUSE

:ERR_NO_DEVICE
call :CHECK_DEVICE
if errorlevel 2 (
    echo  [ERROR] Device is connected but USB debugging is not authorized.
    echo.
    echo  On the device, accept the "Allow USB debugging?" prompt, then retry.
) else (
    echo  [ERROR] No Android device detected.
    echo.
    echo  1. Connect the device with a data USB cable
    echo  2. Enable Developer options and USB debugging
    echo  3. Confirm the device appears in:  adb devices
)
goto :FAIL_PAUSE

:ERR_FILE_NOT_FOUND
echo  [ERROR] File not found:
echo          %~1
goto :FAIL_PAUSE

:ERR_SELECT
goto :FAIL_PAUSE

:ERR_TEMP
echo  [ERROR] Could not create a temporary work folder.
goto :FAIL_PAUSE

:ERR_EXTRACT
echo  [ERROR] Could not extract the XAPK package.
echo  [TIP]  The file may be incomplete, corrupted, or password-protected.
goto :FAIL

:FAIL
if defined WORK_DIR if exist "%WORK_DIR%" rd /s /q "%WORK_DIR%" >nul 2>&1
echo.
echo  ============================================================
echo   FAILED
echo   %COPYRIGHT%
echo  ============================================================
goto :FAIL_PAUSE

:FAIL_PAUSE
echo.
pause
exit /b 1

:CLEAN_EXIT
if defined WORK_DIR if exist "%WORK_DIR%" rd /s /q "%WORK_DIR%" >nul 2>&1
echo.
pause
exit /b 0
