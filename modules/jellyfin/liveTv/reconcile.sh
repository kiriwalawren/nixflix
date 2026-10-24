# Reconcile Jellyfin's Live TV tuners and XMLTV listing providers with the
# declaration in $1 (JSON, see default.nix), keeping a state file ($2) of what
# this unit manages. Jellyfin 10.11 semantics: POST with an existing Id
# updates in place, without one creates.
#
# - A declared tuner/provider is matched by its Url/Path, and only POSTed when
#   what Jellyfin holds differs (merged over the stored object, so fields not
#   declared keep their value).
# - One that was declared before (state file) and is no longer is deleted.
# - Anything else (added by hand) is never touched; it is listed in the log.
# - The guide is refreshed only when something changed.
#
# Env: BASE_URL, TOKEN_FILE (the Authorization header value, from authUtil).
# Url/Path may be secrets: `urlFile`/`pathFile` name a file holding them, and
# the state file stores only their sha256.
set -euo pipefail

SPEC=$1
STATE=$2

api() { # METHOD PATH [JSON-BODY] -> response body; fails on HTTP >= 400
  local body=${3:-} bf rc=0
  if [ -n "$body" ]; then
    bf=$(mktemp)
    printf '%s' "$body" >"$bf"
    curl -sS -f -m 60 --variable "tok@$TOKEN_FILE" --expand-header "Authorization: {{tok:trim}}" \
      -X "$1" -H "Content-Type: application/json" --data-binary "@$bf" "$BASE_URL/$2" || rc=$?
    rm -f "$bf"
  else
    curl -sS -f -m 60 --variable "tok@$TOKEN_FILE" --expand-header "Authorization: {{tok:trim}}" \
      -X "$1" "$BASE_URL/$2" || rc=$?
  fi
  return "$rc"
}

sha() { printf '%s' "$1" | sha256sum | cut -d' ' -f1; }

# Resolve secret files into the declaration (kept in memory only).
resolve() { # ARRAY-NAME VALUE-KEY FILE-KEY
  local out='[]' i n v
  n=$(jq --arg a "$1" '.[$a] | length' "$SPEC")
  for ((i = 0; i < n; i++)); do
    v=$(jq -r --arg a "$1" --arg k "$2" --argjson i "$i" '.[$a][$i][$k] // empty' "$SPEC")
    if [ -z "$v" ]; then
      f=$(jq -r --arg a "$1" --arg k "$3" --argjson i "$i" '.[$a][$i][$k]' "$SPEC")
      v=$(tr -d '\n' <"$f")
      [ -n "$v" ] || { echo "liveTv: $f is empty" >&2; exit 1; }
    fi
    out=$(jq -c --arg a "$1" --arg k "$2" --arg v "$v" --argjson i "$i" --slurpfile s "$SPEC" \
      '. + [$s[0][$a][$i] + {($k): $v}]' <<<"$out")
  done
  printf '%s' "$out"
}

tuners=$(resolve tuners url urlFile)
providers=$(resolve providers path pathFile)
if [ -s "$STATE" ]; then prev=$(cat "$STATE"); else prev='{"tuners":[],"providers":[]}'; fi

cfg=$(api GET System/Configuration/livetv)
jq -e '(.TunerHosts | type == "array") and (.ListingProviders | type == "array")' >/dev/null <<<"$cfg" \
  || { echo "liveTv: unexpected Live TV configuration from Jellyfin: $(head -c 200 <<<"$cfg")" >&2; exit 1; }

changed=0
usable_id='.[0].Id | select(type == "string" and length > 0)'
same() { # BODY STORED-ARRAY -> 0 equal, 1 differs; any jq error aborts
  local rc=0
  jq -e --argjson b "$1" '.[0] == $b' <<<"$2" >/dev/null || rc=$?
  [ "$rc" -le 1 ] || { echo "liveTv: jq failed ($rc) comparing Jellyfin's configuration" >&2; exit 1; }
  return "$rc"
}

# Tuners first: providers refer to them by Id.
declare -A tunerIds=()
n=$(jq length <<<"$tuners")
for ((i = 0; i < n; i++)); do
  t=$(jq -c --argjson i "$i" '.[$i]' <<<"$tuners")
  name=$(jq -r .name <<<"$t")
  url=$(jq -r .url <<<"$t")
  stored=$(jq -c --arg u "$url" '[.TunerHosts[] | select(.Url == $u)]' <<<"$cfg")
  [ "$(jq length <<<"$stored")" -le 1 ] \
    || { echo "liveTv: several tuners in Jellyfin use the URL of tuner '$name'; remove the extras in the dashboard" >&2; exit 1; }
  body=$(jq -c --argjson t "$t" --arg u "$url" \
    '(.[0] // {}) + $t.settings + {Type: "m3u", Url: $u, FriendlyName: $t.friendlyName}' <<<"$stored")
  old=$(jq -r "$usable_id" <<<"$stored")
  if [ -n "$old" ] && same "$body" "$stored"; then
    id=$old
    echo "tuner '$name': unchanged ($id)"
  else
    id=$(api POST LiveTv/TunerHosts "$body" | jq -er '.Id | select(type == "string" and length > 0)')
    changed=1
    echo "tuner '$name': $([ -n "$old" ] && echo updated || echo created) ($id)"
  fi
  tunerIds[$name]=$id
