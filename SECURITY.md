# Security Policy

## Supported versions

Security fixes are provided for the latest released version. Upgrade before
reporting an issue that is already fixed in a newer release.

## Reporting a vulnerability

Do not disclose a suspected vulnerability in a public issue. Use the
repository's **Security** tab and **Report a vulnerability** action to submit a
private report. If private reporting is unavailable, open an issue containing
no exploit details and ask the maintainer for a private contact channel.

Include:

- The affected version and Ubuntu release
- The command or configuration involved
- Required privileges and preconditions
- Reproduction steps or a minimal proof of concept
- The expected and observed security boundary
- Any proposed mitigation

Avoid including credentials, hostnames, private logs, or other secrets. Allow
the maintainer reasonable time to reproduce and address the report before
public disclosure.

## Scope

Privilege escalation, unsafe configuration evaluation, symlink or permissions
attacks on managed files, update-lock bypasses, and unintended reboot behavior
are in scope. Vulnerabilities in Ubuntu, APT, Snap, cron, or configured package
repositories should be reported to their respective maintainers.
