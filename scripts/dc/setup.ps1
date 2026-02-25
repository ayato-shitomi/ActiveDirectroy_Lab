# DC Main Setup Script
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
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name "UserAuthentication" -Value 0
# Enable WinRM
Enable-PSRemoting -Force -SkipNetworkProfileCheck
Set-Item WSMan:\localhost\Client\TrustedHosts -Value "*" -Force
New-NetFirewallRule -DisplayName "WinRM-HTTP" -Direction Inbound -Protocol TCP -LocalPort 5985 -Action Allow -EA SilentlyContinue
New-NetFirewallRule -DisplayName "WinRM-HTTPS" -Direction Inbound -Protocol TCP -LocalPort 5986 -Action Allow -EA SilentlyContinue
Write-Host "WinRM enabled"
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
Install-ADDSForest -DomainName $c.DomainName -DomainNetbiosName $c.DomainNetbios -SafeModeAdministratorPassword $p -InstallDns -DatabasePath "C:\Windows\NTDS" -LogPath "C:\Windows\NTDS" -SysvolPath "C:\Windows\SYSVOL" -DomainMode "WinThreshold" -ForestMode "WinThreshold" -NoRebootOnCompletion:$true -Force
Set-State "CONFIG";Restart-Computer -Force;exit}
"CONFIG"{
$adReady=$false
for($i=1;$i -le 60;$i++){try{Import-Module ActiveDirectory -EA Stop;Get-ADDomain -EA Stop;$adReady=$true;break}catch{Write-Host "Wait AD... $i/60";Start-Sleep 10}}
if(-not $adReady){Write-Warning "AD not ready after 10 min, restarting...";Restart-Computer -Force;exit}
Open-FW;$dn=(Get-ADDomain).DistinguishedName
@("LabUsers","LabComputers","LabServers","LabGroups")|ForEach-Object{if(!(Get-ADOrganizationalUnit -Filter "Name -eq '$_'" -EA SilentlyContinue)){New-ADOrganizationalUnit -Name $_ -Path $dn -ProtectedFromAccidentalDeletion $false}}
$ou="OU=LabUsers,$dn"
@(@{n="hasegawa";fn="Hanako";ln="Hasegawa";p=$c.UserPwdHasegawa},@{n="saitou";fn="Jiro";ln="Saitou";p=$c.UserPwdSaitou})|ForEach-Object{
if(!(Get-ADUser -Filter "SamAccountName -eq '$($_.n)'" -EA SilentlyContinue)){
$sp=ConvertTo-SecureString $_.p -AsPlainText -Force
New-ADUser -Name "$($_.fn) $($_.ln)" -SamAccountName $_.n -UserPrincipalName "$($_.n)@$($c.DomainName)" -GivenName $_.fn -Surname $_.ln -Path $ou -AccountPassword $sp -PasswordNeverExpires $true -Enabled $true}}
$saou="OU=ServiceAccounts,$dn"
if(!(Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$saou'" -EA SilentlyContinue)){New-ADOrganizationalUnit -Name "ServiceAccounts" -Path $dn}
if(!(Get-ADUser -Filter "SamAccountName -eq 'svc_backup'" -EA SilentlyContinue)){
$sasp=ConvertTo-SecureString $c.SvcBackupPwd -AsPlainText -Force
New-ADUser -Name "svc_backup" -SamAccountName "svc_backup" -UserPrincipalName "svc_backup@$($c.DomainName)" -Path $saou -AccountPassword $sasp -PasswordNeverExpires $true -Enabled $true -Description "FILESRV Backup Service Account"}
$go="OU=LabGroups,$dn"
if(!(Get-ADGroup -Filter "Name -eq 'GG_Lab_Users'" -EA SilentlyContinue)){New-ADGroup -Name "GG_Lab_Users" -SamAccountName "GG_Lab_Users" -GroupCategory Security -GroupScope Global -Path $go}
@("hasegawa","saitou")|ForEach-Object{Add-ADGroupMember -Identity "GG_Lab_Users" -Members $_ -EA SilentlyContinue}
$hasegawaDN=(Get-ADUser hasegawa).DistinguishedName
dsacls $hasegawaDN /G "$($c.DomainNetbios)\saitou:CA;Reset Password"|Out-Null
Write-Host "Granted saitou permission to reset hasegawa password"
# Configure svc_backup service account with comprehensive DC access rights including WinRM
$svcBackupSid=(Get-ADUser svc_backup).SID.Value

# Add svc_backup to local Administrators group for full WinRM access (most reliable approach)
try {
    # Wait for AD replication and try multiple approaches
    Start-Sleep 5

    # Method 1: PowerShell cmdlet
    Add-LocalGroupMember -Group "Administrators" -Member "LAB\svc_backup" -EA Stop
    Write-Host "Added svc_backup to local Administrators group via PowerShell"
} catch {
    Write-Warning "PowerShell method failed: $_"
    try {
        # Method 2: net command as fallback
        $result = net localgroup Administrators "LAB\svc_backup" /add 2>&1
        Write-Host "Added svc_backup to local Administrators group via net command: $result"
    } catch {
        Write-Warning "Net command method also failed: $_"
        # Method 3: Direct registry/API approach if needed
        $domain = $c.DomainNetbios
        $result = net localgroup Administrators "$domain\svc_backup" /add 2>&1
        Write-Host "Added svc_backup using domain prefix: $result"
    }
}

# Verify the addition worked
$verification = net localgroup Administrators 2>&1 | Select-String "svc_backup"
if($verification) {
    Write-Host "Verification successful: svc_backup found in Administrators group"
} else {
    Write-Warning "Verification failed: svc_backup NOT found in Administrators group"
    # List current members for debugging
    Write-Host "Current Administrators group members:"
    net localgroup Administrators
}

# Try to add to Remote Management Users if it exists, otherwise skip
$rmGroup = Get-LocalGroup "Remote Management Users" -EA SilentlyContinue
if($rmGroup) {
    Add-LocalGroupMember -Group "Remote Management Users" -Member "LAB\svc_backup" -EA SilentlyContinue
    Write-Host "Added svc_backup to Remote Management Users group"
} else {
    Write-Host "Remote Management Users group not found, skipping (Administrator group membership sufficient)"
}

# Grant comprehensive user rights for all types of remote access
$tmpCfg="$LogPath\secpol_service.cfg";$tmpDb="$LogPath\secedit_service.sdb"
secedit /export /cfg $tmpCfg /areas USER_RIGHTS 2>&1|Out-Null
$cfg=Get-Content $tmpCfg -Raw -Encoding Unicode -EA SilentlyContinue

# Grant all required privileges for comprehensive remote access
$privileges = @(
    "SeServiceLogonRight",           # Log on as a service
    "SeNetworkLogonRight",           # Access this computer from the network
    "SeRemoteInteractiveLogonRight", # Allow log on through Remote Desktop Services
    "SeBatchLogonRight",             # Log on as a batch job
    "SeInteractiveLogonRight",       # Log on locally
    "SeDenyNetworkLogonRight",       # Remove any deny network logon (we'll remove svc_backup from this)
    "SeDenyRemoteInteractiveLogonRight" # Remove any deny RDP logon (we'll remove svc_backup from this)
)

foreach($priv in $privileges){
    if($priv -like "SeDeny*"){
        # For deny rights, remove svc_backup from the list if present
        if($cfg -match "$priv\s*=\s*(.*)"){
            $cur=$matches[1].Trim()
            if($cur -match $svcBackupSid){
                $newCur = $cur -replace ",?\*?$svcBackupSid",""
                $newCur = $newCur -replace "^,",""
                $cfg=$cfg -replace "$priv\s*=\s*.*","$priv = $newCur"
                Write-Host "Removed svc_backup from $priv deny list"
            }
        }
    }else{
        # For allow rights, add svc_backup to the list if not present
        if($cfg -match "$priv\s*=\s*(.*)"){
            $cur=$matches[1].Trim()
            if($cur -notmatch $svcBackupSid){
                $cfg=$cfg -replace "$priv\s*=\s*.*","$priv = $cur,*$svcBackupSid"
            }
        }else{
            $cfg=$cfg -replace '\[Privilege Rights\]',"[Privilege Rights]`r`n$priv = *$svcBackupSid"
        }
    }
}

$cfg|Set-Content $tmpCfg -Encoding Unicode
secedit /configure /db $tmpDb /cfg $tmpCfg /areas USER_RIGHTS 2>&1|Out-Null
Write-Host "Granted svc_backup comprehensive DC access rights: Service, Network, RDP, Batch logon"
# Create flag file on Administrator desktop
$adminDesktop="C:\Users\Administrator\Desktop"
New-Item -ItemType Directory -Path $adminDesktop -Force -EA SilentlyContinue|Out-Null
$c.FlagDcAdmin|Out-File "$adminDesktop\flag.txt" -Encoding UTF8
Write-Host "Created flag file on Administrator desktop"
# Enable comprehensive audit policies for AD monitoring
Write-Host "Enabling comprehensive audit policies for Active Directory monitoring..."
$auditResults = @()
@("File System","Registry","Security State Change","User Account Management","Directory Service Changes","Directory Service Access","Process Creation","File Share","Detailed File Share","Handle Manipulation") | ForEach-Object {
$result = auditpol /set /subcategory:"$_" /success:enable /failure:enable 2>&1
if($LASTEXITCODE -eq 0){Write-Host "[OK] Enabled audit for: $_"}else{Write-Warning "[FAIL] Failed audit for: $_ - $result"}
$auditResults += "$_`: $LASTEXITCODE"
}
$auditResults | Out-File "$LogPath\audit-status.log" -Append
Write-Host "Comprehensive audit policies configuration completed"
Set-State "DONE";Unregister-ScheduledTask -TaskName "ADSetup" -Confirm:$false -EA SilentlyContinue}
"DONE"{Unregister-ScheduledTask -TaskName "ADSetup" -Confirm:$false -EA SilentlyContinue}
}}catch{Write-Error $_;$_|Out-File "$LogPath\error.log" -Append}
Stop-Transcript