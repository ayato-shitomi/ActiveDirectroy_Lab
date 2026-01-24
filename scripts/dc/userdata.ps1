<powershell>
# DC Bootstrap - Downloads and runs setup script
$ErrorActionPreference = "Continue"
$LogPath = "C:\ADLabLogs"
$ScriptPath = "C:\ADLabScripts"
New-Item -ItemType Directory -Path $LogPath, $ScriptPath -Force -EA SilentlyContinue | Out-Null
Start-Transcript -Path "$LogPath\userdata.log" -Append

# Save config
@{AdminPassword="${admin_password}";DomainName="${domain_name}";DomainNetbios="${domain_netbios}";DomainPassword="${domain_password}";DCIP="${dc_ip}";ComputerName="${computer_name}";UserPwdTanaka="${user_password_tanaka}";UserPwdHasegawa="${user_password_hasegawa}";UserPwdSaitou="${user_password_saitou}"} | ConvertTo-Json | Out-File "$ScriptPath\config.json" -Force

# Setup script content
$s = @'
$ErrorActionPreference="Continue"
$LogPath="C:\ADLabLogs";$ScriptPath="C:\ADLabScripts";$StateFile="$LogPath\dc-state.txt"
Start-Transcript -Path "$LogPath\setup.log" -Append
$c=Get-Content "$ScriptPath\config.json"|ConvertFrom-Json
function Get-State{if(Test-Path $StateFile){return(Get-Content $StateFile -Raw).Trim()};"INIT"}
function Set-State($s){$s|Out-File $StateFile -Force;Write-Host "State: $s"}
function Open-FW{
@(53,88,389,445,636,3268)|ForEach-Object{New-NetFirewallRule -DisplayName "AD-TCP-$_" -Direction Inbound -Protocol TCP -LocalPort $_ -Action Allow -EA SilentlyContinue}
@(53,88,389)|ForEach-Object{New-NetFirewallRule -DisplayName "AD-UDP-$_" -Direction Inbound -Protocol UDP -LocalPort $_ -Action Allow -EA SilentlyContinue}
Enable-NetFirewallRule -DisplayGroup "Remote Desktop" -EA SilentlyContinue
}
try{
$state=Get-State;Write-Host "Current: $state"
switch($state){
"INIT"{
$p=ConvertTo-SecureString $c.AdminPassword -AsPlainText -Force
Set-LocalUser -Name "Administrator" -Password $p;Enable-LocalUser -Name "Administrator"
Rename-Computer -NewName $c.ComputerName -Force
Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled True;Open-FW
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name "fDenyTSConnections" -Value 0
$a=Get-NetAdapter|?{$_.Status -eq "Up"}|Select -First 1
if($a){Set-NetIPInterface -InterfaceIndex $a.ifIndex -Dhcp Disabled -EA SilentlyContinue
Remove-NetIPAddress -InterfaceIndex $a.ifIndex -Confirm:$false -EA SilentlyContinue
Remove-NetRoute -InterfaceIndex $a.ifIndex -Confirm:$false -EA SilentlyContinue
$gw=$c.DCIP -replace '\.\d+$','.1'
New-NetIPAddress -InterfaceIndex $a.ifIndex -IPAddress $c.DCIP -PrefixLength 24 -DefaultGateway $gw
Set-DnsClientServerAddress -InterfaceIndex $a.ifIndex -ServerAddresses @("127.0.0.1","8.8.8.8")}
Set-State "INSTALL";Restart-Computer -Force;exit}
"INSTALL"{
Install-WindowsFeature -Name AD-Domain-Services,DNS -IncludeManagementTools
Install-WindowsFeature -Name RSAT-AD-Tools -IncludeAllSubFeature -EA SilentlyContinue
$f1=Get-WindowsFeature AD-Domain-Services;$f2=Get-WindowsFeature DNS
Write-Host "ADDS:$($f1.Installed) DNS:$($f2.Installed)"
if($f1.Installed -and $f2.Installed){Set-State "PROMOTE";Restart-Computer -Force;exit}
else{Write-Error "Install failed";exit 1}}
"PROMOTE"{
$p=ConvertTo-SecureString $c.DomainPassword -AsPlainText -Force
Install-ADDSForest -DomainName $c.DomainName -DomainNetbiosName $c.DomainNetbios -SafeModeAdministratorPassword $p -InstallDns -DatabasePath "C:\Windows\NTDS" -LogPath "C:\Windows\NTDS" -SysvolPath "C:\Windows\SYSVOL" -DomainMode "WinThreshold" -ForestMode "WinThreshold" -NoRebootOnCompletion:$false -Force
Set-State "CONFIG"}
"CONFIG"{
for($i=1;$i -le 30;$i++){try{Import-Module ActiveDirectory -EA Stop;Get-ADDomain -EA Stop;break}catch{Write-Host "Wait AD... $i";Start-Sleep 10}}
Open-FW;$dn=(Get-ADDomain).DistinguishedName
@("LabUsers","LabComputers","LabServers","LabGroups")|ForEach-Object{if(!(Get-ADOrganizationalUnit -Filter "Name -eq '$_'" -EA SilentlyContinue)){New-ADOrganizationalUnit -Name $_ -Path $dn -ProtectedFromAccidentalDeletion $false}}
$ou="OU=LabUsers,$dn"
@(@{n="tanaka";fn="Taro";ln="Tanaka";p=$c.UserPwdTanaka},@{n="hasegawa";fn="Hanako";ln="Hasegawa";p=$c.UserPwdHasegawa},@{n="saitou";fn="Jiro";ln="Saitou";p=$c.UserPwdSaitou})|ForEach-Object{
if(!(Get-ADUser -Filter "SamAccountName -eq '$($_.n)'" -EA SilentlyContinue)){
$sp=ConvertTo-SecureString $_.p -AsPlainText -Force
New-ADUser -Name "$($_.fn) $($_.ln)" -SamAccountName $_.n -UserPrincipalName "$($_.n)@$($c.DomainName)" -GivenName $_.fn -Surname $_.ln -Path $ou -AccountPassword $sp -PasswordNeverExpires $true -Enabled $true}}
$go="OU=LabGroups,$dn"
if(!(Get-ADGroup -Filter "Name -eq 'GG_Lab_Users'" -EA SilentlyContinue)){New-ADGroup -Name "GG_Lab_Users" -SamAccountName "GG_Lab_Users" -GroupCategory Security -GroupScope Global -Path $go}
@("tanaka","hasegawa","saitou")|ForEach-Object{Add-ADGroupMember -Identity "GG_Lab_Users" -Members $_ -EA SilentlyContinue}
Set-State "DONE";Unregister-ScheduledTask -TaskName "ADSetup" -Confirm:$false -EA SilentlyContinue}
"DONE"{Unregister-ScheduledTask -TaskName "ADSetup" -Confirm:$false -EA SilentlyContinue}
}}catch{Write-Error $_;$_|Out-File "$LogPath\error.log" -Append}
Stop-Transcript
'@
$s | Out-File "$ScriptPath\setup.ps1" -Force -Encoding UTF8

# Launcher
'Start-Sleep 30;& C:\ADLabScripts\setup.ps1' | Out-File "$ScriptPath\launcher.ps1" -Force

# Task
$a=New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-EP Bypass -NoProfile -File C:\ADLabScripts\launcher.ps1"
$t=New-ScheduledTaskTrigger -AtStartup;$t.Delay="PT90S"
$p=New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
$st=New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
Unregister-ScheduledTask -TaskName "ADSetup" -Confirm:$false -EA SilentlyContinue
Register-ScheduledTask -TaskName "ADSetup" -Action $a -Trigger $t -Principal $p -Settings $st -Force

& "$ScriptPath\setup.ps1"
Stop-Transcript
</powershell>
