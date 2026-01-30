@echo off
REM N8N Standalone Instance Stop Script for Windows

echo Stopping N8N Workflow Automation...
echo ======================================

REM Get the directory where this script is located
cd /d "%~dp0"

REM Check if n8n container is running
docker ps --format "{{.Names}}" | findstr /r "^n8n$" >nul 2>&1
if %errorlevel% neq 0 (
    echo N8N is not running
    pause
    exit /b 0
)

REM Stop n8n
echo Stopping n8n container...
docker-compose down

echo N8N stopped successfully!
pause
