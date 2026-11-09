#!/usr/bin/env bash
# Bash 3.2+ (including the Bash shipped with macOS).
shopt -s nullglob dotglob

usage() { printf 'Usage: semver-scripts.sh [parent-folder] [--no-prompt]\n'; }
parent_folder=
no_prompt=false
case $# in
    0) ;;
    1) if [[ $1 == --no-prompt ]]; then no_prompt=true; else parent_folder=$1; fi ;;
    2) parent_folder=$1; [[ $2 == --no-prompt && $1 != --no-prompt ]] || { usage; exit 1; }; no_prompt=true ;;
    *) usage; exit 1 ;;
esac
command -v git >/dev/null 2>&1 || { printf 'SemVer: Git is required on PATH.\n'; exit 1; }

test_semver_alias() {
    local normalized
    normalized=$(printf '%s' "$1" | tr -d '[:space:]"\047\\')
    while [[ $normalized == *';' ]]; do normalized=${normalized%;}; done
    case $normalized in
        '!sh.githooks/semver'|'!sh.githooks/semver$@'|\
        '!f(){iftest-f.githooks/semver;thensh.githooks/semver;fi;};f'|\
        '!f(){iftest-f.githooks/semver;thensh.githooks/semver$@;fi;};f'|*semver-release/engine*) return 0 ;;
        *) return 1 ;;
    esac
}

configure_alias() {
    local existing
    if existing=$(git config --global --get alias.semver) && test_semver_alias "$existing"; then
        printf 'SemVer: Global alias already configured.\n'
    else
        git config --global --replace-all alias.semver \
            '!f() { if test -f .githooks/semver; then sh .githooks/semver "$@"; fi; }; f' || return 1
        printf 'SemVer: Global alias configured.\n'
    fi
}

get_semver_status() {
    local folder=$1 hooks_path enabled code selected=false present=0 executable=true file
    hooks_path=$(git -C "$folder" config --path --get core.hooksPath); code=$?
    [[ $code == 0 || $code == 1 ]] || { printf 'SemVer: Cannot read core.hooksPath.\n'; return 1; }
    enabled=$(git -C "$folder" config --get semver.enabled); code=$?
    [[ $code == 0 || $code == 1 ]] || { printf 'SemVer: Cannot read semver.enabled.\n'; return 1; }
    if [[ -n $hooks_path ]]; then
        [[ $hooks_path == /* ]] || hooks_path=$folder/$hooks_path
        hooks_path=$(cd -- "$hooks_path" 2>/dev/null && pwd -P)
        [[ -n $hooks_path && $hooks_path == "$(cd -- "$folder/.githooks" 2>/dev/null && pwd -P)" ]] && selected=true
    fi
    for file in semver post-commit pre-push post-index-change; do
        [[ -f $folder/.githooks/$file ]] && present=$((present + 1))
        if [[ $file != semver && ! -x $folder/.githooks/$file ]]; then executable=false; fi
    done
    if [[ $present == 0 && $selected == false && $enabled != true ]]; then status='Not installed'
    elif [[ $present != 4 || $executable == false ]]; then status=Incomplete
    elif [[ $selected == true && $enabled == true ]]; then status=Activated
    else status='Not activated'
    fi
}

process_repository() {
    local folder=$1 top version= existing command verb
    top=$(git -C "$folder" rev-parse --show-toplevel) || { failed+=("$folder"); return; }
    top=$(cd -- "$top" 2>/dev/null && pwd -P)
    if [[ $top != "$folder" ]]; then
        printf 'SemVer: Git could not verify this repository root: %s\n' "$folder"
        failed+=("$folder"); return
    fi
    if [[ $action == List ]]; then
        get_semver_status "$folder" || { failed+=("$folder"); return; }
        if [[ $status == Activated ]]; then
            if version=$(git -C "$folder" semver --version) && [[ -n $version ]]; then
                version=${version//$'\n'/ }
            else
                version='Version unavailable'
                printf 'SemVer: Cannot read version in %s\n' "$folder"
                failed+=("$folder")
            fi
        fi
        paths+=("$folder"); statuses+=("$status"); versions+=("$version")
    elif [[ ! -f $folder/.githooks/semver ]]; then
        skipped+=("$folder")
    else
        if [[ $action == Activate ]]; then verb=Installing; command=--install
        else verb=Updating; command=--update; fi
        printf '%s: %s\n' "$verb" "$folder"
        if ! existing=$(git -C "$folder" config --get alias.semver); then
            printf 'SemVer: Cannot read the SemVer alias.\n'
            failed+=("$folder"); return
        fi
        if ! test_semver_alias "$existing"; then
            printf 'SemVer: An unrelated local semver alias exists; integrate it manually.\n'
            failed+=("$folder"); return
        fi
        if git -C "$folder" semver "$command"; then completed+=("$folder")
        else failed+=("$folder"); fi
    fi
}

search_repositories() {
    local root=$1 folder child seen path index
    local pending=()
    if ! root=$(cd -- "$root" 2>/dev/null && pwd -P); then
        printf 'Cannot search: %s (Enter an accessible filesystem folder path.)\n' "$1"
        scan_errors+=("$1"); return
    fi
    printf '\nSearching: %s\n' "$root"
    pending+=("$root")
    while [[ ${#pending[@]} -gt 0 ]]; do
        index=$((${#pending[@]} - 1)); folder=${pending[index]}; unset 'pending[index]'
        seen=false
        for path in "${visited[@]}"; do [[ $path == "$folder" ]] && { seen=true; break; }; done
        [[ $seen == true ]] && continue
        visited+=("$folder")
        [[ -e $folder/.git ]] && process_repository "$folder"
        if [[ ! -r $folder || ! -x $folder ]]; then scan_errors+=("$folder"); continue; fi
        for child in "$folder"/*; do
            [[ -d $child && ! -L $child ]] || continue
            case ${child##*/} in .git|node_modules) continue ;; esac
            pending+=("$child")
        done
    done
}

