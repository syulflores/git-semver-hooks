# Git SemVer Hooks

Local Git hooks that use Conventional Commit messages to update a version and `CHANGELOG.md`, amend both into the same commit, and create an annotated `vX.Y.Z` tag. No Node.js dependencies. Requires Git and a POSIX shell (included with Git for Windows).

## Installation

1. Copy all files and folders into your project's repository root, including hidden `.githooks` and `.github` folders. **Skip `README.md` and `.git`.** Merge existing files instead of overwriting them.
2. Open Git Bash or PowerShell in your project's repository root and run:

   ```sh
   git config --local alias.semver-sync '!sh .githooks/semver-sync'
   git semver-sync --install
   ```

   This enables the hooks, automatic annotated-tag pushing, and the `git semver-sync` recovery command for this clone.

3. On Linux/macOS, if the hooks are not executable, run:

   ```sh
   chmod +x .githooks/post-commit .githooks/pre-push .githooks/post-index-change
   ```

Each contributor only needs to run step 2 once when they first clone your project, not after every pull. A new clone requires running it again.

## Usage

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

With a tracking upstream configured (normally by cloning or the first `git push -u origin main`), ordinary commits fetch only the tracking branch without fetching tags, then check whether its history is already included locally. If remote commits are missing, the hook automatically runs full sync before version finalization. Sync rebuilds your unpublished commits on top of that upstream, using its version and changelog as the baseline. For example, if remote is `1.2.4`, your local `fix:` becomes `1.2.5`; a following local `feat:` becomes `1.3.0`. Remote changelog entries are retained and local entries and unpublished tags are regenerated. This rewrites unpublished local commit IDs; published commits are never rewritten.

Sync requires a clean working tree, including no untracked files. It retains temporary remote references between fetches, updates changed references, and prunes deleted remote references without deleting your local version tags. Git still checks the remote tag list during sync; there is no reliable "tags since the last pull" filter. The ordinary commit check fetches no tags. Full sync checks the tag list only when remote branch history is missing locally. Changes made only to remote tags are checked during explicit sync or push, not by the branch-only commit check. Set `auto_sync=false` for local-only commits and run `git semver-sync` before pushing when needed.

The push guard blocks stale history and conflicting tags; run `git semver-sync`, then `git push` if blocked. It cannot replace commits already selected by an in-progress push. If working changes remain after the commit or the remote is unavailable, automatic sync defers, finalizes locally, and prints recovery instructions. Code conflicts pause sync for resolution before version finalization.

Code conflicts pause sync for resolution. Resolve the files in your merge manager and stage them (or run `git add <resolved-files>`). Staging the last resolved conflict automatically resumes sync, rebuilds the versions and tags, and returns you to your branch. You can then run `git push` normally. If another replayed commit conflicts, resolve and stage that set of conflicts too.

Merge tools must run Git hooks when staging. If yours bypasses hooks, run `git semver-sync` again to resume; `--continue` remains supported but is optional. Staging the final resolution completes the replayed commit immediately, so review the resolution before staging it.

Use `git semver-sync --abort` to restore the original local commits and tags. Sync requires linear unpublished history. Manual version/changelog edits produce a warning and are preserved; resolve any resulting merge conflicts normally.

## Configuration

Check the defaults below before using the hooks and change any settings needed for your project. Configuration is at the top of each file listed below.

### `.githooks/post-commit`

Controls version bumps, changelog updates, and local tags. Edit the shell variables at the top of the file. Use single quotes around values containing spaces; use `''` for an empty value. Paths are relative to your project's repository root.

