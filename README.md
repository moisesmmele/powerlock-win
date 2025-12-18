> [!NOTE]
> **AI-Generated Code Disclaimer**
>
> This project was developed with the assistance of Gemini/Antigravity and for personal use.
>
> Please review the code thoroughly before execution.


# PowerLock: System Restriction Tool

PowerLock is a PowerShell-based utility designed to "hard lock" specific Windows system features. It is intended for power users who want to enforce strict focus or security policies by increasing the friction required to change system settings.

> [!WARNING]
> **EXTREME CAUTION REQUIRED**
>
> This tool is aggressive. It modifies file permissions (ACLs) and Registry policies to prevent changes.  
> **Improper use can lock you out of critical system functions (like Network Settings or Registry Editor).**
>
> - Always ensure you have a **Backup Administrator Account** enabled before applying restrictions.
> - You will need a *secondary* administrator account to remove these restrictions if your main account is locked out.

## Features

When enabled, PowerLock imposes the following restrictions:

1.  **Network Adapters**: Locks the Registry keys for network interfaces, preventing changes to DNS servers or IP addresses.
2.  **Hosts File**: Applies "Deny Write" permissions to the system `hosts` file to prevent modification.
3.  **Registry Editor**: Disables `regedit.exe` via Group Policy settings.
4.  **UAC (User Account Control)**: Enforces UAC to the highest notification level.

## Prerequisites

- **OS**: Windows 10/11 (PowerShell 5.1+)
- **Privileges**: Must be run as **Administrator**.

## Usage

1.  Open PowerShell as Administrator.
2.  Navigate to the project directory.
3.  Run the main script:
    ```powershell
    .\main.ps1
    ```
4.  **Preflight Checks**: The script will automatically:
    -   Verify Admin privileges.
    -   Warn you about the risks.
    -   Check for a built-in "Administrator" account. If it is disabled, the script will guide you through enabling it and setting a strong password for emergency recovery.
5.  **Menu**:
    -   Select `1` to **Enable Restrictions**.
    -   Select `2` to **Disable Restrictions** (Restore defaults).

## Disclaimer

This software is provided "as is", without warranty of any kind. The authors are not responsible for any system instability, data loss, or lockouts caused by the use of this tool. Use it at your own risk.
