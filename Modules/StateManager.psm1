<#
.SYNOPSIS
    Module for managing the application state of PowerLock using a hierarchical registry structure.
    Root: HKLM:\SOFTWARE\PowerLock\ActiveRestrictions
#>

$StateRegistryRoot = "HKLM:\SOFTWARE\PowerLock"
$ActiveRestrictionsKey = "ActiveRestrictions"

function Set-PowerLockState {
    <#
    .DESCRIPTION
        Sets (Locks) a restriction for a specific user.
        Structure: ActiveRestrictions\$Category\$Key\$User
    
    .PARAMETER Category
        The resource type (e.g. "NetworkAdapters", "SystemFiles").
    
    .PARAMETER Key
        The unique identifier for the resource (e.g. Interface GUID, "HostsFile").
        
    .PARAMETER User
        The user account being restricted.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Category,

        [Parameter(Mandatory = $true)]
        [string]$Key,

        [Parameter(Mandatory = $true)]
        [string]$User,
        
        [Parameter(Mandatory = $false)]
        [object]$Value = 1
    )

    # New Path Structure: Root\ActiveRestrictions\Category\ResourceKey\User
    $restrictionPath = Join-Path $StateRegistryRoot "$ActiveRestrictionsKey\$Category\$Key\$User"

    try {
        if (-not (Test-Path $restrictionPath)) {
            New-Item -Path $restrictionPath -Force | Out-Null
            Write-Verbose "Created restriction key: $restrictionPath"
        }

        # Value is standard 1, but we could store metadata here later
        Set-ItemProperty -Path $restrictionPath -Name "Locked" -Value $Value
        Write-Verbose "State saved: $Category\$Key\$User = Locked"
    }
    catch {
        Write-Error "Failed to save state to registry: $_"
    }
}

function Get-PowerLockState {
    <#
    .DESCRIPTION
        Retrieves active restrictions.
        
    .PARAMETER Category
        (Optional) Filter by category.
        
    .OUTPUTS
        Returns a generic list of objects describing the locks.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string]$Category
    )

    $results = @()
    
    # Define root to search
    $searchRoot = Join-Path $StateRegistryRoot $ActiveRestrictionsKey
    if ($Category) {
        $searchRoot = Join-Path $searchRoot $Category
    }

    if (-not (Test-Path $searchRoot)) {
        return $results
    }

    # If Category is provided, we map Get-ChildItem results to ResourceKeys
    if ($Category) {
        $resources = Get-ChildItem -Path $searchRoot
        foreach ($res in $resources) {
            $resKey = $res.PSChildName
            
            # Subkeys of the resource are Users
            $users = Get-ChildItem -Path $res.PSPath
            foreach ($u in $users) {
                $results += [PSCustomObject]@{
                    Category = $Category
                    Key      = $resKey
                    User     = $u.PSChildName
                }
            }
        }
    }
    
    return $results
}

function Clear-PowerLockState {
    <#
    .DESCRIPTION
        Clears the active restrictions state.
        If User is provided, only removes state for that user.
        Otherwise, clears EVERYTHING.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string]$User
    )

    $fullPath = Join-Path $StateRegistryRoot $ActiveRestrictionsKey

    if (-not (Test-Path $fullPath)) { return }

    if ($User) {
        Write-Verbose "Clearing state for User: $User"
        # Iterate Categories
        $categories = Get-ChildItem -Path $fullPath
        foreach ($cat in $categories) {
            # Iterate Keys
            $keys = Get-ChildItem -Path $cat.PSPath
            foreach ($k in $keys) {
                $userPath = Join-Path $k.PSPath $User
                if (Test-Path $userPath) {
                    Remove-Item -Path $userPath -Force
                    Write-Verbose "Removed state: $($cat.PSChildName)\$($k.PSChildName)\$User"
                }

                # Cleanup Key if empty
                if ((Get-ChildItem -Path $k.PSPath).Count -eq 0) {
                    Remove-Item -Path $k.PSPath -Force
                }
            }
            # Cleanup Category if empty
            if ((Get-ChildItem -Path $cat.PSPath).Count -eq 0) {
                Remove-Item -Path $cat.PSPath -Force
            }
        }
    }
    else {
        # Global Clear
        Remove-Item -Path $fullPath -Force -Recurse
        Write-Verbose "State cleared globally: $fullPath"
    }
}

function Test-PowerLockState {
    <#
    .DESCRIPTION
        Checks if a restriction exists.
        If User is provided, checks for that specific user.
        If User is NOT provided, checks if ANY user is restricted on this resource.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Category,

        [Parameter(Mandatory = $true)]
        [string]$Key,
        
        [Parameter(Mandatory = $false)]
        [string]$User
    )
    
    $resourcePath = Join-Path $StateRegistryRoot "$ActiveRestrictionsKey\$Category\$Key"
    
    if (-not (Test-Path $resourcePath)) { return $false }

    if ($User) {
        $userPath = Join-Path $resourcePath $User
        return (Test-Path $userPath)
    }
    else {
        # Check if there are any user subkeys
        $subkeys = Get-ChildItem -Path $resourcePath
        return ($subkeys.Count -gt 0)
    }
}

function Set-PowerLockConfig {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Key,

        [Parameter(Mandatory = $true)]
        [object]$Value,
        
        [Parameter(Mandatory = $false)]
        [string]$PropertyType = "DWord"
    )

    try {
        if (-not (Test-Path $StateRegistryRoot)) {
            New-Item -Path $StateRegistryRoot -Force | Out-Null
        }
        Set-ItemProperty -Path $StateRegistryRoot -Name $Key -Value $Value -Type $PropertyType
    }
    catch {
        Write-Error "Failed to set PowerLock config: $_"
    }
}

function Get-PowerLockConfig {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Key
    )

    if (-not (Test-Path $StateRegistryRoot)) { return $null }
    
    return Get-ItemProperty -Path $StateRegistryRoot -Name $Key -ErrorAction SilentlyContinue | Select-Object -ExpandProperty $Key -ErrorAction SilentlyContinue
}

Export-ModuleMember -Function Set-PowerLockState, Get-PowerLockState, Clear-PowerLockState, Test-PowerLockState, Set-PowerLockConfig, Get-PowerLockConfig
