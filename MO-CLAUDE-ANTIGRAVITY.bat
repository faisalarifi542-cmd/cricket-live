@echo off
chcp 65001 >nul

:: Tu xin quyen admin (UAC) neu chua co - mot so may can quyen admin moi chay duoc
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Dang xin quyen admin...
    powershell -Command "Start-Process -FilePath '%~f0' -Verb RunAs" >nul 2>&1
    exit /b
)

title Claude Code (Antigravity) - Nghimmo
color 0B

cls
echo.
echo ============================================================
echo     CLAUDE CODE TREN ANTIGRAVITY - POWERED BY NGHIMMO
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
echo [OK] Da cau hinh xong. Dang mo Antigravity...
echo.

:: Tim Antigravity IDE that su tren may (uu tien "Antigravity IDE")
set "AGEXE="
if exist "%LOCALAPPDATA%\Programs\Antigravity IDE\Antigravity IDE.exe" set "AGEXE=%LOCALAPPDATA%\Programs\Antigravity IDE\Antigravity IDE.exe"
if not defined AGEXE if exist "%ProgramFiles%\Antigravity IDE\Antigravity IDE.exe" set "AGEXE=%ProgramFiles%\Antigravity IDE\Antigravity IDE.exe"
if not defined AGEXE if exist "%LOCALAPPDATA%\Programs\Antigravity\Antigravity.exe" set "AGEXE=%LOCALAPPDATA%\Programs\Antigravity\Antigravity.exe"
if not defined AGEXE if exist "%ProgramFiles%\Antigravity\Antigravity.exe" set "AGEXE=%ProgramFiles%\Antigravity\Antigravity.exe"

if defined AGEXE (
    start "" "%AGEXE%"
) else (
    echo  [CHU Y] Khong tim thay Antigravity tren may.
    echo          Co the ban chua cai Antigravity, hoac cai o duong dan khac.
    echo          Dang thu mo bang lenh 'antigravity' mac dinh...
    antigravity
)

echo.
echo ============================================================
echo  Antigravity da duoc khoi dong. Cua so nay co the dong.
echo ============================================================
pause >nul
