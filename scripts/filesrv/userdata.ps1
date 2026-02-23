<powershell>
$ErrorActionPreference = "Continue"
$LogPath = "C:\ADLabLogs"
$ScriptPath = "C:\ADLabScripts"
New-Item -ItemType Directory -Path $LogPath, $ScriptPath -Force -EA SilentlyContinue | Out-Null
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
}
$config | ConvertTo-Json | Out-File "$ScriptPath\config.json" -Force

# Download scripts from GitHub repository
$baseUrl = "https://raw.githubusercontent.com/ayato-shitomi/ActiveDirectroy_Lab/refs/heads/main"
try {
    Write-Host "Downloading setup scripts from GitHub..."
    Invoke-WebRequest -Uri "$baseUrl/scripts/filesrv/setup.ps1" -OutFile "$ScriptPath\setup.ps1" -UseBasicParsing
    Write-Host "Downloaded setup.ps1"

    Invoke-WebRequest -Uri "$baseUrl/scripts/filesrv/backup_service.ps1" -OutFile "$LogPath\svc_backup.ps1" -UseBasicParsing
    Write-Host "Downloaded backup_service.ps1"
} catch {
    Write-Error "Failed to download scripts: $_"
    $_ | Out-File "$LogPath\download_error.log" -Append
}

# Create main scheduled task
$mainAction = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-EP Bypass -NoProfile -File $ScriptPath\setup.ps1"
$mainTrigger = New-ScheduledTaskTrigger -AtStartup
$mainTrigger.Delay = "PT60S"
$mainPrincipal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
$mainSettings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
Unregister-ScheduledTask -TaskName "ADSetup" -Confirm:$false -EA SilentlyContinue
Register-ScheduledTask -TaskName "ADSetup" -Action $mainAction -Trigger $mainTrigger -Principal $mainPrincipal -Settings $mainSettings -Force

# Run setup immediately
& "$ScriptPath\setup.ps1"
Stop-Transcript
</powershell>