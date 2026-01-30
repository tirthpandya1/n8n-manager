@echo off
setlocal enabledelayedexpansion

REM N8N API Import Script
REM Usage: import_via_api.bat [workflows_dir] [api_key] [n8n_url]

set "WORKFLOWS_DIR=%~1"
set "API_KEY=%~2"
set "N8N_URL=%~3"

if "%N8N_URL%"=="" set "N8N_URL=http://localhost:5678"

echo Importing workflows via n8n REST API...
echo Workflows directory: %WORKFLOWS_DIR%
echo n8n URL: %N8N_URL%
echo.

set "SUCCESS_COUNT=0"
set "FAIL_COUNT=0"

for %%f in ("%WORKFLOWS_DIR%\*.json") do (
    echo Importing: %%~nxf

    curl -X POST "%N8N_URL%/api/v1/workflows" ^
        -H "X-N8N-API-KEY: %API_KEY%" ^
        -H "Content-Type: application/json" ^
        --data-binary "@%%f" ^
        -s -o nul -w "%%{http_code}" > temp_status.txt

    set /p HTTP_STATUS=<temp_status.txt
    del temp_status.txt

    if "!HTTP_STATUS!"=="201" (
        echo   SUCCESS - Created
        set /a SUCCESS_COUNT+=1
    ) else if "!HTTP_STATUS!"=="200" (
        echo   SUCCESS - OK
        set /a SUCCESS_COUNT+=1
    ) else (
        echo   FAILED - HTTP !HTTP_STATUS!
        set /a FAIL_COUNT+=1
    )
)

echo.
echo ========================================
echo Import Summary:
echo   Success: %SUCCESS_COUNT%
echo   Failed: %FAIL_COUNT%
echo ========================================

if %FAIL_COUNT% GTR 0 (
    exit /b 1
) else (
    exit /b 0
)
