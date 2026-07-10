# agent-skills.sh

POSIX-compatible shell script to download an agent skill from any git repository.

## Usage

```
agent-skills.sh <repo> <skill-name> <dest-dir>
```

The script clones `<repo>` (cached at `~/.cache/agent-skills/<owner>/<repo>` and refreshed on subsequent runs with `git pull --depth=1`), finds a directory named `<skill-name>` that directly contains a `SKILL.md`, and copies it to `<dest-dir>/<skill-name>`.

`<repo>` accepts:

- `owner/repo`            → `https://github.com/owner/repo.git`
- `https://host/path`     → used as-is
- `git@host:owner/repo`   → used as-is

### Examples

```
agent-skills.sh sickn33/agentic-awesome-skills my-skill ./skills
agent-skills.sh https://github.com/owner/repo.git my-skill /tmp/skills
agent-skills.sh git@github.com:owner/repo.git my-skill ./skills
```

When multiple directories named `<skill-name>` are found, the script sorts them by canonical-location priority (`.agents` > `.opencode` > `.claude` > `skills` > other, then alphabetically) and prompts with a numbered list (TTY only). In non-interactive contexts the script fails with exit code `5` and lists all matches.

### Exit codes

| Code | Meaning |
| --- | --- |
| 0 | success |
| 1 | generic error |
| 2 | invalid arguments |
| 3 | skill not found in repo |
| 4 | git clone/pull failed |
| 5 | ambiguous match (multiple skills found, stdin is not a TTY) |

## Requirements

- POSIX `sh` (dash, ash, bash --posix, etc.)
- `git`