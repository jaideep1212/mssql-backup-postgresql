# =============================================================
# Backup-PortGate.ps1  (runs ON THE LAPTOP, every X minutes via Task Scheduler)
#
# On-demand, laptop-driven replication with a gated firewall port:
#
#   1. Check dbo.BackupOutbox LOCALLY (shared-memory / localhost - no port needed).
#   2. If nothing is pending, exit. The firewall port is NEVER opened.
#   3. If there is work: open the SQL Server firewall port, then SSH the Pi to
#      run exactly ONE replication cycle. The SSH call BLOCKS until that cycle
#      finishes, so when it returns the backup is done.
#   4. Close the firewall port (always - even on error/timeout).
#
# This replaces the Pi's timer: the laptop decides when backups happen (because
# only the laptop can see BackupOutbox without opening the port), and the Pi
# only ever runs when triggered.
#
# Run as Administrator (firewall changes need elevation).
# =============================================================

# ---- Settings -------------------------------------------------------------
$FirewallRuleName = "allow-pi"                   # must match your inbound rule's name
$SqlInstance      = "localhost\MSSQLSERVER01"    # local instance (shared memory)
$SqlDatabase      = "LocalTestDB"

$PiSshTarget      = "buildwidjai@InTheEnd"       # user@host of the Pi (SSH)
$PiContainerName  = "replicator-test"            # container to exec into
# ---------------------------------------------------------------------------

function Get-PendingCount {
    # Counts rows still pending (0) or claimed/in-progress (2).
    # Local connection - does NOT require the firewall port to be open.
    $query = "SET NOCOUNT ON; SELECT COUNT(*) AS Cnt FROM dbo.BackupOutbox WHERE BackupDone IN (0,2);"
    $r = Invoke-Sqlcmd -ServerInstance $SqlInstance -Database $SqlDatabase `
                       -Query $query -TrustServerCertificate -ErrorAction Stop
    return [int]$r.Cnt
}

function Open-Port  { Enable-NetFirewallRule  -DisplayName $FirewallRuleName; Write-Host "$(Get-Date -Format o)  PORT OPENED" }
function Close-Port { Disable-NetFirewallRule -DisplayName $FirewallRuleName; Write-Host "$(Get-Date -Format o)  PORT CLOSED" }

$portOpened = $false
try {
    # ---- 1. Local check: is there anything to back up? --------------------
    $pending = Get-PendingCount
    if ($pending -eq 0) {
        Write-Host "$(Get-Date -Format o)  No pending work - leaving port CLOSED."
        exit 0
    }
    Write-Host "$(Get-Date -Format o)  $pending pending row(s) - opening port and triggering the Pi."

    # ---- 2. Open the port -------------------------------------------------
    Open-Port
    $portOpened = $true

    # ---- 3. Trigger ONE cycle on the Pi; block until it finishes ----------
    # ssh returns the remote command's exit code:
    #   0 = cycle completed cleanly   1 = cycle failed   2 = config error
    $sshArgs = @(
        "-o", "BatchMode=yes",                 # never prompt (key-based auth only)
        "-o", "ConnectTimeout=15",
        $PiSshTarget,
        "docker exec $PiContainerName python -m replicator.run_once"
    )
    Write-Host "$(Get-Date -Format o)  triggering: ssh $PiSshTarget docker exec $PiContainerName ..."
    $proc = Start-Process -FilePath "ssh" -ArgumentList $sshArgs -NoNewWindow -PassThru -Wait `
                          -RedirectStandardOutput "$env:TEMP\portgate_ssh_out.log" `
                          -RedirectStandardError  "$env:TEMP\portgate_ssh_err.log"

    if ($proc.ExitCode -eq 0) {
        Write-Host "$(Get-Date -Format o)  Pi cycle completed cleanly."
    } else {
        Write-Warning "$(Get-Date -Format o)  Pi cycle returned exit code $($proc.ExitCode). See $env:TEMP\portgate_ssh_err.log"
    }
}
catch {
    Write-Warning "$(Get-Date -Format o)  ERROR: $($_.Exception.Message)"
}
finally {
    # ---- 4. ALWAYS close the port - never leave it open -------------------
    if ($portOpened) { Close-Port }
    else { Write-Host "$(Get-Date -Format o)  (port was never opened)" }
}