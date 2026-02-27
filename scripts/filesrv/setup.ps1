# FILESRV Main Setup Script
$ErrorActionPreference="Continue"
$LogPath="C:\ADLabLogs";$ScriptPath="C:\ADLabScripts";$StateFile="$LogPath\filesrv-state.txt"
Start-Transcript -Path "$LogPath\setup.log" -Append
$c=Get-Content "$ScriptPath\config.json"|ConvertFrom-Json
function Get-State{if(Test-Path $StateFile){return(Get-Content $StateFile -Raw).Trim()};"INIT"}
function Set-State($s){$s|Out-File $StateFile -Force;Write-Host "State: $s"}
function Test-DC{for($i=1;$i -le 40;$i++){try{Resolve-DnsName -Name $c.DomainName -Server $c.DCIP -DnsOnly -EA Stop|Out-Null;return $true}catch{Write-Host "Wait DC $i/40";Start-Sleep 15}};$false}
try{
$state=Get-State;Write-Host "Current: $state"
$a=Get-NetAdapter|?{$_.Status -eq "Up"}|Select -First 1
if($a){Set-DnsClientServerAddress -InterfaceIndex $a.ifIndex -ServerAddresses @($c.DCIP,"8.8.8.8")}
switch($state){
"INIT"{
$p=ConvertTo-SecureString $c.AdminPassword -AsPlainText -Force
Set-LocalUser -Name "Administrator" -Password $p;Enable-LocalUser -Name "Administrator"
Rename-Computer -NewName $c.ComputerName -Force
Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled True
Enable-NetFirewallRule -DisplayGroup "Remote Desktop" -EA SilentlyContinue
Enable-NetFirewallRule -DisplayGroup "File and Printer Sharing" -EA SilentlyContinue
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name "fDenyTSConnections" -Value 0
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name "UserAuthentication" -Value 0
Enable-PSRemoting -Force -SkipNetworkProfileCheck
Set-Item WSMan:\localhost\Client\TrustedHosts -Value "*" -Force
New-NetFirewallRule -DisplayName "WinRM-HTTP" -Direction Inbound -Protocol TCP -LocalPort 5985 -Action Allow -EA SilentlyContinue
New-NetFirewallRule -DisplayName "WinRM-HTTPS" -Direction Inbound -Protocol TCP -LocalPort 5986 -Action Allow -EA SilentlyContinue
Write-Host "WinRM enabled"
Set-State "WAIT";Restart-Computer -Force;exit}
"WAIT"{
Write-Host "WAIT: Testing DC connectivity"
Start-Sleep 30
if(Test-DC){
Write-Host "DC is ready, proceeding to domain join"
Set-State "JOIN";Restart-Computer -Force;exit
}else{
Write-Host "DC not ready, restarting"
Restart-Computer -Force;exit}}
"JOIN"{
Write-Host "JOIN: Attempting domain join to $($c.DomainName)"
$p=ConvertTo-SecureString $c.DomainPassword -AsPlainText -Force
$cred=New-Object PSCredential("$($c.DomainName)\Administrator",$p)
$joinSuccess=$false
for($i=1;$i -le 10;$i++){
try{
Write-Host "Domain join attempt $i/10 to $($c.DomainName)"
Add-Computer -DomainName $c.DomainName -Credential $cred -Force -EA Stop
$joinSuccess=$true
Write-Host "Domain join successful!"
Set-State "SHARE";Restart-Computer -Force;exit
}catch{
Write-Warning "Join attempt $i failed: $_"
if($i -lt 10){Start-Sleep 60}}}
if(-not $joinSuccess){
Write-Error "All domain join attempts failed. Returning to WAIT state."
Set-State "WAIT"
Start-Sleep 300
Restart-Computer -Force;exit
}
Restart-Computer -Force;exit}
"SHARE"{
Install-WindowsFeature -Name FS-FileServer -IncludeManagementTools
Write-Host "Installing RSAT AD Tools..."
Add-WindowsCapability -Online -Name "Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0" -EA SilentlyContinue
Write-Host "Waiting for AD users to be available..."
$adUsers=@("hasegawa","saitou")
for($i=1;$i -le 30;$i++){
$allFound=$true
foreach($u in $adUsers){try{$null=[ADSI]"WinNT://$($c.DomainNetbios)/$u,user"}catch{$allFound=$false;break}}
if($allFound){Write-Host "All AD users found";break}
Write-Host "Waiting for AD users... $i/30";Start-Sleep 10}
foreach($u in $adUsers){
$member="$($c.DomainNetbios)\$u"
for($retry=1;$retry -le 3;$retry++){
try{
Add-LocalGroupMember -Group "Remote Desktop Users" -Member $member -EA SilentlyContinue
Add-LocalGroupMember -Group "Remote Management Users" -Member $member -EA SilentlyContinue
Write-Host "Added $member to Remote Desktop Users and Remote Management Users"
break
}catch{Write-Warning "Retry $retry for $member : $_";Start-Sleep 5}}}
# Add svc_backup to local administrators for service access
$svcBackupMember="$($c.DomainNetbios)\svc_backup"
for($retry=1;$retry -le 3;$retry++){
try{
Add-LocalGroupMember -Group "Administrators" -Member $svcBackupMember -EA SilentlyContinue
Write-Host "Added $svcBackupMember to local Administrators group"
break
}catch{Write-Warning "Retry $retry for adding $svcBackupMember to Administrators : $_";Start-Sleep 5}}
Write-Host "Granting SeShutdownPrivilege to hasegawa..."
$hasegawaAccount = "$($c.DomainNetbios)\hasegawa"
$hasegawaSid=$null
for($i=1;$i -le 5;$i++){
try{$hasegawaSid=(New-Object System.Security.Principal.NTAccount($hasegawaAccount)).Translate([System.Security.Principal.SecurityIdentifier]).Value;break}
catch{Write-Warning "SID lookup retry $i : $_";Start-Sleep 5}}
if(-not $hasegawaSid){Write-Warning "Failed to get hasegawa SID, skipping privilege grant"}else{
Write-Host "hasegawa SID: $hasegawaSid"
$tmpCfg = "$LogPath\secpol_shutdown.cfg"
$tmpDb = "$LogPath\secedit_shutdown.sdb"
secedit /export /cfg $tmpCfg /areas USER_RIGHTS 2>&1 | Out-Null
$cfg = Get-Content $tmpCfg -Raw -Encoding Unicode -EA SilentlyContinue
if($cfg -match 'SeShutdownPrivilege\s*=\s*(.*)'){
$cur = $matches[1].Trim()
if($cur -notmatch $hasegawaSid){$cfg = $cfg -replace 'SeShutdownPrivilege\s*=\s*.*', "SeShutdownPrivilege = $cur,*$hasegawaSid"}
}else{
$cfg = $cfg -replace '\[Privilege Rights\]', "[Privilege Rights]`r`nSeShutdownPrivilege = *$hasegawaSid"
}
$cfg | Set-Content $tmpCfg -Encoding Unicode
secedit /configure /db $tmpDb /cfg $tmpCfg /areas USER_RIGHTS 2>&1 | Out-Null
Write-Host "SeShutdownPrivilege granted to hasegawa"}
$shareRoot = "C:\Shares"
Write-Host "Creating share directories..."
New-Item -ItemType Directory -Path "$shareRoot\Share" -Force -EA SilentlyContinue
New-Item -ItemType Directory -Path "$shareRoot\Public" -Force -EA SilentlyContinue
New-Item -ItemType Directory -Path "$shareRoot\Users\Hasegawa" -Force -EA SilentlyContinue
New-Item -ItemType Directory -Path "$shareRoot\Users\Saitou" -Force -EA SilentlyContinue
Write-Host "Creating SMB shares..."
Remove-SmbShare -Name "Share" -Force -EA SilentlyContinue
New-SmbShare -Name "Share" -Path "$shareRoot\Share" -FullAccess @("Everyone","Administrators")
Remove-SmbShare -Name "Public" -Force -EA SilentlyContinue
New-SmbShare -Name "Public" -Path "$shareRoot\Public" -ReadAccess @("Everyone") -FullAccess @("Administrators")
Remove-SmbShare -Name "Hasegawa" -Force -EA SilentlyContinue
New-SmbShare -Name "Hasegawa" -Path "$shareRoot\Users\Hasegawa" -FullAccess @("$($c.DomainNetbios)\hasegawa","Administrators")
Remove-SmbShare -Name "Saitou" -Force -EA SilentlyContinue
New-SmbShare -Name "Saitou" -Path "$shareRoot\Users\Saitou" -FullAccess @("$($c.DomainNetbios)\saitou","Administrators")
Write-Host "Creating check_event_number.bat for hasegawa..."
$batPath="$shareRoot\Users\Hasegawa\check_event_number.bat"
$batLines=@("@echo off","for /f %%a in ('powershell -Command `"(Get-WinEvent -LogName System -EA SilentlyContinue).Count`"') do set SYSCNT=%%a","for /f %%a in ('powershell -Command `"(Get-WinEvent -LogName Security -EA SilentlyContinue).Count`"') do set SECCNT=%%a","for /f %%a in ('powershell -Command `"(Get-WinEvent -LogName Application -EA SilentlyContinue).Count`"') do set APPCNT=%%a","echo %date% %time% - System:%SYSCNT% Security:%SECCNT% Application:%APPCNT% >> `"C:\Shares\Users\Hasegawa\event_number.log`"")
$batLines -join "`r`n"|Out-File $batPath -Encoding ASCII
$hasegawaUser = $c.DomainNetbios + "\hasegawa"
for($i=1; $i -le 3; $i++) {
    try {
        icacls $batPath /setowner $hasegawaUser 2>&1 | Out-Null
        $grantArg = $hasegawaUser + ":(M)"
        icacls $batPath /grant $grantArg 2>&1 | Out-Null
        Write-Host "Set owner of check_event_number.bat to hasegawa (attempt $i)"
        break
    } catch {
        Write-Warning "Failed to set hasegawa ownership attempt $i : $_"
        if($i -lt 3) { Start-Sleep 10 }
    }
}
$ta=New-ScheduledTaskAction -Execute "cmd.exe" -Argument "/c `"$batPath`""
$tt=New-ScheduledTaskTrigger -AtStartup;$tt.Delay="PT60S"
$tp=New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
$ts=New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
Register-ScheduledTask -TaskName "CheckEventNumber" -Action $ta -Trigger $tt -Principal $tp -Settings $ts -Force
$taskSddl = "D:(A;;FA;;;SY)(A;;FA;;;BA)(A;;GRGX;;;AU)"
schtasks /Change /TN "CheckEventNumber" /SD $taskSddl 2>&1 | Out-Null

# Grant hasegawa read permissions to view scheduled tasks
try {
    icacls "C:\Windows\System32\Tasks\" /grant "$($c.DomainNetbios)\hasegawa:R" 2>&1 | Out-Null
    icacls "C:\Windows\System32\Tasks\CheckEventNumber" /grant "$($c.DomainNetbios)\hasegawa:R" 2>&1 | Out-Null
    Write-Host "Granted hasegawa read permissions to view CheckEventNumber task"
} catch {
    Write-Warning "Failed to grant task permissions to hasegawa: $_"
}

Write-Host "Created check_event_number.bat and CheckEventNumber scheduled task"

# Register svc_backup Windows service (credentials stored in LSA Secrets)
Write-Host "Registering svc_backup Windows service..."
sc.exe delete HasegawaBackup 2>&1|Out-Null
$svcBinary="PowerShell.exe -EP Bypass -NoProfile -File C:\ADLabLogs\svc_backup.ps1"
$svcAccount="$($c.DomainNetbios)\svc_backup"
sc.exe create HasegawaBackup binPath= $svcBinary obj= $svcAccount password= $c.SvcBackupPwd start= delayed-auto 2>&1|Out-Null
sc.exe description HasegawaBackup "Hasegawa Log Backup Service" 2>&1|Out-Null
sc.exe failure HasegawaBackup reset= 3600 actions= restart/60000/restart/60000/restart/60000 2>&1|Out-Null
Write-Host "Registered HasegawaBackup service as $svcAccount"

# Create flag files on user desktops
Write-Host "Creating flag files on user desktops..."
# Administrator desktop
$adminDesktop = "C:\Users\Administrator\Desktop"
New-Item -ItemType Directory -Path $adminDesktop -Force -EA SilentlyContinue | Out-Null
$c.FlagFilesrvAdmin | Out-File "$adminDesktop\flag.txt" -Encoding UTF8
Write-Host "Created Administrator flag file"

# Domain user desktops (create directories first as they may not exist yet)
$hasegawaDesktop = "C:\Users\hasegawa\Desktop"
$saitouDesktop = "C:\Users\saitou\Desktop"
New-Item -ItemType Directory -Path $hasegawaDesktop -Force -EA SilentlyContinue | Out-Null
New-Item -ItemType Directory -Path $saitouDesktop -Force -EA SilentlyContinue | Out-Null
$c.FlagFilesrvHasegawa | Out-File "$hasegawaDesktop\flag.txt" -Encoding UTF8
$c.FlagFilesrvSaitou | Out-File "$saitouDesktop\flag.txt" -Encoding UTF8
Write-Host "Created hasegawa and saitou flag files"

# Set proper ownership for domain user directories
for($retry = 1; $retry -le 3; $retry++) {
    try {
        icacls $hasegawaDesktop /setowner "$($c.DomainNetbios)\hasegawa" /T 2>&1 | Out-Null
        icacls "$hasegawaDesktop\flag.txt" /setowner "$($c.DomainNetbios)\hasegawa" 2>&1 | Out-Null
        icacls $saitouDesktop /setowner "$($c.DomainNetbios)\saitou" /T 2>&1 | Out-Null
        icacls "$saitouDesktop\flag.txt" /setowner "$($c.DomainNetbios)\saitou" 2>&1 | Out-Null
        Write-Host "Set proper ownership for domain user flag files"
        break
    } catch {
        Write-Warning "Failed to set ownership attempt $retry : $_"
        if($retry -lt 3) { Start-Sleep 10 }
    }
}

# Configure File System SACL for C:\Shares monitoring
Write-Host "Configuring File System SACL for C:\Shares access monitoring..."
try {
    $sharesPath = "C:\Shares"
    if(Test-Path $sharesPath) {
        # Set SACL on C:\Shares to monitor all access
        icacls "$sharesPath" /audit "(Everyone):(OI)(CI)(F)" 2>&1 | Out-Null
        Write-Host "[OK] File System SACL configured for C:\Shares monitoring"

        # Also set SACL on subdirectories
        Get-ChildItem "$sharesPath" -Directory -EA SilentlyContinue | ForEach-Object {
            icacls "$($_.FullName)" /audit "(Everyone):(OI)(CI)(F)" 2>&1 | Out-Null
        }
        Write-Host "[OK] File System SACL configured for C:\Shares subdirectories"
    }
} catch {
    Write-Warning "[FAIL] File System SACL configuration failed: $_"
}

# Configure Registry SACL for LSA Secrets monitoring
Write-Host "Configuring Registry SACL for LSA Secrets access monitoring..."
try {
    # Set SACL on HKLM\SECURITY\Policy\Secrets to detect LSA secrets access
    $regPath = "HKLM\SECURITY\Policy\Secrets"
    $acl = Get-Acl -Path "Registry::$regPath" -EA SilentlyContinue
    if($acl) {
        $auditRule = New-Object System.Security.AccessControl.RegistryAuditRule("Everyone","FullControl","ContainerInherit,ObjectInherit","None","Success,Failure")
        $acl.SetAuditRule($auditRule)
        Set-Acl -Path "Registry::$regPath" -AclObject $acl -EA SilentlyContinue
        Write-Host "[OK] Registry SACL configured for LSA Secrets monitoring"
    }
} catch {
    Write-Warning "[FAIL] Registry SACL configuration failed: $_"
}

# Enable audit policies
Write-Host "Enabling audit policies..."
$auditResults = @()
@("File System","Registry","Security State Change","User Account Management","Directory Service Changes","Directory Service Access","Process Creation","File Share","Detailed File Share","Handle Manipulation","Authorization Policy Change","Authentication Policy Change") | ForEach-Object {
$result = auditpol /set /subcategory:"$_" /success:enable /failure:enable 2>&1
if($LASTEXITCODE -eq 0){Write-Host "[OK] Enabled audit for: $_"}else{Write-Warning "[FAIL] Failed audit for: $_ - $result"}
$auditResults += "$_`: $LASTEXITCODE"
}
$auditResults | Out-File "$LogPath\audit-status.log" -Append
Write-Host "Audit policies configuration completed"

# Enable command line logging for Process Creation events
Write-Host "Enabling command line capture for Process Creation events..."
$regResult = reg add "HKLM\Software\Microsoft\Windows\CurrentVersion\Policies\System\Audit" /v ProcessCreationIncludeCmdLine_Enabled /t REG_DWORD /d 1 /f 2>&1
if($LASTEXITCODE -eq 0){
    Write-Host "[OK] Command line logging enabled for Process Creation events"
}else{
    Write-Warning "[FAIL] Failed to enable command line logging: $regResult"
}

# Create SecurityHardening scheduled task for post-setup security measures
Write-Host "Creating SecurityHardening scheduled task for final security hardening..."
try {
    $secAction = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-ExecutionPolicy Bypass -NoProfile -File C:\ADLabScripts\security-hardening.ps1"
    $secTrigger = New-ScheduledTaskTrigger -AtStartup
    $secTrigger.Delay = "PT180S"  # 3 minutes delay to ensure all services (including HasegawaBackup) are ready
    $secPrincipal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    $secSettings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 10)

    # Remove existing task if present
    Unregister-ScheduledTask -TaskName "SecurityHardening" -Confirm:$false -EA SilentlyContinue

    # Register new SecurityHardening task
    Register-ScheduledTask -TaskName "SecurityHardening" -Action $secAction -Trigger $secTrigger -Principal $secPrincipal -Settings $secSettings -Force
    Write-Host "[OK] SecurityHardening task created - will execute security hardening after next reboot"
} catch {
    Write-Warning "[FAIL] Failed to create SecurityHardening task: $_"
}

# Mark setup as complete and remove current setup task
Set-State "DONE"
Write-Host "Setup completed - SecurityHardening will run on next boot to secure config.json and clean temporary files while maintaining services"
Unregister-ScheduledTask -TaskName "ADSetup" -Confirm:$false -EA SilentlyContinue}
}}catch{Write-Error $_;$_|Out-File "$LogPath\error.log" -Append}
Stop-Transcript