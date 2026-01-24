# FILESRV Script 02: Create File Shares
# This script creates the shared folders

param(
    [Parameter(Mandatory=$false)]
    [string]$DomainNetbios = "LAB"
)

$ErrorActionPreference = "Stop"
$LogPath = "C:\ADLabLogs"
$ShareRoot = "C:\Shares"

if (!(Test-Path $LogPath)) {
    New-Item -ItemType Directory -Path $LogPath -Force | Out-Null
}

Start-Transcript -Path "$LogPath\02-create-shares.log" -Append

try {
    Write-Host "Installing File Server Role..."
    Install-WindowsFeature -Name FS-FileServer -IncludeManagementTools

    Write-Host "Creating share directory structure..."

    # Create root share directory
    if (!(Test-Path $ShareRoot)) {
        New-Item -ItemType Directory -Path $ShareRoot -Force | Out-Null
    }

    # Define shares
    $Shares = @(
        @{
            Name = "Share"
            Path = "$ShareRoot\Share"
            Description = "General Share - Read/Write for all domain users"
            FullAccess = @("$DomainNetbios\Domain Users")
        },
        @{
            Name = "Public"
            Path = "$ShareRoot\Public"
            Description = "Public Share - Read Only for all domain users"
            ReadAccess = @("$DomainNetbios\Domain Users")
            FullAccess = @("$DomainNetbios\Domain Admins")
        },
        @{
            Name = "Tanaka"
            Path = "$ShareRoot\Users\Tanaka"
            Description = "Personal folder for Tanaka"
            FullAccess = @("$DomainNetbios\tanaka", "$DomainNetbios\Domain Admins")
        },
        @{
            Name = "Hasegawa"
            Path = "$ShareRoot\Users\Hasegawa"
            Description = "Personal folder for Hasegawa"
            FullAccess = @("$DomainNetbios\hasegawa", "$DomainNetbios\Domain Admins")
        },
        @{
            Name = "Saitou"
            Path = "$ShareRoot\Users\Saitou"
            Description = "Personal folder for Saitou"
            FullAccess = @("$DomainNetbios\saitou", "$DomainNetbios\Domain Admins")
        }
    )

    foreach ($Share in $Shares) {
        Write-Host "Processing share: $($Share.Name)"

        # Create directory if it doesn't exist
        if (!(Test-Path $Share.Path)) {
            New-Item -ItemType Directory -Path $Share.Path -Force | Out-Null
            Write-Host "Created directory: $($Share.Path)"
        }

        # Remove existing share if exists
        if (Get-SmbShare -Name $Share.Name -ErrorAction SilentlyContinue) {
            Remove-SmbShare -Name $Share.Name -Force
            Write-Host "Removed existing share: $($Share.Name)"
        }

        # Create share with permissions
        $shareParams = @{
            Name = $Share.Name
            Path = $Share.Path
            Description = $Share.Description
            FullAccess = @("Administrators")
        }

        if ($Share.FullAccess) {
            $shareParams.FullAccess += $Share.FullAccess
        }

        if ($Share.ReadAccess) {
            $shareParams.ReadAccess = $Share.ReadAccess
        }

        New-SmbShare @shareParams
        Write-Host "Created share: $($Share.Name)"

        # Set NTFS permissions
        $acl = Get-Acl $Share.Path

        # Reset ACL
        $acl.SetAccessRuleProtection($true, $false)
        $acl.Access | ForEach-Object { $acl.RemoveAccessRule($_) } | Out-Null

        # Add SYSTEM - Full Control
        $systemRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            "SYSTEM", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow"
        )
        $acl.AddAccessRule($systemRule)

        # Add Administrators - Full Control
        $adminRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            "Administrators", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow"
        )
        $acl.AddAccessRule($adminRule)

        # Add specific permissions based on share type
        if ($Share.FullAccess) {
            foreach ($identity in $Share.FullAccess) {
                try {
                    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                        $identity, "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow"
                    )
                    $acl.AddAccessRule($rule)
                    Write-Host "Added FullControl for: $identity"
                } catch {
                    Write-Warning "Could not add permission for: $identity - $_"
                }
            }
        }

        if ($Share.ReadAccess) {
            foreach ($identity in $Share.ReadAccess) {
                try {
                    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                        $identity, "ReadAndExecute", "ContainerInherit,ObjectInherit", "None", "Allow"
                    )
                    $acl.AddAccessRule($rule)
                    Write-Host "Added ReadAndExecute for: $identity"
                } catch {
                    Write-Warning "Could not add permission for: $identity - $_"
                }
            }
        }

        Set-Acl -Path $Share.Path -AclObject $acl
        Write-Host "NTFS permissions set for: $($Share.Path)"
    }

    # Create sample files
    Write-Host "Creating sample files..."

    "This is a shared file. Everyone can read and write." | Out-File "$ShareRoot\Share\readme.txt"
    "This is a public file. Read-only for domain users." | Out-File "$ShareRoot\Public\readme.txt"
    "Tanaka's personal folder" | Out-File "$ShareRoot\Users\Tanaka\readme.txt"
    "Hasegawa's personal folder" | Out-File "$ShareRoot\Users\Hasegawa\readme.txt"
    "Saitou's personal folder" | Out-File "$ShareRoot\Users\Saitou\readme.txt"

    Write-Host "`n========== File Shares Summary =========="
    Get-SmbShare | Where-Object { $_.Path -like "$ShareRoot*" } | Format-Table Name, Path, Description -AutoSize
    Write-Host "========================================="

    Write-Host "File shares created successfully."

} catch {
    Write-Error "Failed to create file shares: $_"
    throw
} finally {
    Stop-Transcript
}