done

n=$(jq length <<<"$providers")
for ((i = 0; i < n; i++)); do
  p=$(jq -c --argjson i "$i" '.[$i]' <<<"$providers")
  name=$(jq -r .name <<<"$p")
  path=$(jq -r .path <<<"$p")
  if jq -e '.tuners == null' >/dev/null <<<"$p"; then
    enabled='{"EnableAllTuners": true, "EnabledTuners": []}'
  else
    ids='[]'
    for tn in $(jq -r '.tuners[]' <<<"$p"); do
      [ -n "${tunerIds[$tn]:-}" ] || { echo "liveTv: guide '$name' names undeclared tuner '$tn'" >&2; exit 1; }
      ids=$(jq -c --arg id "${tunerIds[$tn]}" '. + [$id]' <<<"$ids")
    done
    enabled=$(jq -cn --argjson ids "$ids" '{EnableAllTuners: false, EnabledTuners: $ids}')
  fi
  stored=$(jq -c --arg p "$path" '[.ListingProviders[] | select(.Type == "xmltv" and .Path == $p)]' <<<"$cfg")
  [ "$(jq length <<<"$stored")" -le 1 ] \
    || { echo "liveTv: several XMLTV providers in Jellyfin use the path of guide '$name'; remove the extras in the dashboard" >&2; exit 1; }
  body=$(jq -c --argjson s "$(jq -c .settings <<<"$p")" --argjson e "$enabled" --arg p "$path" \
    '(.[0] // {}) + $s + {Type: "xmltv", Path: $p} + $e' <<<"$stored")
  old=$(jq -r "$usable_id" <<<"$stored")
  if [ -n "$old" ] && same "$body" "$stored"; then
    echo "guide '$name': unchanged ($old)"
  else
    id=$(api POST "LiveTv/ListingProviders?validateListings=false&validateLogin=false" "$body" \
      | jq -er '.Id | select(type == "string" and length > 0)')
    changed=1
    echo "guide '$name': $([ -n "$old" ] && echo updated || echo created) ($id)"
  fi
done

# Remove what this unit created before and is no longer declared. The state
# holds hashes, so a secret URL never lands in it.
want_t=$(jq -c '[.[].url]' <<<"$tuners")
want_p=$(jq -c '[.[].path]' <<<"$providers")
for row in $(jq -r '.TunerHosts[] | [.Id, .Url] | @base64' <<<"$cfg"); do
  id=$(base64 -d <<<"$row" | jq -r '.[0]')
  url=$(base64 -d <<<"$row" | jq -r '.[1]')
  jq -e --arg u "$url" 'index($u)' >/dev/null <<<"$want_t" && continue
  if jq -e --arg h "$(sha "$url")" '.tuners | index($h)' >/dev/null <<<"$prev"; then
    api DELETE "LiveTv/TunerHosts?id=$id" >/dev/null
    changed=1
    echo "tuner $id: removed (no longer declared)"
  else
    echo "tuner $id: not managed by nixflix, left alone"
  fi
done
for row in $(jq -r '.ListingProviders[] | [.Id, .Type, (.Path // "")] | @base64' <<<"$cfg"); do
  id=$(base64 -d <<<"$row" | jq -r '.[0]')
  type=$(base64 -d <<<"$row" | jq -r '.[1]')
  path=$(base64 -d <<<"$row" | jq -r '.[2]')
  [ "$type" = xmltv ] && jq -e --arg p "$path" 'index($p)' >/dev/null <<<"$want_p" && continue
  if [ "$type" = xmltv ] && jq -e --arg h "$(sha "$path")" '.providers | index($h)' >/dev/null <<<"$prev"; then
    api DELETE "LiveTv/ListingProviders?id=$id" >/dev/null
    changed=1
    echo "guide $id: removed (no longer declared)"
  else
    echo "guide $id ($type): not managed by nixflix, left alone"
  fi
done

hashes() { # JSON-ARRAY-OF-STRINGS -> JSON array of their sha256
  local out='[]' k n
  n=$(jq length <<<"$1")
  for ((k = 0; k < n; k++)); do
    out=$(jq -c --arg h "$(sha "$(jq -r --argjson k "$k" '.[$k]' <<<"$1")")" '. + [$h]' <<<"$out")
  done
  printf '%s' "$out"
}
if [ "$want_t" = '[]' ] && [ "$want_p" = '[]' ]; then
  # Nothing left to manage: without the state file the unit stops running
  # (ConditionPathExists in default.nix).
  rm -f "$STATE"
else
  tmp=$(mktemp "$STATE.XXXXXX")
  jq -cn --argjson t "$(hashes "$want_t")" --argjson p "$(hashes "$want_p")" '{tuners: $t, providers: $p}' >"$tmp"
  mv "$tmp" "$STATE"
fi

if [ "$changed" = 1 ]; then
  task=$(api GET ScheduledTasks | jq -er '[.[] | select(.Key == "RefreshGuide")][0].Id')
  api POST "ScheduledTasks/Running/$task" >/dev/null
  echo "started Jellyfin task Refresh Guide ($task)"
else
  echo "Live TV configuration unchanged"
fi
