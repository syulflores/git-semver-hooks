# Changelog

All notable changes are documented here automatically by git-semver-hooks.

## 0.24.3

- fix: removed obsolete version file

## 0.24.2

- fix: updated readme to be easier to read

## 0.24.1

- fix: added abbreviations to the semver commands

## 0.24.0

- feat: updated install to create changelog and version files and update gitattributes and semver conf files

## 0.23.0

- feat: added semantic versioning with git-semver-hooks

## 0.22.0

- added functionality to have the version imbedded as a variable in a file

## 0.21.0

- added activate-semver.bat to easily find git repos using git-semver-hooks and run git semver --install

## 0.20.0

- make check for semver alias less strict

## 0.19.1

- updated comments to stay where they need to for config files

## 0.19.0

- update argument for conf files adds new options where they should be inline instead of appending them to the end

## 0.18.1

- updated behavior of changelog_remove_extra_headings

## 0.18.0

- change update to look for new config options and set them with their defaults

## 0.17.0

- added configure option to copy commit message exactly

## 0.16.0

- checks for duplicate changelog headings and removes them by default

## 0.15.2

- fixed global command in readme

## 0.15.1

- added a config file for release.yml so config changes can stay through an update

## 0.15.0

- added update option to find updates automatically

## 0.14.0

- added option for putting version number in commit message

## 0.13.0

- added an uninstall option to get rid of the git hooks

## 0.12.0

- added the option to add semver as a global git command so it can be available in multiple repos

## 0.11.3

- fully restructured the hooks and how they work to be a little bit faster

## 0.11.2

- tried to speed up commit time

## 0.11.1

- added changelog titles as blank by default but configurable

## 0.11.0

- updated behavior of the commit to update the changelog and version without needing to call git semver --sync

## 0.10.0

- restructure of the githooks and renamed command from semver-sync to semver

## 0.9.0

- updated behavior to let users manually edit version and changelog

## 0.8.2

- commit runs fetch and if there is a mismatch then it auto runs the full semver-sync command, otherwise it finsihes

## 0.8.1

- removed the need to do git semver-sync --continue

## 0.8.0

- added auto_sync where a commit fetches any remote changes and updates the versions based off of that

## 0.7.1

- updated installation commands within readme

## 0.7.0

- added syncing command when a version mismatch occurs to be able to fix the mismatch easily

## 0.6.0

- updated and restructured readme

## 0.5.0

- added configurable branches

## 0.4.0

- changed default starting version

## 0.3.2

- added more configurable variables

## 0.3.1

- added tag prefix variable

## 0.3.0

- added configurable variables at the top of the file

## 0.2.0

- added pending and retry messages as configurable variables at the top of the file

## 0.1.1

- added support for multiple line changelog heading

## 0.1.0

- added changelog heading as a variable for the user to configure

## 0.0.0

- initial commit
