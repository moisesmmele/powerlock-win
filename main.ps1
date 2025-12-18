<#
.SYNOPSIS
    PowerLock: System Restriction Tool.
    
    This script Orchestrates the application of restrictions using modular components.
#>

# Define the path to the Modules directory relative to this script
$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
$ModulesPath = Join-Path $ScriptRoot "Modules"

# Import Modules
try {
    Import-Module (Join-Path $ModulesPath "NetworkUtils.psm1") -Force -ErrorAction Stop
    Import-Module (Join-Path $ModulesPath "SystemRestrictions.psm1") -Force -ErrorAction Stop
}
catch {
    Write-Error "Failed to import required modules. Please ensure 'NetworkUtils.psm1' and 'SystemRestrictions.psm1' exist in the 'Modules' folder."
    Write-Error $_
    exit
}

# --- CONFIGURATION CONSTANTS ---
# Define the paths here. This makes the script the source of truth for "Business Logic".
$HostsFilePath = "$env:windir\system32\drivers\etc\hosts"
$UacRegistryPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
$UacValueName = "ConsentPromptBehaviorAdmin"
$RegEditPolicyPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\System"
$RegEditValueName = "DisableRegistryTools"


function Start-RestrictionEnforcement {
    <#
    .DESCRIPTION
        Orchestrates the enabling of all system restrictions.
    #>
    
    # 1. Select Adapters
    try {
        $adapters = Select-TargetAdapters
    }
    catch {
        Write-Error $_
        return
    }

    Write-Host "`n--- ACTIVATING SYSTEM RESTRICTIONS ---" -ForegroundColor Cyan
    $currentUser = $env:USERNAME

    # 2. Network Restrictions
    foreach ($adapter in $adapters) {
        $guid = $adapter.InterfaceGuid
        Write-Host "[*] Locking Network Interface: $($adapter.Name)"
        # Note: We pass the standard registry path format our module expects for HKLM subkeys
        $regPath = "SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\$guid"
        
        Block-RegistryWrite -RegistryPath $regPath -UserAccount $currentUser
    }

    # 3. Hosts File Restriction
    Write-Host "[*] Locking Hosts File..."
    Block-FileWrite -FilePath $HostsFilePath -UserAccount $currentUser

    # 4. Registry Editor Restriction
    Write-Host "[*] Disabling Registry Editor..."
    Set-RegistryValue -Path $RegEditPolicyPath -Name $RegEditValueName -Value 1

    # 5. UAC Restriction
    Write-Host "[*] Enforcing UAC..."
    Set-RegistryValue -Path $UacRegistryPath -Name $UacValueName -Value 1

    Write-Host "`n[SUCCESS] Restrictions Applied." -ForegroundColor Yellow
}

function Stop-RestrictionEnforcement {
    <#
    .DESCRIPTION
        Orchestrates the disabling of system restrictions.
    #>
    
    # 1. Select Adapters (to know which to unlock)
    Write-Host "Select adapters to UNLOCK:"
    try {
        $adapters = Select-TargetAdapters
    }
    catch {
        Write-Error $_
        return
    }

    Write-Host "`n--- DEACTIVATING RESTRICTIONS ---" -ForegroundColor Magenta

    # 2. Network Restrictions
    foreach ($adapter in $adapters) {
        $guid = $adapter.InterfaceGuid
        Write-Host "[*] Unlocking Network Interface: $($adapter.Name)"
        $regPath = "SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\$guid"
        
        Unblock-RegistryWrite -RegistryPath $regPath
    }

    # 3. Hosts File Restriction
    Write-Host "[*] Unlocking Hosts File..."
    Unblock-FileWrite -FilePath $HostsFilePath

    # 4. Registry Editor Restriction
    Write-Host "[*] Enabling Registry Editor..."
    Set-RegistryValue -Path $RegEditPolicyPath -Name $RegEditValueName -Value 0

    # 5. UAC Restriction
    Write-Host "[*] Restoring UAC Defaults..."
    Set-RegistryValue -Path $UacRegistryPath -Name $UacValueName -Value 5

    Write-Host "`n[SUCCESS] Restrictions Removed." -ForegroundColor Green
}


