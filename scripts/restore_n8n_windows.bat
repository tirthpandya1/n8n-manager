@echo off
setlocal enabledelayedexpansion

REM N8N Restore Script for Windows
REM Usage: restore_n8n_windows.bat [native|docker] [backup_name] [container_name]

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

echo Starting N8N Restore...
echo.

REM ============================================
REM Parse Arguments
REM ============================================

set "NON_INTERACTIVE=false"

:parse_args
if "%~1"=="" goto args_done
if "%~1"=="--non-interactive" (
    set "NON_INTERACTIVE=true"
    shift
    goto :parse_args
)
if /i "%~1"=="native" (
    set "INSTANCE_TYPE=native"
    if not "%~2"=="" (
        set "BACKUP_NAME=%~2"
        shift
    )
    shift
    goto :parse_args
)
if /i "%~1"=="docker" (
    set "INSTANCE_TYPE=docker"
    if not "%~2"=="" (
        set "BACKUP_NAME=%~2"
    )
    if not "%~3"=="" (
        set "CONTAINER_NAME=%~3"
    )
    shift
    goto :parse_args
)
if /i "%~1"=="-h" goto show_usage
if /i "%~1"=="--help" goto show_usage
if /i "%~1"=="/?" goto show_usage

shift
goto :parse_args

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

if "%INSTANCE_TYPE%"=="native" (
    call :check_native_n8n
) else (
    call :check_docker_container
)

if errorlevel 1 exit /b 1

REM ============================================
REM Detect N8N Version
REM ============================================

call :detect_n8n_version_and_user

REM ============================================
REM Prepare Backup
REM ============================================

call :prepare_backup
if errorlevel 1 exit /b 1

REM ============================================
REM Show Confirmation
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
        exit /b 0
    )
)

echo.

REM ============================================
REM Perform Restore
REM ============================================

call :restore_credentials
call :restore_workflows

REM ============================================
REM Cleanup and Finish
REM ============================================

if defined TEMP_EXTRACT_DIR (
    if exist "%TEMP_EXTRACT_DIR%" (
        echo Cleaning up temporary files...
        rmdir /s /q "%TEMP_EXTRACT_DIR%"
    )
)

echo.
echo Restore completed successfully!
echo.
echo Next steps:
echo 1. Open your n8n interface
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
echo Usage: %~nx0 [native^|docker] [backup_name] [container_name]
echo.
echo Options:
echo   native              Restore to native n8n installation
echo   docker              Restore to Docker n8n container
echo   backup_name         Name of backup to restore (optional - will show selector)
echo   container_name      Name of Docker container (optional - will show selector)
echo.
echo Examples:
echo   %~nx0 native
echo   %~nx0 docker
echo   %~nx0 native native_backup_20240115_143022
echo   %~nx0 docker docker_backup_20240115_143022
echo   %~nx0 docker docker_backup_20240115_143022 my-n8n
echo.
exit /b 0

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
        echo [!COUNTER!] !BASENAME! ^(tar.gz^)
    )
)

REM Add zip backups
for %%f in ("%BACKUP_BASE_DIR%\*.zip") do (
    if exist "%%f" (
        set /a COUNTER+=1
        set "BASENAME=%%~nf"
        set "BACKUP_!COUNTER!=!BASENAME!"
        echo [!COUNTER!] !BASENAME! ^(zip^)
    )
)

REM Add directory backups
for /d %%d in ("%BACKUP_BASE_DIR%\*_backup_*") do (
    set /a COUNTER+=1
    set "BASENAME=%%~nxd"
    set "BACKUP_!COUNTER!=!BASENAME!"
    echo [!COUNTER!] !BASENAME! ^(directory^)
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
REM Function: Check Native N8N
REM ============================================

:check_native_n8n
where n8n >nul 2>&1
if errorlevel 1 (
    echo ERROR: n8n command not found. Please install n8n globally.
    exit /b 1
)
set "N8N_CMD=n8n"
echo Native n8n installation found
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

REM If default container name, show selector
if "%CONTAINER_NAME%"=="n8n" (
  if "%NON_INTERACTIVE%"=="true" (
    echo Using default container name 'n8n' in non-interactive mode.
  ) else (
    echo Looking for n8n containers...
    echo.

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
      set "SELECTION="
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

      REM *** FIX START: Use CALL to force nested expansion ***
      call set "CONTAINER_NAME=%%CONTAINER_!SELECTION!%%"
      REM *** FIX END ***
      
      echo.
      echo Selected: !CONTAINER_NAME!
    )
  )
  echo.
)

