# Git SemVer Hooks

Dependency-free Conventional Commit releases using Git and its POSIX shell (included with Git for Windows). Version and changelog changes are amended into your own commit. CI publishes releases without adding a release commit or requiring a pull afterward.

## Install

1. Copy `.githooks`, `.github`, and `.gitattributes` into your project. Merge existing files; do not copy `.git`, this README, or this template's release history.
2. Configure `.githooks/semver.conf` and `.github/workflows/release.conf` for your product. For a root `VERSION` file, set `version_file=VERSION` and clear `version_field=`; this repository itself uses an embedded hooks version. Commit the settings and starting version file in a `chore:` commit. The remote branch's version is the release baseline.
3. Run once per clone, in PowerShell or Git Bash:

   ```sh
   git config --local alias.semver '!sh .githooks/semver'
   git semver --install
   ```

For multiple repositories, set this alias once per computer instead of the local alias above:

```sh
git --% config --global alias.semver "!f() { if test -f .githooks/semver; then sh .githooks/semver \"$@\"; fi; }; f"
```

Then run only `git semver --install` once per clone after adding or pulling the hook files. The global alias silently skips repositories without `.githooks/semver`; it does not enable hooks automatically.

On Windows, run `activate-semver.bat` to configure the global alias and search the current user's Documents, Downloads, Desktop, and OneDrive folders (including redirected Windows folder locations). It installs hooks in repositories containing `.githooks/semver`, lists successful installations, skipped repositories, and errors, then prompts for another parent folder to search. Press Enter to finish.

The batch file is self-contained and uses built-in Windows PowerShell internally. You can keep it anywhere. To search a specific parent folder instead, run `activate-semver.bat "C:\Projects"`. Add `-NoPrompt` to skip the final prompt. It replaces a different global `semver` alias with the guarded alias above, skips `.git`, `node_modules`, and directory links, and avoids duplicate installations within a run. Installation and folder-read failures return a nonzero exit code.

The installer enables `post-commit`, `pre-push`, `post-index-change`, automatic annotated-tag pushing, and a recovery-aware `git semver` alias. No wrapper, PowerShell script, profile change, or per-terminal setup is needed. New clones require installation again. Git supplies the shell for aliases even when `sh` is absent from PowerShell's PATH.

## Uninstall

```sh
git semver --uninstall
```

Restores the previous local Git settings saved by `--install` and removes the setup alias. Settings changed after installation are kept. Reinstalling preserves the original backup. Finish or abort any active synchronization first.

Installations made before backup support remove only recognized local SemVer settings; their previous values cannot be recovered automatically. Global settings are unchanged. If a restored or inherited `core.hooksPath=.githooks` would keep these hooks active, uninstall disables hooks with a local null-device override (`/dev/null`, or `nul` with Git for Windows).

Files, commits, tags, and local release records are retained. To remove the shared automation files too, remove `.githooks` and `.github/workflows/release.yml` manually, preserving any unrelated hooks or workflow actions. The GitHub release workflow remains active until removed. To enable hooks again, repeat the installation steps.

## Daily workflow

```sh
git add .
git commit -m "fix: correct a bug"
git push
```

`post-commit` fetches the tracking remote once, uses its version as the baseline, generates the version and grouped changelog, amends the current commit, and creates its provisional annotated tag. If the remote is ahead, its changelog supplies the published history; local code stays in place until `git semver --sync` integrates it. Internal amendments disable hooks to prevent recursion.

`post-commit` contains the release functions and runs automatic commit preparation. The `semver` script handles manual commands and loads only the function definitions from `post-commit`; loading them does not run automatic commit preparation. Ordinary commits do not invoke `semver`. Active recovery snapshots include both scripts and the configuration so synchronization can resume after a rebase checks out older hook files.

Several commits before a push share one provisional release. From `1.2.3`, two fixes keep the draft at `1.2.4`; adding a feature changes it to `1.3.0`. The notes contain all qualifying commits since the published release. The provisional tag follows the latest commit; only tags recorded by this clone as unpublished drafts are moved. Published and unrelated tags are preserved.