show_paths() {
    local path
    if [[ $# == 0 ]]; then printf '  None.\n'; return; fi
    for path in "$@"; do printf '  %s\n' "$path"; done
}

show_results() {
    local group count index label
    if [[ $action == List ]]; then
        printf '\nGit repositories found (%s):\n' "${#paths[@]}"
        for group in Activated 'Not activated' Incomplete 'Not installed'; do
            count=0
            for status in "${statuses[@]}"; do [[ $status == "$group" ]] && count=$((count + 1)); done
            printf '%s (%s):\n' "$group" "$count"
            for ((index=0; index<${#paths[@]}; index++)); do
                [[ ${statuses[index]} == "$group" ]] || continue
                printf '  [%s] %s' "$group" "${paths[index]}"
                [[ -n ${versions[index]} ]] && printf ' - %s' "${versions[index]}"
                printf '\n'
            done
            [[ $count == 0 ]] && printf '  None.\n'
        done
    else
        if [[ $action == Activate ]]; then label='Hooks installed successfully'; else label='Hooks updated successfully'; fi
        printf '\n%s (%s):\n' "$label" "${#completed[@]}"
        show_paths "${completed[@]}"
        if [[ ${#skipped[@]} -gt 0 ]]; then
            printf 'Repositories without git-semver-hooks (%s); skipped:\n' "${#skipped[@]}"
            show_paths "${skipped[@]}"
        fi
    fi
    if [[ ${#failed[@]} -gt 0 ]]; then
        printf 'Repositories with errors (%s); see messages above:\n' "${#failed[@]}"
        show_paths "${failed[@]}"
    fi
    if [[ ${#scan_errors[@]} -gt 0 ]]; then
        printf 'Folders that could not be searched:\n'
        show_paths "${scan_errors[@]}"
    fi
}

invoke_action() {
    local visited=() paths=() statuses=() versions=() completed=() skipped=() failed=() scan_errors=()
    local roots=() root name extra status
    if [[ $action != List ]]; then configure_alias || return 1; fi
    if [[ -n $parent_folder ]]; then search_repositories "$parent_folder"
    else
        roots+=("$HOME/Documents" "$HOME/Downloads" "$HOME/Desktop" "$HOME/OneDrive")
        # Linux desktop redirects; macOS OneDrive folders live in CloudStorage.
        if command -v xdg-user-dir >/dev/null 2>&1; then
            for name in DOCUMENTS DOWNLOAD DESKTOP; do
                root=$(xdg-user-dir "$name") && [[ -n $root ]] && roots+=("$root")
            done
        fi
        roots+=("$HOME"/Library/CloudStorage/OneDrive*)
        for name in OneDrive OneDriveConsumer OneDriveCommercial; do
            root=${!name}; [[ -n $root ]] && roots+=("$root")
        done
        for root in "${roots[@]}"; do [[ -d $root ]] && search_repositories "$root"; done
    fi
    show_results
    if [[ $no_prompt == false ]]; then
        while true; do
            printf '\nEnter another parent folder to search, or press Enter to return to the menu: '
            IFS= read -r extra || break
            extra=${extra#"${extra%%[![:space:]]*}"}; extra=${extra%"${extra##*[![:space:]]}"}
            [[ -n $extra ]] || break
            extra=${extra#\"}; extra=${extra%\"}
            search_repositories "$extra"
            show_results
        done
    fi
    [[ ${#failed[@]} == 0 && ${#scan_errors[@]} == 0 ]]
}

exit_code=0
while true; do
    printf '\nGit SemVer Hooks\n'
    printf '%s\n' '1. List repositories (status and version)' '2. Activate SemVer hooks' '3. Update SemVer hooks' '0. Exit'
    printf 'Select an option: '
    IFS= read -r choice || break
    choice=${choice#"${choice%%[![:space:]]*}"}; choice=${choice%"${choice##*[![:space:]]}"}
    case $choice in
        1) action=List ;; 2) action=Activate ;; 3) action=Update ;;
        0) break ;;
        *) printf 'Please select 1, 2, 3, or 0.\n'; continue ;;
    esac
    invoke_action || exit_code=1
    [[ $no_prompt == true ]] && break
done
exit "$exit_code"
