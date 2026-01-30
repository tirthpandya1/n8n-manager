@echo off
setlocal enabledelayedexpansion

REM N8N API Import Script for v2 - Cleans v1 workflow JSON
REM Usage: import_via_api_v2.bat [workflows_dir] [api_key] [n8n_url]

set "WORKFLOWS_DIR=%~1"
set "API_KEY=%~2"
set "N8N_URL=%~3"

if "%N8N_URL%"=="" set "N8N_URL=http://localhost:5678"

echo Importing workflows via n8n REST API (v2 compatible)...
echo Workflows directory: %WORKFLOWS_DIR%
echo n8n URL: %N8N_URL%
echo.

set "SUCCESS_COUNT=0"
set "FAIL_COUNT=0"
set "TEMP_JSON=%TEMP%\n8n_workflow_temp.json"

for %%f in ("%WORKFLOWS_DIR%\*.json") do (
    echo Importing: %%~nxf

    REM Use PowerShell to clean the JSON (remove id, createdAt, updatedAt, isArchived fields)
    powershell -Command "$json = Get-Content '%%f' | ConvertFrom-Json; $json.PSObject.Properties.Remove('id'); $json.PSObject.Properties.Remove('createdAt'); $json.PSObject.Properties.Remove('updatedAt'); $json.PSObject.Properties.Remove('isArchived'); $json | ConvertTo-Json -Depth 100 | Out-File -Encoding UTF8 '%TEMP_JSON%'"

    REM Post the cleaned JSON to the API
    curl -X POST "%N8N_URL%/api/v1/workflows" ^
        -H "X-N8N-API-KEY: %API_KEY%" ^
        -H "Content-Type: application/json" ^
        --data-binary "@%TEMP_JSON%" ^
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

REM Cleanup
if exist "%TEMP_JSON%" del "%TEMP_JSON%"

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
