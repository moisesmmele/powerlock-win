<#
.SYNOPSIS
    Module for network adapter selection and validation functions.
#>

function Select-TargetAdapters {
    <#
    .DESCRIPTION
        Lists available network adapters, prompts the user for selection,
        and validates that selected adapters are not bridged.
    .OUTPUTS
        [System.Array] List of validated network adapter objects.
    #>
    Write-Host "`n--- AVAILABLE NETWORK ADAPTERS ---" -ForegroundColor Cyan
    $allAdapters = Get-NetAdapter | Sort-Object InterfaceIndex
    
    if (!$allAdapters) {
        throw "No network adapters found on this system."
    }

    $allAdapters | Select-Object InterfaceIndex, Name, Status, InterfaceDescription, MacAddress | Format-Table -AutoSize

    $inputIds = Read-Host "Enter the InterfaceIndex IDs of the adapters to manage (comma-separated)"
    
    if ([string]::IsNullOrWhiteSpace($inputIds)) {
        throw "No adapters selected. Operation aborted."
    }

    $selectedIds = $inputIds -split ',' | ForEach-Object { $_.Trim() }
    $targetAdapters = @()

    foreach ($id in $selectedIds) {
        $adapter = $allAdapters | Where-Object { $_.InterfaceIndex -eq $id }
        
        if (!$adapter) {
            Write-Warning "Adapter with ID '$id' not found. Skipping."
            continue
        }

        # Check for Bridge status
        $isBridged = $false
        
        # Check by description/name hints (Basic check)
        if ($adapter.InterfaceDescription -match "Multiplexor" -or $adapter.Name -match "Bridge") {
            $isBridged = $true
        }

        # Check by Binding (Technical check)
        try {
            $bridgeBinding = Get-NetAdapterBinding -Name $adapter.Name -ComponentID ms_bridge -ErrorAction SilentlyContinue
            if ($bridgeBinding -and $bridgeBinding.Enabled) {
                $isBridged = $true
            }
        }
        catch {
            # Ignore errors if binding check fails, rely on previous check
        }

        if ($isBridged) {
            Write-Error "CRITICAL ERROR: Adapter '$($adapter.Name)' (ID: $id) is BRIDGED or part of a bridge."
            Write-Error "Modifying bridged adapters is prohibited to prevent system instability."
            throw "Operation aborted due to bridged adapter selection."
        }

        $targetAdapters += $adapter
    }

    if ($targetAdapters.Count -eq 0) {
        throw "No valid adapters selected."
    }

    return $targetAdapters
}

Export-ModuleMember -Function Select-TargetAdapters
