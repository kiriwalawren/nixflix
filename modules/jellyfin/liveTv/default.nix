{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  inherit (config) nixflix;
  cfg = config.nixflix.jellyfin;
  inherit (cfg) liveTv;

  util = import ../util.nix { inherit lib; };
  secrets = import ../../../lib/secrets { inherit lib; };
  authUtil = import ../authUtil.nix { inherit lib pkgs cfg; };
  waitForApiScript = import ../waitForApiScript.nix {
    inherit pkgs;
    jellyfinCfg = cfg;
  };

  baseUrl =
    if cfg.network.baseUrl == "" then
      "http://${cfg.connectionAddress}:${toString cfg.network.internalHttpPort}"
    else
      "http://${cfg.connectionAddress}:${toString cfg.network.internalHttpPort}/${cfg.network.baseUrl}";

  stateFile = "${cfg.dataDir}/nixflix-managed-livetv.json";
  declared = liveTv.tuners != { } || liveTv.listingProviders != { };

  # A jq invocation printing one tuner's resolved declaration. The url is
  # passed with the mkJqSecretArgs convention: a plain value becomes --arg,
  # a `{ _secret = path; }` becomes --rawfile of that file, which only this
  # jq process reads - so a secret URL never reaches the store or the state.
  jqTuner =
    name: t:
    let
      jqSecrets = secrets.mkJqSecretArgs { inherit (t) url; };
    in
    ''
      ${pkgs.jq}/bin/jq -cn \
        ${jqSecrets.flagsString} \
        --arg name ${escapeShellArg name} \
        --arg friendlyName ${escapeShellArg t.friendlyName} \
        --argjson settings ${escapeShellArg (builtins.toJSON (util.recursiveTransform t.settings))} \
        '{name: $name, friendlyName: $friendlyName, url: ${jqSecrets.refs.url}, settings: $settings}'
    '';

  # Same for a listing provider. `tuners` still holds names; applyProvider
  # resolves them to tuner Ids at run time.
  jqProvider =
    name: p:
    let
      jqSecrets = secrets.mkJqSecretArgs { inherit (p) path; };
    in
    ''
      ${pkgs.jq}/bin/jq -cn \
        ${jqSecrets.flagsString} \
        --arg name ${escapeShellArg name} \
        --argjson tuners ${escapeShellArg (builtins.toJSON p.tuners)} \
        --argjson settings ${escapeShellArg (builtins.toJSON (util.recursiveTransform p.settings))} \
        '{name: $name, path: ${jqSecrets.refs.path}, tuners: $tuners, settings: $settings}'
    '';

  tunerCalls = concatStringsSep "\n" (
    mapAttrsToList (name: t: ''
      # Tuner ${escapeShellArg name}
      resolved=$(${jqTuner name t})
      applyTuner ${escapeShellArg name} "$resolved"
    '') liveTv.tuners
  );

  providerCalls = concatStringsSep "\n" (
    mapAttrsToList (name: p: ''
      # Guide ${escapeShellArg name}
      resolved=$(${jqProvider name p})
      applyProvider ${escapeShellArg name} "$resolved"
    '') liveTv.listingProviders
  );
in
{
  imports = [ ./options.nix ];

  config = mkIf (nixflix.enable && cfg.enable) {
    assertions = [
      {
        assertion = all (p: p.tuners == null || all (t: liveTv.tuners ? ${t}) p.tuners) (
          attrValues liveTv.listingProviders
        );
        message = "nixflix.jellyfin.liveTv.listingProviders.<name>.tuners must name tuners declared in nixflix.jellyfin.liveTv.tuners";
      }
    ];

    systemd.services.jellyfin-livetv = {
      description = "Configure Jellyfin Live TV tuners and guides via API";
      after = [ "jellyfin-plugins.service" ] ++ config.nixflix.serviceDependencies;
      requires = [ "jellyfin-plugins.service" ] ++ config.nixflix.serviceDependencies;
      wantedBy = [ "multi-user.target" ];

      path = with pkgs; [
        coreutils
        curl
        jq
      ];

      # With nothing declared, run only to remove what was declared before.
      unitConfig.ConditionPathExists = mkIf (!declared) stateFile;

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        TimeoutStartSec = 300;
        ExecStartPre = waitForApiScript;
      };

      script = ''
        set -euo pipefail

        # Reconcile Jellyfin's Live TV tuners and XMLTV listing providers with
        # the declaration (see jqTuner/jqProvider above), keeping a state file
        # of what this unit manages. Jellyfin 10.11 semantics: POST with an
        # existing Id updates in place, without one creates.
        #
        # - A declared tuner/provider is matched by its Url/Path, and only
        #   POSTed when what Jellyfin holds differs (the declared fields merged
        #   over the stored object, so undeclared fields keep their value).
        # - One that was declared before (state file) and is no longer is
        #   deleted.
        # - Anything else (added by hand in the dashboard) is never touched; it
        #   is listed in the log.
        # - The guide is refreshed only when something changed.
        #
        # The state file stores only sha256 hashes of resolved Urls/Paths, so
        # secret values never land in it.

        BASE_URL="${baseUrl}"
        TOKEN_FILE="${authUtil.token._secret}"
        STATE=${escapeShellArg stateFile}

        api() { # METHOD PATH [JSON-BODY] -> response body; fails on HTTP >= 400
          local body=''${3:-} bf rc=0
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

        want_t='[]' # resolved tuner Urls, for the removal pass and the state file
        want_p='[]' # resolved provider Paths
        declare -A tunerIds=()

        # Tuners first: providers refer to them by Id.
        applyTuner() { # NAME RESOLVED-JSON: create or update one tuner
          local name=$1 t=$2 url stored old id body
          url=$(jq -r '.url' <<<"$t")
          [ -n "$url" ] || { echo "liveTv: tuner '$name': url is empty - an empty secret file?" >&2; exit 1; }
          stored=$(jq -c --arg u "$url" '[.TunerHosts[] | select(.Url == $u)]' <<<"$cfg")
          [ "$(jq length <<<"$stored")" -le 1 ] \
            || { echo "liveTv: several tuners in Jellyfin use the URL of tuner '$name'; remove the extras in the dashboard" >&2; exit 1; }
          body=$(jq -c --argjson t "$t" --arg u "$url" \
            '(.[0] // {}) + $t.settings + {Type: "m3u", Url: $u, FriendlyName: $t.friendlyName}' <<<"$stored")
          old=$(jq -r "$usable_id" <<<"$stored")
          if [ -n "$old" ] && same "$body" "$stored"; then
            tunerIds[$name]=$old
            echo "tuner '$name': unchanged ($old)"
          else
            id=$(api POST LiveTv/TunerHosts "$body" | jq -er '.Id | select(type == "string" and length > 0)')
            changed=1
            echo "tuner '$name': $([ -n "$old" ] && echo updated || echo created) ($id)"
            tunerIds[$name]=$id
          fi
          want_t=$(jq -c --arg u "$url" '. + [$u]' <<<"$want_t")
        }

        applyProvider() { # NAME RESOLVED-JSON: create or update one XMLTV listing provider
          local name=$1 p=$2 path enabled ids old id body stored
          path=$(jq -r '.path' <<<"$p")
          [ -n "$path" ] || { echo "liveTv: guide '$name': path is empty - an empty secret file?" >&2; exit 1; }
          if jq -e '.tuners == null' >/dev/null <<<"$p"; then
            enabled='{"EnableAllTuners": true, "EnabledTuners": []}'
          else
            ids='[]'
            for tn in $(jq -r '.tuners[]' <<<"$p"); do
              [ -n "''${tunerIds[$tn]:-}" ] || { echo "liveTv: guide '$name' names undeclared tuner '$tn'" >&2; exit 1; }
              ids=$(jq -c --arg id "''${tunerIds[$tn]}" '. + [$id]' <<<"$ids")
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
          want_p=$(jq -c --arg p "$path" '. + [$p]' <<<"$want_p")
        }

        ${tunerCalls}

        ${providerCalls}

        # Remove what this unit created before and is no longer declared. The
        # state holds hashes, so a secret URL never lands in it.
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
          # Nothing left to manage: without the state file the unit stops
          # running (ConditionPathExists in the unit definition).
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
      '';
    };
  };
}
