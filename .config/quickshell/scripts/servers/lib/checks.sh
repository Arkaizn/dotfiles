# Health checks: the per-server checks from CHECKS in svs.conf, plus the automatic
# container check. Results are stored per phase ("pre" = baseline before updating,
# "post" = after) so failures can be compared against the baseline:
#   CHECK[<phase>|<server>|<name>] = ok | fail: <detail>
#   CTSTATE[<phase>|<server>]      = STATE|<container>|<status>|<health> lines

declare -A CHECK CTSTATE NO_SSH

# check_one <server> <type> <target> <expect> — prints a short reason on failure
check_one() {
  local server="$1" type="$2" target="$3" expect="$4" code rc
  case "$type" in
    http)
      code=$(curl -sk -o /dev/null -m "$CHECK_TIMEOUT" -w '%{http_code}' "$target")
      [[ "$code" =~ ^(${expect:-[23][0-9][0-9]})$ ]] || { echo "HTTP $code"; return 1; }
      ;;
    tcp)
      timeout "$CHECK_TIMEOUT" bash -c "</dev/tcp/${target%:*}/${target##*:}" 2>/dev/null \
        || { echo "port closed"; return 1; }
      ;;
    dns)
      [ -n "$(dig +short +time=3 +tries=1 "@$target" "${expect:-one.one.one.one}" 2>/dev/null)" ] \
        || { echo "no answer"; return 1; }
      ;;
    service|cmd)
      # needs SSH: don't wait for another timeout on a server that's known to be down
      [ "${NO_SSH[$server]}" = 1 ] && { echo "no SSH"; return 1; }
      ;;&
    service)
      remote "$server" service "$target" &>/dev/null || { echo "inactive"; return 1; }
      ;;
    cmd)
      remote "$server" cmd "$target" &>/dev/null
      rc=$?
      [ "$rc" -eq 0 ] || { echo "exit $rc"; return 1; }
      ;;
    *)
      echo "unknown check type '$type'"
      return 1
      ;;
  esac
}

