<powershell>
# FILESRV Bootstrap - Downloads and runs setup script
$ErrorActionPreference = "Continue"
$LogPath = "C:\ADLabLogs"
$ScriptPath = "C:\ADLabScripts"
New-Item -ItemType Directory -Path $LogPath, $ScriptPath -Force -EA SilentlyContinue | Out-Null
Start-Transcript -Path "$LogPath\userdata.log" -Append

# Save config
@{AdminPassword="${admin_password}";DomainName="${domain_name}";DomainNetbios="${domain_netbios}";DomainPassword="${domain_password}";DCIP="${dc_ip}";ComputerName="${computer_name}";SvcBackupPassword="${svc_backup_password}"} | ConvertTo-Json | Out-File "$ScriptPath\config.json" -Force

# Setup script content
$s = @'
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
Write-Host "Created check_event_number.bat and CheckEventNumber scheduled task"
Write-Host "Creating svc_backup service..."
try {
    # Create a simple backup service script that will cache credentials
    $serviceScriptContent = @'
# Simple backup service that maintains credential cache for svc_backup
Add-Type -AssemblyName System.ServiceProcess
$serviceName = "BackupService"
$serviceDisplayName = "FILESRV Backup Service"

# Service main loop - keeps credentials active
while ($true) {
    try {
        $c = Get-Content "C:\ADLabScripts\config.json" | ConvertFrom-Json
        $cred = New-Object System.Management.Automation.PSCredential("$($c.DomainNetbios)\svc_backup", ($c.SvcBackupPassword | ConvertTo-SecureString -AsPlainText -Force))

        # Perform a simple network operation to maintain credential cache
        $null = Invoke-Command -ComputerName localhost -Credential $cred -ScriptBlock { Get-Date } -EA SilentlyContinue

        Start-Sleep -Seconds 300  # Run every 5 minutes
    } catch {
        Start-Sleep -Seconds 60   # Retry in 1 minute on error
    }
}
'@
    $serviceScriptPath = "$LogPath\svc_backup_service.ps1"
    $serviceScriptContent | Out-File $serviceScriptPath -Force -Encoding UTF8

    # Create scheduled task to run as svc_backup user
    $sta = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-ExecutionPolicy Bypass -NoProfile -WindowStyle Hidden -File `"$serviceScriptPath`""
    $stt = New-ScheduledTaskTrigger -AtStartup
    $stt.Delay = "PT300S"
    $stp = New-ScheduledTaskPrincipal -UserId "$($c.DomainNetbios)\svc_backup" -LogonType Password -RunLevel Limited
    $sts = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
    Register-ScheduledTask -TaskName "BackupService" -Action $sta -Trigger $stt -Principal $stp -Settings $sts -Force
    Write-Host "Created BackupService scheduled task"
} catch {
    Write-Warning "Failed to create backup service: $_"
}
Set-State "DONE";Unregister-ScheduledTask -TaskName "ADSetup" -Confirm:$false -EA SilentlyContinue}
"DONE"{Unregister-ScheduledTask -TaskName "ADSetup" -Confirm:$false -EA SilentlyContinue}
}}catch{Write-Error $_;$_|Out-File "$LogPath\error.log" -Append}
Stop-Transcript
'@
$s | Out-File "$ScriptPath\setup.ps1" -Force -Encoding UTF8

# Launcher (10s buffer for network initialization)
'Start-Sleep 10;& C:\ADLabScripts\setup.ps1' | Out-File "$ScriptPath\launcher.ps1" -Force

# Task (60s delay after startup)
$a=New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-EP Bypass -NoProfile -File C:\ADLabScripts\launcher.ps1"
$t=New-ScheduledTaskTrigger -AtStartup;$t.Delay="PT60S"
$p=New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
$st=New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
Unregister-ScheduledTask -TaskName "ADSetup" -Confirm:$false -EA SilentlyContinue
Register-ScheduledTask -TaskName "ADSetup" -Action $a -Trigger $t -Principal $p -Settings $st -Force

& "$ScriptPath\setup.ps1"
Stop-Transcript
</powershell>