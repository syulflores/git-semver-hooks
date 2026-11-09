# Git SemVer Hooks

Automate Conventional Commit releases with Git and its POSIX shell, included with Git for Windows. Version and changelog updates become part of your commit. CI publishes releases without a separate release commit or a follow-up pull. No extra dependencies are needed.

## Install

1. Copy `.githooks` into your project. For GitHub releases, also copy `.github`. Only those two files are needed.
2. Review `.githooks/semver.conf` and, if copied, `.github/workflows/release.conf`. Choose a product version file.
3. Run once per clone in PowerShell or Git Bash:

   ```sh
   git config --local alias.semver '!sh .githooks/semver'
   git semver --install
   ```

For multiple repositories, use this global alias once per computer instead of the local alias above:

```sh
git --% config --global alias.semver "!f() { if test -f .githooks/semver; then sh .githooks/semver \"$@\"; fi; }; f"
```

Installation creates missing version and changelog files, including parent folders, using `initial_version` and `changelog_heading`. Missing embedded version files use the full-line template; JSON files start with a minimal object. Existing files are kept.

It also creates `.gitattributes` if needed and adds missing rules once:

```gitattributes
.githooks/* text eol=lf
.github/workflows/release.conf text eol=lf
```

Review and commit the configuration and new files with a `chore:` commit. Installation does not stage or commit files.

Then run `git semver --install` once per clone after adding or pulling the hooks. The global alias silently skips repositories without `.githooks/semver`; it does not activate hooks itself.

Installation enables `post-commit`, `pre-push`, `post-index-change`, annotated-tag pushing, and a recovery-aware `git semver` alias. No wrapper, separate PowerShell script, profile edit, or terminal setup is needed. Install again for each new clone. Git supplies the alias shell even if PowerShell cannot find `sh`.

## Uninstall

```sh
git semver --uninstall
```

Finish or abort synchronization first. Uninstall restores the local Git settings saved during installation and removes the setup alias. It keeps settings changed since installation. Reinstalling keeps the original backup.

Older installations without backups remove only recognized local SemVer settings; previous values cannot be restored automatically. Global settings stay unchanged. If a restored or inherited `core.hooksPath=.githooks` would leave hooks active, uninstall disables them locally using `/dev/null` (`nul` on Git for Windows).

Files, commits, tags, and local release records are kept. To remove shared automation, manually remove `.githooks` and `.github/workflows/release.yml`, keeping unrelated hooks and workflow actions. The GitHub workflow stays active until removed. Repeat installation to re-enable hooks.

## SemVer scripts

Use `semver-scripts.bat` on Windows or `semver-scripts.sh` on Linux and macOS. Each is self-contained and offers the same menu for listing, activation, and updating:

```text
1. List repositories (status and version)
2. Activate SemVer hooks
3. Update SemVer hooks
0. Exit
```

Both search Documents, Downloads, Desktop, and OneDrive. The Windows script honors redirected folders; the shell script honors Linux desktop redirects through `xdg-user-dir` when available and also searches macOS OneDrive folders under `~/Library/CloudStorage`. Both include OneDrive environment paths when set. After showing results, they ask for another folder; press Enter to return to the menu. Each selection starts a fresh scan.

The batch file works from any location using built-in Windows PowerShell. To search another folder, run:

```bat
semver-scripts.bat "C:\Projects"
```

On Linux and macOS, run the shell script with Bash 3.2 or newer and Git on PATH. It works with the Bash included with macOS and does not require an executable bit when invoked this way:

```sh
bash semver-scripts.sh
bash semver-scripts.sh "$HOME/Projects"
bash semver-scripts.sh "$HOME/Projects" --no-prompt
```

Alternatively, run `chmod +x semver-scripts.sh` once and launch it with `./semver-scripts.sh`. Use an absolute script path when launching from another directory. Both scripts accept `[parent-folder] [--no-prompt]`; a supplied parent folder replaces the default search locations.

Add `--no-prompt` to exit after the selected action without asking for more folders or returning to the menu. The initial menu still appears. Scanning skips `.git`, `node_modules`, and directory links, and processes each repository once per selection. Command or folder-read failures return a nonzero exit code.

