# FILESRV Script 01: Join Domain
# This script joins the file server to the domain

param(
    [Parameter(Mandatory=$true)]
    [string]$DomainName,

    [Parameter(Mandatory=$true)]
    [string]$DomainUser,

    [Parameter(Mandatory=$true)]
    [string]$DomainPassword,

    [Parameter(Mandatory=$true)]
    [string]$DNSIP
)

$ErrorActionPreference = "Stop"
$LogPath = "C:\ADLabLogs"

if (!(Test-Path $LogPath)) {
    New-Item -ItemType Directory -Path $LogPath -Force | Out-Null
}

Start-Transcript -Path "$LogPath\01-domain-join.log" -Append

try {
    Write-Host "Configuring DNS to point to Domain Controller: $DNSIP"

    # Get network adapter
    $adapter = Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | Select-Object -First 1

    if ($adapter) {
        # Set DNS server to DC
        Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ServerAddresses @($DNSIP, "8.8.8.8")
        Write-Host "DNS configured successfully"
    }

    # Wait for DNS to be reachable
    Write-Host "Testing DNS connectivity..."
    $maxAttempts = 30
    $attempt = 0
    while ($attempt -lt $maxAttempts) {
        try {
            $result = Resolve-DnsName -Name $DomainName -DnsOnly -ErrorAction Stop
            Write-Host "DNS resolution successful for $DomainName"
            break
        } catch {
            $attempt++
            Write-Host "Waiting for DNS... (attempt $attempt/$maxAttempts)"
            Start-Sleep -Seconds 10
        }
    }

    if ($attempt -ge $maxAttempts) {
        Write-Error "DNS is not reachable"
        exit 1
    }

    Write-Host "Joining domain: $DomainName"

    # Create credential
    $SecurePassword = ConvertTo-SecureString $DomainPassword -AsPlainText -Force
    $Credential = New-Object System.Management.Automation.PSCredential("$DomainName\Administrator", $SecurePassword)

    # Join domain
    Add-Computer -DomainName $DomainName -Credential $Credential -Restart -Force

    Write-Host "Domain join initiated. Server will restart."

} catch {
    Write-Error "Failed to join domain: $_"
    throw
} finally {
    Stop-Transcript
}
