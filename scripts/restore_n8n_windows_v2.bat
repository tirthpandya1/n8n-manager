@echo off
setlocal enabledelayedexpansion

REM N8N Restore Script for Windows with v2 API Support
REM Usage: restore_n8n_windows_v2.bat [native|docker] [backup_name] [container_name] [--api-key KEY]

REM Get script directory
set "SCRIPT_DIR=%~dp0"
set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
for %%i in ("%SCRIPT_DIR%") do set "N8N_DIR=%%~dpi"
set "N8N_DIR=%N8N_DIR:~0,-1%"
set "BACKUP_BASE_DIR=%N8N_DIR%\backups"

REM Default values
set "INSTANCE_TYPE="
set "CONTAINER_NAME=n8n"
set "BACKUP_NAME="
set "TEMP_EXTRACT_DIR="
set "API_KEY="
set "N8N_URL=http://localhost:5678"

echo ================================================================
echo N8N Restore Utility (v2 API Support)
echo ================================================================
echo.

REM ============================================
REM Parse Arguments
REM ============================================

:parse_args
if "%~1"=="" goto args_done
if /i "%~1"=="native" (
    set "INSTANCE_TYPE=native"
    shift
    goto parse_args
)
if /i "%~1"=="docker" (
    set "INSTANCE_TYPE=docker"
    shift
    goto parse_args
)
if /i "%~1"=="--non-interactive" (
    set "NON_INTERACTIVE=true"
    shift
    goto parse_args
)
if /i "%~1"=="--api-key" (
    set "API_KEY=%~2"
    shift
    shift
    goto parse_args
)
if /i "%~1"=="--url" (
    set "N8N_URL=%~2"
    shift
    shift
    goto parse_args
)
if /i "%~1"=="-h" goto show_usage
if /i "%~1"=="--help" goto show_usage
if /i "%~1"=="/?" goto show_usage
REM If not a flag, assume it's backup_name or container_name
if not defined BACKUP_NAME (
    set "BACKUP_NAME=%~1"
    shift
    goto parse_args
)
if not defined CONTAINER_NAME (
    set "CONTAINER_NAME=%~1"
    shift
    goto parse_args
)
shift
goto parse_args

:args_done

if "%INSTANCE_TYPE%"=="" goto show_usage

REM ============================================
REM Select Backup if not specified
REM ============================================

if "%BACKUP_NAME%"=="" (
    if "%NON_INTERACTIVE%"=="true" (
        echo ERROR: Backup name must be specified in non-interactive mode.
        exit /b 1
    )
    call :select_backup_interactive
    if errorlevel 1 exit /b 1
)

echo Instance type: %INSTANCE_TYPE%
echo Backup: %BACKUP_NAME%
if "%INSTANCE_TYPE%"=="docker" echo Container: %CONTAINER_NAME%
echo.

REM ============================================
REM Check Prerequisites
REM ============================================

if "%INSTANCE_TYPE%"=="docker" (
    call :check_docker_container
    if errorlevel 1 exit /b 1
) else (
    call :check_native_n8n
    if errorlevel 1 exit /b 1
)

REM ============================================
REM Detect N8N Version
REM ============================================

call :detect_n8n_version

REM ============================================
REM V2 API Key Prompt
REM ============================================

if defined N8N_IS_V2 (
    if not defined API_KEY (
        if "%NON_INTERACTIVE%"=="true" (
            echo n8n v2 detected. No API key provided, falling back to CLI restore...
        ) else (
            echo.
            echo ================================================================
            echo n8n v2 DETECTED
            echo ================================================================
            echo.
            echo For n8n v2, API-based restore is STRONGLY RECOMMENDED.
            echo.
            echo To use API restore, you need an API key:
            echo 1. Open http://localhost:5678 in your browser
            echo 2. Go to Settings ^> API
            echo 3. Create an API key
            echo 4. Copy the key
            echo.
            set /p "API_KEY=Enter API Key (or press Enter to use CLI restore): "
            echo.
        )
    )

    if defined API_KEY (
        echo Using API-based restore for n8n v2...
        call :restore_via_api
        goto :cleanup_and_exit
    ) else (
        if not "%NON_INTERACTIVE%"=="true" (
            echo WARNING: CLI restore may have issues with n8n v2
            echo Press Ctrl+C to cancel, or
            pause
        )
    )
)

REM ============================================
REM Prepare Backup (for CLI restore)
REM ============================================

call :prepare_backup
if errorlevel 1 exit /b 1

REM ============================================
REM CLI-Based Restore
REM ============================================

