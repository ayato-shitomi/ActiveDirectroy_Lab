# FILESRV Security Hardening Script
# Executed by SecurityHardening scheduled task after setup completion

$LogPath = "C:\ADLabLogs"
$ScriptPath = "C:\ADLabScripts"
$StateFile = "$LogPath\filesrv-state.txt"
$HardeningLogPath = "C:\Windows\Logs"
$DomainNetbios = "LAB"

# Ensure log directory exists
New-Item -ItemType Directory -Path $HardeningLogPath -Force -EA SilentlyContinue | Out-Null

# Start logging
Start-Transcript -Path "$HardeningLogPath\security-hardening.log" -Append

try {
    Write-Host "=== FILESRV Security Hardening Started ==="
    Write-Host "Timestamp: $(Get-Date)"

    # Check if setup is complete
    $currentState = $null
    if(Test-Path $StateFile) {
        $currentState = (Get-Content $StateFile -Raw -EA SilentlyContinue).Trim()
        Write-Host "Current state: $currentState"
    } else {
        Write-Warning "State file not found: $StateFile"
        Write-Host "Exiting - setup not completed"
        exit 0
    }

    # Only proceed if state is DONE
    if($currentState -ne "DONE") {
        Write-Host "State is not DONE ($currentState) - exiting"
        exit 0
    }

    Write-Host "Setup completed, proceeding with security hardening..."

    # Preserve current state before cleanup
    $newStateLocation = "$HardeningLogPath\filesrv-state.txt"
    if(Test-Path $StateFile) {
        Copy-Item $StateFile $newStateLocation -Force
        Write-Host "[OK] Preserved filesrv-state.txt in secure location: $newStateLocation"
    }

    # Harden config.json permissions - accessible only to service accounts and administrators
    $configPath = "$ScriptPath\config.json"
    if(Test-Path $configPath) {
        # Remove inheritance and set explicit permissions
        icacls $configPath /inheritance:d 2>&1 | Out-Null
        icacls $configPath /grant:r "Administrators:(F)" "SYSTEM:(F)" "$DomainNetbios\svc_backup:(R)" 2>&1 | Out-Null
        icacls $configPath /deny "$DomainNetbios\hasegawa:(F)" "$DomainNetbios\saitou:(F)" "Users:(F)" 2>&1 | Out-Null
        Write-Host "[OK] Hardened config.json permissions - blocked general user access while maintaining service functionality"

        # Verify permissions
        Write-Host "config.json final permissions:"
        icacls $configPath
    }

    # Remove temporary setup files (keep operational files for services)
    $tempFiles = @(
        "$LogPath\setup.log",
        "$LogPath\error.log",
        "$LogPath\audit-status.log",
        "$LogPath\secpol_*.cfg",
        "$LogPath\secedit_*.sdb",
        "$LogPath\download_error.log",
        "$LogPath\secedit_*.jfm"
    )

    $removedCount = 0
    foreach($pattern in $tempFiles) {
        Get-ChildItem $pattern -EA SilentlyContinue | ForEach-Object {
            Remove-Item $_.FullName -Force -EA SilentlyContinue
            Write-Host "[OK] Removed temporary file: $($_.Name)"
            $removedCount++
        }
    }
    Write-Host "[OK] Removed $removedCount temporary files"

    # Verify service-critical files remain accessible
    $serviceFiles = @(
        "$LogPath\svc_backup.ps1",
        "$configPath",
        "C:\Shares\Users\Hasegawa\check_event_number.bat"
    )

    foreach($file in $serviceFiles) {
        if(Test-Path $file) {
            Write-Host "[OK] Verified: $($file | Split-Path -Leaf) preserved for service functionality"
        } else {
            Write-Warning "[WARN] Service file not found: $file"
        }
    }

    # Verify state preservation
    if(Test-Path $newStateLocation) {
        $finalState = Get-Content $newStateLocation -Raw -EA SilentlyContinue
        Write-Host "[OK] State preserved: $($finalState.Trim())"
    }

    Write-Host "[SUCCESS] FILESRV security hardening completed!"
    Write-Host "- config.json: Protected from hasegawa/saitou access"
    Write-Host "- Temporary files: Removed"
    Write-Host "- Services: Maintained (svc_backup.ps1, CheckEventNumber preserved)"

    # Self-destruct: Remove this scheduled task after successful completion
    Write-Host "Removing SecurityHardening scheduled task..."
    Unregister-ScheduledTask -TaskName "SecurityHardening" -Confirm:$false -EA SilentlyContinue
    Write-Host "[OK] SecurityHardening task removed"

} catch {
    Write-Error "Security hardening failed: $_"
    $_ | Out-File "$HardeningLogPath\security-hardening-error.log" -Append -EA SilentlyContinue

    # In case of error, retry on next boot (don't remove task)
    Write-Host "[ERROR] Keeping SecurityHardening task for retry"
    exit 1
}

Stop-Transcript

Write-Host "=== FILESRV Security Hardening Completed Successfully ==="