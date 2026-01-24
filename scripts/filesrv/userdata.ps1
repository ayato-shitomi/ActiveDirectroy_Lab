<powershell>
# FILESRV Userdata Script - Bootstrap File Server
# This script is executed by EC2 user_data on first boot

$ErrorActionPreference = "Continue"
$LogPath = "C:\ADLabLogs"
$StateFile = "$LogPath\filesrv-state.txt"

# Create directories
if (!(Test-Path $LogPath)) { New-Item -ItemType Directory -Path $LogPath -Force | Out-Null }

Start-Transcript -Path "$LogPath\userdata.log" -Append

# Parameters from Terraform template
$AdminPassword = "${admin_password}"
$DomainName = "${domain_name}"
$DomainNetbios = "${domain_netbios}"
$DomainPassword = "${domain_password}"
$DCIP = "${dc_ip}"
$ComputerName = "${computer_name}"

function Get-CurrentState {
    if (Test-Path $StateFile) {
        return Get-Content $StateFile
    }
    return "INIT"
}

function Set-CurrentState {
    param([string]$State)
    $State | Out-File -FilePath $StateFile -Force
}

function Wait-ForDC {
    Write-Host "Waiting for Domain Controller to be ready..."
    $maxAttempts = 60
    $attempt = 0

    while ($attempt -lt $maxAttempts) {
        try {
            $result = Resolve-DnsName -Name $DomainName -Server $DCIP -DnsOnly -ErrorAction Stop
            Write-Host "Domain Controller is ready."
            return $true
        } catch {
            $attempt++
            Write-Host "Waiting for DC... (attempt $attempt/$maxAttempts)"
            Start-Sleep -Seconds 30
        }
    }

    Write-Error "Domain Controller did not become ready in time"
    return $false
}

