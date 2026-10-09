# Agent configuration

This directory contains configuration authored in this repository.

Skills installed from external sources belong in the local `~/.agents/skills`
directory and are managed separately. Do not add external skill content, or the
machine-local global lockfile `~/.agents/.skill-lock.json`, to this repository.

The per-machine dependency manifest is tracked outside this package, in
`skills-personal/` and `skills-corporate/`, and replayed by
`general/bin/skills-sync`. A skill authored here — currently
`skills/jira-issue-formatting/` — does belong here.
