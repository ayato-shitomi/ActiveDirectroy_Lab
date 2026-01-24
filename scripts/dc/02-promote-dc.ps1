# DC Script 02: Promote to Domain Controller
# This script promotes the server to a Domain Controller

param(
    [Parameter(Mandatory=$true)]
    [string]$DomainName,

    [Parameter(Mandatory=$true)]
    [string]$DomainNetbiosName,

    [Parameter(Mandatory=$true)]
    [string]$SafeModePassword
)

$ErrorActionPreference = "Stop"
$LogPath = "C:\ADLabLogs"

if (!(Test-Path $LogPath)) {
    New-Item -ItemType Directory -Path $LogPath -Force | Out-Null
}

Start-Transcript -Path "$LogPath\02-promote-dc.log" -Append

try {
    Write-Host "Promoting server to Domain Controller..."
    Write-Host "Domain Name: $DomainName"
    Write-Host "NetBIOS Name: $DomainNetbiosName"

    # Convert password to secure string
    $SecurePassword = ConvertTo-SecureString $SafeModePassword -AsPlainText -Force

    # Install new AD Forest
    Install-ADDSForest `
        -DomainName $DomainName `
        -DomainNetbiosName $DomainNetbiosName `
        -SafeModeAdministratorPassword $SecurePassword `
        -InstallDns:$true `
        -CreateDnsDelegation:$false `
        -DatabasePath "C:\Windows\NTDS" `
        -LogPath "C:\Windows\NTDS" `
        -SysvolPath "C:\Windows\SYSVOL" `
        -DomainMode "WinThreshold" `
        -ForestMode "WinThreshold" `
        -NoRebootOnCompletion:$false `
        -Force:$true `
        -Verbose

    Write-Host "Domain Controller promotion initiated. Server will restart."

} catch {
    Write-Error "Failed to promote to Domain Controller: $_"
    throw
} finally {
    Stop-Transcript
}