**Activate** sets the global alias and runs `git semver --install` in repositories containing `.githooks/semver`. **Update** sets the same alias and runs `git semver --update` in those repositories. Both replace an unrelated global `semver` alias, but report an error instead of executing an unrelated repository-local alias. Results report successes, skips, and errors.

**List** reports repository status without changing Git settings or installing/updating hooks:

- **Activated:** All four scripts (`semver`, `post-commit`, `pre-push`, and `post-index-change`) exist in `.githooks`, the effective `core.hooksPath` points there, and `semver.enabled` is `true`.
- **Not activated:** All four scripts exist, but the hook path or enabled setting is not active.
- **Incomplete:** Some required scripts are missing, with other scripts or activation settings present.
- **Not installed:** None of the four scripts exist and neither activation setting indicates SemVer is active.

On Linux and macOS, **Incomplete** also covers hook files missing executable permission, which Git requires to run them. Status checks configuration and file presence; it does not execute hooks or verify their contents. For activated repositories, the listing also runs `git semver --version` and displays the installed hooks version beside the path. If that command fails or returns nothing, it shows `Version unavailable`, keeps the activation status, and reports an error with a nonzero exit code.

```bat
semver-scripts.bat
semver-scripts.bat "C:\Projects" --no-prompt
```

## Daily workflow

```sh
git add .
git commit -m "fix: correct a bug"
git push
```

After a commit, `post-commit` fetches the tracking remote once, uses its version as the baseline, updates the version and grouped changelog, amends your commit, and creates a draft annotated tag. If the remote is ahead, its changelog supplies the published history. Your code stays in place until `git semver --sync` integrates it. Internal amendments disable hooks to avoid recursion.

Release functions live in `post-commit`, which prepares ordinary commits directly. Manual `semver` commands load those functions without triggering automatic preparation. Recovery saves both scripts and the configuration so synchronization can resume even if a rebase checks out older hooks.

Commits made before a push share one draft release. From `1.2.3`, two fixes produce `1.2.4`; adding a feature changes it to `1.3.0`. Notes include all qualifying commits since publication. The draft tag follows the latest commit. Only unpublished draft tags recorded by this clone are moved; published and unrelated tags are kept.

Set `commit_version=true` to label the latest release commit, for example `fix: [v1.2.4] correct a bug`. Ordinary subjects get the label at the start. This defaults to off and preserves the message body. Refreshing a draft replaces its generated label. Synchronization removes generated labels from unpublished history before rebuilding. Earlier draft commits may show provisional versions until then; the tagged commit carries the release version.

Before pushing, `pre-push` checks the prepared baseline against the remote ID supplied by Git, plus the selected commit and release tag. It makes no network calls, changes no files, and starts no extra push. `push.followTags=true` includes the annotated tag. Repeating a successful push does not change the version.

If the destination branch changed or your code needs integration, push stops: run `git semver --sync`, then retry `git push`. A conflicting release tag also blocks publication. Unrelated remote branches and tags do not invalidate preparation. Git checks refs again on the server for later changes.

For branch and tag updates that must succeed or fail together, use `git push --atomic`; the server must support it. An ordinary push does not guarantee this.

| Commit message | Release impact |
| --- | --- |
| `fix: ...`, `perf: ...` | Patch |
| `feat: ...` | Minor |
| Valid Conventional Commit with `!` or a `BREAKING CHANGE:` footer | Major |
| `docs: ...`, `chore: ...`, ordinary messages | None by default |

Scopes work: `fix(api): correct a bug`. Notes list qualifying subjects as bullets. Optional category titles in `.githooks/semver.conf` add headings. Docs-only commits create no release, but move an existing draft's tag to the latest unpublished commit.

## Synchronization and conflicts

```sh
git semver --sync
```

Synchronization fetches the remote, removes known generated metadata from unpublished history, rebases code onto the upstream, and rebuilds one draft. This avoids conflicts from generated version/changelog changes. It never rewrites commits published on any fetched branch or tag.

Code conflicts pause synchronization. A configured merge tool opens in an interactive terminal; otherwise use your editor or `git mergetool`. Resolve files, then mark them resolved in your merge manager or stage them:

```sh
git add <resolved-files>
git push
```

