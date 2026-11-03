# Git SemVer Hooks

Dependency-free Conventional Commit releases using Git and its POSIX shell (included with Git for Windows). Version and changelog changes are amended into your own commit. CI publishes releases without adding a release commit or requiring a pull afterward.

## Install

1. Copy `.githooks`, `.github`, and `.gitattributes` into your project. Merge existing files; do not copy `.git`, this README, or this template's release history.
2. Configure `.githooks/semver.conf`. Commit the settings and starting version file in a `chore:` commit. If release tags exist, the version must match the latest reachable stable release.
3. Run once per clone, in PowerShell or Git Bash:

   ```sh
   git config --local alias.semver '!sh .githooks/semver'
   git semver --install
   ```

The installer enables `post-commit`, `pre-push`, `post-index-change`, automatic annotated-tag pushing, and a recovery-aware `git semver` alias. No wrapper, PowerShell script, profile change, or per-terminal setup is needed. New clones require installation again. Git supplies the shell for aliases even when `sh` is absent from PowerShell's PATH.

## Daily workflow

```sh
git add .
git commit -m "fix: correct a bug"
git push
```

`post-commit` checks the tracking remote, analyzes unreleased commits, generates the version and grouped changelog, amends the current commit, and creates its provisional annotated tag. It records the remote's branches and tags for the push check. Internal amendments disable hooks to prevent recursion. If the remote branch has advanced, preparation stops and asks you to run `git semver --sync`; a normal commit does not rebase or merge automatically.

Several commits before a push share one provisional release. From `1.2.3`, two fixes keep the draft at `1.2.4`; adding a feature changes it to `1.3.0`. The notes contain all qualifying commits since the published release. The provisional tag follows the latest commit; only tags recorded by this clone as unpublished drafts are moved. Published and unrelated tags are preserved.

`pre-push` checks that the remote's branches and tags exactly match the snapshot taken during commit preparation, then validates the selected commits and tags. If nothing changed, Git pushes the prepared commit and release tag. Push does not update the version or changelog, rewrite history, or start a nested push. `push.followTags=true` includes the annotated release tag with an ordinary push. Repeating a successful push does not increment the version.

Commits perform network and release work, so they take longer than plain Git commits. If any remote branch or tag is added, changed, or deleted after preparation, the push stops with instructions to run `git semver --sync`, then retry `git push`. Git still checks the refs being pushed on the server; the snapshot check cannot lock unrelated remote refs against changes after the check.

Ordinary `git push` does not guarantee an atomic branch-and-tag update. Use `git push --atomic` when you require both to succeed or fail together; the server must support it. `git semver --push` also prepares and publishes atomically.

| Commit message | Release impact |
| --- | --- |
| `fix: ...`, `perf: ...` | Patch |
| `feat: ...` | Minor |
| Valid Conventional Commit with `!` or a `BREAKING CHANGE:` footer | Major |
| `docs: ...`, `chore: ...`, ordinary messages | None by default |

Scopes work, for example `fix(api): correct a bug`. Notes contain qualifying subjects as bullet points without category headings by default. Set the optional category titles in `.githooks/semver.conf` to add headings. Docs-only commits produce no release unless a release draft already exists; in that case its tag moves to the latest unpublished commit.

## Synchronization and conflicts

```sh
git semver --sync
```

This fetches the remote, strips known generated metadata from unpublished history, rebases code onto the upstream, and rebuilds one release draft. Generated version/changelog changes therefore do not cause avoidable metadata conflicts. Published commits on any fetched branch or tag are never rewritten.

Code conflicts pause synchronization. An explicitly configured merge tool opens when an interactive terminal is available; otherwise use your editor or `git mergetool`. Resolve the files and mark them resolved in your merge manager, or stage them:

```sh
git add <resolved-files>
git push
```

With `auto_continue=true` (the default), staging the last conflict automatically continues synchronization and rebuilds the release draft once there are no unstaged changes. If another commit conflicts, resolve and stage it too. Your merge manager must use Git's hooks when staging; saving a file alone does not trigger continuation. Set `auto_continue=false` before starting synchronization to require `git semver --continue` after staging instead. The manual command remains available for managers that bypass hooks.

