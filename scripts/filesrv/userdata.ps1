<powershell>
$ErrorActionPreference = "Continue"
$LogPath = "C:\ADLabLogs"
$ScriptPath = "C:\ADLabScripts"
New-Item -ItemType Directory -Path $LogPath, $ScriptPath -Force -EA SilentlyContinue | Out-Null

# Directory security disabled temporarily for debugging
Write-Host "Setup directories created - security to be applied later"

Start-Transcript -Path "$LogPath\userdata.log" -Append

# Save config - only variable substitution
$config = @{
    AdminPassword = "${admin_password}"
    DomainName = "${domain_name}"
    DomainNetbios = "${domain_netbios}"
    DomainPassword = "${domain_password}"
    DCIP = "${dc_ip}"
    ComputerName = "${computer_name}"
    SvcBackupPwd = "${svc_backup_password}"
    FlagFilesrvAdmin = "${flag_filesrv_admin}"
    FlagFilesrvHasegawa = "${flag_filesrv_hasegawa}"
    FlagFilesrvSaitou = "${flag_filesrv_saitou}"
}
$config | ConvertTo-Json | Out-File "$ScriptPath\config.json" -Force

# Download scripts from GitHub repository with retry logic
$baseUrl = "https://raw.githubusercontent.com/ayato-shitomi/ActiveDirectroy_Lab/refs/heads/main"
$downloadSuccess = $false

for($retry = 1; $retry -le 3; $retry++) {
    try {
        Write-Host "Downloading setup scripts from GitHub (attempt $retry/3)..."
        # Add TLS 1.2 support for older Windows versions
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri "$baseUrl/scripts/filesrv/setup.ps1" -OutFile "$ScriptPath\setup.ps1" -UseBasicParsing -TimeoutSec 30 -MaximumRedirection 5
        Write-Host "Downloaded setup.ps1"

        Invoke-WebRequest -Uri "$baseUrl/scripts/filesrv/backup_service.ps1" -OutFile "$LogPath\svc_backup.ps1" -UseBasicParsing -TimeoutSec 30 -MaximumRedirection 5
        Write-Host "Downloaded backup_service.ps1"

        # Verify files exist and have content
        if((Test-Path "$ScriptPath\setup.ps1") -and (Test-Path "$LogPath\svc_backup.ps1") -and
           ((Get-Item "$ScriptPath\setup.ps1").Length -gt 0) -and ((Get-Item "$LogPath\svc_backup.ps1").Length -gt 0)) {
            $downloadSuccess = $true
            Write-Host "All scripts downloaded successfully"
            break
        }
    } catch {
        Write-Warning "Download attempt $retry failed: $_"
        $_ | Out-File "$LogPath\download_error.log" -Append
        if($retry -lt 3) { Start-Sleep 10 }
    }
}

if(-not $downloadSuccess) {
    Write-Error "Failed to download required scripts after 3 attempts. Deployment cannot continue."
    "$(Get-Date): CRITICAL - Script download failed, deployment aborted" | Out-File "$LogPath\deployment_failure.log" -Append
    Stop-Transcript
    exit 1
}

# Create main scheduled task
$mainAction = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-EP Bypass -NoProfile -File $ScriptPath\setup.ps1"
$mainTrigger = New-ScheduledTaskTrigger -AtStartup
$mainTrigger.Delay = "PT60S"
$mainPrincipal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
$mainSettings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
Unregister-ScheduledTask -TaskName "ADSetup" -Confirm:$false -EA SilentlyContinue
Register-ScheduledTask -TaskName "ADSetup" -Action $mainAction -Trigger $mainTrigger -Principal $mainPrincipal -Settings $mainSettings -Force

# Run setup only if download was successful
Write-Host "Starting setup execution..."
& "$ScriptPath\setup.ps1"
Stop-Transcript
</powershell>