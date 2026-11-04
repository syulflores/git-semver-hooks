#!/bin/sh
# Local-only updater integration tests; no network or installed hooks required.
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' 0
source_repo=$tmp/source
target=$tmp/target
mkdir -p "$source_repo/.githooks" "$source_repo/.github/workflows" "$target"
cp "$root"/.githooks/* "$source_repo/.githooks/"
cp "$root"/.github/workflows/release.* "$source_repo/.github/workflows/"
sed "s|^update_source=.*|update_source='$source_repo'|" "$root/.githooks/semver" > "$source_repo/.githooks/semver"
git init --quiet "$source_repo"
git -C "$source_repo" config core.autocrlf false
git -C "$source_repo" add .
git -C "$source_repo" -c user.name=Test -c user.email=test@example.invalid -c core.hooksPath=/dev/null commit --quiet -m fixture
git init --quiet "$target"
cp -R "$source_repo/.githooks" "$source_repo/.github" "$target/"
cd "$target"

# Preserve customized values, empty/exported assignments, comments, CRLF, and
# an unterminated last line. A commented-out assignment is still missing.
awk '!/^auto_continue=/ && !/^changelog_fixes_title=/' .githooks/semver.conf > "$tmp/config"
cat "$tmp/config" > .githooks/semver.conf
printf '# auto_continue=false\nexport changelog_fixes_title=\n# custom tail' >> .githooks/semver.conf
printf '# project settings\r\nRELEASE_BRANCHES="stable"\r\nTAG_PREFIX=""\r\n# UPDATE_LATEST=false' > .github/workflows/release.conf
cp .githooks/semver.conf "$tmp/semver-before"
cp .github/workflows/release.conf "$tmp/release-before"
sh .githooks/semver --update
for pair in 'semver-before .githooks/semver.conf' 'release-before .github/workflows/release.conf'; do
    set -- $pair
    head -c "$(wc -c < "$tmp/$1")" "$2" > "$tmp/prefix"
    cmp "$tmp/$1" "$tmp/prefix"
done
grep -Fx 'auto_continue=true # Resume synchronization automatically once all conflicts are staged.' .githooks/semver.conf
test "$(grep -c '^export changelog_fixes_title=$' .githooks/semver.conf)" = 1
test "$(grep -c '^changelog_fixes_title=' .githooks/semver.conf || :)" = 0
cp "$tmp/release-before" "$tmp/release-expected"
printf '\r\n' >> "$tmp/release-expected"
awk '/^(RELEASE_TITLE_PREFIX|UPDATE_LATEST)=/ { sub(/\r$/, ""); printf "%s\r\n", $0 }' \
    "$source_repo/.github/workflows/release.conf" >> "$tmp/release-expected"
cmp "$tmp/release-expected" .github/workflows/release.conf
backup=$(find .git -maxdepth 1 -type d -name 'semver-update-backup.*')
cmp "$tmp/semver-before" "$backup/.githooks/semver.conf"
cmp "$tmp/release-before" "$backup/.github/workflows/release.conf"
cp .githooks/semver.conf "$tmp/semver-after"
cp .github/workflows/release.conf "$tmp/release-after"
sh .githooks/semver --update
cmp "$tmp/semver-after" .githooks/semver.conf
cmp "$tmp/release-after" .github/workflows/release.conf

# Missing release config retains the existing legacy migration behavior.
rm .github/workflows/release.conf
printf 'env:\n  RELEASE_BRANCHES: "stable"\n  TAG_PREFIX: "release-"\n' > .github/workflows/release.yml
sh .githooks/semver --update
grep -Fx "RELEASE_BRANCHES='stable'" .github/workflows/release.conf
grep -Fx "TAG_PREFIX='release-'" .github/workflows/release.conf
echo 'Updater integration tests passed.'
