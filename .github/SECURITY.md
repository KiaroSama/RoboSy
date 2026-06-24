# Security Policy

## Supported versions

RoboSy is a single-file PowerShell tool. Security fixes are applied to the
latest version on the `main` branch. Please use the most recent release.

## Reporting a vulnerability

If you find a security issue, please do not open a public issue.

Instead, report it privately using GitHub's
[private vulnerability reporting](https://docs.github.com/code-security/security-advisories/guidance-on-reporting-and-writing/privately-reporting-a-security-vulnerability)
on this repository (Security tab → Report a vulnerability).

Please include:

- A clear description of the issue.
- Steps to reproduce.
- The affected path or operation (Move, Copy, Fast Delete, Move + Symlink).
- Your environment (Windows version, PowerShell version).

You can expect an initial response within a reasonable time. Once a fix is
available, the advisory will be published.

## Safe use

RoboSy moves, copies, permanently deletes, and relinks real files and folders.

- Fast Delete is permanent and bypasses the Recycle Bin.
- Always confirm source and target paths before running a job.
- Run as Administrator only when you actually need elevated access.
- Never paste secrets or credentials into prompts. RoboSy does not log secret
  values, but treat all paths and inputs with care.
