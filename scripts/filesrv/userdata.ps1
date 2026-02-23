<powershell>
# FILESRV Bootstrap - Downloads and runs setup script
$ErrorActionPreference = "Continue"
$LogPath = "C:\ADLabLogs"
$ScriptPath = "C:\ADLabScripts"
New-Item -ItemType Directory -Path $LogPath, $ScriptPath -Force -EA SilentlyContinue | Out-Null
Start-Transcript -Path "$LogPath\userdata.log" -Append

# Save config (encrypted)
$secConfig = @{
    AdminPassword=[System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("${admin_password}"))
    DomainName="${domain_name}"
    DomainNetbios="${domain_netbios}"
    DomainPassword=[System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("${domain_password}"))
    DCIP="${dc_ip}"
    ComputerName="${computer_name}"
    NakanishiPassword=[System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("${user_password_nakanishi}"))
}
$secConfig | ConvertTo-Json | Out-File "$ScriptPath\config.json" -Force

# Setup script content
$s = @'
$ErrorActionPreference="Continue"
$LogPath="C:\ADLabLogs";$ScriptPath="C:\ADLabScripts";$StateFile="$LogPath\filesrv-state.txt"
Start-Transcript -Path "$LogPath\setup.log" -Append
$c=Get-Content "$ScriptPath\config.json"|ConvertFrom-Json
# Decode encrypted config
$c.AdminPassword=[System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($c.AdminPassword))
$c.DomainPassword=[System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($c.DomainPassword))
$c.NakanishiPassword=[System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($c.NakanishiPassword))
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
if(-not (Test-DC)){Write-Warning "DC not reachable, returning to WAIT";Set-State "WAIT";Restart-Computer -Force;exit}
$p=ConvertTo-SecureString $c.DomainPassword -AsPlainText -Force
$cred=New-Object PSCredential("$($c.DomainName)\Administrator",$p)
$joinSuccess=$false;$maxAttempts=10
for($i=1;$i -le $maxAttempts;$i++){
try{
Write-Host "Domain join attempt $i/$maxAttempts to $($c.DomainName)"
Add-Computer -DomainName $c.DomainName -Credential $cred -Force -EA Stop
$joinSuccess=$true
Write-Host "Domain join successful!"
Set-State "SHARE";Restart-Computer -Force;exit
}catch{
$errMsg=$_.Exception.Message
Write-Warning "Join attempt $i failed: $errMsg"
if($errMsg -like "*trust relationship*" -or $errMsg -like "*already exists*"){Write-Warning "Critical domain error, returning to WAIT";Set-State "WAIT";Start-Sleep 300;Restart-Computer -Force;exit}
if($i -lt $maxAttempts){Start-Sleep 60}}}
if(-not $joinSuccess){
Write-Error "All $maxAttempts domain join attempts failed. Returning to WAIT state."
Set-State "WAIT"
Start-Sleep 300
Restart-Computer -Force;exit
}
Write-Warning "Unexpected state in JOIN, restarting"
Restart-Computer -Force;exit}
"SHARE"{
Install-WindowsFeature -Name FS-FileServer -IncludeManagementTools
Write-Host "Installing RSAT AD Tools..."
Add-WindowsCapability -Online -Name "Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0" -EA SilentlyContinue
Write-Host "Waiting for AD users to be available..."
$adUsers=@("nakanishi","hasegawa","saitou")
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
$nakanishiMember="$($c.DomainNetbios)\nakanishi"
for($retry=1;$retry -le 3;$retry++){
try{
Add-LocalGroupMember -Group "Administrators" -Member $nakanishiMember -EA SilentlyContinue
Write-Host "Added $nakanishiMember to local Administrators group"
break
}catch{Write-Warning "Retry $retry for adding $nakanishiMember to Administrators : $_";Start-Sleep 5}}
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
$exportResult = secedit /export /cfg $tmpCfg /areas USER_RIGHTS 2>&1
if($LASTEXITCODE -ne 0){Write-Warning "secedit export failed: $exportResult"}else{
$cfg = Get-Content $tmpCfg -Raw -Encoding Unicode -EA SilentlyContinue
if($cfg){
if($cfg -match 'SeShutdownPrivilege\s*=\s*(.*)'){
$cur = $matches[1].Trim()
if($cur -notmatch $hasegawaSid){$cfg = $cfg -replace 'SeShutdownPrivilege\s*=\s*.*', "SeShutdownPrivilege = $cur,*$hasegawaSid"}
}else{
$cfg = $cfg -replace '\[Privilege Rights\]', "[Privilege Rights]`r`nSeShutdownPrivilege = *$hasegawaSid"
}
$cfg | Set-Content $tmpCfg -Encoding Unicode
$configResult = secedit /configure /db $tmpDb /cfg $tmpCfg /areas USER_RIGHTS 2>&1
if($LASTEXITCODE -eq 0){Write-Host "SeShutdownPrivilege granted to hasegawa"}else{Write-Warning "secedit configure failed: $configResult"}
}else{Write-Warning "Failed to read security policy config"}}}}
$shareRoot = "C:\Shares"
Write-Host "Creating share directories..."
New-Item -ItemType Directory -Path "$shareRoot\Share" -Force -EA SilentlyContinue
New-Item -ItemType Directory -Path "$shareRoot\Public" -Force -EA SilentlyContinue
New-Item -ItemType Directory -Path "$shareRoot\Users\Nakanishi" -Force -EA SilentlyContinue
New-Item -ItemType Directory -Path "$shareRoot\Users\Hasegawa" -Force -EA SilentlyContinue
New-Item -ItemType Directory -Path "$shareRoot\Users\Saitou" -Force -EA SilentlyContinue
Write-Host "Creating SMB shares..."
Remove-SmbShare -Name "Share" -Force -EA SilentlyContinue
New-SmbShare -Name "Share" -Path "$shareRoot\Share" -FullAccess @("Everyone","Administrators")
Remove-SmbShare -Name "Public" -Force -EA SilentlyContinue
New-SmbShare -Name "Public" -Path "$shareRoot\Public" -ReadAccess @("Everyone") -FullAccess @("Administrators")
Remove-SmbShare -Name "Nakanishi" -Force -EA SilentlyContinue
New-SmbShare -Name "Nakanishi" -Path "$shareRoot\Users\Nakanishi" -FullAccess @("$($c.DomainNetbios)\nakanishi","Administrators")
Remove-SmbShare -Name "Hasegawa" -Force -EA SilentlyContinue
New-SmbShare -Name "Hasegawa" -Path "$shareRoot\Users\Hasegawa" -FullAccess @("$($c.DomainNetbios)\hasegawa","Administrators")
Remove-SmbShare -Name "Saitou" -Force -EA SilentlyContinue
New-SmbShare -Name "Saitou" -Path "$shareRoot\Users\Saitou" -FullAccess @("$($c.DomainNetbios)\saitou","Administrators")
Write-Host "Creating check_event_number.bat for hasegawa..."
$batPath="$shareRoot\Users\Hasegawa\check_event_number.bat"
$eventLogPath="$shareRoot\Users\Hasegawa\event_number.log"
$batLines=@("@echo off","for /f %%a in ('powershell -Command `"(Get-WinEvent -LogName System -EA SilentlyContinue).Count`"') do set SYSCNT=%%a","for /f %%a in ('powershell -Command `"(Get-WinEvent -LogName Security -EA SilentlyContinue).Count`"') do set SECCNT=%%a","for /f %%a in ('powershell -Command `"(Get-WinEvent -LogName Application -EA SilentlyContinue).Count`"') do set APPCNT=%%a","echo %date% %time% - System:%SYSCNT% Security:%SECCNT% Application:%APPCNT% >> `"C:\Shares\Users\Hasegawa\event_number.log`"")
$batLines -join "`r`n"|Out-File $batPath -Encoding ASCII
$hasegawaUser = $c.DomainNetbios + "\hasegawa"
for($i=1; $i -le 3; $i++) {
    try {
        $ownerResult = icacls $batPath /setowner $hasegawaUser 2>&1
        if($LASTEXITCODE -eq 0){
            $grantArg = $hasegawaUser + ":(M)"
            $grantResult = icacls $batPath /grant $grantArg 2>&1
            if($LASTEXITCODE -eq 0){
                Write-Host "Set owner of check_event_number.bat to hasegawa (attempt $i)"
                break
            }else{Write-Warning "Grant failed attempt $i : $grantResult"}
        }else{Write-Warning "Setowner failed attempt $i : $ownerResult"}
        if($i -lt 3) { Start-Sleep 10 }
    } catch {
        Write-Warning "Exception setting hasegawa ownership attempt $i : $_"
        if($i -lt 3) { Start-Sleep 10 }
    }
}
$ta=New-ScheduledTaskAction -Execute "cmd.exe" -Argument "/c `"$batPath`""
$tt=New-ScheduledTaskTrigger -AtStartup;$tt.Delay="PT60S"
$tp=New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
$ts=New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
try{
$task = Register-ScheduledTask -TaskName "CheckEventNumber" -Action $ta -Trigger $tt -Principal $tp -Settings $ts -Force -EA Stop
$taskSddl = "D:(A;;FA;;;SY)(A;;FA;;;BA)(A;;GRGX;;;AU)"
$schtaskResult = schtasks /Change /TN "CheckEventNumber" /SD $taskSddl 2>&1
if($LASTEXITCODE -eq 0){Write-Host "Created check_event_number.bat and CheckEventNumber scheduled task"}else{Write-Warning "SDDL change failed: $schtaskResult"}
}catch{Write-Warning "Failed to create CheckEventNumber task: $_"}
Write-Host "Creating nakanishi credential cache..."
try {
    $cacheScriptContent = "try{`$c=Get-Content 'C:\ADLabScripts\config.json'|ConvertFrom-Json;`$c.NakanishiPassword=[System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String(`$c.NakanishiPassword));`$u='$($c.DomainNetbios)\nakanishi';`$p=`$c.NakanishiPassword|ConvertTo-SecureString -AsPlainText -Force;`$cr=New-Object System.Management.Automation.PSCredential(`$u,`$p);Invoke-Command -ComputerName localhost -Credential `$cr -ScriptBlock {Get-Process|Select -First 1|Out-Null} -EA Stop}catch{}finally{Unregister-ScheduledTask -TaskName 'NakanishiCache' -Confirm:`$false -EA SilentlyContinue}"
    $cacheScriptPath = "$LogPath\nakanishi_cache.ps1"
    if(-not (Test-Path $cacheScriptPath)){$cacheScriptContent | Out-File $cacheScriptPath -Force -Encoding UTF8}
    $nta = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-ExecutionPolicy Bypass -NoProfile -File `"$cacheScriptPath`""
    $ntt = New-ScheduledTaskTrigger -AtStartup
    $ntt.Delay = "PT480S"
    $ntp = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    $nts = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
    $cacheTask = Register-ScheduledTask -TaskName "NakanishiCache" -Action $nta -Trigger $ntt -Principal $ntp -Settings $nts -Force -EA Stop
    if($cacheTask){Write-Host "Created NakanishiCache task"}else{Write-Warning "NakanishiCache task creation uncertain"}
} catch {
    Write-Warning "Failed to create nakanishi cache task: $_"
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