# check_lines <server> — the server's checks as "type<TAB>name<TAB>target<TAB>expect"
check_lines() {
  local line type name target expect
  while IFS= read -r line; do
    [[ "$line" =~ ^[[:space:]]*(#|$) ]] && continue
    read -r type name target <<< "$line"
    if [ "$type" != cmd ]; then
      read -r type name target expect _ <<< "$line"
      [[ "$expect" == "#"* ]] && expect=""
    fi
    printf '%s\t%s\t%s\t%s\n' "$type" "$name" "$target" "$expect"
  done <<< "${CHECKS[$1]}"
}

# run_checks <server> <phase>
run_checks() {
  local server="$1" phase="$2" type name target expect detail dir n=0 i
  local -a names pids
  # every check of the server at once (each has its own timeout: one after the other,
  # a server that is down took minutes); results come back through files
  dir=$(mktemp -d "$RUN_DIR/chk.XXXXXX")
  while IFS=$'\t' read -r type name target expect; do
    [ -n "$type" ] || continue
    n=$((n + 1))
    names[n]=$name
    (
      if detail=$(check_one "$server" "$type" "$target" "$expect"); then echo ok; else echo "fail: $detail"; fi > "$dir/$n"
    ) &
    pids[n]=$!
  done <<< "$(check_lines "$server")"
  for ((i = 1; i <= n; i++)); do
    wait "${pids[i]}" 2>/dev/null
    CHECK["$phase|$server|${names[i]}"]=$(cat "$dir/$i" 2>/dev/null || echo "fail: no result")
  done
  if [ "${NO_SSH[$server]}" = 1 ]; then CTSTATE["$phase|$server"]=""
  else CTSTATE["$phase|$server"]=$(remote "$server" state 2>/dev/null | grep '^STATE|'); fi
}

# failed_checks <server> <phase> — "name: reason" for every failing check
failed_checks() {
  local server="$1" phase="$2" type name rest
  while IFS=$'\t' read -r type name rest; do
    [ -n "$name" ] || continue
    [ "${CHECK[$phase|$server|$name]}" = ok ] || echo "$name: ${CHECK[$phase|$server|$name]#fail: }"
  done <<< "$(check_lines "$server")"
}

# unhealthy_containers <server> <phase> — containers that are unhealthy or crash-looping
unhealthy_containers() {
  local name status health
  while IFS='|' read -r _ name status health; do
    [ -n "$name" ] || continue
    if [ "$status" = restarting ] || [ "$health" = unhealthy ]; then
      echo "container $name: ${health/none/$status}"
    fi
  done <<< "${CTSTATE[$2|$1]}"
}

# regressions <server> — everything that was fine in the baseline but isn't now
regressions() {
  local server="$1" type name rest
  while IFS=$'\t' read -r type name rest; do
    [ -n "$name" ] || continue
    if [ "${CHECK[pre|$server|$name]}" = ok ] && [ "${CHECK[post|$server|$name]}" != ok ]; then
      echo "$name: ${CHECK[post|$server|$name]#fail: }"
    fi
  done <<< "$(check_lines "$server")"

  local status health now_status now_health
  declare -A now
  while IFS='|' read -r _ name status health; do
    [ -n "$name" ] && now[$name]="$status|$health"
  done <<< "${CTSTATE[post|$server]}"
  while IFS='|' read -r _ name status health; do
    [ -n "$name" ] || continue
    [ "$status" = running ] || continue
    [ "$health" = unhealthy ] && continue   # already broken before the update
    IFS='|' read -r now_status now_health <<< "${now[$name]:-missing|none}"
    if [ "$now_status" != running ]; then
      echo "container $name: $now_status"
    elif [ "$health" != none ] && [ "$now_health" != healthy ]; then
      echo "container $name: $now_health"
    fi
  done <<< "${CTSTATE[pre|$server]}"
}

# split_problems <server> <problems> — sorts what's still wrong after an update into
# HARD (the update may have broken it: worth a rollback) and SOFT (needs a look, but a
# rollback wouldn't help), SOFT lines with the reason in brackets:
#   - a container that is still "starting": its own health check hasn't passed yet
#   - a container that wasn't updated in this run
#   - a check named like such a container
split_problems() {
  local server="$1" p name state why soft_names=" " touched=" " payload
  HARD="" SOFT=""
  while IFS= read -r payload; do
    [ -n "$payload" ] && touched+="$(ct_name "$payload") "
  done <<< "${SEL_CT[$server]}"
  while IFS= read -r payload; do
    [ -n "$payload" ] && touched+="$payload "
  done <<< "${SEL_PLAIN[$server]}"
  while IFS= read -r p; do
    [[ "$p" =~ ^container\ ([^:]+):\ (.+)$ ]] || continue
    name=${BASH_REMATCH[1]} state=${BASH_REMATCH[2]} why=""
    if [ "$state" = starting ]; then why="still starting: its own health check hasn't passed yet"
    elif [[ "$touched" != *" $name "* ]]; then why="it wasn't updated in this run"
    fi
    if [ -n "$why" ]; then
      SOFT+="${SOFT:+$'\n'}$p ($why)"
      soft_names+="${name,,} "
    else
      HARD+="${HARD:+$'\n'}$p"
    fi
  done <<< "$2"
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    [[ "$p" =~ ^container\  ]] && continue
    name=${p%%:*}
    if [[ "$soft_names" == *" ${name,,} "* ]]; then SOFT+="${SOFT:+$'\n'}$p (the check of a container that wasn't updated)"
    else HARD+="${HARD:+$'\n'}$p"
    fi
  done <<< "$2"
}

# verify <server> — re-run the checks until nothing regressed or VERIFY_TIMEOUT runs
# out. Prints the remaining regressions and returns 1 if there are any (2: the user
# aborted the wait, see aborted()).
verify() {
  # after a reboot everything starts at once (and a VPN has to connect first): wait longer
  local server="$1" limit=$VERIFY_TIMEOUT problems
  [ "${R_REBOOT[$server]}" = rebooted ] && limit=$VERIFY_TIMEOUT_REBOOT
  local deadline=$((SECONDS + limit))
  while :; do
    run_checks "$server" post
    problems=$(regressions "$server")
    [ -z "$problems" ] && return 0
    if aborted "$server"; then
      printf '%s\n' "$problems"
      return 2
    fi
    if ((SECONDS >= deadline)); then
      printf '%s\n' "$problems"
      return 1
    fi
    phase "verifying — $(count_lines "$problems") issue(s) left, $((deadline - SECONDS))s to go"
    log "  not healthy yet: $(paste -sd ';' <<< "$problems")"
    sleep "$VERIFY_INTERVAL"
  done
}