| Setting | Default | Meaning and accepted input |
| --- | --- | --- |
| `version_file` | `VERSION` | Path to the plain-text or JSON version file, such as `VERSION` or `manifest.json`. |
| `version_field` | Empty | Leave empty for a plain-text version file. For JSON, enter the unique field name, such as `version`; do not use a dotted path. |
| `tag_prefix` | `v` | Text before the version in tags, such as `v` for `v1.2.3`. Use `''` for no prefix. Must match `TAG_PREFIX` in the release workflow. |
| `changelog_file` | `CHANGELOG.md` | Path to the changelog file. |
| `changelog_heading` | `# Changelog\n\nAll notable changes to this project are documented here.` | Changelog header text. Use literal `\n` for line breaks and match the existing file's header. Change the setting and header together in a `docs:` commit. |
| `patch_types` | `fix perf` | Space-separated lowercase Conventional Commit types that trigger a patch bump, such as `'fix perf'`. |
| `minor_types` | `feat` | Space-separated lowercase Conventional Commit types that trigger a minor bump, such as `'feat'`. Breaking changes override these lists and trigger a major bump. |
| `create_tag` | `true` | Exactly `true` or `false`. Set to `false` to disable local tag creation; version and changelog updates still run. |
| `allowed_branches` | `main` | Space-separated exact branch names, such as `'main develop'`. Use `''` to allow all branches. |
| `initial_version` | `0.0.0` | Baseline used when the parent commit has no version file. Enter a stable `X.Y.Z` version; the selected bump is applied to this baseline. |
| `auto_sync` | `true` | Fetch only the tracking branch before ordinary commit finalization; run full sync when remote commits are missing locally. Set to `false` for local-only finalization and manual `git semver-sync`. |

The default version source is a root `VERSION` file containing only a stable version such as `0.0.1`:

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

Commit the chosen version file and hook settings in a `chore:` commit before making version-bumping commits: the hook reads its baseline from the parent commit. Keep versions in `X.Y.Z` format. Manual version/changelog edits are allowed with a warning: the hook preserves them and skips automatic version/changelog generation and tagging for that commit. Pending working changes in these files also warn and skip automatic versioning so your edits remain intact. Unrelated JSON fields do not count as manual version edits.

### `.githooks/pre-push`

The shell variables at the top control the messages shown when an unfinished version update blocks a push. Both accept quoted text with literal `\n` for additional lines.

| Setting | Default | Meaning and accepted input |
| --- | --- | --- |
| `pending_message` | `Versioning: push blocked because version finalization is pending.` | Text explaining why the push is blocked. |
| `retry_message` | `Run: sh .githooks/post-commit --retry (use Git Bash on Windows).` | Recovery instructions. Keep the retry command accurate if you customize the text. |

### `.github/workflows/release.yml`

The `env` settings at the top control GitHub release publishing. Edit these as YAML values.

| Setting | Default | Meaning and accepted input |
| --- | --- | --- |
| `RELEASE_BRANCHES` | `"main"` | Space-separated exact branch names whose pushes publish releases, such as `"main develop"`. Use `""` to allow all branches. |
| `TAG_PREFIX` | `"v"` | Tag prefix to recognize. Must match `tag_prefix` in `.githooks/post-commit`; use `""` for no prefix. |
| `RELEASE_TITLE_PREFIX` | `""` | Optional text before the tag in release titles, such as `"Release "`. |
| `UPDATE_LATEST` | `"true"` | Exactly `"true"` or `"false"`. Controls whether the highest published stable version is marked as GitHub's Latest release. |

GitHub does not support `env` expressions in `on.push.branches`, so all branch pushes start a workflow run; the script exits before publishing when the branch is not allowed. Tag pushes and manual runs through `workflow_dispatch` bypass `RELEASE_BRANCHES`. All tag pushes trigger the workflow, but only tags matching `TAG_PREFIX` followed by a stable `X.Y.Z` version become releases.

The workflow publishes missing releases for all matching existing tags, not just the tag that triggered the run. If `create_tag=false`, automatic local tag creation stops; the workflow can still publish matching tags created separately.

## If versioning fails

The original commit remains, and pushes are blocked until finalization succeeds. Fix the reported issue, then run (in Git Bash on Windows):

```sh
sh .githooks/post-commit --retry
```
