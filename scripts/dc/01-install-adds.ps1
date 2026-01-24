# DC Script 01: Install Active Directory Domain Services
# This script installs the AD DS role and management tools

$ErrorActionPreference = "Stop"
$LogPath = "C:\ADLabLogs"

if (!(Test-Path $LogPath)) {
    New-Item -ItemType Directory -Path $LogPath -Force | Out-Null
}

Start-Transcript -Path "$LogPath\01-install-adds.log" -Append

try {
    Write-Host "Installing AD DS Role and Management Tools..."

    # Install AD DS Role
    Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools -Verbose

    # Install DNS Server Role
    Install-WindowsFeature -Name DNS -IncludeManagementTools -Verbose

    # Install RSAT tools
    Install-WindowsFeature -Name RSAT-AD-Tools -IncludeAllSubFeature -Verbose
    Install-WindowsFeature -Name RSAT-DNS-Server -Verbose

    Write-Host "AD DS Role installation completed successfully."

} catch {
    Write-Error "Failed to install AD DS Role: $_"
    throw
} finally {
    Stop-Transcript
}