echo.
echo WARNING: This will import workflows and credentials to your n8n instance.
echo WARNING: Existing workflows with the same names may be overwritten!
echo.
if "%NON_INTERACTIVE%"=="true" (
    echo Proceeding with restore in non-interactive mode...
) else (
    set /p "CONFIRM=Are you sure you want to continue? (y/N): "

    if /i not "!CONFIRM!"=="y" (
        echo Restore cancelled by user.
        goto :cleanup_and_exit
    )
)

echo.
call :restore_credentials
call :restore_workflows

REM ============================================
REM Cleanup and Exit
REM ============================================

:cleanup_and_exit

if defined TEMP_EXTRACT_DIR (
    if exist "%TEMP_EXTRACT_DIR%" (
        echo Cleaning up temporary files...
        rmdir /s /q "%TEMP_EXTRACT_DIR%"
    )
)

echo.
echo ================================================================
echo Restore Process Completed
echo ================================================================
echo.
echo Next steps:
echo 1. Open your n8n interface at %N8N_URL%
echo 2. Verify that workflows are present and functional
echo 3. Test credentials by running a workflow
echo 4. Activate workflows as needed
echo.

if "%INSTANCE_TYPE%"=="docker" (
    echo Restarting n8n container...
    docker restart %CONTAINER_NAME%
    timeout /t 5 /nobreak >nul
    echo Container restarted.
)

exit /b 0

REM ============================================
REM Function: Show Usage
REM ============================================

