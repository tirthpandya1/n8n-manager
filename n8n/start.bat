@echo off
REM N8N Standalone Instance Startup Script for Windows
REM This script starts the standalone n8n instance on port 5678

echo Starting N8N Workflow Automation...
echo ======================================

REM Check if Docker is running
docker info >nul 2>&1
if %errorlevel% neq 0 (
    echo ERROR: Docker is not running. Please start Docker Desktop first.
    pause
    exit /b 1
)

REM Get the directory where this script is located
cd /d "%~dp0"

echo Working directory: %cd%

REM Check if n8n container is already running
docker ps --format "{{.Names}}" | findstr /r "^n8n$" >nul 2>&1
if %errorlevel% equ 0 (
    echo N8N is already running
    echo Access at: http://localhost:5678
    echo Username: admin
    echo Password: Ivoryt#1
    pause
    exit /b 0
)

REM Stop any existing n8n container
docker ps -a --format "{{.Names}}" | findstr /r "^n8n$" >nul 2>&1
if %errorlevel% equ 0 (
    echo Removing existing n8n container...
    docker-compose down
)

REM Start n8n
echo Starting n8n container...
docker-compose up -d

REM Wait for n8n to be ready
echo Waiting for n8n to be ready...
set max_attempts=30
set attempt=1

:wait_loop
if %attempt% gtr %max_attempts% goto timeout

docker exec n8n wget --no-verbose --tries=1 --spider http://localhost:5678/healthz >nul 2>&1
if %errorlevel% equ 0 goto ready

echo Attempt %attempt%/%max_attempts% - waiting...
timeout /t 2 /nobreak >nul
set /a attempt+=1
goto wait_loop

:timeout
echo ERROR: N8N failed to start within timeout
echo Check logs with: docker-compose logs n8n
pause
exit /b 1

:ready
echo N8N is ready!
echo.
echo ====================================
echo N8N Started Successfully!
echo ====================================
echo Access URL:  http://localhost:5678
echo Username:    admin
echo Password:    Ivoryt#1
echo.
echo Useful Commands:
echo   View logs:     docker-compose logs -f n8n
echo   Stop n8n:      docker-compose down
echo   Restart n8n:   docker-compose restart n8n
echo.
pause
