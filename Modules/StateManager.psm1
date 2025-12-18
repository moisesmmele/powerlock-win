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
        Sets a state value in a specific category subkey.
        Example: Category="Adapters", Key="{GUID}", Value=1
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Category, # e.g., "Adapters", "Files", "System"

        [Parameter(Mandatory = $true)]
        [string]$Key,      # The specific item ID (GUID, Filename, FeatureName)

        [Parameter(Mandatory = $false)]
        [object]$Value = 1,

        [Parameter(Mandatory = $false)]
        [string]$PropertyType = "DWord"
    )

    $categoryPath = Join-Path $StateRegistryRoot "$ActiveRestrictionsKey\$Category"

    try {
        if (-not (Test-Path $categoryPath)) {
            New-Item -Path $categoryPath -Force | Out-Null
            Write-Verbose "Created category key: $categoryPath"
        }

        Set-ItemProperty -Path $categoryPath -Name $Key -Value $Value -Type $PropertyType
        Write-Verbose "State saved: [$Category] $Key = $Value"
    }
    catch {
        Write-Error "Failed to save state to registry: $_"
    }
}

function Get-PowerLockState {
    <#
    .DESCRIPTION
        Retrieves all items within a specific category.
        Returns a Hashtable where Keys are the item names and Values are the stored values.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Category
    )

    $categoryPath = Join-Path $StateRegistryRoot "$ActiveRestrictionsKey\$Category"
    $results = @{}

    if (-not (Test-Path $categoryPath)) {
        return $results
    }

    try {
        $properties = Get-ItemProperty -Path $categoryPath
        
        # Filter out standard PowerShell properties
        $excludedProps = @("PSPath", "PSParentPath", "PSChildName", "PSDrive", "PSProvider")
        
        foreach ($prop in $properties.PSObject.Properties) {
            if ($excludedProps -notcontains $prop.Name) {
                $results[$prop.Name] = $prop.Value
            }
        }
        return $results
    }
    catch {
        Write-Error "Failed to retrieve state category '$Category': $_"
        return $results
    }
}

function Clear-PowerLockState {
    <#
    .DESCRIPTION
        Clears the entire active restrictions state.
    #>
    [CmdletBinding()]
    param ()

    $fullPath = Join-Path $StateRegistryRoot $ActiveRestrictionsKey

    if (Test-Path $fullPath) {
        Remove-Item -Path $fullPath -Force -Recurse
        Write-Verbose "State cleared: $fullPath"
    }
}

function Test-PowerLockState {
    <#
    .DESCRIPTION
        Checks if a specific Key exists in a Category.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Category,

        [Parameter(Mandatory = $true)]
        [string]$Key
    )
    
    $categoryPath = Join-Path $StateRegistryRoot "$ActiveRestrictionsKey\$Category"
    
    if (-not (Test-Path $categoryPath)) { return $false }

    $val = Get-ItemProperty -Path $categoryPath -Name $Key -ErrorAction SilentlyContinue
    if ($val) { return $true }
    return $false
}

function Set-PowerLockConfig {
    <#
    .DESCRIPTION
        Sets a configuration value in the PowerLock root key (HKLM:\SOFTWARE\PowerLock).
        This is for settings that are not ephemeral "ActiveRestrictions".
    #>
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
        Write-Verbose "Config Saved: $Key = $Value"
    }
    catch {
        Write-Error "Failed to set PowerLock config: $_"
    }
}

function Get-PowerLockConfig {
    <#
    .DESCRIPTION
        Retrieves a configuration value from the PowerLock root key.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Key
    )

    if (-not (Test-Path $StateRegistryRoot)) { return $null }
    
    return Get-ItemProperty -Path $StateRegistryRoot -Name $Key -ErrorAction SilentlyContinue | Select-Object -ExpandProperty $Key -ErrorAction SilentlyContinue
}

Export-ModuleMember -Function Set-PowerLockState, Get-PowerLockState, Clear-PowerLockState, Test-PowerLockState, Set-PowerLockConfig, Get-PowerLockConfig
