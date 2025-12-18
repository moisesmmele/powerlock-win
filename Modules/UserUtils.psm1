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
        $currentUser = $env:USERNAME
        # Get local users (Enabled only, and EXCLUDE current user)
        $users = Get-LocalUser | Where-Object { $_.Enabled -eq $true -and $_.Name -ne $currentUser }
        
        if ($users.Count -eq 0) {
            Write-Error "No other enabled local users found."
            Write-Error "STRICT MODE: You cannot restrict the same account you are running this script with ($currentUser)."
            Write-Error "Please run this script from a DIFFERENT Administrator account (e.g. Backup Admin) to lock your target user."
            throw "NoSelectableUsersException"
        }

        # Display users with index
        for ($i = 0; $i -lt $users.Count; $i++) {
            Write-Host "[$i] $($users[$i].Name) ($($users[$i].Description))"
        }

        while ($true) {
            $selection = Read-Host "Select user index (0-$($users.Count - 1))"
            if ($selection -match "^\d+$" -and [int]$selection -ge 0 -and [int]$selection -lt $users.Count) {
                $selectedUser = $users[[int]$selection].Name
                
                if ($selectedUser -eq $env:USERNAME) {
                    Write-Error "CRITICAL: The current user was somehow selected. Aborting for safety."
                    exit
                }

                Write-Host "Selected User: $selectedUser" -ForegroundColor Green
                return $selectedUser
            }
            Write-Warning "Invalid selection. Please try again."
        }
    }
    catch {
        if ($_.Exception.Message -eq "NoSelectableUsersException") {
            exit
        }
        Write-Warning "Could not enumerate local users (requires Admin)."
        Write-Error $_
        exit
    }
}

function Initialize-SecondaryAdmin {
    <#
    .DESCRIPTION
        Checks if the built-in Administrator account is active.
        If not, prompts to enable it and set a password.
        If enabled here, can attempt to auto-escalate the running script context.
    #>
    [CmdletBinding()]
    param()

    Write-Host "`n[*] Checking for Backup Administrator Account..." -ForegroundColor Cyan
    try {
        # Find built-in Administrator by SID (ends in -500)
        $adminAccount = Get-LocalUser | Where-Object { $_.SID.Value -match "-500$" } | Select-Object -First 1
        
        if (-not $adminAccount) {
            # Fallback if somehow -500 SID not found and 'Administrator' name not found
            Write-Warning "Could not identify the built-in Administrator account."
        }

        # Step 1: Explain Context & Skip Option
        Write-Host "For this script to work safely, it is required to use an administrator account DIFFERENT than the account you want to lock."
        Write-Host "This account can be used to run locked features if needed, and for unlocking your system."
        Write-Host "If you're already running this script as a SECONDARY administrator account, you can skip the next steps."
        
        $skip = Read-Host "Do you want to skip? (y/n)"
        if ($skip -eq 'y') {
            return $null
        }

        # Step 2: Propose Built-in Admin
        Write-Host "Windows has a Built-in Administrator Account. Do you want to enable and use it?"
        $useBuiltIn = Read-Host "(y/n)"

        if ($useBuiltIn -eq 'y') {
            if ($adminAccount -and -not $adminAccount.Enabled) {
                Write-Host "The built-in Administrator account ('$($adminAccount.Name)') is currently DISABLED." -ForegroundColor Yellow
                
                $enableAdmin = Read-Host "Do you want to enable the '$($adminAccount.Name)' account and set a password? (y/n)"
                if ($enableAdmin -eq 'y') {
                    Write-Host "`n--- PASSWORD SETUP ---" -ForegroundColor Cyan
                    Write-Host "Please choose a STRONG password (random, lengthy, and challenging)."
                    Write-Host "IMPORTANT: Write this password down on PHYSICAL PAPER and store it safely." -ForegroundColor Red
                    
                    while ($true) {
                        $pass1 = Read-Host "Enter new password for '$($adminAccount.Name)'" -AsSecureString
                        $pass2 = Read-Host "Verify password" -AsSecureString
                        
                        if ((ConvertFrom-SecureString $pass1) -eq (ConvertFrom-SecureString $pass2)) {
                            Set-LocalUser -Name $adminAccount.Name -Password $pass1 -Description "PowerLock Default Admin"
                            Enable-LocalUser -Name $adminAccount.Name
                            Write-Host "[SUCCESS] Administrator account ('$($adminAccount.Name)') enabled." -ForegroundColor Green
                            
                            # Return credential for auto-escalation
                            return @{
                                AccountName = $adminAccount.Name
                                Password    = $pass1
                            }
                        }
                        else {
                            Write-Warning "Passwords did not match. Please try again."
                        }
                    }
                }
            }
            elseif ($adminAccount -and $adminAccount.Enabled) {
                Write-Host "[OK] Built-in Administrator account ('$($adminAccount.Name)') is already enabled." -ForegroundColor Green
                # Proceed with current logic (return null)
                return $null
            }
        }

        # Step 3: Propose New Account
        $createNew = Read-Host "Do you want to create a new administrator account? (y/n)"
        if ($createNew -eq 'y') {
            Write-Host "TODO: Implement account creation logic." -ForegroundColor Yellow
            # Fall through to error as requested implies we stop if we can't providing a valid admin
        }
        
        # Step 4: Failure
        Write-Error "You need to create a new administrator account to use this script!"
        exit
    }
    catch {
        Write-Error "Failed to query local accounts: $_"
        exit
    }
    return $null
}

function Invoke-Escalation {
    <#
    .DESCRIPTION
        Restarts the current script process under a different user context (escalation).
    #>
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$CredentialDetails,

        [Parameter(Mandatory = $true)]
        [string]$ScriptPath
    )

    Write-Host "`n[*] Auto-escalating to Secondary Administrator context..." -ForegroundColor Yellow
    $cred = New-Object System.Management.Automation.PSCredential($CredentialDetails.AccountName, $CredentialDetails.Password)
    
    try {
        # Start new instance as Secondary Admin
        Start-Process powershell.exe -Credential $cred -ArgumentList "-NoExit", "-File", "`"$ScriptPath`"", "-SkipConfirmation"
        # Exit current instance
        exit
    }
    catch {
        Write-Warning "Failed to auto-escalate: $_"
    }
}

Export-ModuleMember -Function Select-TargetUser, Initialize-SecondaryAdmin, Invoke-Escalation
