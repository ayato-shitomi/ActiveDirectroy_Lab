<powershell>
# DC Userdata Script - Bootstrap Domain Controller
# This script is executed by EC2 user_data on first boot

$ErrorActionPreference = "Continue"
$LogPath = "C:\ADLabLogs"
$ScriptPath = "C:\ADLabScripts"
$StateFile = "$LogPath\dc-state.txt"

# Create directories
if (!(Test-Path $LogPath)) { New-Item -ItemType Directory -Path $LogPath -Force | Out-Null }
if (!(Test-Path $ScriptPath)) { New-Item -ItemType Directory -Path $ScriptPath -Force | Out-Null }

Start-Transcript -Path "$LogPath\userdata.log" -Append

# Parameters from Terraform template
$AdminPassword = "${admin_password}"
$DomainName = "${domain_name}"
$DomainNetbios = "${domain_netbios}"
$DomainPassword = "${domain_password}"
$DCIP = "${dc_ip}"
$ComputerName = "${computer_name}"
$UserPasswordTanaka = "${user_password_tanaka}"
$UserPasswordHasegawa = "${user_password_hasegawa}"
$UserPasswordSaitou = "${user_password_saitou}"

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

function Set-StaticIP {
    Write-Host "Configuring static IP: $DCIP"

    # Get the primary network adapter
    $adapter = Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | Select-Object -First 1

    if ($adapter) {
        # Get current IP configuration
        $currentIP = Get-NetIPAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 | Select-Object -First 1
        $currentGateway = Get-NetRoute -InterfaceIndex $adapter.ifIndex -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue | Select-Object -First 1

        # Remove DHCP and set static IP
        Set-NetIPInterface -InterfaceIndex $adapter.ifIndex -Dhcp Disabled -ErrorAction SilentlyContinue

        # Remove existing IP configuration
        Remove-NetIPAddress -InterfaceIndex $adapter.ifIndex -Confirm:$false -ErrorAction SilentlyContinue
        Remove-NetRoute -InterfaceIndex $adapter.ifIndex -Confirm:$false -ErrorAction SilentlyContinue

        # Calculate gateway (first IP in subnet)
        $subnet = $DCIP -replace '\.\d+$', '.1'

        # Set new static IP
        New-NetIPAddress -InterfaceIndex $adapter.ifIndex -IPAddress $DCIP -PrefixLength 24 -DefaultGateway $subnet

        # Set DNS to localhost (will be DNS server)
        Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ServerAddresses @("127.0.0.1", "8.8.8.8")

        Write-Host "Static IP configured successfully"
    }
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

            # Enable Administrator account
            Enable-LocalUser -Name "Administrator"

            # Set computer name
            Write-Host "Setting computer name to: $ComputerName"
            Rename-Computer -NewName $ComputerName -Force

            # Configure firewall for AD
            Write-Host "Configuring Windows Firewall..."
            Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled True
            Enable-NetFirewallRule -DisplayGroup "Remote Desktop"
            Enable-NetFirewallRule -DisplayGroup "Windows Remote Management"

            # Disable IE Enhanced Security
            $AdminKey = "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A7-37EF-4b3f-8CFC-4F3A74704073}"
            $UserKey = "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A8-37EF-4b3f-8CFC-4F3A74704073}"
            Set-ItemProperty -Path $AdminKey -Name "IsInstalled" -Value 0 -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $UserKey -Name "IsInstalled" -Value 0 -ErrorAction SilentlyContinue

            # Enable RDP
            Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name "fDenyTSConnections" -Value 0
            Enable-NetFirewallRule -DisplayGroup "Remote Desktop"

            Set-CurrentState "INSTALL_ADDS"
            Write-Host "Rebooting to continue with AD DS installation..."
            Restart-Computer -Force
        }

        "INSTALL_ADDS" {
            Write-Host "=== Phase 2: Installing AD DS Role ==="

            # Set static IP before AD installation
            Set-StaticIP
            Start-Sleep -Seconds 5

            # Install AD DS Role
            Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools
            Install-WindowsFeature -Name DNS -IncludeManagementTools
            Install-WindowsFeature -Name RSAT-AD-Tools -IncludeAllSubFeature
            Install-WindowsFeature -Name RSAT-DNS-Server

            Set-CurrentState "PROMOTE_DC"
            Write-Host "Rebooting before DC promotion..."
            Restart-Computer -Force
        }

        "PROMOTE_DC" {
            Write-Host "=== Phase 3: Promoting to Domain Controller ==="

            $SecurePassword = ConvertTo-SecureString $DomainPassword -AsPlainText -Force

            Install-ADDSForest `
                -DomainName $DomainName `
                -DomainNetbiosName $DomainNetbios `
                -SafeModeAdministratorPassword $SecurePassword `
                -InstallDns:$true `
                -CreateDnsDelegation:$false `
                -DatabasePath "C:\Windows\NTDS" `
                -LogPath "C:\Windows\NTDS" `
                -SysvolPath "C:\Windows\SYSVOL" `
                -DomainMode "WinThreshold" `
                -ForestMode "WinThreshold" `
                -NoRebootOnCompletion:$false `
                -Force:$true

            Set-CurrentState "CONFIGURE_AD"
            # Server will auto-restart after DC promotion
        }

        "CONFIGURE_AD" {
            Write-Host "=== Phase 4: Configuring Active Directory ==="

            # Wait for AD DS to be fully operational
            $maxAttempts = 30
            $attempt = 0
            while ($attempt -lt $maxAttempts) {
                try {
                    Import-Module ActiveDirectory -ErrorAction Stop
                    Get-ADDomain -ErrorAction Stop
                    break
                } catch {
                    $attempt++
                    Write-Host "Waiting for AD DS to be ready... (attempt $attempt/$maxAttempts)"
                    Start-Sleep -Seconds 10
                }
            }

            if ($attempt -ge $maxAttempts) {
                Write-Error "AD DS did not become ready in time"
                exit 1
            }

            # Get domain DN
            $DomainDN = (Get-ADDomain).DistinguishedName

            # Create OUs
            $OUs = @("LabUsers", "LabComputers", "LabServers", "LabGroups")
            foreach ($OU in $OUs) {
                $OUPath = "OU=$OU,$DomainDN"
                if (!(Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$OUPath'" -ErrorAction SilentlyContinue)) {
                    New-ADOrganizationalUnit -Name $OU -Path $DomainDN -ProtectedFromAccidentalDeletion $false
                    Write-Host "Created OU: $OU"
                }
            }

            # Create Users with individual passwords
            $Users = @(
                @{ Name = "Taro Tanaka"; SamAccountName = "tanaka"; GivenName = "Taro"; Surname = "Tanaka"; Password = $UserPasswordTanaka },
                @{ Name = "Hanako Hasegawa"; SamAccountName = "hasegawa"; GivenName = "Hanako"; Surname = "Hasegawa"; Password = $UserPasswordHasegawa },
                @{ Name = "Jiro Saitou"; SamAccountName = "saitou"; GivenName = "Jiro"; Surname = "Saitou"; Password = $UserPasswordSaitou }
            )

            $UserOU = "OU=LabUsers,$DomainDN"
            foreach ($User in $Users) {
                if (!(Get-ADUser -Filter "SamAccountName -eq '$($User.SamAccountName)'" -ErrorAction SilentlyContinue)) {
                    $SecureUserPassword = ConvertTo-SecureString $User.Password -AsPlainText -Force
                    New-ADUser `
                        -Name $User.Name `
                        -SamAccountName $User.SamAccountName `
                        -UserPrincipalName "$($User.SamAccountName)@$DomainName" `
                        -GivenName $User.GivenName `
                        -Surname $User.Surname `
                        -Path $UserOU `
                        -AccountPassword $SecureUserPassword `
                        -PasswordNeverExpires $true `
                        -ChangePasswordAtLogon $false `
                        -Enabled $true
                    Write-Host "Created user: $($User.SamAccountName)"
                }
            }

            # Create Group
            $GroupOU = "OU=LabGroups,$DomainDN"
            if (!(Get-ADGroup -Filter "Name -eq 'GG_Lab_Users'" -ErrorAction SilentlyContinue)) {
                New-ADGroup `
                    -Name "GG_Lab_Users" `
                    -SamAccountName "GG_Lab_Users" `
                    -GroupCategory Security `
                    -GroupScope Global `
                    -Description "Global Group - All Lab Users" `
                    -Path $GroupOU
                Write-Host "Created group: GG_Lab_Users"
            }

            # Add users to group
            foreach ($User in $Users) {
                Add-ADGroupMember -Identity "GG_Lab_Users" -Members $User.SamAccountName -ErrorAction SilentlyContinue
            }

            Set-CurrentState "COMPLETED"
            Write-Host "=== Domain Controller Setup Completed ==="
        }

        "COMPLETED" {
            Write-Host "Domain Controller setup already completed."
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
