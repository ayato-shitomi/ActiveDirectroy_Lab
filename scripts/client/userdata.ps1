<powershell>
# CLIENT Userdata Script - Bootstrap Client Machine
# This script is executed by EC2 user_data on first boot

$ErrorActionPreference = "Continue"
$LogPath = "C:\ADLabLogs"
$StateFile = "$LogPath\client-state.txt"

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

            # Install Desktop Experience features (for better client experience)
            Write-Host "Installing Desktop Experience features..."
            Install-WindowsFeature -Name Desktop-Experience -ErrorAction SilentlyContinue

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
                Set-CurrentState "CONFIGURE_CLIENT"
                Write-Host "Domain join successful. Rebooting..."
                Restart-Computer -Force
            } catch {
                Write-Warning "Domain join failed: $_"
                Write-Host "Will retry on next boot..."
                Start-Sleep -Seconds 60
                Restart-Computer -Force
            }
        }

        "CONFIGURE_CLIENT" {
            Write-Host "=== Phase 4: Configure Client ==="

            # Wait for domain services
            Start-Sleep -Seconds 30

            # Add domain users to Remote Desktop Users group
            try {
                Add-LocalGroupMember -Group "Remote Desktop Users" -Member "$DomainNetbios\Domain Users" -ErrorAction SilentlyContinue
                Write-Host "Added Domain Users to Remote Desktop Users group"
            } catch {
                Write-Warning "Could not add Domain Users to RDP group: $_"
            }

            # Create shortcuts on desktop for common tools
            $DesktopPath = "C:\Users\Public\Desktop"

            # CMD shortcut
            $WScriptShell = New-Object -ComObject WScript.Shell
            $Shortcut = $WScriptShell.CreateShortcut("$DesktopPath\Command Prompt.lnk")
            $Shortcut.TargetPath = "C:\Windows\System32\cmd.exe"
            $Shortcut.Save()

            # PowerShell shortcut
            $Shortcut = $WScriptShell.CreateShortcut("$DesktopPath\PowerShell.lnk")
            $Shortcut.TargetPath = "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"
            $Shortcut.Save()

            # File Explorer to file server shortcut
            $Shortcut = $WScriptShell.CreateShortcut("$DesktopPath\File Server.lnk")
            $Shortcut.TargetPath = "\\FILESRV1\Share"
            $Shortcut.Save()

            Set-CurrentState "COMPLETED"
            Write-Host "=== Client Setup Completed ==="
        }

        "COMPLETED" {
            Write-Host "Client setup already completed."
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
