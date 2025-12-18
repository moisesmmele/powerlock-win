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

*   **Context-Aware Execution**: The script forces you to run as a **Secondary Administrator** to apply restrictions to a *different* target user. This prevents you from accidentally locking the keys inside the car (locking your own active admin session).
*   **Auto-Escalation**: If you lack a secondary admin account, the script can help you enable the built-in Administrator, set a password, and automatically restart itself in that context.
*   **Persistent State Tracking**: Modifications are tracked in the Registry (`HKLM:\SOFTWARE\PowerLock`), allowing the script to cleanly undo *only* the changes it made.
*   **Auto-Recovery**: 
    *   Upon locking, an Auto-Recovery timer is set (default 60 mins).
    *   A Scheduled Task (`PowerLock_Recovery`) is registered to run as **SYSTEM**.
    *   This task automatically triggers a headless recovery script (`recovery.ps1`) at the designated time, unlocking the system if you are unable to do so manually.

## Prerequisites

- **OS**: Windows 10/11 (PowerShell 5.1+)
- **Privileges**: Must be run as **Administrator**.

## Project Structure

*   `main.ps1`: The primary interactive CLI. Orchestrates preflight checks, escalation, and the main menu.
*   `Modules/`:
    *   `NetworkUtils.psm1`: Adapter discovery and registry locking logic.
    *   `SystemRestrictions.psm1`: Core locking primitives (ACL management) and system policies.
    *   `StateManager.psm1`: Registry-based state tracking logic.
    *   `UserUtils.psm1`: Handles user selection, admin account verification, and process escalation.
*   `recovery.ps1`: Headless "Emergency Eject" script designed to run via Scheduled Task.

## Usage

1.  Open PowerShell as Administrator.
2.  Navigate to the project directory.
3.  Run the main script:
    ```powershell
    .\main.ps1
    ```
4.  **Preflight & Escalation**:
    -   The script verifies if you are running as a suitable Secondary Administrator.
    -   If not, it will prompt you to enable/create one and will **automatically restart** itself as that user once credentials are provided.
5.  **Target Selection**: You will be prompted to select which *other* Local User Account to restrict.
6.  **Menu**:
    -   Select `1` to **Enable Restrictions**. (Requires configuring the Auto-Recovery timer).
    -   Select `2` to **Disable Restrictions** (Restores defaults and unregisters recovery task).

## Recovery

If you are locked out:
1.  **Wait**: The Auto-Recovery timer (set during setup) will automatically unlock the system eventually.
2.  **Manual Recovery**: If the timer fails or was disabled manually:
    -   Log in with the **Secondary Administrator Account**.
    -   Run `main.ps1` and select "Disable Restrictions".
    -   (Advanced) Run `recovery.ps1` as SYSTEM using Task Scheduler or PsExec.

## Disclaimer

This software is provided "as is", without warranty of any kind. The authors are not responsible for any system instability, data loss, or lockouts caused by the use of this tool. Use it at your own risk.