Set `commit_version=true` in `.githooks/semver.conf` to include the release tag after the colon in the latest release commit's subject, for example `fix: [v1.2.4] correct a bug`. Subjects without a Conventional Commit prefix get the label at the start. This is off by default. The message body is preserved. Refreshing a draft replaces its generated label; synchronization removes generated labels from unpublished history before rebuilding the release. Earlier commits in a draft can show provisional versions until synchronization; the tagged commit carries the release version.

`pre-push` compares the prepared branch baseline with the remote ID Git already supplies to the hook, checks the selected commit and release tag, then lets Git push. It makes no network calls and does not change files or start another push. `push.followTags=true` includes the annotated release tag with an ordinary push. Repeating a successful push does not increment the version.

If the destination branch changes between commit and push, or local code still needs integration, push stops with instructions to run `git semver --sync`, then retry `git push`. A conflicting release tag also blocks publication. Unrelated remote branches and tags no longer invalidate preparation. Git checks the refs again on the server, covering changes after the hook runs.

Ordinary `git push` does not guarantee an atomic branch-and-tag update. Use `git push --atomic` when you require both to succeed or fail together; the server must support it.

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

Automatic continuation finishes synchronization and prepares the release locally; run `git push` to publish. A commit hook's failure does not undo the original code commit: read its output. Pushes remain blocked until preparation succeeds. When working files or connectivity caused the failure, fix the problem and run `git semver --sync` to resume.

```sh
git semver --abort
```

Abort restores an active rebase and its original provisional tag. Completed synchronization is retained. An aborted, incompletely prepared code commit still needs `git semver --sync` before it can be pushed. Original commits remain protected by a private reference during active recovery.

A rejected ordinary push retains its prepared commit and tag. Retry the push after fixing authentication or server policy; if remote history changed, synchronize first. No hook force-pushes or silently discards working files.

If an ordinary push published the branch but rejected the tag, run `git semver --sync` to confirm publication, follow its tag-only push command, then run `git semver --sync` again. The published release commit is retained. This check prevents Git from publishing a draft tag alone when it has omitted a rejected branch from the hook input.

## Commands

```sh
git semver                 # Show help
git semver --help
git semver --install       # Enable hooks for this clone
git semver --update        # Check the source and update hooks and the release workflow
git semver --uninstall     # Restore local Git settings and disable these hooks
git semver --sync          # Synchronize and refresh the release draft; do not push
git semver --continue      # Resume the interrupted operation
git semver --abort         # Cancel the interrupted operation
```

`git semver --update` checks the source repository's default branch using Git. It replaces changed hook scripts and `.github/workflows/release.yml`, including customizations to their implementation. It also checks `.githooks/semver.conf` and `.github/workflows/release.conf` for missing options and inserts them with the source defaults beside their neighboring options in the source template. Existing values (including empty values), comments, and formatting are preserved; commented-out options count as missing. Repeating an update does not add duplicates. Previous files, including changed configs, are saved under the Git directory in `semver-update-backup.*`. Your `.gitattributes`, version, changelog, and other project files are retained. Review and commit the updated files. Finish active recovery, rebases, and merges before updating.

When `.github/workflows/release.conf` is missing, the updater creates it from the source defaults and migrates the four publishing settings from the old workflow's top-level `env:` block. Simple quoted strings and plain values are supported. Complex YAML or GitHub expressions stop the update before files are replaced; create the config manually and retry. Older copies of the updater do not perform this migration: create `.github/workflows/release.conf` with your settings before their first update, or recover the settings from the workflow backup afterward.

When no files differ, it reports `SemVer: updated to the most recent version.` If the source cannot be reached or found, it reports `SemVer: can't find the source.` without showing the repository name or URL.

## Configuration

Edit shell variables in `.githooks/semver.conf`. Use quotes for spaces and `''` for an empty value.

