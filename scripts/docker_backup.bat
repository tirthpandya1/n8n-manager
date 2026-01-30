@echo off
setlocal enabledelayedexpansion

REM Docker N8N Backup Helper Script for Windows
REM Usage: docker_backup.bat [container_name] [--include-volumes] [--include-logs] [--non-interactive]

REM Get script directory
set "SCRIPT_DIR=%~dp0"
set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
for %%i in ("%SCRIPT_DIR%") do set "N8N_DIR=%%~dpi"
set "N8N_DIR=%N8N_DIR:~0,-1%"
set "BACKUP_BASE_DIR=%N8N_DIR%\backups"

REM Default values
set "CONTAINER_NAME=n8n"
set "INCLUDE_VOLUMES=false"
set "INCLUDE_LOGS=false"
set "NON_INTERACTIVE=false"

REM Generate timestamp
for /f "tokens=1-6 delims=/:. " %%a in ("%date% %time%") do (
    set "TIMESTAMP=%%c%%a%%b_%%d%%e%%f"
)
set "TIMESTAMP=%TIMESTAMP: =0%"

REM Parse arguments
:parse_args
if "%~1"=="--include-volumes" (
    set "INCLUDE_VOLUMES=true"
    shift
    goto :parse_args
)
if "%~1"=="--include-logs" (
    set "INCLUDE_LOGS=true"
    shift
    goto :parse_args
)
if "%~1"=="--non-interactive" (
    set "NON_INTERACTIVE=true"
    shift
    goto :parse_args
)
if not "%~1"=="" if not "%~1:~0,1%"=="-" (
    set "CONTAINER_NAME=%~1"
    shift
    goto :parse_args
)
if not "%~1"=="" (
    shift
    goto :parse_args
)

echo [INFO] Docker N8N Backup Helper v1.0.0
echo [INFO] =================================
echo [INFO] Container: %CONTAINER_NAME%
echo [INFO] Include volumes: %INCLUDE_VOLUMES%
echo [INFO] Include logs: %INCLUDE_LOGS%
echo [INFO] Non-interactive: %NON_INTERACTIVE%
echo.

REM Create backup directory
set "BACKUP_DIR=%BACKUP_BASE_DIR%\docker_enhanced_backup_%TIMESTAMP%"
if not exist "%BACKUP_DIR%" mkdir "%BACKUP_DIR%"

REM Verify container exists
docker ps -a --format "{{.Names}}" | findstr /x "%CONTAINER_NAME%" >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Docker container '%CONTAINER_NAME%' not found.
    exit /b 1
)

REM Check if container is running
docker ps --format "{{.Names}}" | findstr /x "%CONTAINER_NAME%" >nul 2>&1
if errorlevel 1 (
    echo [WARNING] Container is not running. Some operations may fail.
)

REM Gathering container information
echo [INFO] Gathering container information...
set "INFO_FILE=%BACKUP_DIR%\container_info.json"
docker inspect "%CONTAINER_NAME%" > "%INFO_FILE%"

REM Backup logs
if "%INCLUDE_LOGS%"=="true" (
    echo [INFO] Backing up container logs...
    docker logs "%CONTAINER_NAME%" > "%BACKUP_DIR%\container_logs.txt" 2>&1
    echo [SUCCESS] Container logs backed up
)

REM Backup volumes
if "%INCLUDE_VOLUMES%"=="true" (
    echo [INFO] Backing up Docker volumes...
    set "VOLUMES_DIR=%BACKUP_DIR%\volumes"
    if not exist "!VOLUMES_DIR!" mkdir "!VOLUMES_DIR!"
    
    REM This is a simplified way to list volumes for a container and back them up
    for /f "tokens=*" %%v in ('docker inspect --format "{{range .Mounts}}{{if eq .Type ""volume""}}{{.Name}} {{end}}{{end}}" %CONTAINER_NAME%') do (
        for %%n in (%%v) do (
            echo [INFO] Backing up volume: %%n
            docker run --rm -v "%%n":/volume -v "!VOLUMES_DIR!":/backup alpine tar -cf "/backup/%%n_backup.tar" -C /volume .
            echo [SUCCESS] Volume %%n backed up
        )
    )
)

REM Create Docker Compose template (Simplified version)
echo [INFO] Creating Docker Compose template...
set "COMPOSE_FILE=%BACKUP_DIR%\docker-compose.yml"
echo version: '3.8' > "%COMPOSE_FILE%"
echo services: >> "%COMPOSE_FILE%"
echo   n8n: >> "%COMPOSE_FILE%"
echo     container_name: %CONTAINER_NAME% >> "%COMPOSE_FILE%"
echo     restart: unless-stopped >> "%COMPOSE_FILE%"

REM Run standard backup
echo [INFO] Running standard n8n backup...
set "EXTRA_FLAGS="
if "%NON_INTERACTIVE%"=="true" set "EXTRA_FLAGS=--non-interactive"
docker exec -u node %CONTAINER_NAME% mkdir -p /tmp/workflows_export >nul 2>&1
call "%SCRIPT_DIR%\backup_n8n_windows.bat" %EXTRA_FLAGS% docker %CONTAINER_NAME%

REM Move the standard backup folder into our enhanced directory
for /f "delims=" %%i in ('dir /b /ad /o-d "%BACKUP_BASE_DIR%\docker_backup_*" 2^>nul') do (
    set "LATEST_STD=%%i"
    move "%BACKUP_BASE_DIR%\!LATEST_STD!" "%BACKUP_DIR%\" >nul
    goto :std_moved
)
:std_moved
echo [SUCCESS] Standard backup included

REM Create metadata
echo [INFO] Creating metadata...
set "METADATA_FILE=%BACKUP_DIR%\enhanced_backup_metadata.json"
echo { > "%METADATA_FILE%"
echo   "enhanced_backup_info": { >> "%METADATA_FILE%"
echo     "timestamp": "%TIMESTAMP%", >> "%METADATA_FILE%"
echo     "container_name": "%CONTAINER_NAME%", >> "%METADATA_FILE%"
echo     "include_volumes": %INCLUDE_VOLUMES%, >> "%METADATA_FILE%"
echo     "include_logs": %INCLUDE_LOGS% >> "%METADATA_FILE%"
echo   } >> "%METADATA_FILE%"
echo } >> "%METADATA_FILE%"

REM Compress
echo [INFO] Compressing enhanced backup...
cd /d "%BACKUP_BASE_DIR%"
set "BACKUP_NAME=docker_enhanced_backup_%TIMESTAMP%"
where tar >nul 2>&1
if %errorlevel%==0 (
    tar -czf "%BACKUP_NAME%.tar.gz" "%BACKUP_NAME%"
    if !errorlevel!==0 (
        rmdir /s /q "%BACKUP_DIR%"
        echo [SUCCESS] Enhanced backup compressed: %BACKUP_NAME%.tar.gz
    )
) else (
    powershell -Command "Compress-Archive -Path '%BACKUP_DIR%' -DestinationPath '%BACKUP_BASE_DIR%\%BACKUP_NAME%.zip' -Force"
    if !errorlevel!==0 (
        rmdir /s /q "%BACKUP_DIR%"
        echo [SUCCESS] Enhanced backup compressed: %BACKUP_NAME%.zip
    )
)

echo [SUCCESS] Enhanced Docker backup completed!
exit /b 0