By default, `auto_continue=true` resumes synchronization after the last conflict is staged and no unstaged changes remain. Resolve and stage any further conflicts the same way. Your merge manager must run Git hooks when staging; saving alone does not resume. For manual continuation, set `auto_continue=false` before synchronization and run `git semver --continue` after staging. That command also works when managers bypass hooks.

Continuation prepares the release locally. Run `git push` to publish.

A commit-hook failure leaves your original code commit intact. Read the output; push stays blocked until preparation succeeds. Fix working-file or connection problems, then run `git semver --sync`.

```sh
git semver --abort
```

Abort restores an active rebase and its original draft tag; completed synchronization is kept. An incompletely prepared commit still needs `git semver --sync` before pushing. A private reference protects original commits during recovery.

A rejected push keeps the prepared commit and tag. Fix authentication or server-policy issues and retry; synchronize first if remote history changed. Hooks never force-push or silently discard working files.

If the branch was published but its tag was rejected:

1. Run `git semver --sync` to confirm publication.
2. Follow its tag-only push command.
3. Run `git semver --sync` again.

The published release commit is kept. This check prevents publishing a draft tag alone if Git omits a rejected branch from the hook input.

## Commands

```sh
git semver                 # Show help
git semver -h              # Show help (--help is intercepted by Git)
git semver --version       # Show the hooks version
git semver --install       # Enable hooks for this clone
git semver --update        # Update hooks and the release workflow from the source
git semver --uninstall     # Restore local settings and disable hooks
git semver --sync          # Synchronize and refresh the draft without pushing
git semver --continue      # Resume an interrupted operation
git semver --abort         # Cancel an interrupted operation
```

Short options: `-h` help, `-v` version, `-i` install, `-u` update, `-U` uninstall, `-s` sync, `-c` continue, `-a` abort. Options are case-sensitive; use one per command and do not combine them.

Help and version run before loading configuration or recovery. Run `git semver --install` to refresh an existing alias so these options reach the current script during recovery.

### Updating

`git semver --update` checks the source repository's default branch using Git. It replaces changed hook scripts and `.github/workflows/release.yml`, including custom code edits.

For `.githooks/semver.conf` and `.github/workflows/release.conf`, it adds missing options beside their neighbors using source defaults. Existing values (even empty ones), comments, and formatting are kept. Commented-out options count as missing; repeated updates add no duplicates.

Backups, including changed configs, go under the Git directory in `semver-update-backup.*`. Your `.gitattributes`, version, changelog, and other project files are kept. Finish recovery, rebases, and merges before updating; review and commit the updated files afterward.

If `release.conf` is missing, the updater creates it and copies the four publishing settings from the old workflow's top-level `env:` block. Plain values and simple quoted strings work. Complex YAML or GitHub expressions stop the update before replacement; create the config manually and retry.

Older updaters cannot migrate these settings. Create `release.conf` before their first update, or recover settings from the workflow backup afterward.

If nothing differs, the message is `SemVer: updated to the most recent version.` If the source is unavailable or missing, it is `SemVer: can't find the source.` The error hides the repository name and URL.

## Configuration

Edit shell variables in `.githooks/semver.conf`. Quote values containing spaces; use `''` for an empty value.

| Setting | Default | Meaning |
| --- | --- | --- |
| `version_file` | `.githooks/semver` in this repository | Relative path to a plain-text, JSON, or embedded version file. Choose your product file when copying hooks. |
| `version_field` | `semver_version='{version}'` in this repository | Empty for plain text; a unique field name for JSON; a literal full-line template with one `{version}` for embedded versions. |
| `tag_prefix` | `v` | Must match `TAG_PREFIX` in `release.conf`. |
| `commit_version` | `false` | Add `[<release tag>]` after the subject colon, or at the start for ordinary subjects. Uses `tag_prefix`. |
| `changelog_exact_commit_message` | `false` | Use full qualifying messages in changelogs and tag notes, keeping generated version labels. With `commit_version=true`, the latest entry gets its new tag. Bodies are indented below bullets; trailing blank lines are removed. |
| `changelog_file` | `CHANGELOG.md` | Relative changelog path. |
| `changelog_heading` | Template heading | Header above releases. Use literal `\n` for line breaks. |
| `changelog_remove_extra_headings` | `true` | When generating releases, replace existing `#` titles and introductions (up to the next `##`–`######` heading) with the configured header. Keep release/category headings and content. Set `false` to keep custom titles and introductions. Manually preserved changelogs are untouched. |
| `changelog_breaking_title` | Empty | Optional breaking-changes heading. |
| `changelog_features_title` | Empty | Optional features heading. |
| `changelog_fixes_title` | Empty | Optional bug-fixes heading. |
| `changelog_performance_title` | Empty | Optional performance heading. |
| `patch_types` | `fix perf` | Space-separated patch commit types. |
| `minor_types` | `feat` | Space-separated minor commit types. |
| `allowed_branches` | `main` | Space-separated exact branch names; empty allows all. |
| `auto_continue` | `true` | Resume when all conflicts are staged and no unstaged changes remain. Set `false` to require `--continue`. |
| `initial_version` | `0.0.0` | Baseline when no version exists. |

