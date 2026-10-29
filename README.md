# Git SemVer Hooks

Local Git hooks that use Conventional Commit messages to update a version and `CHANGELOG.md`, amend both into the same commit, and create an annotated `vX.Y.Z` tag. No Node.js dependencies. Requires Git and a POSIX shell (included with Git for Windows).

## Setup after every clone

Run from the cloned repository's root:

```sh
git config --local core.hooksPath .githooks
git config --local push.followTags true
```

Git does not copy this configuration when cloning, so every contributor must run these commands for each clone. On Linux/macOS, also run `chmod +x .githooks/post-commit .githooks/pre-push` if the hooks are not executable.

Commit and push normally:

```sh
git add .
git commit -m "fix: correct a bug"
git push
```

| Commit message | Version bump |
| --- | --- |
| `fix: ...` or `perf: ...` | Patch: `1.2.3` → `1.2.4` |
| `feat: ...` | Minor: `1.2.3` → `1.3.0` |
| `feat!: ...` (or another type with `!`) | Major: `1.2.3` → `2.0.0` |
| Valid Conventional Commit with a `BREAKING CHANGE: ...` footer | Major |
| `docs: ...`, `chore: ...`, other types or ordinary messages | None |

Scopes also work, e.g. `fix(api): correct a bug`. Amends, merges and replayed commits are skipped. Pushed annotated tags are included automatically; the included GitHub Actions workflow publishes GitHub releases from version tags.

## Version source

The default is a root `VERSION` file containing only a stable version such as `0.0.1`. Settings are at the top of `.githooks/post-commit`:

```sh
version_file=VERSION
version_field=
```

To use `manifest.json` instead, change those settings to:

```sh
version_file=manifest.json
version_field=version
```

The JSON field must be on its own line:

```json
{
  "version": "0.0.1"
}
```

Nested fields work with the same settings, regardless of depth:

```json
{
  "app": {
    "release": {
      "version": "0.0.1"
    }
  }
}
```

Use the field name only (`version`), not a dotted path (`app.release.version`). Exactly one matching field is allowed in the file. For a differently named key, set `version_field` to that name; for a different file location, change `version_file` to its repository-relative path.

Commit the chosen version file and hook settings in a `chore:` commit before making version-bumping commits: the hook reads its baseline from the parent commit. Keep versions in `X.Y.Z` format and let the hook manage version/changelog updates; commit manual changelog edits separately with `docs:`.

## If versioning fails

The original commit remains, and pushes are blocked until finalization succeeds. Fix the reported issue, then run (in Git Bash on Windows):

```sh
sh .githooks/post-commit --retry
```
