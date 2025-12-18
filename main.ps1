# PowerLock: System Restriction Tool.
# This script Orchestrates the application of restrictions using modular components.
# Warning: This script is agressive. Use with caution, might break your system.

param(
    [switch]$SkipConfirmation
)

# --- SCRIPT CONFIGURATION ---

# Define the path to the Modules directory relative to this script
$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
$ModulesPath = Join-Path $ScriptRoot "Modules"

# Import Modules
try {
    Import-Module (Join-Path $ModulesPath "NetworkUtils.psm1") -Force -ErrorAction Stop
    Import-Module (Join-Path $ModulesPath "SystemRestrictions.psm1") -Force -ErrorAction Stop
    Import-Module (Join-Path $ModulesPath "StateManager.psm1") -Force -ErrorAction Stop
    Import-Module (Join-Path $ModulesPath "UserUtils.psm1") -Force -ErrorAction Stop
}
catch {
    Write-Error "Failed to import required modules. Please ensure 'NetworkUtils.psm1' and 'SystemRestrictions.psm1' exist in the 'Modules' folder."
    Write-Error $_
    exit
}

# --- CONFIGURATION CONSTANTS ---

$HostsFilePath = "$env:windir\system32\drivers\etc\hosts"
$UacRegistryPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
$UacValueName = "ConsentPromptBehaviorAdmin"
$RegEditPolicyPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\System"
$RegEditValueName = "DisableRegistryTools"

# --- MAIN FUNCTION ---
function Start-PowerLock {
    
    # Run Preflight Checks immediately
    Invoke-PreflightChecks

    # Select Target User immediately after pre-checks
    $targetUser = Select-TargetUser

    # --- EXECUTION MENU ---
    Write-Host "--- PowerLock: System Restriction Tool ---" -ForegroundColor Cyan
    Write-Host "1. Enable Restrictions"
    Write-Host "2. Disable Restrictions"
    $choice = Read-Host "Select an option"

    if ($choice -eq "1") {
        Enable-Restrictions -User $targetUser
    }
    elseif ($choice -eq "2") {
        Disable-Restrictions -User $targetUser
    }
    else {
        Write-Warning "Invalid selection."
    }

}

