# Support Policy

Ubuntu Update Manager targets Ubuntu Server and Desktop LTS releases that are
within Canonical's [standard support window](https://ubuntu.com/about/release-cycle).
For release 1.1.1, those series are:

- Ubuntu 22.04 LTS
- Ubuntu 24.04 LTS
- Ubuntu 26.04 LTS

The project aims to test all listed releases with disposable systems as the
integration test suite develops. A listed release describes the intended
support surface; it is not a substitute for testing a change in your own
environment before production rollout.

Ubuntu derivatives using APT may work, but are supported on a best-effort
basis. Interim Ubuntu releases, ESM-only releases, non-Ubuntu Debian systems,
and distributions without the expected Ubuntu cron and package-management
layout are outside the primary support target.

## Compatibility guarantees

- Patch releases preserve valid configuration from earlier releases in the
  same minor series.
- Unknown or unsafe configuration remains a hard error rather than being
  silently ignored.
- Manual update runs do not automatically reboot.
- Existing Ubuntu APT timers and unattended-upgrade services are never
  silently disabled.
- Downgrades are not guaranteed. Export configuration before changing versions.

When reporting a compatibility problem, include the Ubuntu release, manager
version, `doctor` output, relevant status output, and sanitized log excerpts.
Remove email addresses, repository credentials, hostnames, and other secrets.
