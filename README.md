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
> - The script creates a **System Restore Point** for safety, but manual backups are encouraged.

## Features

When enabled, PowerLock imposes the following restrictions:

1.  **Network Adapters**: Locks the Registry keys for network interfaces, preventing changes to DNS servers or IP addresses.
2.  **Hosts File**: Applies "Deny Write" permissions to the system `hosts` file to prevent modification.
3.  **Registry Editor**: Disables `regedit.exe` via Group Policy settings.
4.  **UAC (User Account Control)**: Enforces UAC to the highest notification level.

### Smart Safety Mechanisms

*   **Multi-User Context**: Restrictions (Adapters/Hosts) are applied with granular "Deny" rules for the *specific user* selected at runtime, allowing other administrators to remain unrestricted if intended.
*   **Persistent State Tracking**: Modifications are tracked in the Registry (`HKLM:\SOFTWARE\PowerLock`), allowing the script to cleanly undo *only* the changes it made.
*   **Auto-Recovery**: 
    *   Upon locking, an Auto-Recovery timer is set (default 60 mins).
    *   A Scheduled Task (`PowerLock_Recovery`) is registered to run as **SYSTEM**.
    *   This task automatically triggers a headless recovery script (`recovery.ps1`) at the designated time, unlocking the system if you are unable to do so manually.

## Prerequisites

- **OS**: Windows 10/11 (PowerShell 5.1+)
- **Privileges**: Must be run as **Administrator**.

## Project Structure

*   `main.ps1`: The primary interactive CLI. Orchestrates user selection, backup creation, and restriction logic.
*   `Modules/`:
    *   `NetworkUtils.psm1`: Adapter discovery and selection.
    *   `SystemRestrictions.psm1`: Core locking primitives (ACL management).
    *   `StateManager.psm1`: Registry-based state tracking logic.
    *   `UserUtils.psm1`: interactive user selection.
*   `recovery.ps1`: Headless "Emergency Eject" script designed to run via Scheduled Task.

## Usage

1.  Open PowerShell as Administrator.
2.  Navigate to the project directory.
3.  Run the main script:
    ```powershell
    .\main.ps1
    ```
4.  **Preflight Checks**: The script will:
    -   Verify Admin privileges.
    -   Check for a generic "Administrator" backup account.
    -   Create a **System Restore Point**.
5.  **Target Selection**: You will be prompted to select which Local User Account to restrict.
6.  **Menu**:
    -   Select `1` to **Enable Restrictions**. (Requires configuring the Dead-Man's Hand timer).
    -   Select `2` to **Disable Restrictions** (Restore defaults and unregister recovery task).

## Recovery

If you are locked out:
1.  **Wait**: The Auto-Recovery timer (set during setup) will automatically unlock the system eventually.
2.  **Manual Recovery**: If the timer fails or was disabled manually, log in with the **Backup Administrator Account** ensuring you have one enabled, and manually run `recovery.ps1` as SYSTEM (requires PsExec or Task Scheduler intervention) or simply use `main.ps1` to Disable restrictions if the backup admin was not restricted.

## Disclaimer

This software is provided "as is", without warranty of any kind. The authors are not responsible for any system instability, data loss, or lockouts caused by the use of this tool. Use it at your own risk.
