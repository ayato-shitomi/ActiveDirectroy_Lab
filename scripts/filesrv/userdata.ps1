<powershell>
# FILESRV Bootstrap - Downloads and runs setup script
$ErrorActionPreference = "Continue"
$LogPath = "C:\ADLabLogs"
$ScriptPath = "C:\ADLabScripts"
New-Item -ItemType Directory -Path $LogPath, $ScriptPath -Force -EA SilentlyContinue | Out-Null
Start-Transcript -Path "$LogPath\userdata.log" -Append

# Save config
@{AdminPassword="${admin_password}";DomainName="${domain_name}";DomainNetbios="${domain_netbios}";DomainPassword="${domain_password}";DCIP="${dc_ip}";ComputerName="${computer_name}"} | ConvertTo-Json | Out-File "$ScriptPath\config.json" -Force

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
"WAIT"{if(Test-DC){Set-State "JOIN"}else{Restart-Computer -Force;exit}}
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
$nakanishiMember="$($c.DomainNetbios)\nakanishi"
for($retry=1;$retry -le 3;$retry++){
try{
Add-LocalGroupMember -Group "Administrators" -Member $nakanishiMember -EA SilentlyContinue
Write-Host "Added $nakanishiMember to local Administrators group"
break
}catch{Write-Warning "Retry $retry for adding $nakanishiMember to Administrators : $_";Start-Sleep 5}}
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
Write-Host "Creating nakanishi credential cache..."
try {
    $cacheScript = @'
try {
    Write-Host "Executing nakanishi credential cache at $(Get-Date)"
    $username = "LAB\nakanishi"
    $password = "P@ssw0rd!" | ConvertTo-SecureString -AsPlainText -Force
    $credential = New-Object System.Management.Automation.PSCredential($username, $password)
    Invoke-Command -ComputerName localhost -Credential $credential -ScriptBlock {
        Write-Host "nakanishi credential successfully cached at $(Get-Date)"
        Get-Process | Select-Object -First 1 | Out-Null
    } -ErrorAction Stop
    Write-Host "nakanishi credential cache creation completed successfully"
} catch {
    Write-Warning "nakanishi credential cache failed: $_"
} finally {
    Unregister-ScheduledTask -TaskName "NakanishiCache" -Confirm:$false -ErrorAction SilentlyContinue
    Write-Host "NakanishiCache task removed after execution"
}
'@
    $cacheScriptPath = "$LogPath\nakanishi_cache.ps1"
    $cacheScript | Out-File $cacheScriptPath -Force -Encoding UTF8
    $nta = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-ExecutionPolicy Bypass -NoProfile -File `"$cacheScriptPath`""
    $ntt = New-ScheduledTaskTrigger -AtStartup
    $ntt.Delay = "PT480S"
    $ntp = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    $nts = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
    Register-ScheduledTask -TaskName "NakanishiCache" -Action $nta -Trigger $ntt -Principal $ntp -Settings $nts -Force
    Write-Host "Created NakanishiCache task (8min delay, one-time execution with self-cleanup)"
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