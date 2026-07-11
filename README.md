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
- `file:///local/path`    → used as-is (useful for local testing; cached under `local/<basename>`)

### Examples

```
agent-skills.sh owner/repo my-skill .agents/skills
agent-skills.sh https://github.com/owner/repo.git my-skill .agents/skills
agent-skills.sh git@github.com:owner/repo.git my-skill .agents/skills
```

When multiple directories named `<skill-name>` are found, the script applies the **5-bucket rule** to classify each match into one of 5 buckets by path shape and sorts them by bucket priority (then depth asc, then path asc). Buckets (highest to lowest priority):

1. `.X/skills/<skill>` — a dotfile-prefixed directory containing a `skills` subdirectory that directly holds the skill (depth 2).
2. `skills/<skill>` — a top-level `skills` directory holding the skill (depth 1).
3. `<skill>` — the skill is a direct child of the cache root (depth 0).
4. `.X/<...>/<skill>` — any other path under a dotfile-prefixed directory.
5. `<...>/<skill>` — any other path.

Bucket priority is absolute: a bucket 1 match wins over a bucket 5 match even when bucket 1 has higher depth. Within a bucket, ties are broken by depth (lower first), then alphabetically (under `LC_ALL=C`).

In interactive contexts (TTY), the script prompts with a numbered list. In non-interactive contexts (stdin is not a TTY), it fails with exit code `5` and lists all matches.

#### Ranking example

Given these 6 paths under the cache root:

```
.claude/skills/my-skill/SKILL.md              → bucket 1, depth 2
.opencode/skills/my-skill/SKILL.md            → bucket 1, depth 2
skills/my-skill/SKILL.md                      → bucket 2, depth 1
my-skill/SKILL.md                             → bucket 3, depth 0
.agents/community/skills/my-skill/SKILL.md    → bucket 4, depth 3
community/python/skills/my-skill/SKILL.md     → bucket 5, depth 3
```

The script ranks them in this order:

1. `.claude/skills/my-skill` (bucket 1, alphabetical tiebreak)
2. `.opencode/skills/my-skill` (bucket 1)
3. `skills/my-skill` (bucket 2)
4. `my-skill` (bucket 3)
5. `.agents/community/skills/my-skill` (bucket 4 — note: `community` between `.agents` and `skills` puts this in bucket 4, not bucket 1)
6. `community/python/skills/my-skill` (bucket 5)

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

## Development

Run the test suite (bats):

```
./scripts/test.sh
```

Run the full gate (tests + syntax check + POSIX shellcheck + optional checkbashisms):

```
./scripts/lint.sh
```