REM Verify container exists
docker ps -a --format "{{.Names}}" | findstr "%CONTAINER_NAME%" >nul 2>&1
if errorlevel 1 (
  echo ERROR: Container '%CONTAINER_NAME%' not found.
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

echo Docker container '%CONTAINER_NAME%' is ready
goto :eof

REM ============================================
REM Function: Detect N8N Version and Get User ID
REM ============================================

:detect_n8n_version_and_user
set "N8N_VERSION="
set "N8N_MAJOR_VERSION="
set "USER_ID="
set "PROJECT_ID="

REM Get n8n version
if "%INSTANCE_TYPE%"=="docker" (
    for /f "tokens=*" %%v in ('docker exec %CONTAINER_NAME% n8n --version 2^>nul') do set "N8N_VERSION=%%v"
) else (
    for /f "tokens=*" %%v in ('%N8N_CMD% --version 2^>nul') do set "N8N_VERSION=%%v"
)

if not defined N8N_VERSION (
    echo WARNING: Could not detect n8n version
    goto :eof
)

echo Detected n8n version: %N8N_VERSION%

REM Extract major version (first digit before the dot)
for /f "tokens=1 delims=." %%a in ("%N8N_VERSION%") do set "N8N_MAJOR_VERSION=%%a"

REM Check if n8n v2 or higher (only if version was detected)
if defined N8N_MAJOR_VERSION (
    if %N8N_MAJOR_VERSION% GEQ 2 (
        echo n8n v2+ detected - getting owner information for imports

        REM Try to get owner credentials ID (owner credential is auto-created in v2)
        REM This is more reliable than trying to get user/project IDs
        if "%INSTANCE_TYPE%"=="docker" (
            echo Note: n8n v2 requires owner authentication for CLI imports
            echo Attempting import without explicit userId/projectId - n8n will auto-assign to owner
            REM Don't set USER_ID or PROJECT_ID - let n8n handle it
            REM The credentials import already worked, so the owner exists
        ) else (
            echo Note: n8n v2 requires owner authentication for CLI imports
            echo Attempting import without explicit userId/projectId - n8n will auto-assign to owner
        )
    ) else (
        echo n8n v1 detected - userId parameter not needed
    )
)

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

echo [DEBUG] Checking for:
echo   !COMPRESSED_BACKUP!
echo   !ZIP_BACKUP!
echo   !DIRECTORY_BACKUP!

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
REM Function: Restore Credentials
REM ============================================

:restore_credentials
set "CREDENTIALS_FILE=%BACKUP_DIR%\credentials.json"

if not exist "%CREDENTIALS_FILE%" (
    echo No credentials file found in backup
    goto :eof
)

echo Importing credentials...

if "%INSTANCE_TYPE%"=="native" (
    %N8N_CMD% import:credentials --input="%CREDENTIALS_FILE%"
    if errorlevel 1 (
        echo [WARNING] Failed to import credentials
        echo TIP: If you see 'Project' matching errors, ensure you have created an owner user in the n8n UI first.
    ) else (
        echo [SUCCESS] Credentials imported successfully
    )
) else (
    docker cp "%CREDENTIALS_FILE%" %CONTAINER_NAME%:/tmp/credentials_import.json
    docker exec -u node %CONTAINER_NAME% n8n import:credentials --input=/tmp/credentials_import.json

    if errorlevel 1 (
        echo [WARNING] Failed to import credentials (exit code: %ERRORLEVEL%)
        echo TIP: If you see 'Project' matching errors, ensure you have created an owner user in the n8n UI first.
        REM Try to cleanup anyway
        docker exec -u node %CONTAINER_NAME% rm -f /tmp/credentials_import.json 2>nul
    ) else (
        echo [SUCCESS] Credentials imported successfully
        REM Cleanup (ignore errors)
        docker exec -u node %CONTAINER_NAME% rm -f /tmp/credentials_import.json 2>nul
    )
)

goto :eof

REM ============================================
REM Function: Restore Workflows
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

if "%INSTANCE_TYPE%"=="native" (
    REM Build import command
    if defined USER_ID (
        echo Importing workflows for n8n v2 with User ID: %USER_ID%
        set "SUCCESS_COUNT=0"
        set "FAIL_COUNT=0"
        for %%f in ("%WORKFLOWS_DIR%\*.json") do (
            echo   Importing %%~nxf...
            %N8N_CMD% import:workflow --input="%%f" --userId=%USER_ID% >nul 2>&1
            if not errorlevel 1 (
                set /a SUCCESS_COUNT+=1
            ) else (
                echo   WARNING: Failed to import %%~nxf
                set /a FAIL_COUNT+=1
            )
        )
        echo Import summary: !SUCCESS_COUNT! succeeded, !FAIL_COUNT! failed
        if !FAIL_COUNT! equ 0 (
            echo Workflows imported successfully
        ) else (
            echo WARNING: Some workflows failed to import.
        )
    ) else (
        %N8N_CMD% import:workflow --separate --input="%WORKFLOWS_DIR%"
        if errorlevel 1 (
            echo ERROR: Failed to import workflows
            exit /b 1
        ) else (
            echo Workflows imported successfully
        )
    )
) else (
    docker exec -u node %CONTAINER_NAME% mkdir -p /tmp/workflows_import
    docker cp "%WORKFLOWS_DIR%\." %CONTAINER_NAME%:/tmp/workflows_import/

    REM Build import command - handle n8n v2 with USER_ID
    if defined USER_ID (
        echo Importing workflows to Docker for n8n v2 with User ID: %USER_ID%
        set "SUCCESS_COUNT=0"
        set "FAIL_COUNT=0"
        
        REM Loop through files in container
        for /f "tokens=*" %%f in ('docker exec -u node %CONTAINER_NAME% sh -c "ls /tmp/workflows_import/*.json"') do (
            echo   Importing %%~nxf...
            docker exec -u node %CONTAINER_NAME% n8n import:workflow --input="%%f" --userId=%USER_ID% >nul 2>&1
            if not errorlevel 1 (
                set /a SUCCESS_COUNT+=1
            ) else (
                echo   WARNING: Failed to import %%~nxf
                set /a FAIL_COUNT+=1
            )
        )
        echo Import summary: !SUCCESS_COUNT! succeeded, !FAIL_COUNT! failed
        if !FAIL_COUNT! equ 0 (
            set "IMPORT_STATUS=0"
        ) else (
            set "IMPORT_STATUS=1"
        )
    ) else (
        if defined N8N_MAJOR_VERSION (
            if %N8N_MAJOR_VERSION% GEQ 2 echo Importing workflows for n8n v2...
        )
        docker exec -u node %CONTAINER_NAME% n8n import:workflow --separate --input=/tmp/workflows_import
        set "IMPORT_STATUS=%ERRORLEVEL%"
    )

    if "%IMPORT_STATUS%" NEQ "0" (
        echo ERROR: Failed to import workflows
        REM Try to cleanup anyway
        docker exec -u node %CONTAINER_NAME% rm -rf /tmp/workflows_import 2>nul
        exit /b 1
    ) else (
        echo Workflows imported successfully
        REM Cleanup (ignore errors)
        docker exec -u node %CONTAINER_NAME% rm -rf /tmp/workflows_import 2>nul
    )
)

goto :eof
