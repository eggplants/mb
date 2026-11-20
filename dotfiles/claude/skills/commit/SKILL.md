---
name: commit
description: Analyze the git diff and commit it following my commit conventions.
---

## Steps

1. Read every change with `git status` and `git diff HEAD`
2. Pick the message language (see **Language** below)
3. Split the changes into logical units and draft a message for each
4. Show the split to the user and wait for approval before committing
5. Commit each unit with `git add <files>` then `git commit -m "..."`
6. Confirm the result with `git log --oneline -5`

## Commit convention

### Language

If the repository has cached a language, use it without looking at the history:

```sh
cat "$(git rev-parse --git-common-dir)/commit_language"
```

Otherwise write the message in the language used most in the repository's last
10 commits, and cache that language name (e.g. `Japanese`) in the file above:

```sh
git log -10 --no-merges --format=%s
```

Judge each subject by the text after `type:`. Merge commits are left out
because Git writes their messages in English on its own. On a tie, or in a
repository with no commits yet, use English but cache nothing, so the next run
judges again once there is history to go on. When the user asks for another
language, use it and overwrite the cache. The type itself stays in English
whatever the language.

### Subject

```
type: what changed
```

- **type**: `feat` / `fix` / `refactor` / `chore` / `docs` / `test`
- No scope. `feat(cli): ...` is wrong; write `feat: ...`
- No trailing period, under 50 columns (a full-width character counts as two)
- A bare noun phrase is fine when it is obvious what happened to it:
  `feat: pyinstaller`, `docs: installation`, `fix: gh pages`, `docs: 校正`
- The very first commit of a repository is `init`, with no type

In English, write lowercase after the colon, and otherwise use the imperative
or a short phrase naming the change:
`feat: remove --batch-id from otpa cm`, `fix: skip waiting if already logged-in`

In Japanese, otherwise end with the plain form of the verb (〜する, 〜しない):
`feat: 一覧に並べ替えを追加する`, `fix: ログイン済みなら待たない`

### Body

Most commits have no body. Add one only when the subject leaves a real question
open, and keep it to a sentence or two saying **why**, not what — the diff
already says what. Bullets are for the rare commit that changes several
unrelated things at once, which usually means it should have been split.

## How to split

| Situation | Call |
|-----------|------|
| A shared/base change plus the callers that use it | Separate commits |
| A feature and its tests | One commit |
| A bug fix and an unrelated refactor | Separate commits |
| Formatter-only churn | Its own `chore: format` commit (usually unnecessary) |
| The same edit repeated across several files | One commit |

## Never

- Add a `Co-Authored-By` or `Claude-Session` trailer
- Write the message in a language other than the one chosen under **Language**
- Run `git add -A` or `git add .`; name the files you changed
- Pass `--no-verify`
