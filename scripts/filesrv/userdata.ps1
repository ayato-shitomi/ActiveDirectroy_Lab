<powershell>
$ErrorActionPreference = "Continue"
$LogPath = "C:\ADLabLogs"
$ScriptPath = "C:\ADLabScripts"
New-Item -ItemType Directory -Path $LogPath, $ScriptPath -Force -EA SilentlyContinue | Out-Null
Start-Transcript -Path "$LogPath\userdata.log" -Append

# Save config - templatefile only used for variable substitution
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

# Build script dynamically to avoid templatefile parsing issues
$scriptBuilder = {
    # Build the main setup script content dynamically
    $mainScript = @'
$ErrorActionPreference="Continue"
$LogPath="C:\ADLabLogs"
$ScriptPath="C:\ADLabScripts"
$StateFile="$LogPath\filesrv-state.txt"
Start-Transcript -Path "$LogPath\setup.log" -Append
$c = Get-Content "$ScriptPath\config.json" | ConvertFrom-Json

function Get-State {
    if (Test-Path $StateFile) { return (Get-Content $StateFile -Raw).Trim() }
    "INIT"
}

function Set-State($s) {
    $s | Out-File $StateFile -Force
    Write-Host "State: $s"
}

function Test-DC {
    for ($i = 1; $i -le 40; $i++) {
        try {
            Resolve-DnsName -Name $c.DomainName -Server $c.DCIP -DnsOnly -EA Stop | Out-Null
            return $true
        }
        catch {
            Write-Host "Wait DC $i/40"
            Start-Sleep 15
        }
    }
    $false
}

try {
    $state = Get-State
    Write-Host "Current: $state"

    $adapter = Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | Select-Object -First 1
    if ($adapter) {
        Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ServerAddresses @($c.DCIP, "8.8.8.8")
    }

    switch ($state) {
        "INIT" {
            $password = ConvertTo-SecureString $c.AdminPassword -AsPlainText -Force
            Set-LocalUser -Name "Administrator" -Password $password
            Enable-LocalUser -Name "Administrator"
            Rename-Computer -NewName $c.ComputerName -Force
            Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled True
            Enable-NetFirewallRule -DisplayGroup "Remote Desktop" -EA SilentlyContinue
            Enable-NetFirewallRule -DisplayGroup "File and Printer Sharing" -EA SilentlyContinue
            Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name "fDenyTSConnections" -Value 0
            Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name "UserAuthentication" -Value 0
            Enable-PSRemoting -Force -SkipNetworkProfileCheck
            Set-Item WSMan:\localhost\Client\TrustedHosts -Value "*" -Force
            New-NetFirewallRule -DisplayName "WinRM-HTTP" -Direction Inbound -Protocol TCP -LocalPort 5985 -Action Allow -EA SilentlyContinue
            Write-Host "WinRM enabled"
            Set-State "WAIT"
            Restart-Computer -Force
            exit
        }
        "WAIT" {
            Write-Host "WAIT: Testing DC connectivity"
            Start-Sleep 30
            if (Test-DC) {
                Write-Host "DC is ready"
                Set-State "JOIN"
                Restart-Computer -Force
                exit
            } else {
                Write-Host "DC not ready"
                Restart-Computer -Force
                exit
            }
        }
        "JOIN" {
            Write-Host "JOIN: Domain join"
            $domainPassword = ConvertTo-SecureString $c.DomainPassword -AsPlainText -Force
            $credential = New-Object PSCredential("$($c.DomainName)\Administrator", $domainPassword)
            $joinSuccess = $false
            for ($i = 1; $i -le 10; $i++) {
                try {
                    Add-Computer -DomainName $c.DomainName -Credential $credential -Force -EA Stop
                    $joinSuccess = $true
                    Set-State "SHARE"
                    Restart-Computer -Force
                    exit
                }
                catch {
                    if ($i -lt 10) { Start-Sleep 60 }
                }
            }
            if (-not $joinSuccess) {
                Set-State "WAIT"
                Start-Sleep 300
                Restart-Computer -Force
                exit
            }
        }
        "SHARE" {
            Install-WindowsFeature -Name FS-FileServer -IncludeManagementTools
            Add-WindowsCapability -Online -Name "Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0" -EA SilentlyContinue

            # Wait for AD users
            for($i=1;$i -le 30;$i++){$allFound=$true;foreach($u in @("hasegawa","saitou")){try{$null=[ADSI]"WinNT://$($c.DomainNetbios)/$u,user"}catch{$allFound=$false;break}};if($allFound){break};Start-Sleep 10}

            # Add users to groups with verification
            foreach($u in @("hasegawa","saitou")){$m="$($c.DomainNetbios)\$u";for($r=1;$r -le 5;$r++){try{Add-LocalGroupMember -Group "Remote Desktop Users" -Member $m -EA Stop;Add-LocalGroupMember -Group "Remote Management Users" -Member $m -EA Stop;Write-Host "Added $u to RDP groups";break}catch{Write-Warning "Retry $r for $u";if($r -lt 5){Start-Sleep 10}}};if(-not(Get-LocalGroupMember -Group "Remote Desktop Users" -EA 0|?{$_.Name -like "*$u*"})){Write-Warning "CRITICAL: $u missing from RDP group"}}

            # Add svc_backup to administrators
            $svcMember = "$($c.DomainNetbios)\svc_backup"
            for ($retry = 1; $retry -le 3; $retry++) {
                try {
                    Add-LocalGroupMember -Group "Administrators" -Member $svcMember -EA SilentlyContinue
                    break
                }
                catch { Start-Sleep 5 }
            }

            # Create shares
            $shareRoot = "C:\Shares"
            @("Share", "Public", "Users\Hasegawa", "Users\Saitou") | ForEach-Object {
                New-Item -ItemType Directory -Path "$shareRoot\$_" -Force -EA SilentlyContinue
            }

            @("Share", "Public", "Hasegawa", "Saitou") | ForEach-Object {
                Remove-SmbShare -Name $_ -Force -EA SilentlyContinue
            }

            New-SmbShare -Name "Share" -Path "$shareRoot\Share" -FullAccess @("Everyone", "Administrators")
            New-SmbShare -Name "Public" -Path "$shareRoot\Public" -ReadAccess @("Everyone") -FullAccess @("Administrators")
            New-SmbShare -Name "Hasegawa" -Path "$shareRoot\Users\Hasegawa" -FullAccess @("$($c.DomainNetbios)\hasegawa", "Administrators")
            New-SmbShare -Name "Saitou" -Path "$shareRoot\Users\Saitou" -FullAccess @("$($c.DomainNetbios)\saitou", "Administrators")

            # Grant SeShutdownPrivilege to hasegawa
            $hAcc="$($c.DomainNetbios)\hasegawa";$hSid=$null
            for($i=1;$i -le 5;$i++){try{$hSid=(New-Object System.Security.Principal.NTAccount($hAcc)).Translate([System.Security.Principal.SecurityIdentifier]).Value;break}catch{Start-Sleep 5}}
            if($hSid){$cfg="$LogPath\secpol_shutdown.cfg";$db="$LogPath\secedit_shutdown.sdb";secedit /export /cfg $cfg /areas USER_RIGHTS 2>&1|Out-Null;$c2=Get-Content $cfg -Raw -Encoding Unicode -EA 0;if($c2 -match 'SeShutdownPrivilege\s*=\s*(.*)'){$cur=$matches[1].Trim();if($cur -notmatch $hSid){$c2=$c2 -replace 'SeShutdownPrivilege\s*=\s*.*',"SeShutdownPrivilege = $cur,*$hSid"}}else{$c2=$c2 -replace '\[Privilege Rights\]',"[Privilege Rights]`r`nSeShutdownPrivilege = *$hSid"};$c2|Set-Content $cfg -Encoding Unicode;secedit /configure /db $db /cfg $cfg /areas USER_RIGHTS 2>&1|Out-Null}

            # Create event bat file
            $batPath="$shareRoot\Users\Hasegawa\check_event_number.bat"
            @("@echo off","for /f %%a in ('powershell -Command `"(Get-WinEvent -LogName System -EA 0).Count`"') do set SYSCNT=%%a","for /f %%a in ('powershell -Command `"(Get-WinEvent -LogName Security -EA 0).Count`"') do set SECCNT=%%a","for /f %%a in ('powershell -Command `"(Get-WinEvent -LogName Application -EA 0).Count`"') do set APPCNT=%%a","echo %date% %time% - System:%SYSCNT% Security:%SECCNT% Application:%APPCNT% >> `"C:\Shares\Users\Hasegawa\event_number.log`"")-join"`r`n"|Out-File $batPath -Encoding ASCII

            # Set hasegawa ownership
            $hUser=$c.DomainNetbios+"\hasegawa"
            for($i=1;$i -le 3;$i++){try{icacls $batPath /setowner $hUser 2>&1|Out-Null;icacls $batPath /grant ($hUser+":(M)") 2>&1|Out-Null;break}catch{if($i -lt 3){Start-Sleep 10}}}

            # Create event task
            $ta=New-ScheduledTaskAction -Execute "cmd.exe" -Argument "/c `"$batPath`"";$tt=New-ScheduledTaskTrigger -AtStartup;$tt.Delay="PT60S";$tp=New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest;$ts=New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable;Register-ScheduledTask -TaskName "CheckEventNumber" -Action $ta -Trigger $tt -Principal $tp -Settings $ts -Force;schtasks /Change /TN "CheckEventNumber" /SD "D:(A;;FA;;;SY)(A;;FA;;;BA)(A;;GRGX;;;AU)" 2>&1|Out-Null

            Set-State "DONE"
        }
        "DONE" {
            Unregister-ScheduledTask -TaskName "ADSetup" -Confirm:$false -EA SilentlyContinue
        }
    }
}
catch {
    Write-Error $_
    $_ | Out-File "$LogPath\error.log" -Append
}
Stop-Transcript
'@

    # Create backup service script separately
    $backupScript = @'
for ($i = 1; $i -le 30; $i++) {
    if ((Get-Service lsass -EA 0).Status -eq 'Running' -and (Get-SmbShare Hasegawa -EA 0)) {
        break
    }
    Start-Sleep 5
}

try {
    $c = Get-Content 'C:\ADLabScripts\config.json' | ConvertFrom-Json
    $backupDir = "C:\Backup\Hasegawa\" + (Get-Date -Format "yyyy-MM-dd")
    New-Item -ItemType Directory -Path $backupDir -Force | Out-Null

    $credential = New-Object PSCredential("$($c.DomainNetbios)\svc_backup", ($c.SvcBackupPwd | ConvertTo-SecureString -AsPlainText -Force))

    if (Get-PSDrive H -EA 0) {
        Remove-PSDrive H -Force -EA 0
    }

    New-PSDrive H FileSystem "\\$env:COMPUTERNAME\Hasegawa" -Credential $credential -Scope Global | Out-Null
    Get-ChildItem H:\ -Filter *.log -Recurse -EA 0 | ForEach-Object {
        Copy-Item $_.FullName $backupDir -Force -EA 0
    }
    Remove-PSDrive H -Force -EA 0

    "Backup completed" | Out-File C:\ADLabLogs\backup.log -Append
}
catch {
    "Backup failed: $_" | Out-File C:\ADLabLogs\backup.log -Append
    Remove-PSDrive H -Force -EA 0
}
'@

    # Write scripts to files
    $mainScript | Out-File "$ScriptPath\setup.ps1" -Force
    $backupScript | Out-File "$LogPath\svc_backup.ps1" -Force
}

# Execute the script builder
& $scriptBuilder

# Create backup scheduled task
$backupAction = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-EP Bypass -File $LogPath\svc_backup.ps1"
$backupTrigger = New-ScheduledTaskTrigger -AtStartup
$backupTrigger.Delay = "PT180S"
$backupPrincipal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
Register-ScheduledTask -TaskName "LogBackup" -Action $backupAction -Trigger $backupTrigger -Principal $backupPrincipal -Force

# Create launcher
'Start-Sleep 10; & C:\ADLabScripts\setup.ps1' | Out-File "$ScriptPath\launcher.ps1" -Force

# Create main scheduled task
$mainAction = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-EP Bypass -NoProfile -File C:\ADLabScripts\launcher.ps1"
$mainTrigger = New-ScheduledTaskTrigger -AtStartup
$mainTrigger.Delay = "PT60S"
$mainPrincipal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
$mainSettings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
Unregister-ScheduledTask -TaskName "ADSetup" -Confirm:$false -EA SilentlyContinue
Register-ScheduledTask -TaskName "ADSetup" -Action $mainAction -Trigger $mainTrigger -Principal $mainPrincipal -Settings $mainSettings -Force

& "$ScriptPath\setup.ps1"
Stop-Transcript
</powershell>