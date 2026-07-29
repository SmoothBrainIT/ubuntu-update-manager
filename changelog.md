# Changelog

All notable changes to Ubuntu Update Manager are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## 1.1.1 - 2026-07-29

### Added

- `doctor` (also available as `check`) to validate required utilities, managed
  file ownership and permissions, configuration and cron parsing, cron service
  state, reboot prerequisites, Snap availability, and optional mail delivery.
- `preview` (also available as `dry-run`) to show pending APT and Snap updates
  without changing the system or refreshing package lists.
- `export-config` for validated, noninteractive configuration backups and
  audits.
- `check-update` and an interactive-menu prompt when the public repository has
  a newer semantic version.
- `self-update` and `set-self-update off|manual|scheduled|both` for validated,
  atomic manager updates before selected package-update runs.
- `/usr/local/sbin/uum` as a short command for every existing subcommand, with
  collision-aware installation, health checks, and uninstall cleanup.
- `set-lock-timeout SECONDS` and the `APT_LOCK_TIMEOUT` setting, accepting 0
  through 3600 seconds with the existing conservative 300-second default.
- Explicit checks for required base utilities before installation and update
  execution.
- Automated Bash syntax checks, ShellCheck, and CLI smoke tests through GitHub
  Actions.
- Support, contribution, and security policies.

### Changed

- Failure output, system-log entries, email notifications, and persistent state
  now identify the exact failed update phase.
- Persistent run state now records whether the last run required a reboot and
  whether a reboot was scheduled.
- Status output now includes the configured APT lock timeout and last-run reboot
  details.
- The support target is documented as Ubuntu 22.04, 24.04, and 26.04 LTS while
  those releases remain in Canonical's standard support window.

### Compatibility

- Existing 1.1.0 configuration files migrate automatically; the new lock
  timeout uses 300 seconds and automatic manager updates remain off when the
  corresponding keys are absent.
- Menu checks remain enabled when automatic manager updates are off. A failed
  check or self-update never blocks Ubuntu package updates.
- The `uum` shorthand intentionally takes precedence in the administrator
  `PATH`. Installation refuses to overwrite an unrelated local `uum` path, and
  the full `ubuntu-update-manager` command remains available.

### Fixed

- Corrected the README license section to reflect the repository's MIT license.

## 1.1.0 - 2026-07-28

### Added

- Strict configuration parsing that treats values as data instead of executing
  `/etc/default/ubuntu-update-manager` as shell code.
- Field-aware validation for all five cron fields, including numeric bounds,
  lists, ranges, and nonzero step values.
- Atomic writes for the installed program, configuration, cron definition,
  logrotate definition, and run-state file.
- Weekly log rotation with 12 retained archives, compression, and
  `delaycompress`.
- Persistent run history containing:
  - Last run start and finish times
  - Last result and exit code
  - Last run duration
  - Most recent success and failure times
- Optional failure email notifications through a locally configured
  sendmail-compatible service.
- `set-email ADDRESS|off` command.
- APT repository retries and a five-minute package-lock timeout.
- Fatal handling of incomplete repository refreshes through
  `APT::Update::Error-Mode=any`.
- Installation and startup verification for cron and logrotate.
- Status warnings for active Ubuntu APT timers, enabled unattended upgrades,
  missing local mail delivery, inactive cron, and pending reboots.
- Protection against uninstalling the manager while an update run is active.
- Backward-compatible parsing and normalization of valid v1.0 configuration
  files.

### Changed

- Update execution now runs in a subshell so file descriptors, traps,
  environment variables, and locks are released when the run finishes.
- Manual update runs never trigger an automatic reboot. Automatic rebooting
  applies only to scheduled runs.
- Existing valid run-time and run-day values are retained when a custom cron
  schedule is selected.
- Affected v1.0 custom schedules containing `RUN_TIME=custom` or
  `RUN_DAY=custom` are repaired with safe defaults during migration.
- Package-list refreshes now fail the update run if any configured repository
  fails to refresh.
- Installed and generated files are rejected when a symbolic link is present at
  a protected destination.
- Configuration files must be regular files owned by root and may not be group
  or world writable.
- Update logs are created as `0640` and assigned to `root:adm` when the `adm`
  group exists, otherwise `root:root`.
- Configuration, cron, state, and logrotate files are normalized to root
  ownership with controlled permissions.

### Fixed

- Fixed the interactive menu retaining update log redirection after a manual
  run.
- Fixed the interactive menu retaining the update lock until the menu exited.
- Fixed invalid cron expressions such as out-of-range values, zero steps,
  malformed ranges, and unsupported colon syntax being accepted.
- Fixed switching from a custom schedule back to daily, weekly, or monthly
  without explicitly supplying a new run time.
- Fixed manually invoked updates scheduling a reboot when automatic rebooting
  was enabled.
- Fixed installation being able to report success without verifying that cron
  was actually running.

### Security

- Removed root-level execution of configuration file contents.
- Rejects unknown keys, duplicate keys, malformed lines, unsafe file ownership,
  unsafe permissions, symbolic links, and invalid values in the configuration.
- Preserves existing package configuration files with `--force-confold` during
  noninteractive upgrades.
- Uses authenticated APT behavior without insecure repository or package
  overrides.

## 1.0.0 - 2026-07-26

### Added

- Initial cron-based Ubuntu update manager.
- Interactive management menu and command-line interface.
- Daily, weekly, monthly, and custom cron schedules.
- Enable and disable controls without uninstalling.
- Safe and full APT update modes.
- Optional Snap refreshes.
- Optional automatic reboot when updates require one.
- Manual update execution and update log viewing.
- Nonblocking update lock through `flock`.
- Installation, status, version, help, and uninstall commands.
- Default weekly schedule for Sunday at 03:17 local server time.
