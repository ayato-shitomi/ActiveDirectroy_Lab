$l="C:\ADLabLogs\backup.log"
"$(Get-Date): Service Start"|Out-File $l -Append
try{
for($i=1;$i -le 15;$i++){
if((Get-Service lsass -EA 0).Status -eq "Running"-and(Get-SmbShare Hasegawa -EA 0)){break}
Start-Sleep 3
}
"$(Get-Date): Dependencies Ready"|Out-File $l -Append
$c=Get-Content "C:\ADLabScripts\config.json"|ConvertFrom-Json
$d="C:\Backup\Hasegawa\"+(Get-Date -F yyyy-MM-dd)
mkdir $d -F|Out-Null

# Secure backup directory - Admin only access
$backupRoot="C:\Backup"
if(!(Test-Path $backupRoot)){mkdir $backupRoot -F|Out-Null}
icacls $backupRoot /inheritance:d 2>&1|Out-Null
icacls $backupRoot /grant:r "Administrators:(OI)(CI)F" "SYSTEM:(OI)(CI)F" 2>&1|Out-Null
icacls $backupRoot /deny "Users:(OI)(CI)RX" "Everyone:(OI)(CI)RX" 2>&1|Out-Null
"$(Get-Date): Accessing Hasegawa share"|Out-File $l -Append
$fs=Get-ChildItem "\\$env:COMPUTERNAME\Hasegawa" -Filter *.log -Recurse -EA 0
$fs|%{Copy-Item $_.FullName $d -F -EA 0}
"$(Get-Date): Service Complete - Files: $($fs.Count)"|Out-File $l -Append
}catch{
"$(Get-Date): Service Error: $_"|Out-File $l -Append
}