function Invoke-PreflightChecks {
    <#
    .DESCRIPTION
        Performs safety checks before execution:
        1. Verifies Administrator privileges.
        2. Warns the user about risks and gets confirmation.
        3. Ensures a backup Administrator account is available for recovery.
    #>
    
    # 1. Administrator Privilege Check
    $currentPrincipal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Warning "This script requires Administrator privileges to manage system restrictions."
        Write-Warning "Please run this script as an Administrator."
        exit
    }

    # 2. Risk Warning & Confirmation
    Write-Host "`n--- READ CAREFULLY ---" -ForegroundColor Red
    Write-Host "This script acts aggressively to lock down system features." -ForegroundColor Yellow
    Write-Host "It has the potential to break system functionality or lock you out if not managed correctly."
    Write-Host "To bypass or reverse these restrictions, you will likely need a SECONDARY Administrator account,"
    Write-Host "as your current user might be restricted from performing recovery actions."
    
    $confirmation = Read-Host "`nDo you understand the risks and wish to proceed? (Type 'YES' to confirm)"
    if ($confirmation -ne 'YES') { 
        Write-Host "Operation cancelled by user."
        exit 
    }

    # 3. Backup Administrator Account Check
    Write-Host "`n[*] Checking for Backup Administrator Account..." -ForegroundColor Cyan
    try {
        # Find built-in Administrator by SID (ends in -500) to support all languages (e.g., 'Administrator', 'Administrador')
        $adminAccount = Get-LocalUser | Where-Object { $_.SID.Value -match "-500$" } | Select-Object -First 1
        
        if (-not $adminAccount) {
            Write-Warning "Could not identify the built-in Administrator account by SID. Trying standard name 'Administrator'..."
            $adminAccount = Get-LocalUser -Name "Administrator"
        }

        if (-not $adminAccount.Enabled) {
            Write-Host "The built-in Administrator account ('$($adminAccount.Name)') is currently DISABLED." -ForegroundColor Yellow
            Write-Host "It is HIGHLY RECOMMENDED to enable this account as your emergency backup."
            
            $enableAdmin = Read-Host "Do you want to enable the '$($adminAccount.Name)' account and set a password? (y/n)"
            if ($enableAdmin -eq 'y') {
                Write-Host "`n--- PASSWORD SETUP ---" -ForegroundColor Cyan
                Write-Host "Please choose a STRONG password (random, lengthy, and challenging)."
                Write-Host "IMPORTANT: Write this password down on PHYSICAL PAPER and store it safely." -ForegroundColor Red
                Write-Host "If you lose this password, you may effectively lose control of this machine while locked."
                
                while ($true) {
                    $pass1 = Read-Host "Enter new password for '$($adminAccount.Name)'" -AsSecureString
                    $pass2 = Read-Host "Verify password" -AsSecureString
                    
                    if ((ConvertFrom-SecureString $pass1) -eq (ConvertFrom-SecureString $pass2)) {
                        Set-LocalUser -Name $adminAccount.Name -Password $pass1 -Description "PowerLock Backup Admin"
                        Enable-LocalUser -Name $adminAccount.Name
                        Write-Host "[SUCCESS] Backup Administrator account ('$($adminAccount.Name)') enabled." -ForegroundColor Green
                        break
                    }
                    else {
                        Write-Warning "Passwords did not match. Please try again."
                    }
                }
            }
            else {
                Write-Warning "Proceeding without a dedicated backup admin account is extremely risky."
                Start-Sleep -Seconds 2
            }
        }
        else {
            Write-Host "[OK] Backup Administrator account ('$($adminAccount.Name)') is already enabled." -ForegroundColor Green
        }
    }
    catch {
        Write-Error "Failed to query local accounts. Ensure you are running on a compatible Windows version."
        Write-Error $_
        exit
    }
}

# Run Preflight Checks immediately
Invoke-PreflightChecks

# --- EXECUTION MENU ---
Write-Host "--- PowerLock: System Enforcement ---" -ForegroundColor Cyan
Write-Host "1. Enable Restrictions"
Write-Host "2. Disable Restrictions"
$choice = Read-Host "Select an option"

if ($choice -eq "1") {
    Start-RestrictionEnforcement
}
elseif ($choice -eq "2") {
    Stop-RestrictionEnforcement
}
else {
    Write-Warning "Invalid selection."
}