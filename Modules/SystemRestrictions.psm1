<#
.SYNOPSIS
    Module for generic system restriction primitives.
    Provides abstract functions to lock/unlock files and registry keys, and set registry values.
    Does NOT contain specific business logic or hardcoded paths.
#>

function Block-RegistryWrite {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$RegistryPath,

        [Parameter(Mandatory = $true)]
        [string]$UserAccount
    )
    
    Write-Verbose "Blocking write access to registry path: $RegistryPath for user $UserAccount"

    # We need to translate the PowerShell drive path (HKLM:\...) to a .NET Registry Key if possible, 
    # or just use the standard ACL cmdlets. 
    # However, the original script used .NET classes for granular control. Let's stick to that for robustness,
    # but clean paths are tricky. Let's use Get-Acl/Set-Acl for abstraction if possible, or mapping.
    
    # Original script logic used [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey.
    # To be truly abstract, we should handle HKLM and HKCU.
    
    # Simple parsing for standard hives
    $hive = $null
    $subKeyPath = $null

    if ($RegistryPath -match "^HKLM:\\?(.*)") {
        $hive = [Microsoft.Win32.Registry]::LocalMachine
        $subKeyPath = $matches[1]
    }
    elseif ($RegistryPath -match "^HKCU:\\?(.*)") {
        $hive = [Microsoft.Win32.Registry]::CurrentUser
        $subKeyPath = $matches[1]
    }
    elseif ($RegistryPath -match "^SYSTEM\\CurrentControlSet") {
        # Handle the specific case passed often (SYSTEM\...) -> HKLM relative
        $hive = [Microsoft.Win32.Registry]::LocalMachine
        $subKeyPath = $RegistryPath
    }
    else {
        Write-Error "Unsupported registry path format for Block-RegistryWrite: $RegistryPath. Use HKLM:\... or SYSTEM\..."
        return
    }

    try {
        $key = $hive.OpenSubKey($subKeyPath, [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree, [System.Security.AccessControl.RegistryRights]::ChangePermissions)
        if ($key) {
            $acl = $key.GetAccessControl()

            $denyRule = New-Object System.Security.AccessControl.RegistryAccessRule(
                $UserAccount,
                "SetValue,CreateSubKey,Delete,ChangePermissions",
                "ContainerInherit,ObjectInherit",
                "None",
                "Deny"
            )
            $acl.AddAccessRule($denyRule)
            $key.SetAccessControl($acl)
            Write-Verbose "Successfully locked registry key: $RegistryPath"
        }
        else {
            Write-Warning "Registry key not found: $RegistryPath"
        }
    }
    catch {
        Write-Error "Failed to block registry key '$RegistryPath': $_"
    }
}

function Unblock-RegistryWrite {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$RegistryPath,

        [Parameter(Mandatory = $false)]
        [string]$UserAccount
    )

    Write-Verbose "Unblocking access to registry path: $RegistryPath (User: $(if($UserAccount){$UserAccount}else{'ALL'}))"

    # Similar hive parsing
    $hive = $null
    $subKeyPath = $null

    if ($RegistryPath -match "^HKLM:\\?(.*)") {
        $hive = [Microsoft.Win32.Registry]::LocalMachine
        $subKeyPath = $matches[1]
    }
    elseif ($RegistryPath -match "^HKCU:\\?(.*)") {
        $hive = [Microsoft.Win32.Registry]::CurrentUser
        $subKeyPath = $matches[1]
    }
    elseif ($RegistryPath -match "^SYSTEM\\CurrentControlSet") {
        $hive = [Microsoft.Win32.Registry]::LocalMachine
        $subKeyPath = $RegistryPath
    }
    else {
        Write-Error "Unsupported registry path format for Unblock-RegistryWrite: $RegistryPath"
        return
    }

    try {
        $key = $hive.OpenSubKey($subKeyPath, [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree, [System.Security.AccessControl.RegistryRights]::ChangePermissions)
        if ($key) {
            $acl = $key.GetAccessControl()
            $rules = $acl.GetAccessRules($true, $false, [System.Security.Principal.NTAccount])
            
            foreach ($rule in $rules) {
                # Filter by Deny rule
                if ($rule.AccessControlType -eq "Deny") { 
                    # If UserAccount is specified, check identity match
                    if ($UserAccount) {
                        # Clean up identity strings for comparison (e.g. "HOSTNAME\User" vs "User")
                        # Simple match: check if the rule identity contains the requested username
                        if ($rule.IdentityReference.Value -like "*$UserAccount") {
                            $acl.RemoveAccessRule($rule) 
                            Write-Verbose "Removed Deny rule for specific user $($rule.IdentityReference)"
                        }
                    }
                    else {
                        # No specific user, remove all Deny rules (Legacy/Emergency Unblock)
                        $acl.RemoveAccessRule($rule) 
                        Write-Verbose "Removed Deny rule for user $($rule.IdentityReference)"
                    }
                }
            }
            $key.SetAccessControl($acl)
        }
        else {
            Write-Warning "Registry key not found: $RegistryPath"
        }
    }
    catch {
        Write-Error "Failed to unlock registry key '$RegistryPath': $_"
    }
}

function Block-FileWrite {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [Parameter(Mandatory = $true)]
        [string]$UserAccount
    )

    if (-not (Test-Path $FilePath)) {
        Write-Warning "File not found: $FilePath"
        return
    }

    try {
        $acl = Get-Acl $FilePath
        $denyRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            $UserAccount, 
            "Write,Delete,ChangePermissions", 
            "Deny"
        )
        $acl.AddAccessRule($denyRule)
        Set-Acl $FilePath $acl
        Write-Verbose "Blocked write access to file: $FilePath"
    }
    catch {
        Write-Error "Failed to block file '$FilePath': $_"
    }
}

function Unblock-FileWrite {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$FilePath,
        
        [Parameter(Mandatory = $false)]
        [string]$UserAccount
    )

    if (-not (Test-Path $FilePath)) {
        Write-Warning "File not found: $FilePath"
        return
    }

    try {
        $acl = Get-Acl $FilePath
        $rules = $acl.GetAccessRules($true, $false, [System.Security.Principal.NTAccount])
        
        foreach ($rule in $rules) {
            if ($rule.AccessControlType -eq "Deny") { 
                if ($UserAccount) {
                    if ($rule.IdentityReference.Value -like "*$UserAccount") {
                        $acl.RemoveAccessRule($rule)
                        Write-Verbose "Unblocked file for specific user: $UserAccount"
                    }
                }
                else {
                    $acl.RemoveAccessRule($rule)
                    Write-Verbose "Unblocked file access (Global Deny removal)"
                }
            }
        }
        Set-Acl $FilePath $acl
    }
    catch {
        Write-Error "Failed to unlock file '$FilePath': $_"
    }
}

function Set-RegistryValue {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$Value,

        [Parameter(Mandatory = $false)]
        [string]$PropertyType = "DWord"
    )

    try {
        if (-not (Test-Path $Path)) {
            New-Item $Path -Force | Out-Null
        }
        Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $PropertyType
        Write-Verbose "Set registry value $Name = $Value at $Path"
    }
    catch {
        Write-Error "Failed to set registry value at '$Path': $_"
    }
}

Export-ModuleMember -Function Block-RegistryWrite, Unblock-RegistryWrite, Block-FileWrite, Unblock-FileWrite, Set-RegistryValue
