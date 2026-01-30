@echo off
REM Sync N8N data from Voice Agent Platform backend to standalone instance

echo N8N Data Synchronization Tool
echo ================================
echo.

REM Source path
set VOICE_AGENT_BACKEND=C:\Users\Admin\Code\Projects\Voice-Agent-Platform-Final\voice-agent-platform\backend

REM Get the directory where this script is located
cd /d "%~dp0"

REM Check if n8n container is running
docker ps --format "{{.Names}}" | findstr /r "^n8n" >nul 2>&1
if %errorlevel% neq 0 (
    echo ERROR: N8N container is not running. Please start it first with start.bat
    pause
    exit /b 1
)

echo Choose sync method:
echo 1. One-time copy ^(copy data from backend to standalone^)
echo 2. Export current standalone data
echo.
set /p choice="Enter your choice (1-2): "

if "%choice%"=="1" goto one_time_copy
if "%choice%"=="2" goto export_data

echo Invalid choice
pause
exit /b 1

:one_time_copy
echo.
echo One-time copy mode
echo ====================

REM Copy workflows
if exist "%VOICE_AGENT_BACKEND%\n8n-workflows" (
    echo Copying workflows...
    docker exec n8n mkdir -p /home/node/.n8n/workflows
    docker cp "%VOICE_AGENT_BACKEND%\n8n-workflows\." n8n:/home/node/.n8n/workflows/
    echo Workflows copied
)

REM Copy credentials
if exist "%VOICE_AGENT_BACKEND%\n8n-credentials" (
    echo Copying credentials...
    docker exec n8n mkdir -p /home/node/.n8n/credentials
    docker cp "%VOICE_AGENT_BACKEND%\n8n-credentials\." n8n:/home/node/.n8n/credentials/
    echo Credentials copied
)

REM Copy certificates
if exist "%VOICE_AGENT_BACKEND%\security\CloudflareCertificates" (
    echo Copying certificates...
    docker exec n8n mkdir -p /opt/custom-certificates
    docker cp "%VOICE_AGENT_BACKEND%\security\CloudflareCertificates\." n8n:/opt/custom-certificates/
    echo Certificates copied
)

echo.
echo Data sync complete!
echo Restarting n8n container to apply changes...
docker-compose restart n8n
echo Done! Access n8n at http://localhost:5678
pause
exit /b 0

:export_data
echo.
echo Export standalone data
echo ========================

REM Create export directory with timestamp
for /f "tokens=2-4 delims=/ " %%a in ('date /t') do (set mydate=%%c%%a%%b)
for /f "tokens=1-2 delims=/:" %%a in ('time /t') do (set mytime=%%a%%b)
set EXPORT_DIR=n8n-export-%mydate%_%mytime%
mkdir "%EXPORT_DIR%"

echo Export directory: %cd%\%EXPORT_DIR%

REM Export workflows
echo Exporting workflows...
docker cp n8n:/home/node/.n8n/workflows "%EXPORT_DIR%\" 2>nul || echo Warning: No workflows found

REM Export credentials
echo Exporting credentials...
docker cp n8n:/home/node/.n8n/credentials "%EXPORT_DIR%\" 2>nul || echo Warning: No credentials found

REM Export full .n8n directory
echo Exporting full n8n data...
docker cp n8n:/home/node/.n8n "%EXPORT_DIR%\n8n-data" 2>nul || echo Warning: Could not export full data

echo.
echo Export complete!
echo Data exported to: %cd%\%EXPORT_DIR%
pause
exit /b 0
