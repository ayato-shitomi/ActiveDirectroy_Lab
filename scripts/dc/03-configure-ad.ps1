# DC Script 03: Configure Active Directory
# Creates OUs, Users, and Groups

param(
    [Parameter(Mandatory=$true)]
    [string]$DomainName,

    [Parameter(Mandatory=$false)]
    [string]$UserPassword = "P@ssw0rd!"
)

$ErrorActionPreference = "Stop"
$LogPath = "C:\ADLabLogs"

if (!(Test-Path $LogPath)) {
    New-Item -ItemType Directory -Path $LogPath -Force | Out-Null
}

Start-Transcript -Path "$LogPath\03-configure-ad.log" -Append

try {
    # Import AD Module
    Import-Module ActiveDirectory

    # Get domain DN
    $DomainDN = (Get-ADDomain).DistinguishedName

    Write-Host "Configuring Active Directory for domain: $DomainName"
    Write-Host "Domain DN: $DomainDN"

    # Create OUs
    $OUs = @("LabUsers", "LabComputers", "LabServers", "LabGroups")

    foreach ($OU in $OUs) {
        $OUPath = "OU=$OU,$DomainDN"
        if (!(Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$OUPath'" -ErrorAction SilentlyContinue)) {
            New-ADOrganizationalUnit -Name $OU -Path $DomainDN -ProtectedFromAccidentalDeletion $false
            Write-Host "Created OU: $OU"
        } else {
            Write-Host "OU already exists: $OU"
        }
    }

    # Convert password to secure string
    $SecurePassword = ConvertTo-SecureString $UserPassword -AsPlainText -Force

    # Create Users
    $Users = @(
        @{
            Name = "Taro Tanaka"
            SamAccountName = "tanaka"
            GivenName = "Taro"
            Surname = "Tanaka"
            Description = "Lab User - Tanaka"
        },
        @{
            Name = "Hanako Hasegawa"
            SamAccountName = "hasegawa"
            GivenName = "Hanako"
            Surname = "Hasegawa"
            Description = "Lab User - Hasegawa"
        },
        @{
            Name = "Jiro Saitou"
            SamAccountName = "saitou"
            GivenName = "Jiro"
            Surname = "Saitou"
            Description = "Lab User - Saitou"
        }
    )

    $UserOU = "OU=LabUsers,$DomainDN"

    foreach ($User in $Users) {
        if (!(Get-ADUser -Filter "SamAccountName -eq '$($User.SamAccountName)'" -ErrorAction SilentlyContinue)) {
            New-ADUser `
                -Name $User.Name `
                -SamAccountName $User.SamAccountName `
                -UserPrincipalName "$($User.SamAccountName)@$DomainName" `
                -GivenName $User.GivenName `
                -Surname $User.Surname `
                -Description $User.Description `
                -Path $UserOU `
                -AccountPassword $SecurePassword `
                -PasswordNeverExpires $true `
                -ChangePasswordAtLogon $false `
                -Enabled $true
            Write-Host "Created user: $($User.SamAccountName)"
        } else {
            Write-Host "User already exists: $($User.SamAccountName)"
        }
    }

    # Create Groups
    $GroupOU = "OU=LabGroups,$DomainDN"

    $Groups = @(
        @{
            Name = "GG_Lab_Users"
            Description = "Global Group - All Lab Users"
            GroupScope = "Global"
        },
        @{
            Name = "GG_Lab_Admins"
            Description = "Global Group - Lab Administrators"
            GroupScope = "Global"
        }
    )

    foreach ($Group in $Groups) {
        if (!(Get-ADGroup -Filter "Name -eq '$($Group.Name)'" -ErrorAction SilentlyContinue)) {
            New-ADGroup `
                -Name $Group.Name `
                -SamAccountName $Group.Name `
                -GroupCategory Security `
                -GroupScope $Group.GroupScope `
                -Description $Group.Description `
                -Path $GroupOU
            Write-Host "Created group: $($Group.Name)"
        } else {
            Write-Host "Group already exists: $($Group.Name)"
        }
    }

    # Add users to groups
    Write-Host "Adding users to GG_Lab_Users group..."
    foreach ($User in $Users) {
        try {
            Add-ADGroupMember -Identity "GG_Lab_Users" -Members $User.SamAccountName -ErrorAction SilentlyContinue
            Write-Host "Added $($User.SamAccountName) to GG_Lab_Users"
        } catch {
            Write-Host "User $($User.SamAccountName) may already be a member of GG_Lab_Users"
        }
    }

    Write-Host "Active Directory configuration completed successfully."

    # Display summary
    Write-Host "`n========== AD Configuration Summary =========="
    Write-Host "OUs Created:"
    Get-ADOrganizationalUnit -Filter * | Where-Object { $_.Name -like "Lab*" } | Format-Table Name, DistinguishedName -AutoSize

    Write-Host "Users Created:"
    Get-ADUser -Filter * -SearchBase $UserOU | Format-Table Name, SamAccountName, Enabled -AutoSize

    Write-Host "Groups Created:"
    Get-ADGroup -Filter * -SearchBase $GroupOU | Format-Table Name, GroupScope -AutoSize
    Write-Host "=============================================="

} catch {
    Write-Error "Failed to configure Active Directory: $_"
    throw
} finally {
    Stop-Transcript
}
