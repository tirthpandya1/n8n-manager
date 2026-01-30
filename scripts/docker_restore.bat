@echo off
setlocal enabledelayedexpansion

REM Docker N8N Restore Helper Script for Windows
REM Usage: docker_restore.bat [backup_name] [container_name] [--recreate-container] [--non-interactive]

REM Get script directory
set "SCRIPT_DIR=%~dp0"
set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
for %%i in ("%SCRIPT_DIR%") do set "N8N_DIR=%%~dpi"
set "N8N_DIR=%N8N_DIR:~0,-1%"
set "BACKUP_BASE_DIR=%N8N_DIR%\backups"

REM Default values
set "BACKUP_NAME="
set "CONTAINER_NAME=n8n"
set "RECREATE_CONTAINER=false"
set "NON_INTERACTIVE=false"

REM Parse arguments
:parse_args
if "%~1"=="" goto args_done
if "%~1"=="--recreate-container" (
    set "RECREATE_CONTAINER=true"
    shift
    goto :parse_args
)
if "%~1"=="--non-interactive" (
    set "NON_INTERACTIVE=true"
    shift
    goto :parse_args
)
if not defined BACKUP_NAME (
    set "BACKUP_NAME=%~1"
    shift
    goto :parse_args
)
if not defined CONTAINER_NAME (
    set "CONTAINER_NAME=%~1"
    shift
    goto :parse_args
)
shift
goto :parse_args

:args_done

if not defined BACKUP_NAME (
    echo Usage: docker_restore.bat [backup_name] [container_name] [--recreate-container] [--non-interactive]
    exit /b 1
)

echo [INFO] Docker N8N Restore Helper v1.0.0
echo [INFO] =================================
echo [INFO] Backup: %BACKUP_NAME%
echo [INFO] Container: %CONTAINER_NAME%
echo [INFO] Recreate container: %RECREATE_CONTAINER%
echo [INFO] Non-interactive: %NON_INTERACTIVE%
echo.

REM Prepare Backup
REM Strip extensions from BACKUP_NAME if present
set "TEMP_NAME=%BACKUP_NAME%"
if "%TEMP_NAME:~-7%"==".tar.gz" set "TEMP_NAME=%TEMP_NAME:~0,-7%"
if "%TEMP_NAME:~-4%"==".zip" set "TEMP_NAME=%TEMP_NAME:~0,-4%"
set "CLEAN_BACKUP_NAME=%TEMP_NAME%"

set "TEMP_EXTRACT_DIR=%BACKUP_BASE_DIR%\temp_restore_%RANDOM%"
set "BACKUP_DIR="

if exist "%BACKUP_BASE_DIR%\%CLEAN_BACKUP_NAME%" (
    set "BACKUP_DIR=%BACKUP_BASE_DIR%\%CLEAN_BACKUP_NAME%"
) else if exist "%BACKUP_BASE_DIR%\%CLEAN_BACKUP_NAME%.tar.gz" (
    mkdir "!TEMP_EXTRACT_DIR!"
    echo [INFO] Extracting .tar.gz backup...
    tar -xzf "%BACKUP_BASE_DIR%\%CLEAN_BACKUP_NAME%.tar.gz" -C "!TEMP_EXTRACT_DIR!"
    for /d %%d in ("!TEMP_EXTRACT_DIR!\*") do set "BACKUP_DIR=%%d"
) else if exist "%BACKUP_BASE_DIR%\%CLEAN_BACKUP_NAME%.zip" (
    mkdir "!TEMP_EXTRACT_DIR!"
    echo [INFO] Extracting .zip backup...
    powershell -Command "Expand-Archive -Path '%BACKUP_BASE_DIR%\%CLEAN_BACKUP_NAME%.zip' -DestinationPath '!TEMP_EXTRACT_DIR!'"
    for /d %%d in ("!TEMP_EXTRACT_DIR!\*") do set "BACKUP_DIR=%%d"
)

if not defined BACKUP_DIR (
    echo [ERROR] Backup not found: %BACKUP_NAME%
    exit /b 1
)

REM Confirmation
if not "%NON_INTERACTIVE%"=="true" (
    set /p "CONFIRM=This will restore the backup to container '%CONTAINER_NAME%'. Continue? (y/N): "
    if /i not "!CONFIRM!"=="y" (
        echo [INFO] Restore cancelled.
        goto :cleanup
    )
)

REM Recreate container if requested
if "%RECREATE_CONTAINER%"=="true" (
    if exist "%BACKUP_DIR%\docker-compose.yml" (
        echo [INFO] Recreating container from docker-compose.yml...
        docker-compose -f "%BACKUP_DIR%\docker-compose.yml" up -d --force-recreate
    ) else (
        echo [WARNING] docker-compose.yml not found in backup. Skipping recreation.
    )
)

REM Run standard restore
echo [INFO] Running standard n8n restore...
set "EXTRA_FLAGS="
if "%NON_INTERACTIVE%"=="true" set "EXTRA_FLAGS=--non-interactive"

REM Try to find the standard backup folder inside enhanced backup
for /d %%d in ("%BACKUP_DIR%\docker_backup_*") do (
    set "STD_BACKUP_NAME=%%~nxd"
    REM Standard restore script expects the backup to be in the BACKUP_BASE_DIR
    REM So we might need to point it to the nested folder or move it temporarily
    move "%%d" "%BACKUP_BASE_DIR%\" >nul
    call "%SCRIPT_DIR%\restore_n8n_windows.bat" %EXTRA_FLAGS% docker "!STD_BACKUP_NAME!" %CONTAINER_NAME%
    move "%BACKUP_BASE_DIR%\!STD_BACKUP_NAME!" "%%d" >nul
    goto :std_done
)
echo [WARNING] Standard backup not found inside enhanced backup directory.
:std_done

echo [SUCCESS] Enhanced Docker restore completed!

:cleanup
if exist "!TEMP_EXTRACT_DIR!" (
    echo [INFO] Cleaning up temporary files...
    rmdir /s /q "!TEMP_EXTRACT_DIR!"
)

exit /b 0
