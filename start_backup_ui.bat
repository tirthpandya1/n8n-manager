@echo off
REM #############################################################################
REM N8N Backup Utility - Startup Script (Windows)
REM Starts the FastAPI backup utility web interface
REM #############################################################################

setlocal enabledelayedexpansion

echo ========================================
echo N8N Backup Utility - Starting Server
echo ========================================
echo.

REM Get script directory
set "SCRIPT_DIR=%~dp0"
set "BACKUP_UI_DIR=%SCRIPT_DIR%backup_ui"

REM Check if Python is available
python --version >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Python is not installed or not in PATH
    echo Please install Python 3.8 or higher
    pause
    exit /b 1
)

for /f "tokens=2" %%i in ('python --version 2^>^&1') do set PYTHON_VERSION=%%i
echo [INFO] Python version: %PYTHON_VERSION%

REM Change to backup_ui directory
cd /d "%BACKUP_UI_DIR%"

REM Check if virtual environment exists
if not exist "venv" (
    echo [INFO] Virtual environment not found. Creating...
    python -m venv venv
    echo [SUCCESS] Virtual environment created
)

REM Activate virtual environment
echo [INFO] Activating virtual environment...
call venv\Scripts\activate.bat

REM Install/upgrade dependencies
echo [INFO] Installing dependencies...
python -m pip install --quiet --upgrade pip
python -m pip install --quiet -r requirements.txt
echo [SUCCESS] Dependencies installed

REM Check if port 8001 is already in use
netstat -ano | findstr :8001 | findstr LISTENING >nul 2>&1
if not errorlevel 1 (
    echo [WARNING] Port 8001 is already in use
    echo The backup utility may already be running or another service is using this port
    set /p CONTINUE="Do you want to continue anyway? (y/N): "
    if /i not "!CONTINUE!"=="y" (
        exit /b 1
    )
)

REM Start the server
echo.
echo ========================================
echo Starting N8N Backup Utility Server
echo ========================================
echo.
echo Server will be available at:
echo   http://localhost:8001
echo   http://127.0.0.1:8001
echo.
echo Press CTRL+C to stop the server
echo.

REM Start FastAPI with uvicorn
python -m uvicorn main:app --host 0.0.0.0 --port 8001 --reload

REM Cleanup on exit
call venv\Scripts\deactivate.bat
pause
