@echo off
setlocal enabledelayedexpansion

REM N8N Backup Script for Windows
REM Usage: backup_n8n_windows.bat [native|docker] [container_name]

REM Get script directory
set "SCRIPT_DIR=%~dp0"
set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
for %%i in ("%SCRIPT_DIR%") do set "N8N_DIR=%%~dpi"
set "N8N_DIR=%N8N_DIR:~0,-1%"
set "BACKUP_BASE_DIR=%N8N_DIR%\backups"

REM Default values
set "INSTANCE_TYPE=native"
set "CONTAINER_NAME=n8n"

REM Generate timestamp
for /f "tokens=1-6 delims=/:. " %%a in ("%date% %time%") do (
    set "TIMESTAMP=%%c%%a%%b_%%d%%e%%f"
)
set "TIMESTAMP=%TIMESTAMP: =0%"

REM Parse arguments
set "NON_INTERACTIVE=false"

:parse_args
if "%~1"=="" goto args_done
if "%~1"=="--non-interactive" (
    set "NON_INTERACTIVE=true"
    shift
    goto :parse_args
)
if "%~1"=="docker" (
    set "INSTANCE_TYPE=docker"
    if not "%~2"=="" (
        set "CONTAINER_NAME=%~2"
        shift
    )
    shift
    goto :parse_args
)
if "%~1"=="native" (
    set "INSTANCE_TYPE=native"
    shift
    goto :parse_args
)
shift
goto :parse_args

:args_done

echo Starting N8N Backup...
echo Instance type: %INSTANCE_TYPE%
if "%INSTANCE_TYPE%"=="docker" echo Container: %CONTAINER_NAME%
echo.

REM Create backup directories
set "BACKUP_DIR=%BACKUP_BASE_DIR%\%INSTANCE_TYPE%_backup_%TIMESTAMP%"
set "WORKFLOWS_DIR=%BACKUP_DIR%\workflows"
set "CREDENTIALS_FILE=%BACKUP_DIR%\credentials.json"

if not exist "%WORKFLOWS_DIR%" mkdir "%WORKFLOWS_DIR%"

echo Backup directory: %BACKUP_DIR%
echo.

REM Check prerequisites
if "%INSTANCE_TYPE%"=="native" (
    where n8n >nul 2>&1
    if errorlevel 1 (
        echo ERROR: n8n command not found. Please install n8n globally.
        exit /b 1
    )
    set "N8N_CMD=n8n"
) else (
    where docker >nul 2>&1
    if errorlevel 1 (
        echo ERROR: Docker not found.
        exit /b 1
    )

    REM If no container name specified, show selector
    if "%CONTAINER_NAME%"=="n8n" (
        if "%NON_INTERACTIVE%"=="true" (
            echo Using default container name 'n8n' in non-interactive mode.
        ) else (
            echo Looking for n8n containers...
            echo.

            REM Get all containers with 'n8n' in the name
            set "COUNTER=0"
            for /f "delims=" %%c in ('docker ps -a --format "{{.Names}}" ^| findstr /i "n8n"') do (
                set /a COUNTER+=1
                set "CONTAINER_!COUNTER!=%%c"
                echo [!COUNTER!] %%c
            )

            if !COUNTER!==0 (
                echo ERROR: No containers with 'n8n' in the name found.
                echo.
                echo All available containers:
                docker ps -a --format "{{.Names}}"
                exit /b 1
            )

            if !COUNTER!==1 (
                set "CONTAINER_NAME=!CONTAINER_1!"
                echo.
                echo Only one n8n container found: !CONTAINER_NAME!
                echo Using this container...
            ) else (
                echo.
                set /p "SELECTION=Select container number (1-!COUNTER!): "

                if not defined SELECTION (
                    echo ERROR: No selection made.
                    exit /b 1
                )

                if !SELECTION! lss 1 (
                    echo ERROR: Invalid selection.
                    exit /b 1
                )

                if !SELECTION! gtr !COUNTER! (
                    echo ERROR: Invalid selection.
                    exit /b 1
                )

                set "CONTAINER_NAME=!CONTAINER_%SELECTION%!"
                echo.
                echo Selected: !CONTAINER_NAME!
            )
            echo.
        )
    )

    REM Verify selected container exists
    docker ps -a --format "{{.Names}}" | findstr "%CONTAINER_NAME%" >nul 2>&1
    if errorlevel 1 (
        echo ERROR: Container '%CONTAINER_NAME%' not found.
        echo Available containers:
        docker ps -a --format "{{.Names}}"
        exit /b 1
    )

    REM Check if container is running
    docker ps --format "{{.Names}}" | findstr "%CONTAINER_NAME%" >nul 2>&1
    if errorlevel 1 (
        echo WARNING: Container '%CONTAINER_NAME%' exists but is not running.
        echo Starting container...
        docker start %CONTAINER_NAME%
        timeout /t 3 /nobreak >nul
    )
)