For example, `changelog_fixes_title='Bug fixes'` adds `### Bug fixes` above fix entries. Empty titles omit headings. A heading appears only when its category has entries.

This repository versions its hooks through `semver_version` in `.githooks/semver`, starting at `0.0.0` and advancing with qualifying commits after installation. `git semver --version` shows the hooks version separately from your product version.

### Product version files

When copying hooks, choose your product's version source:

- Plain text containing only `X.Y.Z`: `version_file=VERSION` and `version_field=`.
- JSON: `version_file=manifest.json` and `version_field=version`. The field must appear once, on its own line:

```json
{
  "version": "1.2.3",
  "name": "example"
}
```

Nested JSON fields use their unique name, not a dotted path. Other fields are kept.

For embedded versions, use a literal full-line template, such as `version_field="semver_version='{version}'"`. Exactly one line must match, for example `semver_version='1.2.3'`. Only `X.Y.Z` versions match. Indentation and quotes are literal; templates are not regular expressions and cannot span lines. Replacement keeps other lines and CRLF endings. Synchronization restores only the generated version, keeping other edits in that file.

Updates keep your `version_field`, including an explicitly empty value.

### Manual release edits

Manual version or changelog edits trigger a warning but stay in the commit and push. Versions must use `X.Y.Z` and determine the release tag. Changelogs stay as written. Overrides apply to later commits in the same draft; tag notes still collect qualifying messages.

After publication, automatic updates resume from the published version and changelog. Synchronization keeps manual edits, so conflicts involving them need resolution. Without release-triggering changes or an active draft, commits do not regenerate metadata.

### GitHub publishing

Edit `.github/workflows/release.conf`; updates preserve existing settings.

| Setting | Default | Meaning |
| --- | --- | --- |
| `RELEASE_BRANCHES` | `main` | Space-separated exact branch names; empty allows all. Tag pushes and manual runs bypass this filter. |
| `TAG_PREFIX` | `v` | Must match `tag_prefix` in `.githooks/semver.conf`. |
| `RELEASE_TITLE_PREFIX` | Empty | Text before the tag in release titles. |
| `UPDATE_LATEST` | `true` | Set `false` to leave GitHub's Latest selection unchanged. |

CI reads config from the checked-out commit, so commit and push changes to apply them. Older tags without the file use these defaults. Grouped notes come from annotated tags. Disable previous semantic-release jobs that bump versions or commit release files to the branch.

## Boundaries

- Release preparation needs a clean working tree, including no untracked files. Commit or stash unrelated work first. Pushing does not change working files.
- Use a tracking upstream matching the push destination. Without one, preparation uses `origin` and the current branch, then saves tracking settings for the first ordinary push.
- Use one matching fetch/push URL. Triangular workflows, custom push refspecs, mirror remotes, multiple push URLs, and unpublished merge commits need manual integration.
- IDEs must run normal Git hooks. If they bypass commit hooks, pre-push detects missing preparation; run `git semver --sync`.
- Supports stable versions and configurable Conventional Commit types. Prerelease channels, package publishing integrations, and semantic-release's full plugin API are unsupported.
- Finish recovery with the old hooks before upgrading. Older unpublished releases need reconciliation; unknown metadata is not silently removed.