| Setting | Default | Meaning |
| --- | --- | --- |
| `version_file` | `.githooks/semver` in this repository | Repository-relative plain-text, JSON, or embedded version file. Set this to your own product file when copying the hooks. |
| `version_field` | `semver_version='{version}'` in this repository | Empty for plain text; a unique JSON field name for JSON; or a literal full-line template containing exactly one `{version}` placeholder for embedded versions. |
| `tag_prefix` | `v` | Must match `TAG_PREFIX` in `.github/workflows/release.conf`. |
| `commit_version` | `false` | Insert `[<release tag>]` after the subject colon (or at the start for ordinary subjects); uses `tag_prefix`. |
| `changelog_exact_commit_message` | `false` | Include full qualifying commit messages (subject and body) in changelog entries and tag notes, retaining generated version labels. With `commit_version=true`, the latest entry includes its new release tag. Bodies are indented under their bullet; trailing blank lines are omitted. |
| `changelog_file` | `CHANGELOG.md` | Repository-relative changelog path. |
| `changelog_heading` | Template heading | Header placed above generated releases; literal `\n` separates lines. |
| `changelog_remove_extra_headings` | `true` | Remove existing Markdown top-level (`#`) titles and all introductory text below each title until the next heading (`##` through `######`), keeping the configured header. Set `false` to retain custom titles and introductions. Release and category headings and their contents are preserved. Applies when generating releases; manually preserved changelogs remain untouched. |
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

This repository uses its own hooks to update `semver_version` inside `.githooks/semver`. Run `git semver --version` to see the installed hooks version, independently of your product version. The starting hooks version is `0.0.0`; qualifying commits advance it after installation.

When copying the hooks into another repository, configure its product version. For a plain-text version file containing only `X.Y.Z`, set `version_file=VERSION` and `version_field=`. For JSON, set `version_file=manifest.json` and `version_field=version`. The field must appear exactly once on its own line:

```json
{
  "version": "1.2.3",
  "name": "example"
}
```

For a version embedded in another text file, set `version_field` to a literal full-line template, for example `version_field="semver_version='{version}'"`. The file must contain exactly one matching line such as `semver_version='1.2.3'`. Only `X.Y.Z` values match. Everything around `{version}` is literal, including indentation and quotes; this is not a regular expression. Other lines and CRLF endings are preserved when replacing the value. Patterns cannot span lines. Synchronization restores only the generated version, preserving other edits in that file.

Updates preserve your existing `version_field` setting, including an explicitly empty value.

Nested JSON fields work by their unique name, not a dotted path. Unrelated JSON fields are preserved. Manual version or changelog edits produce a warning and are kept in the commit and push. A manually chosen version must use `X.Y.Z` and becomes the release tag's version. A manually edited changelog is kept as written. These overrides remain in effect for subsequent commits in the same unpublished release; tag notes still collect qualifying commit messages. After publication, automatic updates resume from the published version and changelog. Synchronization preserves manual edits, so conflicts involving those edits require resolution. Commits with no release-triggering changes and no active draft do not regenerate metadata.

Edit shell variables in `.github/workflows/release.conf` to control publishing. This file is retained by `git semver --update`.

| Setting | Default | Meaning |
| --- | --- | --- |
| `RELEASE_BRANCHES` | `main` | Space-separated exact branch names; empty allows all branches. Tag pushes and manual runs bypass this filter. |
| `TAG_PREFIX` | `v` | Must match `tag_prefix` in `.githooks/semver.conf`. |
| `RELEASE_TITLE_PREFIX` | Empty | Text before the tag in release titles. |
| `UPDATE_LATEST` | `true` | Set to `false` to leave GitHub's Latest selection alone. |

The workflow loads the config from the checked-out commit, so commit and push config changes to use them in CI. Older tagged commits without the file use the defaults above. Grouped release notes come from annotated tags. Disable any previous semantic-release job that increments versions or commits release files back to the branch.

## Boundaries

- Release preparation requires a clean working tree, including no untracked files. Commit or stash unrelated work before preparation. A push itself does not alter working files.
- Configure a tracking upstream matching the push destination. With none configured, preparation uses `origin` and the current branch, then records that tracking configuration for the first ordinary push.
- Use one matching fetch/push URL. Triangular workflows, custom push refspecs, mirror remotes, multiple push URLs, and unpublished merge commits require manual integration.
- IDEs that run normal Git hooks also use this workflow. IDEs that bypass hooks are detected by the pre-push readiness check; run `git semver --sync` before pushing.
- This supports stable versions and configurable Conventional Commit types, not semantic-release's complete plugin API, prerelease channels, or package publishing integrations.
- Finish recovery with the old hooks before upgrading. Existing unpublished versions generated by an older installation need reconciliation; this tool does not silently strip unknown metadata.