Automatic continuation resumes the original operation: a normal commit or `--sync` prepares locally, while an explicit `--push` also publishes. A commit hook's failure does not undo the original code commit: read its output. Pushes remain blocked until preparation succeeds. When working files or connectivity caused the failure, fix the problem and run `git semver --sync` to resume.

```sh
git semver --abort
```

Abort restores an active rebase and its original provisional tag. Completed synchronization is retained. An aborted, incompletely prepared code commit still needs `git semver --sync` before it can be pushed. Original commits remain protected by a private reference during active recovery.

A rejected ordinary push retains its prepared commit and tag. Retry the push after fixing authentication or server policy; if remote history changed, synchronize first. No hook force-pushes or silently discards working files.

If an ordinary push published the branch but rejected the tag, retry the push to complete tag publication. If you already made another commit, follow the error's tag-only push command, then run `git semver --sync`. The published release commit is retained.

## Commands

```sh
git semver                 # Show help
git semver --help
git semver --install       # Enable hooks for this clone
git semver --sync          # Synchronize and refresh the release draft; do not push
git semver --continue      # Resume the interrupted operation
git semver --abort         # Cancel the interrupted operation
git semver --push          # Optional: synchronize, prepare and push atomically
```

## Configuration

Edit shell variables in `.githooks/semver.conf`. Use quotes for spaces and `''` for an empty value.

| Setting | Default | Meaning |
| --- | --- | --- |
| `version_file` | `VERSION` | Repository-relative plain-text or JSON file. |
| `version_field` | Empty | Empty for plain text; otherwise a unique JSON field name. |
| `tag_prefix` | `v` | Must match `TAG_PREFIX` in the release workflow. |
| `changelog_file` | `CHANGELOG.md` | Repository-relative changelog path. |
| `changelog_heading` | Template heading | Literal `\n` separates lines; must match the file header. |
| `changelog_breaking_title` | Empty | Optional heading for breaking changes. |
| `changelog_features_title` | Empty | Optional heading for features. |
| `changelog_fixes_title` | Empty | Optional heading for bug fixes. |
| `changelog_performance_title` | Empty | Optional heading for performance improvements. |
| `patch_types` | `fix perf` | Space-separated patch commit types. |
| `minor_types` | `feat` | Space-separated minor commit types. |
| `allowed_branches` | `main` | Exact names separated by spaces; empty enables all branches. |
| `auto_continue` | `true` | Automatically resume paused synchronization when all conflicts are staged and no unstaged changes remain; `false` requires `--continue`. |
| `initial_version` | `0.0.0` | Baseline when no version exists. |

For example, set `changelog_fixes_title='Bug fixes'` to include `### Bug fixes` above fix entries. Leave a title empty to omit that heading. Headings only appear when their category has entries.

Plain-text version files contain only `X.Y.Z`. For JSON, set `version_file=manifest.json` and `version_field=version`. The field must appear exactly once on its own line:

```json
{
  "version": "1.2.3",
  "name": "example"
}
```

Nested fields work by their unique name, not a dotted path. Unrelated JSON fields are preserved. Manual version changes or edits to an active draft's changelog block generation for reconciliation instead of being discarded. Existing committed changelog content is retained below the generated section.

Settings at the top of `.github/workflows/release.yml` control publishing. Grouped release notes come from annotated tags. Disable any previous semantic-release job that increments versions or commits release files back to the branch.

## Boundaries

- Release preparation requires a clean working tree, including no untracked files. Commit or stash unrelated work before preparation. A push itself does not alter working files.
- Configure a tracking upstream matching the push destination. With none configured, preparation uses `origin` and the current branch, then records that tracking configuration for the first ordinary push.
- Use one matching fetch/push URL. Triangular workflows, custom push refspecs, mirror remotes, multiple push URLs, and unpublished merge commits require manual integration.
- IDEs that run normal Git hooks also use this workflow. IDEs that bypass hooks are detected by the pre-push readiness check; run `git semver --sync` before pushing.
- This supports stable versions and configurable Conventional Commit types, not semantic-release's complete plugin API, prerelease channels, or package publishing integrations.
- Finish recovery with the old hooks before upgrading. Existing unpublished versions generated by an older installation need reconciliation; this tool does not silently strip unknown metadata.
