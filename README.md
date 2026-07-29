# Ubuntu Update Manager

Ubuntu Update Manager is a self-contained Bash utility for installing and
managing scheduled Ubuntu package updates. It provides safe defaults, a simple
command-line interface, an interactive menu, strict configuration validation,
rotated logs, update history, and optional failure notifications.

The current release is **1.1.0**.

## Highlights

- Installs as a single command at `/usr/local/sbin/ubuntu-update-manager`
- Runs on a daily, weekly, monthly, or custom five-field cron schedule
- Defaults to every Sunday at 03:17 in the server's local timezone
- Uses a conservative safe upgrade mode by default
- Optionally performs full upgrades and Snap refreshes
- Prevents overlapping update runs with `flock`
- Retries temporary repository failures and waits up to five minutes for APT
  locks
- Treats an incomplete repository refresh as a failed update
- Never automatically reboots after a manual update
- Rotates logs weekly and retains 12 archives
- Records the last run, result, exit code, duration, success, and failure
- Can email failure details through a local sendmail-compatible service
- Parses configuration strictly without executing it as shell code
- Preserves compatible settings when upgrading from version 1.0

## Requirements

- Ubuntu or an Ubuntu-derived system using APT
- Bash
- Root access through `sudo`
- Working Ubuntu package repositories and network access
- Standard Ubuntu utilities, including `flock`

The installer automatically installs `cron` and `logrotate` when either is
missing. Failure email delivery is optional and requires a separately configured
sendmail-compatible local mail service.

## Install or Upgrade

Download `ubuntu-update-manager.sh`, then run:

```bash
sudo bash ubuntu-update-manager.sh install
```

The installer:

1. Validates and preserves an existing compatible configuration.
2. Installs any missing cron and logrotate packages.
3. Installs the manager at `/usr/local/sbin/ubuntu-update-manager`.
4. Writes the validated configuration, cron job, and logrotate policy.
5. Starts and verifies the cron service.
6. Displays the effective configuration and service status.

Running `install` again upgrades the installed script while preserving valid
settings. Existing version 1.0 configuration values are safely migrated and
normalized.

## Quick Start

Open the interactive menu:

```bash
sudo ubuntu-update-manager menu
```

Show the current configuration and last run:

```bash
sudo ubuntu-update-manager status
```

Run updates immediately:

```bash
sudo ubuntu-update-manager run
```

The manual `run` command will report a required reboot but will not schedule
one, even when automatic rebooting is enabled.

## Commands

| Command | Purpose |
| --- | --- |
| `install` | Install or upgrade the manager and preserve valid settings |
| `enable` | Enable the configured update schedule |
| `disable` | Disable scheduled updates without uninstalling |
| `status` | Show configuration, service state, warnings, and last run details |
| `run` | Install updates immediately without automatic reboot |
| `set-frequency daily [HH:MM]` | Run every day |
| `set-frequency weekly [DAY] [HH:MM]` | Run on a selected weekday |
| `set-frequency monthly [DAY] [HH:MM]` | Run on day 1 through 28 of each month |
| `set-schedule "EXPRESSION"` | Set a validated five-field cron expression |
| `set-mode safe\|full` | Select the APT upgrade strategy |
| `set-reboot on\|off` | Control automatic reboot after scheduled runs |
| `set-snaps on\|off` | Control Snap refreshes |
| `set-email ADDRESS\|off` | Configure or disable failure email |
| `logs [LINES]` | Display the last 100 log lines or a selected count |
| `menu` | Open the interactive management menu |
| `uninstall [--yes]` | Remove the manager while retaining its update log |
| `version` | Display the installed version |
| `help` | Display built-in help |

Commands that change the system require root privileges.

## Scheduling

Schedules use the server's local timezone.

### Daily

```bash
sudo ubuntu-update-manager set-frequency daily 03:17
```

When the time is omitted, the last valid configured time is retained.

### Weekly

```bash
sudo ubuntu-update-manager set-frequency weekly sunday 03:17
```

Weekdays may be supplied as names or numbers from `0` through `6`, where `0` is
Sunday.

### Monthly

```bash
sudo ubuntu-update-manager set-frequency monthly 1 03:17
```

Monthly schedules accept days `1` through `28`. This avoids silently skipping a
run in shorter months.

### Custom

```bash
sudo ubuntu-update-manager set-schedule "30 2 * * 1,4"
```

Custom schedules must contain exactly five numeric cron fields:

```text
minute hour day-of-month month day-of-week
```

Supported syntax includes `*`, numeric values, lists, forward ranges, and
positive steps on `*` or a range. Month and weekday names, macros such as
`@weekly`, environment assignments, commands, and shell syntax are not
accepted.

## Update Modes

### Safe Mode

Safe mode is the default:

```bash
sudo ubuntu-update-manager set-mode safe
```

It runs:

```bash
apt-get --with-new-pkgs upgrade
```

This can install new dependency packages but does not intentionally remove
installed packages.

### Full Mode

```bash
sudo ubuntu-update-manager set-mode full
```

Full mode runs:

```bash
apt-get full-upgrade
```

It may install new dependencies, change dependency relationships, or remove
packages when APT determines that doing so is required. Review this choice
carefully on production systems.

Both modes:

- Run noninteractively
- Keep the currently installed version of a modified package configuration file
- Retry package retrieval up to three times
- Wait up to 300 seconds for the APT or dpkg lock
- Fail if any configured repository cannot refresh successfully
- Run `apt-get autoclean` after a successful upgrade

## Snap Updates

Snap refreshes are enabled by default:

```bash
sudo ubuntu-update-manager set-snaps on
sudo ubuntu-update-manager set-snaps off
```

When enabled, `snap refresh` runs after the APT upgrade if the `snap` command is
installed. A failed Snap refresh causes the overall update run to fail.

