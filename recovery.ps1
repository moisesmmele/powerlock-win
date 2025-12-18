<#
.SYNOPSIS
    PowerLock Headless Recovery Script.
    Designed to be run silently (e.g., via Task Scheduler or Emergency Command) to restore system access.
    
    Logging: C:\powerlock_recovery.log
#>

$LogFile = "C:\powerlock_recovery.log"

function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$timestamp] $Message"
    try {
        Add-Content -Path $LogFile -Value $line -Force
    }
    catch {
        # Fallback if we cannot write to C:\ root (though we should be admin)
        Write-Host $line 
    }
}

Write-Log "--- STARTING HEADLESS RECOVERY ---"

# 0. User Context Validation (Must be SYSTEM)
$currentUser = [Security.Principal.WindowsIdentity]::GetCurrent().Name
if ($currentUser -ne "NT AUTHORITY\SYSTEM") {
    Write-Log "CRITICAL ERROR: Recovery script must be run as SYSTEM (NT AUTHORITY\SYSTEM)."
    Write-Log "Current user is: $currentUser"
    Write-Log "Aborting recovery to prevent unauthorized usage."
    exit
}

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
$ModulesPath = Join-Path $ScriptRoot "Modules"

# Import Modules
try {
    Write-Log "Importing modules from $ModulesPath"
    Import-Module (Join-Path $ModulesPath "SystemRestrictions.psm1") -Force -ErrorAction Stop
    Import-Module (Join-Path $ModulesPath "StateManager.psm1") -Force -ErrorAction Stop
}
catch {
    Write-Log "CRITICAL ERROR: Failed to import modules. Ensure the 'Modules' folder is adjacent to this script. Details: $_"
    exit
}

# Configuration Paths (Must match main.ps1)
$HostsFilePath = "$env:windir\system32\drivers\etc\hosts"
$UacRegistryPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
$UacValueName = "ConsentPromptBehaviorAdmin"
$RegEditPolicyPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\System"
$RegEditValueName = "DisableRegistryTools"

# --- TIMER VALIDATION (Fail-Safe) ---
try {
    $startTicks = Get-PowerLockConfig -Key "LockStartTime"
    $durationMinutes = Get-PowerLockConfig -Key "LockDurationMinutes"
    
    if ($startTicks -and $durationMinutes) {
        $startTime = [datetime][long]$startTicks
        $unlockTime = $startTime.AddMinutes([int]$durationMinutes)
        $now = Get-Date

        if ($now -lt $unlockTime) {
            $remaining = ($unlockTime - $now).TotalMinutes
            Write-Log "FAIL-SAFE LOCKED. Current time: $now. Unlock time: $unlockTime."
            Write-Log "Approximately $([math]::Round($remaining, 2)) minutes remaining."
            Write-Log "Recovery aborted."
            exit
        }
        else {
            Write-Log "Fail-Safe timer expired. Proceeding with recovery."
        }
    }
    else {
        Write-Log "No active timer configuration found. Proceeding with immediate recovery."
    }
}
catch {
    Write-Log "Error checking timer status: $_. Safe side: Proceeding with recovery."
}

# 1. Unlock Network Adapters
try {
    $lockedAdapters = Get-PowerLockState -Category "NetworkAdapters"
    if ($lockedAdapters.Count -gt 0) {
        foreach ($item in $lockedAdapters) {
            $guid = $item.Key
            $user = $item.User
            Write-Log "Unlocking Network Interface GUID: $guid (User: $user)"
            $regPath = "SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\$guid"
            try {
                Unblock-RegistryWrite -RegistryPath $regPath -UserAccount $user
                Write-Log "  -> Success."
            }
            catch {
                Write-Log "  -> Error: $_"
            }
        }
    }
    else {
        Write-Log "No locked network adapters found in state."
    }
}
catch {
    Write-Log "Error processing network adapters: $_"
}

# 2. Unlock Hosts File
try {
    $lockedFiles = Get-PowerLockState -Category "SystemFiles"
    if ($lockedFiles) {
        foreach ($item in $lockedFiles) {
            if ($item.Key -eq "HostsFile") {
                Write-Log "Unlocking Hosts File for User: $($item.User)..."
                Unblock-FileWrite -FilePath $HostsFilePath -UserAccount $item.User
                Write-Log "  -> Success."
            }
        }
    }
}
catch {
    Write-Log "Error unlocking Hosts file: $_"
}

# 3. Enable Registry Editor
try {
    if (Test-PowerLockState -Category "SystemTools" -Key "RegEdit") {
        Write-Log "Enabling Registry Editor..."
        Set-RegistryValue -Path $RegEditPolicyPath -Name $RegEditValueName -Value 0
        Write-Log "  -> Success."
    }
}
catch {
    Write-Log "Error enabling RegEdit: $_"
}

# 4. Restore UAC
try {
    if (Get-PowerLockConfig -Key "UacEnforced") {
        Write-Log "Restoring UAC Defaults..."
        Set-RegistryValue -Path $UacRegistryPath -Name $UacValueName -Value 5
        Set-PowerLockConfig -Key "UacEnforced" -Value 0
        Write-Log "  -> Success."
    }
}
catch {
    Write-Log "Error restoring UAC: $_"
}

# 5. Clear Global State
try {
    Clear-PowerLockState
    Write-Log "State registry cleared."
}
catch {
    Write-Log "Error clearing state: $_"
}

Write-Log "--- RECOVERY COMPLETE ---"
