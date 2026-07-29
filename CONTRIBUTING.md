# Contributing

Contributions that keep Ubuntu Update Manager small, auditable, and safe are
welcome. Open an issue before starting a large feature or architectural change.

## Development checks

Run the same checks used by continuous integration:

```bash
bash -n ubuntu-update-manager.sh tests/smoke.sh
shellcheck ubuntu-update-manager.sh tests/smoke.sh
bash tests/smoke.sh
```

Changes to installation, scheduling, update execution, permissions, or
uninstallation should also be tested in a disposable Ubuntu system. Never run
update-path tests against a production host.

## Pull requests

- Keep each pull request focused on one behavior or closely related group of
  behaviors.
- Explain the failure behavior and privilege implications of the change.
- Add or update tests and documentation for user-visible behavior.
- Preserve strict configuration parsing; configuration values must never be
  evaluated as shell code.
- Preserve existing settings during upgrades whenever they remain valid.
- Do not disable Ubuntu background update facilities automatically.

## Compatibility

Patch releases preserve valid configuration written by earlier releases in the
same minor series. New configuration keys must have safe defaults so an
existing installation can be upgraded noninteractively. Downgrades are not
guaranteed; use `ubuntu-update-manager export-config` before changing versions.

Security reports should follow [SECURITY.md](SECURITY.md), not a public issue.