REM Backup workflows
echo Exporting workflows...
if "%INSTANCE_TYPE%"=="native" (
    %N8N_CMD% export:workflow --all --separate --output="%WORKFLOWS_DIR%"
) else (
    REM Ensure clean state in container
    docker exec -u node %CONTAINER_NAME% rm -rf /tmp/workflows_export 2>nul
    docker exec -u node %CONTAINER_NAME% mkdir -p /tmp/workflows_export
    docker exec -u node %CONTAINER_NAME% n8n export:workflow --all --separate --output=/tmp/workflows_export
    docker cp %CONTAINER_NAME%:/tmp/workflows_export/. "%WORKFLOWS_DIR%/"
    docker exec -u node %CONTAINER_NAME% rm -rf /tmp/workflows_export
)

if errorlevel 1 (
    echo ERROR: Failed to export workflows
    exit /b 1
)

set "WORKFLOW_COUNT=0"
for /f %%i in ('dir /b /a-d "%WORKFLOWS_DIR%\*.json" 2^>nul ^| find /c /v ""') do set "WORKFLOW_COUNT=%%i"
echo Exported %WORKFLOW_COUNT% workflows
echo.

REM Backup credentials
echo Exporting credentials...
if "%INSTANCE_TYPE%"=="native" (
    %N8N_CMD% export:credentials --all --decrypted --output="%CREDENTIALS_FILE%"
) else (
    docker exec -u node %CONTAINER_NAME% n8n export:credentials --all --decrypted --output=/tmp/credentials_export.json
    docker cp %CONTAINER_NAME%:/tmp/credentials_export.json "%CREDENTIALS_FILE%"
    docker exec -u node %CONTAINER_NAME% rm -f /tmp/credentials_export.json
)

if exist "%CREDENTIALS_FILE%" (
    echo Credentials exported
) else (
    echo No credentials to export
)
echo.

REM Compress backup
echo Compressing backup...
where tar >nul 2>&1
if %errorlevel%==0 (
    cd /d "%BACKUP_BASE_DIR%"
    for %%i in ("%BACKUP_DIR%") do set "BACKUP_NAME=%%~nxi"
    tar -czf "!BACKUP_NAME!.tar.gz" "!BACKUP_NAME!"
    if !errorlevel!==0 (
        rmdir /s /q "%BACKUP_DIR%"
        echo Backup compressed: !BACKUP_NAME!.tar.gz
    )
) else (
    powershell -Command "Compress-Archive -Path '%BACKUP_DIR%' -DestinationPath '%BACKUP_BASE_DIR%\%INSTANCE_TYPE%_backup_%TIMESTAMP%.zip' -Force" >nul 2>&1
    if !errorlevel!==0 (
        rmdir /s /q "%BACKUP_DIR%"
        echo Backup compressed: %INSTANCE_TYPE%_backup_%TIMESTAMP%.zip
    )
)
echo.

REM Cleanup old backups
echo Cleaning up old backups...
cd /d "%BACKUP_BASE_DIR%"
set "COUNT=0"
for /f "delims=" %%f in ('dir /b /o-d "%INSTANCE_TYPE%_backup_*.tar.gz" "%INSTANCE_TYPE%_backup_*.zip" 2^>nul') do (
    set /a COUNT+=1
    if !COUNT! gtr 10 del "%%f" >nul 2>&1
)
echo.

echo Backup completed successfully!
echo Location: %BACKUP_BASE_DIR%
echo.

exit /b 0
