# CLIENT Main Setup Script
$ErrorActionPreference="Continue"
$LogPath="C:\ADLabLogs";$ScriptPath="C:\ADLabScripts";$StateFile="$LogPath\client-state.txt"
Start-Transcript -Path "$LogPath\setup.log" -Append
$c=Get-Content "$ScriptPath\config.json"|ConvertFrom-Json
function Get-State{if(Test-Path $StateFile){return(Get-Content $StateFile -Raw).Trim()};"INIT"}
function Set-State($s){$s|Out-File $StateFile -Force;Write-Host "State: $s"}
try{
$state=Get-State;Write-Host "Current: $state"
# CLIENT is standalone - use standard DNS servers
$a=Get-NetAdapter|?{$_.Status -eq "Up"}|Select -First 1
if($a){Set-DnsClientServerAddress -InterfaceIndex $a.ifIndex -ServerAddresses @("8.8.8.8","1.1.1.1")}
switch($state){
"INIT"{
$p=ConvertTo-SecureString $c.AdminPassword -AsPlainText -Force
Set-LocalUser -Name "Administrator" -Password $p;Enable-LocalUser -Name "Administrator"
$up=ConvertTo-SecureString $c.NagataPassword -AsPlainText -Force
New-LocalUser -Name "nagata" -Password $up -PasswordNeverExpires -EA SilentlyContinue
Add-LocalGroupMember -Group "Remote Desktop Users" -Member "nagata" -EA SilentlyContinue
Add-LocalGroupMember -Group "Users" -Member "nagata" -EA SilentlyContinue
Add-LocalGroupMember -Group "Backup Operators" -Member "nagata" -EA SilentlyContinue
Add-LocalGroupMember -Group "Remote Management Users" -Member "nagata" -EA SilentlyContinue
Write-Host "Added nagata to Backup Operators and Remote Management Users groups"
# Grant SeBackupPrivilege and SeRestorePrivilege to Backup Operators group
$backupOpsSid = "S-1-5-32-551"
$tmpCfg = "$LogPath\secpol_backup.cfg"
$tmpDb = "$LogPath\secedit_backup.sdb"
secedit /export /cfg $tmpCfg /areas USER_RIGHTS 2>&1 | Out-Null
$cfg = Get-Content $tmpCfg -Raw -Encoding Unicode -EA SilentlyContinue
@("SeBackupPrivilege","SeRestorePrivilege") | ForEach-Object {
$priv = $_
if($cfg -match "$priv\s*=\s*(.*)"){
$cur = $matches[1].Trim()
if($cur -notmatch $backupOpsSid){
$cfg = $cfg -replace "$priv\s*=\s*.*", "$priv = $cur,*$backupOpsSid"
}
}else{
$cfg = $cfg -replace '\[Privilege Rights\]', "[Privilege Rights]`r`n$priv = *$backupOpsSid"
}
}
$cfg | Set-Content $tmpCfg -Encoding Unicode
secedit /configure /db $tmpDb /cfg $tmpCfg /areas USER_RIGHTS 2>&1 | Out-Null
Write-Host "Granted SeBackupPrivilege and SeRestorePrivilege to Backup Operators"
# Also grant privileges directly to nagata user (additional security for RDP access)
$nagataAccount = "nagata"
$nagataSid = $null
try {
    $nagataLocalUser = Get-LocalUser -Name $nagataAccount -EA Stop
    $nagataSid = $nagataLocalUser.SID.Value
    Write-Host "nagata SID: $nagataSid"

    # Grant privileges directly to nagata user
    @("SeBackupPrivilege","SeRestorePrivilege") | ForEach-Object {
        $priv = $_
        if($cfg -match "$priv\s*=\s*(.*)"){
            $cur = $matches[1].Trim()
            if($cur -notmatch $nagataSid){
                $cfg = $cfg -replace "$priv\s*=\s*.*", "$priv = $cur,*$nagataSid"
            }
        }else{
            $cfg = $cfg -replace '\[Privilege Rights\]', "[Privilege Rights]`r`n$priv = *$nagataSid"
        }
    }
    $cfg | Set-Content $tmpCfg -Encoding Unicode
    secedit /configure /db $tmpDb /cfg $tmpCfg /areas USER_RIGHTS 2>&1 | Out-Null
    Write-Host "Granted SeBackupPrivilege and SeRestorePrivilege directly to nagata user"
} catch {
    Write-Warning "Could not grant direct privileges to nagata: $_"
}
Rename-Computer -NewName $c.ComputerName -Force
Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled True
Enable-NetFirewallRule -DisplayGroup "Remote Desktop" -EA SilentlyContinue
Enable-NetFirewallRule -DisplayGroup "File and Printer Sharing" -EA SilentlyContinue
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name "fDenyTSConnections" -Value 0
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name "UserAuthentication" -Value 0
# Enable WinRM
Enable-PSRemoting -Force -SkipNetworkProfileCheck
Set-Item WSMan:\localhost\Client\TrustedHosts -Value "*" -Force
New-NetFirewallRule -DisplayName "WinRM-HTTP" -Direction Inbound -Protocol TCP -LocalPort 5985 -Action Allow -EA SilentlyContinue
New-NetFirewallRule -DisplayName "WinRM-HTTPS" -Direction Inbound -Protocol TCP -LocalPort 5986 -Action Allow -EA SilentlyContinue
Write-Host "WinRM enabled"
# Disable UAC Token Filtering for RDP access (enables full tokens for local accounts)
Write-Host "Disabling UAC Token Filtering for local accounts..."
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "LocalAccountTokenFilterPolicy" -Value 1
Write-Host "LocalAccountTokenFilterPolicy set to 1 - local accounts will have full tokens via RDP"
Set-State "CONFIG";Restart-Computer -Force;exit}
"CONFIG"{
Write-Host "Configuring CLIENT as standalone machine..."
$podNum=$c.ComputerName -replace '\D',''
$adminDoc="C:\Users\Administrator\Documents"
New-Item -ItemType Directory -Path $adminDoc -Force -EA SilentlyContinue|Out-Null
$memoLines=@()
$memoLines+="=== Domain User Credentials ==="
$memoLines+="Username: $($c.DomainNetbios)\saitou"
$memoLines+="Password: $($c.SaitouPassword)"
$memoLines -join "`r`n"|Out-File "$adminDoc\memo.txt" -Encoding UTF8
Write-Host "Created memo.txt with saitou credentials"
$d="C:\Users\Public\Desktop";$ws=New-Object -ComObject WScript.Shell
$sc=$ws.CreateShortcut("$d\PowerShell.lnk");$sc.TargetPath="C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe";$sc.Save()
# Note: File Server access available via IP address if needed (e.g., \\10.100.1.20\Share)
Write-Host "CLIENT configured as standalone machine"
# Create flag file on Administrator desktop
$adminDesktop="C:\Users\Administrator\Desktop"
New-Item -ItemType Directory -Path $adminDesktop -Force -EA SilentlyContinue|Out-Null
$c.FlagClientAdmin|Out-File "$adminDesktop\flag.txt" -Encoding UTF8
Write-Host "Created flag file on Administrator desktop"
# Enable audit policies
Write-Host "Enabling audit policies..."
$auditResults = @()
@("File System","Registry","Security State Change","User Account Management") | ForEach-Object {
$result = auditpol /set /subcategory:"$_" /success:enable /failure:enable 2>&1
if($LASTEXITCODE -eq 0){Write-Host "✓ Enabled audit for: $_"}else{Write-Warning "✗ Failed audit for: $_ - $result"}
$auditResults += "$_`: $LASTEXITCODE"
}
$auditResults | Out-File "$LogPath\audit-status.log" -Append
Write-Host "Audit policies configuration completed"
Set-State "DONE";Unregister-ScheduledTask -TaskName "ADSetup" -Confirm:$false -EA SilentlyContinue}
"DONE"{Unregister-ScheduledTask -TaskName "ADSetup" -Confirm:$false -EA SilentlyContinue}
}}catch{Write-Error $_;$_|Out-File "$LogPath\error.log" -Append}
Stop-Transcript