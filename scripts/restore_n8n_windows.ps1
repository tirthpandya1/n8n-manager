# PowerShell script to restore n8n backup
# Usage: .\restore_n8n_windows.ps1

Write-Host "Starting n8n restore process from Windows..." -ForegroundColor Blue

# Navigate to the n8n directory
Set-Location "C:\Users\Admin\Code\Projects\Voice-Agent-Platform-Final\voice-agent-platform\backend\n8n"

# Set environment variable to prevent path conversion issues
$env:MSYS_NO_PATHCONV = "1"

Write-Host "Attempting to restore backup: docker_backup_20250925_073104" -ForegroundColor Green
Write-Host "Target container: backend-n8n-1" -ForegroundColor Green

# Check if Docker is available
try {
    docker --version | Out-Null
    Write-Host "Docker is available" -ForegroundColor Green
} catch {
    Write-Host "Docker not found in PATH" -ForegroundColor Red
    exit 1
}

# Try to run the restore script using WSL
try {
    Write-Host "Using WSL to run restore script..." -ForegroundColor Yellow
    wsl bash -c "cd '/mnt/c/Users/Admin/Code/Projects/Voice-Agent-Platform-Final/voice-agent-platform/backend/n8n' && export MSYS_NO_PATHCONV=1 && ./scripts/restore_n8n.sh docker docker_backup_20250925_073104 backend-n8n-1"
} catch {
    Write-Host "Error running restore script: $_" -ForegroundColor Red
    
    # Alternative: Try to run Docker commands directly
    Write-Host "Attempting direct Docker restore..." -ForegroundColor Yellow
    
    # Check if container exists
    $containerExists = docker ps -a --format "{{.Names}}" | Select-String "^backend-n8n-1$"
    if ($containerExists) {
        Write-Host "Container backend-n8n-1 found" -ForegroundColor Green

        # Detect n8n version
        $n8nVersion = docker exec backend-n8n-1 n8n --version 2>$null | Select-Object -First 1
        Write-Host "Detected n8n version: $n8nVersion" -ForegroundColor Cyan

        # Check if n8n v2 or higher
        $userId = $null
        if ($n8nVersion -match "^(\d+)\.") {
            $majorVersion = [int]$matches[1]
            if ($majorVersion -ge 2) {
                Write-Host "n8n v2+ detected - will use userId parameter for imports" -ForegroundColor Cyan
                $userId = "00000000-0000-0000-0000-000000000000"
                Write-Host "Using default user ID for workflow import: $userId" -ForegroundColor Cyan
            } else {
                Write-Host "n8n v1 detected - userId parameter not needed" -ForegroundColor Cyan
            }
        }

        # Manual restore process
        $backupDir = "C:\Users\Admin\Code\Projects\Voice-Agent-Platform-Final\voice-agent-platform\backend\n8n\backups\docker_backup_20250925_073104"

        # Copy credentials
        if (Test-Path "$backupDir\credentials.json") {
            Write-Host "Copying credentials to container..." -ForegroundColor Yellow
            docker cp "$backupDir\credentials.json" "backend-n8n-1:/tmp/credentials_import.json"
            docker exec -u node backend-n8n-1 n8n import:credentials --input=/tmp/credentials_import.json
            docker exec -u node backend-n8n-1 rm -f /tmp/credentials_import.json
        }

        # Copy workflows
        if (Test-Path "$backupDir\workflows") {
            Write-Host "Copying workflows to container..." -ForegroundColor Yellow
            docker exec -u node backend-n8n-1 mkdir -p /tmp/workflows_import
            docker cp "$backupDir\workflows\." "backend-n8n-1:/tmp/workflows_import/"

            # Import workflows with userId if needed (n8n v2+)
            if ($userId) {
                Write-Host "Importing workflows with userId for n8n v2 compatibility..." -ForegroundColor Yellow
                docker exec -u node backend-n8n-1 n8n import:workflow --separate --input=/tmp/workflows_import --userId=$userId
            } else {
                docker exec -u node backend-n8n-1 n8n import:workflow --separate --input=/tmp/workflows_import
            }

            docker exec -u node backend-n8n-1 rm -rf /tmp/workflows_import
        }
        
        # Restart container
        Write-Host "Restarting container..." -ForegroundColor Yellow
        docker restart backend-n8n-1
        
        Write-Host "Restore completed successfully!" -ForegroundColor Green
    } else {
        Write-Host "Container backend-n8n-1 not found" -ForegroundColor Red
    }
}

Write-Host "Press any key to continue..."
$Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown") | Out-Null