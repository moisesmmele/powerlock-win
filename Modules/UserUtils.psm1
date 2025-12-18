<#
.SYNOPSIS
    Module for user selection and management utility functions.
#>

function Select-TargetUser {
    <#
    .DESCRIPTION
        Lists local user accounts and prompts the user to select one.
    .OUTPUTS
        [string] The name of the selected user.
    #>
    Write-Host "`n--- SELECT TARGET USER ---" -ForegroundColor Cyan
    
    try {
        # Get local users (filtering out disabled ones handles most rough edges)
        $users = Get-LocalUser | Where-Object { $_.Enabled -eq $true }
        
        if ($users.Count -eq 0) {
            Write-Warning "No enabled local users found."
            # Fallback to current environment user
            return $env:USERNAME
        }

        # Display users with index
        for ($i = 0; $i -lt $users.Count; $i++) {
            Write-Host "[$i] $($users[$i].Name) ($($users[$i].Description))"
        }

        while ($true) {
            $selection = Read-Host "Select user index (0-$($users.Count - 1))"
            if ($selection -match "^\d+$" -and [int]$selection -ge 0 -and [int]$selection -lt $users.Count) {
                $selectedUser = $users[[int]$selection].Name
                Write-Host "Selected User: $selectedUser" -ForegroundColor Green
                return $selectedUser
            }
            Write-Warning "Invalid selection. Please try again."
        }
    }
    catch {
        Write-Warning "Could not enumerate local users (requires Admin). Defaulting to current user."
        Write-Error $_
        return $env:USERNAME
    }
}

Export-ModuleMember -Function Select-TargetUser
