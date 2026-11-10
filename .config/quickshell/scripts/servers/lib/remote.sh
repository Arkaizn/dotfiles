#!/bin/bash
# Remote helper for manage-svs.sh. It is never installed on the servers: every call
# pipes this file over SSH (ssh host "bash -s -- <command> <args>"), so the servers
# always run the current version.
#
# Lines of the form TAG|... are machine-readable results parsed by manage-svs.sh;
# any other output is plain log output.
#
# Everything runs from main() on the last line: bash reads this script from stdin,
# so nothing may run (or read stdin) before the whole file has been read.

export LC_ALL=C DEBIAN_FRONTEND=noninteractive

SUDO=""
[ "$(id -u)" -ne 0 ] && SUDO="sudo -n"

# Fields printed per container, '|' separated (the leading '/' of .Name is stripped)
CT_FORMAT='{{.Name}}|{{.State.Status}}|{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}|{{.Image}}|{{.Config.Image}}|{{index .Config.Labels "com.docker.compose.project"}}|{{index .Config.Labels "com.docker.compose.service"}}|{{index .Config.Labels "com.docker.compose.project.working_dir"}}|{{index .Config.Labels "com.docker.compose.project.config_files"}}'

pkg_manager() {
  if command -v pacman &>/dev/null; then echo pacman
  elif command -v apt-get &>/dev/null; then echo apt
  else echo none
  fi
}

has_docker() { command -v docker &>/dev/null && $SUDO docker info &>/dev/null; }

# Proxmox VE / Backup Server machines are only ever rebooted by hand
is_proxmox() { command -v pveversion &>/dev/null || command -v proxmox-backup-manager &>/dev/null; }

# compose <workdir> <project> <config_files (comma separated)> <compose args...>
compose() {
  local workdir="$1" project="$2" files="$3" f
  shift 3
  local args=(-p "$project")
  IFS=',' read -ra f <<< "$files"
  for x in "${f[@]}"; do args+=(-f "$x"); done
  (cd "$workdir" && $SUDO docker compose "${args[@]}" "$@")
}

ct_inspect_all() {
  local ids
  ids=$($SUDO docker ps -aq)
  [ -n "$ids" ] || return 0
  # shellcheck disable=SC2086
  $SUDO docker inspect -f "$CT_FORMAT" $ids | sed -e 's#^/##' -e 's#<no value>##g'
}

img_version() {
  $SUDO docker image inspect -f '{{index .Config.Labels "org.opencontainers.image.version"}}' "$1" 2>/dev/null \
    | sed 's#<no value>##' | tr -d '|,'
}

# Prints PKG|<name> <old> -> <new> for every pending package update
os_pending() {
  case "$(pkg_manager)" in
    pacman)
      # Sync into a throwaway db (same trick as checkupdates) so the real sync db is
      # untouched: a bare `pacman -Sy` would leave the system in a partial-upgrade state.
      # The db dir must be traversable: pacman downloads as the unprivileged alpm user.
      local db
      db=$(mktemp -d)
      chmod 755 "$db"
      ln -s /var/lib/pacman/local "$db/local"
      if $SUDO pacman -Sy --dbpath "$db" --logfile /dev/null &>/dev/null; then
        $SUDO pacman -Qu --dbpath "$db" 2>/dev/null | grep -v '\[ignored\]' | sed 's/^/PKG|/'
        # security: packages with a known vulnerability that a newer version fixes
        command -v arch-audit &>/dev/null && arch-audit --upgradable --quiet 2>/dev/null | sed 's/^/SEC|/'
      else
        echo "WARN|pacman database sync failed"
      fi
      $SUDO rm -rf "$db"
      ;;
    apt)
      $SUDO apt-get update -qq &>/dev/null || echo "WARN|apt-get update failed"
      apt-get -s -o Debug::NoLocking=1 dist-upgrade 2>/dev/null | awk '/^Inst /{
        if ($3 ~ /^\[/) { o = $3; n = $4 } else { o = "(new)"; n = $3 }
        gsub(/[\[\]\(\)]/, "", o); gsub(/[\(\)]/, "", n)
        print "PKG|" $2 " " o " -> " n
        # security: the new version comes from a *-security archive (Debian-Security:12/…, jammy-security)
        if ($0 ~ /[Ss]ecurity/) print "SEC|" $2 }'
      ;;
    *) echo "WARN|unknown package manager" ;;
  esac
}

