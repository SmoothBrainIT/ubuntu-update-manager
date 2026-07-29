# Ubuntu Update Manager Roadmap

Ubuntu Update Manager is intentionally a small, auditable tool for maintaining
individual Ubuntu systems. Reliability, predictable failure behavior, and safe
defaults take priority over adding a large number of features.

No dates in this roadmap are commitments. Priorities may change as the script
is used across more Ubuntu releases and server configurations.

## Current Release: 1.1

Version 1.1 provides the hardened cron-based foundation:

- Strict, non-executable configuration parsing
- Validated daily, weekly, monthly, and custom schedules
- Safe and full APT update modes
- Optional Snap refreshes
- Scheduled-only automatic rebooting
- Atomic managed-file writes
- Update locking and uninstall protection
- Rotated logs and persistent run status
- Optional local email notification on failure
- Detection of common APT scheduling conflicts

## 1.1.x: Reliability and Compatibility

The next maintenance releases will focus on low-risk improvements to the
existing architecture.

- Add automated ShellCheck and Bash syntax checks.
- Add repeatable integration tests using disposable Ubuntu containers or
  virtual machines.
- Test supported behavior on active Ubuntu LTS releases.
- Add explicit checks for all required base utilities before installation.
- Improve failure summaries with the exact failed update phase.
- Record whether a reboot was required or scheduled during the last run.
- Add a `check` or `doctor` command that validates installation permissions,
  configuration, cron parsing, mail delivery prerequisites, and service state
  without installing updates.
- Add a dry-run or update-preview command that reports pending APT and Snap
  updates without changing the system.
- Add a noninteractive configuration export suitable for backups and audits.
- Add a configurable APT lock timeout while retaining a conservative default.

## 1.2: Persistent systemd Scheduling

The primary architectural goal is a systemd timer backend.

- Use a dedicated oneshot service and timer instead of `/etc/cron.d`.
- Enable `Persistent=true` so a missed run occurs after the machine starts.
- Apply systemd security hardening appropriate for APT operations.
- Expose recent service and timer state through the existing `status` command.
- Support controlled randomized delay to prevent many servers from updating at
  exactly the same time.
- Preserve the existing command-line interface where practical.
- Migrate existing cron installations without creating duplicate schedules.
- Provide an explicit scheduling-backend choice during the transition period.

The cron backend should remain available until the systemd implementation has
been validated on supported Ubuntu environments, including containers where
systemd may not be PID 1.

## 1.3: Reporting and Notifications

- Add notification backends that do not require a local mail transfer agent.
- Support success, failure, reboot-required, and reboot-scheduled notification
  policies independently.
- Produce a concise machine-readable run summary.
- Add optional JSON output for `status`, `version`, and update history.
- Retain a bounded history of recent update runs instead of only the latest
  state.
- Include updated package names and versions in an optional post-run report.
- Add notification test commands that do not perform an update.

Webhook support must include strict URL validation, short connection timeouts,
bounded output, and protection against leaking sensitive log content.

## 1.4: Update Policy Controls

- Allow opt-in security-only update policies.
- Allow explicitly configured package holds or exclusions without silently
  modifying existing administrator-managed APT holds.
- Add configurable cleanup behavior for `autoclean`, `autoremove`, and retained
  package caches.
- Add a maintenance-window deadline for reboot scheduling.
- Support a configurable reboot delay and cancellation message.
- Add pre-update and post-update health checks with explicit timeouts.
- Prevent a failed health check from being mistaken for a successful update.

Any hook system must use fixed executable paths, root-owned files, controlled
permissions, timeouts, and clear failure semantics. Arbitrary shell fragments
will not be accepted from the configuration file.

## 2.0: Multi-System Operations

Multi-system features are under consideration, but they should not turn the
local updater into a privileged network daemon.

- Provide a read-only status export for external monitoring.
- Define a stable JSON schema for run results and compliance checks.
- Support fleet orchestration through existing tools such as Ansible rather
  than embedding remote root access.
- Provide reference Ansible tasks for installation, configuration, upgrades,
  status collection, and removal.
- Add release signing and checksum verification for distributed installer
  artifacts.
- Document staged rollout and rollback strategies for managed environments.

## Documentation and Release Engineering

These tasks apply across all planned releases:

- Publish an explicit support policy for Ubuntu versions.
- Maintain upgrade notes and backward-compatibility guarantees.
- Add a security policy and responsible disclosure instructions.
- Add a license and contribution guidelines before accepting public
  contributions.
- Add changelog release links when a canonical repository is established.
- Attach checksums and signed provenance to published releases.

## Non-Goals

The following are outside the intended scope:

- Replacing APT, Snap, or Ubuntu repository trust mechanisms
- Bypassing package signatures or TLS verification
- Executing configuration values as shell code
- Silently disabling unattended upgrades or Ubuntu APT timers
- Acting as a general remote administration service
- Automatically rebooting after an interactive or manual update
- Supporting unattended distribution upgrades without a separate design and
  recovery workflow