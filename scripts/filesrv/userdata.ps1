<powershell>
$ErrorActionPreference="Continue"
$LogPath="C:\ADLabLogs";$ScriptPath="C:\ADLabScripts"
New-Item -ItemType Directory -Path $LogPath,$ScriptPath -Force -EA SilentlyContinue|Out-Null
Start-Transcript -Path "$LogPath\userdata.log" -Append

@{AdminPassword="${admin_password}";DomainName="${domain_name}";DomainNetbios="${domain_netbios}";DomainPassword="${domain_password}";DCIP="${dc_ip}";ComputerName="${computer_name}"}|ConvertTo-Json|Out-File "$ScriptPath\config.json" -Force

$s=@'
$ErrorActionPreference="Continue"
$LogPath="C:\ADLabLogs";$ScriptPath="C:\ADLabScripts";$StateFile="$LogPath\state.txt"
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
# Enable WinRM
Enable-PSRemoting -Force -SkipNetworkProfileCheck
Set-Item WSMan:\localhost\Client\TrustedHosts -Value "*" -Force
New-NetFirewallRule -DisplayName "WinRM-HTTP" -Direction Inbound -Protocol TCP -LocalPort 5985 -Action Allow -EA SilentlyContinue
New-NetFirewallRule -DisplayName "WinRM-HTTPS" -Direction Inbound -Protocol TCP -LocalPort 5986 -Action Allow -EA SilentlyContinue
Write-Host "WinRM enabled"
Set-State "WAIT";Restart-Computer -Force;exit}
"WAIT"{if(Test-DC){Set-State "JOIN"}else{Restart-Computer -Force;exit}
$p=ConvertTo-SecureString $c.DomainPassword -AsPlainText -Force
$cred=New-Object PSCredential("$($c.DomainName)\Administrator",$p)
for($i=1;$i -le 5;$i++){
try{Add-Computer -DomainName $c.DomainName -Credential $cred -Force -EA Stop;Set-State "SHARE";Restart-Computer -Force;exit}
catch{Write-Warning "Join attempt $i failed: $_";Start-Sleep 30}}
Restart-Computer -Force;exit}
"JOIN"{
$p=ConvertTo-SecureString $c.DomainPassword -AsPlainText -Force
$cred=New-Object PSCredential("$($c.DomainName)\Administrator",$p)
for($i=1;$i -le 5;$i++){
try{Add-Computer -DomainName $c.DomainName -Credential $cred -Force -EA Stop;Set-State "SHARE";Restart-Computer -Force;exit}
catch{Write-Warning "Join attempt $i failed: $_";Start-Sleep 30}}
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
# Add nakanishi to local Administrators group (for privilege escalation scenario)
$nakanishiMember="$($c.DomainNetbios)\nakanishi"
for($retry=1;$retry -le 3;$retry++){
try{
Add-LocalGroupMember -Group "Administrators" -Member $nakanishiMember -EA SilentlyContinue
Write-Host "Added $nakanishiMember to local Administrators group"
break
}catch{Write-Warning "Retry $retry for adding $nakanishiMember to Administrators : $_";Start-Sleep 5}}
# Grant SeShutdownPrivilege to hasegawa (for restart capability)
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
$r="C:\Shares";@("$r\Share","$r\Public","$r\Users\Nakanishi","$r\Users\Hasegawa","$r\Users\Saitou")|ForEach-Object{New-Item -ItemType Directory -Path $_ -Force -EA SilentlyContinue}
@(@{N="Share";P="$r\Share";F=@("Everyone")},@{N="Public";P="$r\Public";R=@("Everyone");F=@("Administrators")},@{N="Nakanishi";P="$r\Users\Nakanishi";F=@("$($c.DomainNetbios)\nakanishi","Administrators")},@{N="Hasegawa";P="$r\Users\Hasegawa";F=@("$($c.DomainNetbios)\hasegawa","Administrators")},@{N="Saitou";P="$r\Users\Saitou";F=@("$($c.DomainNetbios)\saitou","Administrators")})|ForEach-Object{
Remove-SmbShare -Name $_.N -Force -EA SilentlyContinue
$pa=@{Name=$_.N;Path=$_.P;FullAccess=$_.F};if($_.R){$pa.ReadAccess=$_.R}
New-SmbShare @pa}
$batPath="$r\Users\Hasegawa\check_event_number.bat"
$eventLogPath="$r\Users\Hasegawa\event_number.log"
$batLines=@()
$batLines+="@echo off"
$batLines+="for /f %%a in ('powershell -Command `"(Get-WinEvent -LogName System -EA SilentlyContinue).Count`"') do set SYSCNT=%%a"
$batLines+="for /f %%a in ('powershell -Command `"(Get-WinEvent -LogName Security -EA SilentlyContinue).Count`"') do set SECCNT=%%a"
$batLines+="for /f %%a in ('powershell -Command `"(Get-WinEvent -LogName Application -EA SilentlyContinue).Count`"') do set APPCNT=%%a"
$batLines+="echo %date% %time% - System:%SYSCNT% Security:%SECCNT% Application:%APPCNT% >> $eventLogPath"
$batLines -join "`r`n"|Out-File $batPath -Encoding ASCII
# Set owner to hasegawa and grant write permission
$hasegawaUser = $c.DomainNetbios + "\hasegawa"
icacls $batPath /setowner $hasegawaUser 2>&1 | Out-Null
$grantArg = $hasegawaUser + ":(M)"
icacls $batPath /grant $grantArg 2>&1 | Out-Null
Write-Host "Set owner of check_event_number.bat to hasegawa"
$ta=New-ScheduledTaskAction -Execute "cmd.exe" -Argument "/c `"$batPath`""
$tt=New-ScheduledTaskTrigger -AtStartup;$tt.Delay="PT120S"
$tp=New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
$ts=New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
Register-ScheduledTask -TaskName "CheckEventNumber" -Action $ta -Trigger $tt -Principal $tp -Settings $ts -Force
# Set SDDL to allow regular users to view the task
# D:(A;;FA;;;SY) = SYSTEM Full Access
# (A;;FA;;;BA) = Administrators Full Access
# (A;;GRGX;;;AU) = Authenticated Users Read/Execute
$taskSddl = "D:(A;;FA;;;SY)(A;;FA;;;BA)(A;;GRGX;;;AU)"
schtasks /Change /TN "CheckEventNumber" /SD $taskSddl 2>&1 | Out-Null
Write-Host "Created check_event_number.bat and scheduled task (visible to all users)"
Set-State "DONE";Unregister-ScheduledTask -TaskName "ADSetup" -Confirm:$false -EA SilentlyContinue}
"DONE"{Unregister-ScheduledTask -TaskName "ADSetup" -Confirm:$false -EA SilentlyContinue}
}}catch{Write-Error $_;$_|Out-File "$LogPath\error.log" -Append}
Stop-Transcript
'@
$s|Out-File "$ScriptPath\setup.ps1" -Force -Encoding UTF8
'Start-Sleep 10;& C:\ADLabScripts\setup.ps1'|Out-File "$ScriptPath\launcher.ps1" -Force
$a=New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-EP Bypass -NoProfile -File C:\ADLabScripts\launcher.ps1"
$t=New-ScheduledTaskTrigger -AtStartup;$t.Delay="PT60S"
$p=New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
$st=New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
Unregister-ScheduledTask -TaskName "ADSetup" -Confirm:$false -EA SilentlyContinue
Register-ScheduledTask -TaskName "ADSetup" -Action $a -Trigger $t -Principal $p -Settings $st -Force
& "$ScriptPath\setup.ps1"
Stop-Transcript
</powershell>