reboot_needed() {
  [ -e /var/run/reboot-required ] && return 0
  systemd-detect-virt -cq 2>/dev/null && return 1   # containers (LXC) share the host kernel
  local running newest
  running=$(uname -r)
  # Arch removes the running kernel's modules when the kernel package is upgraded
  [ -d "/usr/lib/modules/$running" ] || return 0
  if [ "$(pkg_manager)" = apt ]; then
    newest=$(ls /usr/lib/modules | sort -V | tail -n1)
    [ "$newest" != "$running" ] && return 0
  fi
  return 1
}

# remote_digest <image ref> — the digest the registry has for this tag right now, without
# pulling (a HEAD request: no layers, and it doesn't count against Docker Hub's pull limit).
# Prints "absent" when the registry says there is no such image (one built on the
# server), and nothing when it can't tell (registry down, no curl).
remote_digest() {
  local ref="$1" reg repo tag hdr realm service scope token auth=() accept
  command -v curl &>/dev/null || return 1
  [[ "$ref" == *@sha256:* ]] && { echo "${ref##*@}"; return 0; }
  tag=latest
  if [[ "${ref##*/}" == *:* ]]; then tag=${ref##*:}; ref=${ref%:*}; fi
  if [[ "$ref" == */* ]] && [[ "${ref%%/*}" == *.* || "${ref%%/*}" == *:* || "${ref%%/*}" == localhost ]]; then
    reg=${ref%%/*}; repo=${ref#*/}
  else
    reg=registry-1.docker.io; repo=$ref
    [[ "$repo" == */* ]] || repo=library/$repo
  fi
  # lscr.io only redirects to ghcr.io (and turns away bursts of requests): ask ghcr directly
  [ "$reg" = lscr.io ] && reg=ghcr.io
  # Docker Hub: its API lives on another host, and official images are under library/
  if [ "$reg" = docker.io ] || [ "$reg" = index.docker.io ] || [ "$reg" = registry-1.docker.io ]; then
    reg=registry-1.docker.io
    [[ "$repo" == */* ]] || repo=library/$repo
  fi
  accept='Accept: application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json, application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.v2+json'
  hdr=$(curl -sIL -m 15 -H "$accept" "https://$reg/v2/$repo/manifests/$tag" 2>/dev/null | tr -d '\r')
  if grep -qi '^www-authenticate: *bearer' <<< "$hdr" && ! grep -qi '^docker-content-digest:' <<< "$hdr"; then
    realm=$(grep -i '^www-authenticate:' <<< "$hdr" | tail -n1 | sed -n 's/.*realm="\([^"]*\)".*/\1/p')
    service=$(grep -i '^www-authenticate:' <<< "$hdr" | tail -n1 | sed -n 's/.*service="\([^"]*\)".*/\1/p')
    [ -n "$realm" ] || return 1
    # (a registry that knows no such image still hands out a token; the answer comes below)
    token=$(curl -s -m 15 -G --data-urlencode "service=$service" --data-urlencode "scope=repository:$repo:pull" "$realm" 2>/dev/null \
              | sed -n 's/.*"\(token\|access_token\)" *: *"\([^"]*\)".*/\2/p' | head -n1)
    [ -n "$token" ] || return 1
    hdr=$(curl -sIL -m 15 -H "$accept" -H "Authorization: Bearer $token" "https://$reg/v2/$repo/manifests/$tag" 2>/dev/null | tr -d '\r')
  fi
  if grep -i '^docker-content-digest:' <<< "$hdr" | tail -n1 | awk '{print $2}' | grep '^sha256:[0-9a-f]\{64\}$'; then return 0; fi
  case "$(awk '/^HTTP\//{ c = $2 } END { print c }' <<< "$hdr")" in
    401|403|404) echo absent ;;
  esac
}

# scan [pull] — what's pending on this server. Containers:
#   CTUPD|name|project|service|ref|old_id|new_id|old_version|new_version|workdir|config_files|state
#     state "pulled": the new image is already here, the container still runs the old one
#     state "remote": the registry has a newer image (new_id / new_version aren't known yet)
#   CTSKIP|name|kind|reason     kind: plain (started with docker run) | aio (Nextcloud AIO
#                               looks after its own containers) | missing (compose dir gone)
# By default nothing is downloaded: every image's tag is compared with the registry's
# digest. "pull" is the old way (docker compose pull for every project), also used for an
# image the registry check can't answer for.
cmd_scan() {
  local how="${1:-check}"
  echo "PM|$(pkg_manager)"
  # what it is, for the Servers app's logos: OS|<id>|<pretty name>, DOCKER|1
  ( . /etc/os-release 2>/dev/null && echo "OS|${ID:-}|${PRETTY_NAME:-}" )
  has_docker && echo "DOCKER|1"
  is_proxmox && echo "PROXMOX|1"
  os_pending
  if reboot_needed; then echo "REBOOT|1"; else echo "REBOOT|0"; fi
  has_docker || return 0

  local rows name status health imgid ref project service workdir files tagid key dig loc dir n=0
  declare -A pulled warned
  rows=$(ct_inspect_all)
  dir=$(mktemp -d)
  if [ "$how" != pull ]; then
    # every image once, a few registries at a time
    while IFS='|' read -r name status health imgid ref _; do
      [ "$status" = running ] && [ -n "$ref" ] || continue
      key=$(printf '%s' "$ref" | md5sum | cut -c1-16)
      [ -e "$dir/$key.ref" ] && continue
      printf '%s' "$ref" > "$dir/$key.ref"
      ( remote_digest "$ref" > "$dir/$key.dig" 2>/dev/null ) &
      n=$((n + 1))
      [ $((n % 6)) -eq 0 ] && wait
    done <<< "$rows"
    wait
    # some registries (lscr.io) turn away several requests at once: ask again, one by one
    for key in "$dir"/*.ref; do
      [ -e "$key" ] || continue
      [ -s "${key%.ref}.dig" ] || remote_digest "$(cat "$key")" > "${key%.ref}.dig" 2>/dev/null
    done
  fi
  while IFS='|' read -r name status health imgid ref project service workdir files; do
    [ "$status" = running ] || continue
    if [ -z "$project" ] || [ -z "$workdir" ] || [ -z "$files" ]; then
      if [[ "$name" == nextcloud-aio-* ]]; then echo "CTSKIP|$name|aio|managed by Nextcloud AIO (it updates its own containers)"
      else
        echo "CTSKIP|$name|plain|started with docker run, not from a compose file"
        # is there a newer image for it? (updated through Watchtower when the server allows it)
        if [ "$how" != pull ] && [ -n "$ref" ]; then
          loc=$($SUDO docker image inspect -f '{{join .RepoDigests " "}}' "$ref" 2>/dev/null)
          dig=$(cat "$dir/$(printf '%s' "$ref" | md5sum | cut -c1-16).dig" 2>/dev/null)
          if [ -n "$loc" ] && [ -n "$dig" ] && [ "$dig" != absent ] && [[ " $loc " != *"@$dig "* ]]; then
            echo "PLAINUPD|$name|$ref|$imgid|$(img_version "$imgid")"
          fi
        fi
      fi
      continue
    fi
    if [ ! -d "$workdir" ]; then
      echo "CTSKIP|$name|missing|compose dir $workdir missing"
      continue
    fi
    if [ "$how" = pull ] && [ -z "${pulled[$project]}" ]; then
      pulled[$project]=1
      compose "$workdir" "$project" "$files" pull --quiet --ignore-buildable --ignore-pull-failures &>/dev/null \
        || echo "WARN|image pull failed for compose project $project"
    fi
    tagid=$($SUDO docker image inspect -f '{{.Id}}' "$ref" 2>/dev/null) || continue
    if [ "$tagid" != "$imgid" ]; then
      echo "CTUPD|$name|$project|$service|$ref|$imgid|$tagid|$(img_version "$imgid")|$(img_version "$tagid")|$workdir|$files|pulled"
      continue
    fi
    [ "$how" = pull ] && continue
    loc=$($SUDO docker image inspect -f '{{join .RepoDigests " "}}' "$ref" 2>/dev/null)
    [ -n "$loc" ] || continue                      # built on this server: nothing to compare with
    key=$(printf '%s' "$ref" | md5sum | cut -c1-16)
    dig=$(cat "$dir/$key.dig" 2>/dev/null)
    if [ "$dig" = absent ]; then
      continue                                     # not in a registry: built on this server
    elif [ -z "$dig" ]; then
      [ -n "${warned[$ref]}" ] || echo "WARN|couldn't ask the registry about $ref (not reachable right now)"
      warned[$ref]=1
    elif [[ " $loc " != *"@$dig "* ]]; then
      echo "CTUPD|$name|$project|$service|$ref|$imgid||$(img_version "$imgid")||$workdir|$files|remote"
    fi
  done <<< "$rows"
  rm -rf "$dir"
}

# projects_of <payload>... — fills svcs / wd / fl (per compose project) from CTUPD payloads
projects_of() {
  local p name project service ref oldid newid oldver newver workdir files state
  for p in "$@"; do
    IFS='|' read -r name project service ref oldid newid oldver newver workdir files state <<< "$p"
    [[ " ${svcs[$project]} " == *" $service "* ]] || svcs[$project]+=" $service"
    wd[$project]=$workdir
    fl[$project]=$files
  done
}

# ct-pull <payload>... — download the new images of these containers (nothing restarts).
# NEW|name|new_id|new_version for each one, PULLFAIL|project when a pull failed.
cmd_ct_pull() {
  local p name project service ref oldid newid oldver newver workdir files state id
  declare -A svcs wd fl
  projects_of "$@"
  for project in "${!svcs[@]}"; do
    echo ">> $project: pulling${svcs[$project]}"
    # shellcheck disable=SC2086
    compose "${wd[$project]}" "$project" "${fl[$project]}" pull --quiet --ignore-buildable ${svcs[$project]} \
      || echo "PULLFAIL|$project"
  done
  for p in "$@"; do
    IFS='|' read -r name project service ref oldid newid oldver newver workdir files state <<< "$p"
    id=$($SUDO docker image inspect -f '{{.Id}}' "$ref" 2>/dev/null) || continue
    echo "NEW|$name|$id|$(img_version "$id")"
  done
}

# plain-update <tag> <watchtower image> <container>... — update containers that were
# started with `docker run`. Recreating one by hand means rebuilding every option it was
# started with; Watchtower does exactly that, so it is run once, for these containers
# only, and is gone again (--rm). The old image is kept as svs-rollback/<name>:<tag>.
# PLAINOK|name|new_id|new_version · PLAINSAME|name (nothing newer) · PLAINFAIL|name
cmd_plain_update() {
  local tag="$1" wt="$2" name before after
  shift 2
  for name in "$@"; do
    before=$($SUDO docker inspect -f '{{.Image}}' "$name" 2>/dev/null) || { echo "PLAINFAIL|$name"; continue; }
    $SUDO docker tag "$before" "svs-rollback/${name,,}:$tag"
    echo ">> $name: updating through Watchtower (run once)"
    if ! $SUDO docker run --rm -v /var/run/docker.sock:/var/run/docker.sock "$wt" --run-once --no-startup-message "$name"; then
      echo "PLAINFAIL|$name"
      continue
    fi
    after=$($SUDO docker inspect -f '{{.Image}}' "$name" 2>/dev/null) || { echo "PLAINFAIL|$name"; continue; }
    if [ "$after" = "$before" ]; then echo "PLAINSAME|$name"; else echo "PLAINOK|$name|$after|$(img_version "$after")"; fi
  done
}

# ct-down <tag> <payload>... — take these containers away right before a reboot, so they
# go down once and come up on the new image after it (ct-update). The old image is kept
# as svs-rollback/<name>:<tag> first: a removed container doesn't hold it any more.
cmd_ct_down() {
  local tag="$1" p name project service ref oldid newid oldver newver workdir files state
  shift
  declare -A svcs wd fl
  for p in "$@"; do
    IFS='|' read -r name project service ref oldid newid oldver newver workdir files state <<< "$p"
    $SUDO docker tag "$oldid" "svs-rollback/${name,,}:$tag"
  done
  projects_of "$@"
  for project in "${!svcs[@]}"; do
    echo ">> $project: stopping${svcs[$project]} for the reboot"
    # shellcheck disable=SC2086
    compose "${wd[$project]}" "$project" "${fl[$project]}" rm -sf ${svcs[$project]} || echo "DOWNFAIL|$project"
  done
}

# ct-update <tag> <CTUPD payload>... — recreate the given containers on their new image.
# The old image is kept as svs-rollback/<name>:<tag> so it survives pruning.
cmd_ct_update() {
  local tag="$1" p name project service ref oldid newid oldver newver workdir files state
  shift
  declare -A svcs wd fl
  for p in "$@"; do
    IFS='|' read -r name project service ref oldid newid oldver newver workdir files state <<< "$p"
    $SUDO docker tag "$oldid" "svs-rollback/${name,,}:$tag"
    [[ " ${svcs[$project]} " == *" $service "* ]] || svcs[$project]+=" $service"
    wd[$project]=$workdir
    fl[$project]=$files
  done
  for project in "${!svcs[@]}"; do
    echo ">> $project: recreating${svcs[$project]}"
    # shellcheck disable=SC2086
    if compose "${wd[$project]}" "$project" "${fl[$project]}" up -d --no-deps --pull never ${svcs[$project]}; then
      echo "UPDATED|$project"
    else
      echo "UPDFAIL|$project"
    fi
  done
}

# ct-rollback <CTUPD payload>... — point each image tag back at the old image and recreate
cmd_ct_rollback() {
  local p name project service ref oldid newid oldver newver workdir files state
  declare -A svcs wd fl
  for p in "$@"; do
    IFS='|' read -r name project service ref oldid newid oldver newver workdir files state <<< "$p"
    $SUDO docker tag "$oldid" "$ref"
    [[ " ${svcs[$project]} " == *" $service "* ]] || svcs[$project]+=" $service"
    wd[$project]=$workdir
    fl[$project]=$files
  done
  for project in "${!svcs[@]}"; do
    echo ">> $project: rolling back${svcs[$project]}"
    # shellcheck disable=SC2086
    if compose "${wd[$project]}" "$project" "${fl[$project]}" up -d --no-deps --pull never ${svcs[$project]}; then
      echo "ROLLED|$project"
    else
      echo "ROLLFAIL|$project"
    fi
  done
}

# os-update-only <package>… — upgrade just these packages (apt). Arch has no safe
# partial upgrade, so there it's the full system upgrade.
cmd_os_update_only() {
  case "$(pkg_manager)" in
    pacman) cmd_os_update ;;
    apt)
      $SUDO apt-get update &&
        $SUDO apt-get -y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold \
          install --only-upgrade -- "$@"
      ;;
    *) echo "Unknown package manager, skipping system update." ;;
  esac
}

cmd_os_update() {
  case "$(pkg_manager)" in
    pacman)
      # Keyring first, so new packages signed by new keys don't fail the upgrade
      $SUDO pacman -Sy --needed --noconfirm archlinux-keyring && $SUDO pacman -Su --noconfirm
      ;;
    apt)
      # dist-upgrade is required on Proxmox VE/PBS; plain `upgrade` holds back kernel/pve packages
      $SUDO apt-get update &&
        $SUDO apt-get -y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold dist-upgrade
      ;;
    *) echo "Unknown package manager, skipping system update." ;;
  esac
}

# health_probe <container> — run the container's own health check now. Docker only
# repeats it at the image's interval (flaresolverr: every 15 minutes) and says
# "starting" until one passes, however long the service has been up.
health_probe() {
  local kind test args
  kind=$($SUDO docker inspect -f '{{index .Config.Healthcheck.Test 0}}' "$1" 2>/dev/null) || return 1
  case "$kind" in
    CMD-SHELL)
      test=$($SUDO docker inspect -f '{{index .Config.Healthcheck.Test 1}}' "$1" 2>/dev/null) || return 1
      $SUDO timeout 20 docker exec "$1" sh -c "$test" &>/dev/null
      ;;
    CMD)
      mapfile -t args < <($SUDO docker inspect -f '{{range $i, $a := .Config.Healthcheck.Test}}{{if $i}}{{println $a}}{{end}}{{end}}' "$1" 2>/dev/null)
      [ ${#args[@]} -gt 0 ] && [ -z "${args[-1]}" ] && unset 'args[-1]'
      [ ${#args[@]} -gt 0 ] || return 1
      $SUDO timeout 20 docker exec "$1" "${args[@]}" &>/dev/null
      ;;
    *) return 1 ;;
  esac
}

# STATE|<container>|<status>|<health> for every container; a "starting" one whose
# health check passes right now counts as healthy
cmd_state() {
  has_docker || return 0
  local name status health rest
  while IFS='|' read -r name status health rest; do
    [ -n "$name" ] || continue
    if [ "$status" = running ] && [ "$health" = starting ] && health_probe "$name"; then health=healthy; fi
    echo "STATE|$name|$status|$health"
  done <<< "$(ct_inspect_all)"
}

# cleanup <keep_days> — drop rollback images older than keep_days, then dangling images
cmd_cleanup() {
  has_docker || return 0
  local cutoff img d
  cutoff=$(date -d "-$1 days" +%Y%m%d)
  while read -r img; do
    [ -n "$img" ] || continue
    d=${img##*:}
    d=${d%%-*}
    if [[ "$d" =~ ^[0-9]{8}$ ]] && [ "$d" -lt "$cutoff" ]; then
      $SUDO docker rmi "$img" >/dev/null && echo "removed old rollback image $img"
    fi
  done <<< "$($SUDO docker images --filter 'reference=svs-rollback/*' --format '{{.Repository}}:{{.Tag}}')"
  $SUDO docker image prune -f >/dev/null
}

# On a Proxmox node: SNAP|<qm|pct>|<vmid>|<guest name>|<snapshot> for every snapshot
# this script created (svsupd_*). Manual snapshots are never listed.
cmd_snapshots() {
  local id name snap
  while read -r id name; do
    [ -n "$id" ] || continue
    for snap in $(qm listsnapshot "$id" | grep -o 'svsupd_[0-9]\{8\}_[0-9]\{4\}' | sort -u); do
      echo "SNAP|qm|$id|$name|$snap"
    done
  done <<< "$(qm list | awk 'NR > 1 {print $1, $2}')"
  while read -r id name; do
    [ -n "$id" ] || continue
    for snap in $(pct listsnapshot "$id" | grep -o 'svsupd_[0-9]\{8\}_[0-9]\{4\}' | sort -u); do
      echo "SNAP|pct|$id|$name|$snap"
    done
  done <<< "$(pct list | awk 'NR > 1 {print $1, $NF}')"
}

main() {
  exec </dev/null
  local cmd="$1"
  shift
  case "$cmd" in
    scan)          cmd_scan "$@" ;;
    state)         cmd_state ;;
    os-update)     cmd_os_update ;;
    os-update-only) cmd_os_update_only "$@" ;;
    ct-update)     cmd_ct_update "$@" ;;
    ct-pull)       cmd_ct_pull "$@" ;;
    ct-down)       cmd_ct_down "$@" ;;
    plain-update)  cmd_plain_update "$@" ;;
    ct-rollback)   cmd_ct_rollback "$@" ;;
    reboot-needed) if reboot_needed; then echo "REBOOT|1"; else echo "REBOOT|0"; fi ;;
    reboot)
      # Hard stop, whatever the caller asks for: Proxmox machines are rebooted manually
      if is_proxmox; then
        echo "refusing to reboot a Proxmox machine — reboot it manually" >&2
        exit 3
      fi
      nohup sh -c "sleep 2; $SUDO systemctl reboot" >/dev/null 2>&1 &
      ;;
    cleanup)       cmd_cleanup "$@" ;;
    is-proxmox)    is_proxmox ;;
    snapshots)     cmd_snapshots ;;
    pool-usage)    lvs --noheadings --separator '|' -o vg_name,lv_name,data_percent,lv_size -S 'lv_attr=~^t' 2>/dev/null | tr -d ' ' ;;
    service)       systemctl is-active --quiet "$1" ;;
    cmd)           bash -c "$1" ;;
    *)             echo "unknown remote command: $cmd" >&2; exit 2 ;;
  esac
}

main "$@"
