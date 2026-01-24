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
function Test-DC{for($i=1;$i -le 20;$i++){try{Resolve-DnsName -Name $c.DomainName -Server $c.DCIP -DnsOnly -EA Stop|Out-Null;return $true}catch{Write-Host "Wait DC $i";Start-Sleep 15}};$false}
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
Set-State "WAIT";Restart-Computer -Force;exit}
"WAIT"{if(Test-DC){Set-State "JOIN";Restart-Computer -Force}else{Start-Sleep 60;Restart-Computer -Force};exit}
"JOIN"{
Start-Sleep 30
$p=ConvertTo-SecureString $c.DomainPassword -AsPlainText -Force
$cred=New-Object PSCredential("$($c.DomainName)\Administrator",$p)
try{Add-Computer -DomainName $c.DomainName -Credential $cred -Force -EA Stop;Set-State "SHARE";Restart-Computer -Force}
catch{Write-Warning $_;Start-Sleep 60;Restart-Computer -Force};exit}
"SHARE"{
Start-Sleep 30;Install-WindowsFeature -Name FS-FileServer -IncludeManagementTools
$r="C:\Shares";@("$r\Share","$r\Public","$r\Users\Tanaka","$r\Users\Hasegawa","$r\Users\Saitou")|ForEach-Object{New-Item -ItemType Directory -Path $_ -Force -EA SilentlyContinue}
@(@{N="Share";P="$r\Share";F=@("Everyone")},@{N="Public";P="$r\Public";R=@("Everyone");F=@("Administrators")},@{N="Tanaka";P="$r\Users\Tanaka";F=@("$($c.DomainNetbios)\tanaka","Administrators")},@{N="Hasegawa";P="$r\Users\Hasegawa";F=@("$($c.DomainNetbios)\hasegawa","Administrators")},@{N="Saitou";P="$r\Users\Saitou";F=@("$($c.DomainNetbios)\saitou","Administrators")})|ForEach-Object{
Remove-SmbShare -Name $_.N -Force -EA SilentlyContinue
$pa=@{Name=$_.N;Path=$_.P;FullAccess=$_.F};if($_.R){$pa.ReadAccess=$_.R}
New-SmbShare @pa}
Set-State "DONE";Unregister-ScheduledTask -TaskName "ADSetup" -Confirm:$false -EA SilentlyContinue}
"DONE"{Unregister-ScheduledTask -TaskName "ADSetup" -Confirm:$false -EA SilentlyContinue}
}}catch{Write-Error $_;$_|Out-File "$LogPath\error.log" -Append}
Stop-Transcript
'@
$s|Out-File "$ScriptPath\setup.ps1" -Force -Encoding UTF8
'Start-Sleep 30;& C:\ADLabScripts\setup.ps1'|Out-File "$ScriptPath\launcher.ps1" -Force
$a=New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-EP Bypass -NoProfile -File C:\ADLabScripts\launcher.ps1"
$t=New-ScheduledTaskTrigger -AtStartup;$t.Delay="PT90S"
$p=New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
$st=New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
Unregister-ScheduledTask -TaskName "ADSetup" -Confirm:$false -EA SilentlyContinue
Register-ScheduledTask -TaskName "ADSetup" -Action $a -Trigger $t -Principal $p -Settings $st -Force
& "$ScriptPath\setup.ps1"
Stop-Transcript
</powershell>
