@echo off
chcp 65001 >nul

:: Tu xin quyen admin (UAC) neu chua co - mot so may can quyen admin moi chay duoc
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Dang xin quyen admin...
    powershell -Command "Start-Process -FilePath '%~f0' -Verb RunAs" >nul 2>&1
    exit /b
)

title Claude Code (VS Code) - Nghimmo
color 0B

cls
echo.
echo ============================================================
echo       CLAUDE CODE TREN VS CODE - POWERED BY NGHIMMO
echo ============================================================
echo.
echo  Server : https://api.nghimmo.com
echo  Check  : https://api.nghimmo.com/check
echo.
echo ============================================================
echo.

:: Nhap API key cua khach
set "APIKEY="
set /p "APIKEY=Nhap API Key cua ban (sk-...): "

if "%APIKEY%"=="" (
    echo.
    echo [LOI] Ban chua nhap API Key. Dong cua so va mo lai.
    echo.
    pause
    exit /b
)

:: Tro Claude Code ve server Nghimmo (chi trong phien nay, dong la mat)
set "ANTHROPIC_BASE_URL=https://api.nghimmo.com"
set "ANTHROPIC_AUTH_TOKEN=%APIKEY%"
set "ANTHROPIC_API_KEY=%APIKEY%"

echo.
echo [OK] Da cau hinh xong. Dang mo VS Code...
echo.

:: Tim VS Code that su (tranh bi Cursor chiem lenh 'code')
set "VSCODE="
if exist "%LOCALAPPDATA%\Programs\Microsoft VS Code\bin\code.cmd" set "VSCODE=%LOCALAPPDATA%\Programs\Microsoft VS Code\bin\code.cmd"
if not defined VSCODE if exist "%ProgramFiles%\Microsoft VS Code\bin\code.cmd" set "VSCODE=%ProgramFiles%\Microsoft VS Code\bin\code.cmd"
if not defined VSCODE if exist "%ProgramFiles(x86)%\Microsoft VS Code\bin\code.cmd" set "VSCODE=%ProgramFiles(x86)%\Microsoft VS Code\bin\code.cmd"

if defined VSCODE (
    call "%VSCODE%"
) else (
    echo  [CHU Y] Khong tim thay VS Code that su tren may.
    echo          Co the ban chua cai VS Code, hoac dang dung Cursor.
    echo          Neu ban dung Cursor, hay xem tab "Cursor" trong huong dan.
    echo          Dang thu mo bang lenh 'code' mac dinh...
    code
)

echo.
echo ============================================================
echo  VS Code da duoc khoi dong. Cua so nay co the dong.
echo ============================================================
pause >nul
