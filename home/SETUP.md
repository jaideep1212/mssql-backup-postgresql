# Laptop setup — Backup-PortGate (on-demand replication trigger)

This sets up the laptop so that, every few minutes, it checks whether SQL Server
has tables to back up and — only if it does — opens the firewall port, tells the
Pi to run one replication cycle, and closes the port again.

Two one-time setup steps: (1) an SSH key so the laptop can trigger the Pi without
a password, and (2) a scheduled task that runs the script on a timer.

---

## 0. Prerequisites

- `Backup-PortGate.ps1` copied to a **permanent** path, e.g. `C:\Scripts\Backup-PortGate.ps1`
  (do NOT run it from Downloads or the git repo — the task points at a fixed path).
- The `SqlServer` PowerShell module (for `Invoke-Sqlcmd`):
      Install-Module -Name SqlServer -Scope AllUsers
  (run PowerShell as Administrator). If you'd rather not install a module, ask for
  the ADO.NET version of the outbox check instead.
- The firewall inbound rule "SQL Server 1433" already exists (you created it).
- OpenSSH client on Windows (built in on Win10/11; `ssh` works from PowerShell).

---

## 1. SSH key: laptop -> Pi (passwordless trigger)

The script uses `ssh -o BatchMode=yes`, which NEVER prompts for a password — so
key-based auth must be set up, or the scheduled task will silently fail to trigger.

On the **laptop**, in PowerShell:

    # generate a key (press Enter for defaults; leave passphrase EMPTY so the
    # scheduled task can use it unattended)
    ssh-keygen -t ed25519 -f $env:USERPROFILE\.ssh\id_ed25519_pi

    # copy the PUBLIC key to the Pi (enter the Pi password this one time)
    type $env:USERPROFILE\.ssh\id_ed25519_pi.pub | ssh buildwidjai@InTheEnd "mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys"

Tell SSH to use this key for the Pi by adding to `%USERPROFILE%\.ssh\config`:

    Host InTheEnd
        HostName InTheEnd            # or the Pi's IP, e.g. 192.168.1.x
        User buildwidjai
        IdentityFile ~/.ssh/id_ed25519_pi
        IdentitiesOnly yes

Test it — this must return WITHOUT asking for a password:

    ssh -o BatchMode=yes buildwidjai@InTheEnd "echo OK && docker ps --format '{{.Names}}'"

You should see `OK` and your container names (including `replicator-test`).
If it asks for a password or fails, fix this before going further — the whole
trigger depends on it.

NOTE ON THE TASK USER: an SSH key lives under a specific Windows user's profile.
The scheduled task MUST run as that SAME user (see step 2), or it won't find the
key. Running the task as SYSTEM will NOT have access to your user's SSH key.

---

## 2. Scheduled task: run the script every X minutes

Open **Task Scheduler** -> **Create Task...** (NOT "Create Basic Task" — you need
the advanced options).

### General tab
- **Name:** `Backup Port Gate`
- **Run whether user is logged on or not** — select this (so it runs in the
  background). It will ask for your Windows password when you save.
- **Run with highest privileges** — CHECK THIS. Firewall changes need elevation;
  without it, Enable/Disable-NetFirewallRule fails.
- **Configure for:** Windows 10 / 11.
- Confirm the task runs as YOUR user (the one whose SSH key you set up in step 1).

### Triggers tab  -> New...
This is the WHEN.
- **Begin the task:** On a schedule
- **Settings:** Daily, Recur every 1 day
- Check **Repeat task every:** and choose your interval, e.g. **5 minutes**
- **for a duration of:** **Indefinitely**
- **Enabled** checked
- OK

### Actions tab  -> New...
This is WHAT runs, and it points at PowerShell, NOT at the .ps1 directly.
- **Action:** Start a program
- **Program/script:**
      powershell.exe
- **Add arguments (optional):**
      -NoProfile -ExecutionPolicy Bypass -File "C:\Scripts\Backup-PortGate.ps1"
- (Leave "Start in" blank, or set it to `C:\Scripts`)
- OK

### Settings tab
- Check **Allow task to be run on demand** (lets you test it with Run).
- **If the task is already running, then the following rule applies:**
      **Do not start a new instance**
  (prevents a new run starting while a previous cycle is still going).
- OK, and enter your Windows password when prompted.

---

## 3. Test it

In Task Scheduler, right-click the task -> **Run**. Then check:

- The script's own output / any errors: run it once by hand in an elevated
  PowerShell to see the messages live:
      powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Scripts\Backup-PortGate.ps1"
- With NO pending outbox rows -> it should print "No pending work" and the
  firewall rule should stay DISABLED (check in Windows Defender Firewall).
- With pending rows (run an instrumented SP first to create some) -> it should
  open the port, trigger the Pi (you'll see the Pi's replicator logs via
  `docker logs replicator-test` — actually run_once logs to stdout of the exec),
  then close the port. Confirm the Postgres mirror table updated.

SSH diagnostics, if the trigger misbehaves, are written to:
    %TEMP%\portgate_ssh_out.log
    %TEMP%\portgate_ssh_err.log

---

## Where the cadence lives now

This scheduled task's **Repeat task every X minutes** IS the system's schedule.
The Pi no longer runs on a timer — it only acts when this task triggers it. So
the interval here == the maximum staleness of the PostgreSQL mirror. Change it
any time by editing this one trigger; no code or container change needed.