function Enable-Restrictions {
    <#
    .DESCRIPTION
        Orchestrates the enabling of all system restrictions.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$User
    )
    
    # 0. Create System Restore Point
    Write-Host "`n[*] Creating System Restore Point..." -ForegroundColor Cyan
    try {
        # Checkpoint-Computer can fail if one was created recently (frequency cap) or if disabled.
        Checkpoint-Computer -Description "PowerLock Enforcement" -RestorePointType "MODIFY_SETTINGS" -ErrorAction Stop
        Write-Host "[OK] Restore Point Created." -ForegroundColor Green
    }
    catch {
        Write-Warning "Failed to create System Restore Point. System Restore might be disabled or a point was created recently."
        Write-Warning "Error: $($_.Exception.Message)"
        $continue = Read-Host "Do you want to continue WITHOUT a restore point? (y/n)"
        if ($continue -ne 'y') { 
            Write-Host "Operation cancelled."
            return 
        }
    }

    # 1. Auto-Recovery Configuration
    Write-Host "`n--- AUTO-RECOVERY CONFIGURATION ---" -ForegroundColor Cyan
    Write-Host "This timer will automatically trigger the Emergency Recovery script (""recovery.ps1"")"
    Write-Host "at the specified time to unlock the system if you are unable to do so manually."
    
    $durationStr = Read-Host "Enter Auto-Recovery Timer in MINUTES (default: 60)"
    if ([string]::IsNullOrWhiteSpace($durationStr)) { $durationStr = "60" }
    
    try {
        $durationMinutes = [int]$durationStr
    }
    catch {
        Write-Warning "Invalid input. Defaulting to 60 minutes."
        $durationMinutes = 60
    }

    $startTime = Get-Date

    # Store Configuration
    Set-PowerLockConfig -Key "LockStartTime" -Value $startTime.Ticks -PropertyType String
    Set-PowerLockConfig -Key "LockDurationMinutes" -Value $durationMinutes -PropertyType DWord
    
    $unlockTime = $startTime.AddMinutes($durationMinutes)
    Write-Host "System will be locked until: $unlockTime" -ForegroundColor Yellow

    # Schedule Recovery Task
    Write-Host "[*] Scheduling Auto-Recovery Task..." -ForegroundColor Cyan
    try {
        $recoveryScript = Join-Path $ScriptRoot "recovery.ps1"
        $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -WindowStyle Hidden -File ""$recoveryScript"""
        $trigger = New-ScheduledTaskTrigger -Once -At $unlockTime
        
        # Run as SYSTEM to ensure it has permission to unlock everything regardless of user context
        $principal = New-ScheduledTaskPrincipal -UserId "NT AUTHORITY\SYSTEM" -LogonType ServiceAccount -RunLevel Highest
        
        Register-ScheduledTask -TaskName "PowerLock_Recovery" -Action $action -Trigger $trigger -Principal $principal -Force | Out-Null
        Write-Host "[OK] Recovery Task Scheduled." -ForegroundColor Green
    }
    catch {
        Write-Warning "Failed to register Scheduled Task. Automatic recovery will NOT work."
        Write-Warning $_
    }

    Write-Host "`n--- ACTIVATING SYSTEM RESTRICTIONS ---" -ForegroundColor Cyan

    Enable-NetworkRestrictions -User $User
    Enable-FileRestrictions -User $User
    Enable-SystemRestrictions -User $User

    Write-Host "`n[SUCCESS] Restrictions Applied." -ForegroundColor Yellow
}

function Disable-Restrictions {
    <#
    .DESCRIPTION
        Orchestrates the disabling of system restrictions.
    #>
    param(
        [Parameter(Mandatory = $false)]
        [string]$User
    )
    
    Write-Host "`n--- DEACTIVATING RESTRICTIONS ---" -ForegroundColor Magenta
    
    Disable-NetworkRestrictions -User $User
    Disable-FileRestrictions -User $User
    Disable-SystemRestrictions -User $User

    # Clear state for this user
    Clear-PowerLockState -User $User

    # Remove Scheduled Task if exists
    Write-Host "[*] Removing Auto-Recovery Task..."
    try {
        Unregister-ScheduledTask -TaskName "PowerLock_Recovery" -Confirm:$false -ErrorAction SilentlyContinue
    }
    catch {} # Ignore if not found
    
    Write-Host "`n[SUCCESS] Restrictions Removed for User: $User" -ForegroundColor Green
}

# --- HELPER FUNCTIONS ---

function Enable-NetworkRestrictions {
    param([string]$User)
    
    try {
        $adapters = Select-TargetAdapters
    }
    catch {
        Write-Error $_
        return
    }

    foreach ($adapter in $adapters) {
        $guid = $adapter.InterfaceGuid
        Write-Host "[*] Locking Network Interface: $($adapter.Name)"
        $regPath = "SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\$guid"
        
        Block-RegistryWrite -RegistryPath $regPath -UserAccount $User
        Set-PowerLockState -Category "NetworkAdapters" -Key $guid -User $User
    }
}

function Disable-NetworkRestrictions {
    param([string]$User)

    $lockedAdapters = Get-PowerLockState -Category "NetworkAdapters"
    if ($lockedAdapters.Count -gt 0) {
        foreach ($item in $lockedAdapters) {
            # Filter by user if provided
            if ($User -and $item.User -ne $User) { continue }

            $guid = $item.Key
            $targetUser = $item.User
            Write-Host "[*] Unlocking Network Interface (GUID: $guid) for User: $targetUser..." 
            $regPath = "SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\$guid"
            Unblock-RegistryWrite -RegistryPath $regPath -UserAccount $targetUser
            
            # TODO: Remove specific state entry for this user
            # Currently we don't have Remove-PowerLockStateItem, so the registry artifact remains until full clear.
        }
    }
    else {
        Write-Warning "No locked adapters found in state."
    }
}

function Enable-FileRestrictions {
    param([string]$User)
    
    Write-Host "[*] Locking Hosts File..."
    Block-FileWrite -FilePath $HostsFilePath -UserAccount $User
    Set-PowerLockState -Category "SystemFiles" -Key "HostsFile" -User $User
}

function Disable-FileRestrictions {
    param([string]$User)

    $lockedFiles = Get-PowerLockState -Category "SystemFiles"
    if ($lockedFiles) {
        foreach ($item in $lockedFiles) {
            # Filter by user if provided
            if ($User -and $item.User -ne $User) { continue }

            if ($item.Key -eq "HostsFile") {
                Write-Host "[*] Unlocking Hosts File for User: $($item.User)..."
                Unblock-FileWrite -FilePath $HostsFilePath -UserAccount $item.User
            }
        }
    }
}

function Enable-SystemRestrictions {
    param([string]$User)

    # Registry Editor
    Write-Host "[*] Disabling Registry Editor..."
    Set-RegistryValue -Path $RegEditPolicyPath -Name $RegEditValueName -Value 1
    Set-PowerLockState -Category "SystemTools" -Key "RegEdit" -User $User

    # UAC
    Write-Host "[*] Enforcing UAC..."
    Set-RegistryValue -Path $UacRegistryPath -Name $UacValueName -Value 1
    Set-PowerLockConfig -Key "UacEnforced" -Value 1
}

function Disable-SystemRestrictions {
    param([string]$User)
    
    # Registry Editor
    # RegEdit logic in HKCU depends on the running user, but the state tracks who it was intended for.
    if (Test-PowerLockState -Category "SystemTools" -Key "RegEdit" -User $User) {
        Write-Host "[*] Enabling Registry Editor..."
        Set-RegistryValue -Path $RegEditPolicyPath -Name $RegEditValueName -Value 0
    }

    # UAC
    # UAC is global machine policy. If we are disabling restrictions for "A User", 
    # and UAC is enforced globally, do we turn it off?
    # Logic: If UAC is Enforced, we turn it off regardless of user because it affects everyone.
    if (Get-PowerLockConfig -Key "UacEnforced") {
        Write-Host "[*] Restoring UAC Defaults..."
        Set-RegistryValue -Path $UacRegistryPath -Name $UacValueName -Value 5
        Set-PowerLockConfig -Key "UacEnforced" -Value 0
    }
}

function Get-UserWarningConfirmation {
    param([switch]$SkipConfirmation)

    if ($SkipConfirmation) {
        Write-Host "Skipping confirmation as requested." -ForegroundColor DarkGray
        return $true
    }

    Write-Host "`n--- READ CAREFULLY ---" -ForegroundColor Red
    Write-Host "This script acts aggressively to lock down system features." -ForegroundColor Yellow
    Write-Host "It has the potential to break system functionality or lock you out if not managed correctly."
    Write-Host "To bypass or reverse these restrictions, you will likely need a SECONDARY Administrator account,"
    Write-Host "as your current user might be restricted from performing recovery actions."
    
    $confirmation = Read-Host "`nDo you understand the risks and wish to proceed? (Type 'YES' to confirm)"
    if ($confirmation -eq 'YES') { 
        return $true
    }
    return $false
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
    if (-not (Get-UserWarningConfirmation -SkipConfirmation $SkipConfirmation)) {
        Write-Host "Operation cancelled by user."
        exit
    }

    # 3. Secondary Administrator Account Check
    $escalationCreds = Initialize-SecondaryAdmin

    if ($escalationCreds) {
        # Auto-Escalation: Use the credentials we just got to switch context
        if ($PSCommandPath) { $scriptPath = $PSCommandPath } else { $scriptPath = $MyInvocation.MyCommand.Definition }
        Invoke-Escalation -CredentialDetails $escalationCreds -ScriptPath $scriptPath
    }
}

Start-PowerLock