try {
    $currentState = Get-CurrentState
    Write-Host "Current state: $currentState"

    switch ($currentState) {
        "INIT" {
            Write-Host "=== Phase 1: Initial Setup ==="

            # Set Administrator password
            Write-Host "Setting Administrator password..."
            $securePassword = ConvertTo-SecureString $AdminPassword -AsPlainText -Force
            Set-LocalUser -Name "Administrator" -Password $securePassword
            Enable-LocalUser -Name "Administrator"

            # Set computer name
            Write-Host "Setting computer name to: $ComputerName"
            Rename-Computer -NewName $ComputerName -Force

            # Configure firewall
            Write-Host "Configuring Windows Firewall..."
            Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled True
            Enable-NetFirewallRule -DisplayGroup "Remote Desktop"
            Enable-NetFirewallRule -DisplayGroup "Windows Remote Management"
            Enable-NetFirewallRule -DisplayGroup "File and Printer Sharing"

            # Enable RDP
            Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name "fDenyTSConnections" -Value 0

            # Disable IE Enhanced Security
            $AdminKey = "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A7-37EF-4b3f-8CFC-4F3A74704073}"
            $UserKey = "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A8-37EF-4b3f-8CFC-4F3A74704073}"
            Set-ItemProperty -Path $AdminKey -Name "IsInstalled" -Value 0 -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $UserKey -Name "IsInstalled" -Value 0 -ErrorAction SilentlyContinue

            Set-CurrentState "WAIT_DC"
            Write-Host "Rebooting after initial setup..."
            Restart-Computer -Force
        }

        "WAIT_DC" {
            Write-Host "=== Phase 2: Configure DNS and Wait for DC ==="

            # Set DNS to DC
            $adapter = Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | Select-Object -First 1
            if ($adapter) {
                Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ServerAddresses @($DCIP, "8.8.8.8")
                Write-Host "DNS configured to use DC: $DCIP"
            }

            # Wait for DC to be ready
            if (Wait-ForDC) {
                Set-CurrentState "JOIN_DOMAIN"
                Write-Host "Proceeding to domain join..."
                Start-Sleep -Seconds 10
                Restart-Computer -Force
            } else {
                Write-Host "DC not ready, will retry on next boot..."
                Start-Sleep -Seconds 60
                Restart-Computer -Force
            }
        }

        "JOIN_DOMAIN" {
            Write-Host "=== Phase 3: Join Domain ==="

            # Set DNS again to ensure it's correct
            $adapter = Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | Select-Object -First 1
            if ($adapter) {
                Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ServerAddresses @($DCIP, "8.8.8.8")
            }

            # Wait a bit more for DC
            Start-Sleep -Seconds 30

            # Create credential
            $SecurePassword = ConvertTo-SecureString $DomainPassword -AsPlainText -Force
            $Credential = New-Object System.Management.Automation.PSCredential("$DomainName\Administrator", $SecurePassword)

            # Join domain
            try {
                Add-Computer -DomainName $DomainName -Credential $Credential -Force -ErrorAction Stop
                Set-CurrentState "CREATE_SHARES"
                Write-Host "Domain join successful. Rebooting..."
                Restart-Computer -Force
            } catch {
                Write-Warning "Domain join failed: $_"
                Write-Host "Will retry on next boot..."
                Start-Sleep -Seconds 60
                Restart-Computer -Force
            }
        }

        "CREATE_SHARES" {
            Write-Host "=== Phase 4: Create File Shares ==="

            # Wait for domain services
            Start-Sleep -Seconds 30

            # Install File Server role
            Install-WindowsFeature -Name FS-FileServer -IncludeManagementTools

            $ShareRoot = "C:\Shares"

            # Create directories
            $Dirs = @(
                "$ShareRoot\Share",
                "$ShareRoot\Public",
                "$ShareRoot\Users\Tanaka",
                "$ShareRoot\Users\Hasegawa",
                "$ShareRoot\Users\Saitou"
            )

            foreach ($Dir in $Dirs) {
                if (!(Test-Path $Dir)) {
                    New-Item -ItemType Directory -Path $Dir -Force | Out-Null
                }
            }

            # Create shares
            $Shares = @(
                @{ Name = "Share"; Path = "$ShareRoot\Share"; FullAccess = @("Everyone") },
                @{ Name = "Public"; Path = "$ShareRoot\Public"; ReadAccess = @("Everyone"); FullAccess = @("Administrators") },
                @{ Name = "Tanaka"; Path = "$ShareRoot\Users\Tanaka"; FullAccess = @("$DomainNetbios\tanaka", "Administrators") },
                @{ Name = "Hasegawa"; Path = "$ShareRoot\Users\Hasegawa"; FullAccess = @("$DomainNetbios\hasegawa", "Administrators") },
                @{ Name = "Saitou"; Path = "$ShareRoot\Users\Saitou"; FullAccess = @("$DomainNetbios\saitou", "Administrators") }
            )

            foreach ($Share in $Shares) {
                if (Get-SmbShare -Name $Share.Name -ErrorAction SilentlyContinue) {
                    Remove-SmbShare -Name $Share.Name -Force
                }

                $params = @{
                    Name = $Share.Name
                    Path = $Share.Path
                    FullAccess = $Share.FullAccess
                }

                if ($Share.ReadAccess) {
                    $params.ReadAccess = $Share.ReadAccess
                }

                New-SmbShare @params
                Write-Host "Created share: $($Share.Name)"
            }

            # Create sample files
            "Shared folder - everyone can read and write" | Out-File "$ShareRoot\Share\readme.txt"
            "Public folder - read only" | Out-File "$ShareRoot\Public\readme.txt"
            "Tanaka's personal folder" | Out-File "$ShareRoot\Users\Tanaka\readme.txt"
            "Hasegawa's personal folder" | Out-File "$ShareRoot\Users\Hasegawa\readme.txt"
            "Saitou's personal folder" | Out-File "$ShareRoot\Users\Saitou\readme.txt"

            Set-CurrentState "COMPLETED"
            Write-Host "=== File Server Setup Completed ==="
        }

        "COMPLETED" {
            Write-Host "File Server setup already completed."
        }

        default {
            Write-Host "Unknown state: $currentState"
        }
    }

} catch {
    Write-Error "Error during setup: $_"
    $_ | Out-File -FilePath "$LogPath\error.log" -Append
} finally {
    Stop-Transcript
}
</powershell>
