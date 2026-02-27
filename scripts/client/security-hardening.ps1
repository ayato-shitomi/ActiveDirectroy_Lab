# CLIENT Security Hardening Script
# Executed by SecurityHardening scheduled task after setup completion

$LogPath = "C:\ADLabLogs"
$ScriptPath = "C:\ADLabScripts"
$StateFile = "$LogPath\client-state.txt"
$HardeningLogPath = "C:\Windows\Logs"

# Ensure log directory exists
New-Item -ItemType Directory -Path $HardeningLogPath -Force -EA SilentlyContinue | Out-Null

# Start logging
Start-Transcript -Path "$HardeningLogPath\security-hardening.log" -Append

try {
    Write-Host "=== CLIENT Security Hardening Started ==="
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

    # Update StateFile path to secure location before cleanup
    $newStateLocation = "$HardeningLogPath\client-state.txt"

    # Backup current state before cleanup
    if(Test-Path $StateFile) {
        Copy-Item $StateFile $newStateLocation -Force
        Write-Host "[OK] Preserved client-state.txt in secure location: $newStateLocation"
    }

    # Remove sensitive directories containing credentials
    if(Test-Path $ScriptPath) {
        Remove-Item $ScriptPath -Recurse -Force -EA SilentlyContinue
        Write-Host "[OK] Removed $ScriptPath (contained config.json with admin passwords)"
    }

    if(Test-Path $LogPath) {
        Remove-Item $LogPath -Recurse -Force -EA SilentlyContinue
        Write-Host "[OK] Removed $LogPath (contained setup logs and temp files)"
    }

    # Verify state preservation
    if(Test-Path $newStateLocation) {
        $finalState = Get-Content $newStateLocation -Raw -EA SilentlyContinue
        Write-Host "[OK] State preserved: $($finalState.Trim())"
    }

    Write-Host "[SUCCESS] CLIENT security hardening completed!"
    Write-Host "- Sensitive credential files removed"
    Write-Host "- State preserved in secure location"

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

Write-Host "=== CLIENT Security Hardening Completed Successfully ==="