:show_usage
echo Usage: %~nx0 [native^|docker] [backup_name] [container_name] [options]
echo.
echo Arguments:
echo   native/docker       Type of n8n installation
echo   backup_name         Name of backup to restore (optional - will show selector)
echo   container_name      Docker container name (default: n8n)
echo.
echo Options:
echo   --api-key KEY       n8n API key for v2 restore
echo   --url URL           n8n URL (default: http://localhost:5678)
echo.
echo Examples:
echo   %~nx0 docker
echo   %~nx0 docker docker_backup_20240115_143022
echo   %~nx0 docker docker_backup_20240115_143022 --api-key your_key_here
echo.
exit /b 0

REM ============================================
REM Function: Detect N8N Version
REM ============================================

:detect_n8n_version
set "N8N_VERSION="
set "N8N_MAJOR_VERSION="
set "N8N_IS_V2="

if "%INSTANCE_TYPE%"=="docker" (
    for /f "tokens=*" %%v in ('docker exec %CONTAINER_NAME% n8n --version 2^>nul') do set "N8N_VERSION=%%v"
) else (
    for /f "tokens=*" %%v in ('n8n --version 2^>nul') do set "N8N_VERSION=%%v"
)

if not defined N8N_VERSION (
    echo WARNING: Could not detect n8n version
    goto :eof
)

echo Detected n8n version: %N8N_VERSION%

REM Extract major version
for /f "tokens=1 delims=." %%a in ("%N8N_VERSION%") do set "N8N_MAJOR_VERSION=%%a"

if defined N8N_MAJOR_VERSION (
    if %N8N_MAJOR_VERSION% GEQ 2 (
        set "N8N_IS_V2=true"
        echo Status: n8n v2+ detected
    ) else (
        echo Status: n8n v1 detected
    )
)

goto :eof

REM ============================================
REM Function: Restore via API
REM ============================================

:restore_via_api
echo.
echo ================================================================
echo API-Based Restore (n8n v2)
echo ================================================================
echo.

REM Prepare backup directory
call :prepare_backup
if errorlevel 1 exit /b 1

REM Check if Python is available
python --version >nul 2>&1
if errorlevel 1 (
    echo ERROR: Python is not installed or not in PATH
    echo Please install Python 3 or use CLI restore
    exit /b 1
)

REM Fix workflows using credential mapper
echo Step 1: Fixing workflow credentials...
python "%SCRIPT_DIR%\fix_workflow_credentials.py" "%BACKUP_DIR%\credentials.json" "%BACKUP_DIR%\credentials.json" "%BACKUP_DIR%\workflows" "%BACKUP_DIR%\workflows_fixed"

if errorlevel 1 (
    echo WARNING: Credential fix failed, using original workflows
    set "WORKFLOWS_DIR=%BACKUP_DIR%\workflows"
) else (
    set "WORKFLOWS_DIR=%BACKUP_DIR%\workflows_fixed"
)

REM Import via API
echo.
echo Step 2: Importing workflows via API...
python "%SCRIPT_DIR%\bulk_import_api.py" "%WORKFLOWS_DIR%" "%API_KEY%" "%N8N_URL%"

if errorlevel 1 (
    echo ERROR: API import failed
    exit /b 1
)

echo.
echo ================================================================
echo API Restore Completed Successfully!
echo ================================================================

goto :eof

REM ============================================
REM Function: Select Backup Interactively
REM ============================================

:select_backup_interactive
echo Looking for available backups...
echo.

set "COUNTER=0"

REM Add compressed backups (.tar.gz)
for %%f in ("%BACKUP_BASE_DIR%\*.tar.gz") do (
    if exist "%%f" (
        set /a COUNTER+=1
        set "FILENAME=%%~nxf"
        REM Remove .tar.gz extension (remove last 7 characters)
        set "BASENAME=!FILENAME:~0,-7!"
        set "BACKUP_!COUNTER!=!BASENAME!"
        echo [!COUNTER!] !BASENAME! (tar.gz)
    )
)

REM Add zip backups
for %%f in ("%BACKUP_BASE_DIR%\*.zip") do (
    if exist "%%f" (
        set /a COUNTER+=1
        set "BASENAME=%%~nf"
        set "BACKUP_!COUNTER!=!BASENAME!"
        echo [!COUNTER!] !BASENAME! (zip)
    )
)

REM Add directory backups
for /d %%d in ("%BACKUP_BASE_DIR%\*_backup_*") do (
    set /a COUNTER+=1
    set "BASENAME=%%~nxd"
    set "BACKUP_!COUNTER!=!BASENAME!"
    echo [!COUNTER!] !BASENAME! (directory)
)

if %COUNTER%==0 (
    echo ERROR: No backups found in %BACKUP_BASE_DIR%
    exit /b 1
)

echo.
set /p "SELECTION=Select backup number (1-%COUNTER%): "

if not defined SELECTION (
    echo ERROR: No selection made.
    exit /b 1
)

if %SELECTION% lss 1 (
    echo ERROR: Invalid selection.
    exit /b 1
)

if %SELECTION% gtr %COUNTER% (
    echo ERROR: Invalid selection.
    exit /b 1
)

set "BACKUP_NAME=!BACKUP_%SELECTION%!"
echo.
echo Selected backup: %BACKUP_NAME%
echo.

goto :eof

REM ============================================
REM Function: Check Docker Container
REM ============================================

:check_docker_container
where docker >nul 2>&1
if errorlevel 1 (
    echo ERROR: Docker not found.
    exit /b 1
)

docker ps -a --format "{{.Names}}" | findstr /x "%CONTAINER_NAME%" >nul 2>&1
if errorlevel 1 (
    echo ERROR: Container '%CONTAINER_NAME%' not found.
    exit /b 1
)

docker ps --format "{{.Names}}" | findstr /x "%CONTAINER_NAME%" >nul 2>&1
if errorlevel 1 (
    echo WARNING: Container '%CONTAINER_NAME%' exists but is not running.
    echo Starting container...
    docker start %CONTAINER_NAME%
    timeout /t 3 /nobreak >nul
)

echo Docker container '%CONTAINER_NAME%' is ready
goto :eof

REM ============================================
REM Function: Check Native N8N
REM ============================================

:check_native_n8n
where n8n >nul 2>&1
if errorlevel 1 (
    echo ERROR: n8n command not found. Please install n8n globally.
    exit /b 1
)
echo Native n8n installation found
goto :eof

REM ============================================
REM Function: Prepare Backup
REM ============================================

:prepare_backup
REM Strip extensions from BACKUP_NAME if present
set "TEMP_NAME=%BACKUP_NAME%"
if "%TEMP_NAME:~-7%"==".tar.gz" set "TEMP_NAME=%TEMP_NAME:~0,-7%"
if "%TEMP_NAME:~-4%"==".zip" set "TEMP_NAME=%TEMP_NAME:~0,-4%"
set "CLEAN_BACKUP_NAME=%TEMP_NAME%"

set "COMPRESSED_BACKUP=%BACKUP_BASE_DIR%\%CLEAN_BACKUP_NAME%.tar.gz"
set "ZIP_BACKUP=%BACKUP_BASE_DIR%\%CLEAN_BACKUP_NAME%.zip"
set "DIRECTORY_BACKUP=%BACKUP_BASE_DIR%\%CLEAN_BACKUP_NAME%"
set "BACKUP_DIR="

REM Check for compressed backup
if exist "%COMPRESSED_BACKUP%" (
    echo Found compressed backup: %COMPRESSED_BACKUP%
    echo Extracting backup...

    set "TEMP_EXTRACT_DIR=%BACKUP_BASE_DIR%\temp_extract_%RANDOM%"
    mkdir "!TEMP_EXTRACT_DIR!"

    where tar >nul 2>&1
    if !errorlevel!==0 (
        tar -xzf "%COMPRESSED_BACKUP%" -C "!TEMP_EXTRACT_DIR!"
        set "BACKUP_DIR=!TEMP_EXTRACT_DIR!\%CLEAN_BACKUP_NAME%"
    ) else (
        echo ERROR: tar command not found. Cannot extract .tar.gz files.
        exit /b 1
    )

    goto backup_prepared
)

REM Check for zip backup
if exist "%ZIP_BACKUP%" (
    echo Found zip backup: %ZIP_BACKUP%
    echo Extracting backup...

    set "TEMP_EXTRACT_DIR=%BACKUP_BASE_DIR%\temp_extract_%RANDOM%"
    mkdir "!TEMP_EXTRACT_DIR!"

    powershell -Command "Expand-Archive -Path '%ZIP_BACKUP%' -DestinationPath '!TEMP_EXTRACT_DIR!'" >nul 2>&1
    if !errorlevel!==0 (
        set "BACKUP_DIR=!TEMP_EXTRACT_DIR!\%CLEAN_BACKUP_NAME%"
    ) else (
        echo ERROR: Failed to extract zip backup.
        exit /b 1
    )

    goto backup_prepared
)

REM Check for directory backup
if exist "%DIRECTORY_BACKUP%" (
    echo Found directory backup: %DIRECTORY_BACKUP%
    set "BACKUP_DIR=%DIRECTORY_BACKUP%"
    goto backup_prepared
)

echo ERROR: Backup not found: %BACKUP_NAME%
exit /b 1

:backup_prepared
if not exist "%BACKUP_DIR%\workflows" (
    echo ERROR: Invalid backup - workflows directory not found
    exit /b 1
)

echo Backup prepared successfully
goto :eof

REM ============================================
REM Function: Restore Credentials (CLI)
REM ============================================

:restore_credentials
set "CREDENTIALS_FILE=%BACKUP_DIR%\credentials.json"

if not exist "%CREDENTIALS_FILE%" (
    echo No credentials file found in backup
    goto :eof
)

echo Importing credentials...

if "%INSTANCE_TYPE%"=="docker" (
    docker cp "%CREDENTIALS_FILE%" %CONTAINER_NAME%:/tmp/credentials_import.json
    docker exec -u node %CONTAINER_NAME% n8n import:credentials --input=/tmp/credentials_import.json

    if errorlevel 1 (
        echo WARNING: Failed to import credentials
    ) else (
        echo Credentials imported successfully
    )
    docker exec -u node %CONTAINER_NAME% rm -f /tmp/credentials_import.json 2>nul
) else (
    n8n import:credentials --input="%CREDENTIALS_FILE%"
    if errorlevel 1 (
        echo WARNING: Failed to import credentials
    ) else (
        echo Credentials imported successfully
    )
)

goto :eof

REM ============================================
REM Function: Restore Workflows (CLI)
REM ============================================

:restore_workflows
set "WORKFLOWS_DIR=%BACKUP_DIR%\workflows"

if not exist "%WORKFLOWS_DIR%" (
    echo No workflows found in backup
    goto :eof
)

set "WORKFLOW_COUNT=0"
for /f %%i in ('dir /b /a-d "%WORKFLOWS_DIR%\*.json" 2^>nul ^| find /c /v ""') do set "WORKFLOW_COUNT=%%i"

if %WORKFLOW_COUNT%==0 (
    echo No workflows found in backup
    goto :eof
)

echo Importing %WORKFLOW_COUNT% workflows...

if "%INSTANCE_TYPE%"=="docker" (
    docker exec -u node %CONTAINER_NAME% mkdir -p /tmp/workflows_import
    docker cp "%WORKFLOWS_DIR%\." %CONTAINER_NAME%:/tmp/workflows_import/
    docker exec -u node %CONTAINER_NAME% n8n import:workflow --separate --input=/tmp/workflows_import

    if errorlevel 1 (
        echo ERROR: Failed to import workflows
    ) else (
        echo Workflows imported successfully
    )
    docker exec -u node %CONTAINER_NAME% rm -rf /tmp/workflows_import 2>nul
) else (
    n8n import:workflow --separate --input="%WORKFLOWS_DIR%"
    if errorlevel 1 (
        echo ERROR: Failed to import workflows
    ) else (
        echo Workflows imported successfully
    )
)

goto :eof