## Automatic Reboot

Automatic rebooting is disabled by default:

```bash
sudo ubuntu-update-manager set-reboot on
```

When enabled, a scheduled run checks `/var/run/reboot-required`. If the file is
present after successful updates, the manager schedules a reboot in one minute.

Manual runs never automatically reboot the server. This safeguard applies to
the command-line `run` command and updates started from the interactive menu.

## Failure Email

Configure one recipient:

```bash
sudo ubuntu-update-manager set-email admin@example.com
```

Disable notifications:

```bash
sudo ubuntu-update-manager set-email off
```

Email delivery requires `/usr/sbin/sendmail` from a configured local
sendmail-compatible service. The notification contains the host, timestamps,
exit code, approximate script line, log path, and the last 80 log lines.

The cron file intentionally sets `MAILTO=""`; notifications are sent by the
manager only when an address is configured.

## Status and Logs

Show the current state:

```bash
sudo ubuntu-update-manager status
```

The status output includes:

- Installed and enabled state
- Human-readable and raw cron schedules
- Update, Snap, reboot, and email settings
- Log rotation policy
- Last run result, exit code, duration, success, and failure
- Cron service health
- Relevant warnings for APT timers, unattended upgrades, missing mail service,
  and pending reboots

Display the default last 100 log lines:

```bash
sudo ubuntu-update-manager logs
```

Display a different number:

```bash
sudo ubuntu-update-manager logs 250
```

The active log is `/var/log/ubuntu-update-manager.log`. It is rotated weekly,
12 archives are retained, and older archives are compressed.

## Managed Files

| Path | Purpose |
| --- | --- |
| `/usr/local/sbin/ubuntu-update-manager` | Installed executable |
| `/etc/default/ubuntu-update-manager` | Validated configuration |
| `/etc/cron.d/ubuntu-update-manager` | Root cron schedule |
| `/etc/logrotate.d/ubuntu-update-manager` | Log rotation policy |
| `/var/log/ubuntu-update-manager.log` | Update output |
| `/var/lib/ubuntu-update-manager/status` | Last run state |
| `/run/lock/ubuntu-update-manager.lock` | Concurrent-run lock |

The configuration and generated system files are root-owned. The manager
rejects symbolic links at protected destinations and rejects a configuration
file that is not root-owned or is group or world writable.

Use the manager's commands to edit settings. Do not add shell expressions,
quotes, or commands to the configuration file; values are parsed as literal
data and strictly validated.

## Interaction With Ubuntu Background Updates

Ubuntu may already use `apt-daily.timer`, `apt-daily-upgrade.timer`, or
`unattended-upgrades`. Ubuntu Update Manager does not disable them.

The `status` command warns when overlapping facilities are detected. Update
runs wait up to five minutes for APT locks, but administrators should review all
active policies and avoid redundant update schedules.

Cron does not replay a missed job after a powered-off system starts. A future
systemd timer backend is planned to support persistent scheduling. Until then,
choose a schedule when the server is normally online.

## Failure Behavior

An update run is marked failed when a required command fails, including:

- Repository refresh
- APT upgrade
- APT cleanup
- Snap refresh, when enabled and installed
- Run-state or other required update bookkeeping

Failure details are written to the update log and system log. The status file
records the exit code and failure time. If configured, a notification is also
sent through the local mail service.

If another update run already owns the manager lock, a new run exits without
starting another update. Uninstall also refuses to continue while an update is
active.

## Uninstall

Interactive removal:

```bash
sudo ubuntu-update-manager uninstall
```

Confirmed noninteractive removal:

```bash
sudo ubuntu-update-manager uninstall --yes
```

Uninstall removes the executable, configuration, cron job, logrotate policy,
and state file. It intentionally retains:

```text
/var/log/ubuntu-update-manager.log
```

Remove that log separately only when its history is no longer needed.

## Troubleshooting

### Cron is inactive

Run the installer again:

```bash
sudo bash ubuntu-update-manager.sh install
```

Then verify:

```bash
sudo systemctl status cron
sudo ubuntu-update-manager status
```

### APT lock timeout

Another package-management process held the APT lock for more than five
minutes. Check active APT, dpkg, unattended-upgrade, and Ubuntu background timer
activity. Do not delete dpkg lock files while a package process is running.

### Repository refresh failure

Review the update log:

```bash
sudo ubuntu-update-manager logs 250
```

Repair or disable the failing repository through the appropriate Ubuntu package
source configuration, then run the update manually again.

### Failure email is not delivered

Confirm that `/usr/sbin/sendmail` exists and that the local mail service can
deliver external mail. Setting an address in Ubuntu Update Manager does not
install or configure a mail server.

### A reboot is required

The manager reports the presence of `/var/run/reboot-required`. Reboot manually,
or enable automatic rebooting for future scheduled runs after confirming that
the maintenance window is appropriate.

## Security Model

- Configuration is never sourced or evaluated as shell code.
- Only known keys and validated values are accepted.
- Unknown keys, duplicate keys, malformed lines, unsafe permissions, and
  symbolic links are rejected.
- APT package authentication and repository verification remain enabled.
- Managed writes use temporary files followed by atomic replacement.
- Update execution is serialized with a nonblocking lock.
- Automatic rebooting requires explicit opt-in and a scheduled run.
- Package configuration changes retain the administrator's existing file by
  default.

The manager runs package operations as root by necessity. Review the script and
obtain it from a trusted location before installation.

## Project Files

- [changelog.md](changelog.md): release history
- [roadmap.md](roadmap.md): planned improvements and project direction
- `ubuntu-update-manager.sh`: complete installer and management utility

## License

No license has been selected yet. Until a license is added, the script remains
copyrighted by its author and is not automatically granted open-source reuse
rights.