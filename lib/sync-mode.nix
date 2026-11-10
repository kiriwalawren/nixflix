# Shared implementation of `nixflix.syncMode` for sync units that GET live
# objects, compare them with the declared config and DELETE the undeclared ones.
#
#   delete  remove live objects that are not declared (the historical behaviour)
#   keep    create/update declared objects, leave undeclared ones alone, log them
#   refuse  fail the unit before changing anything, listing the undeclared ones
#
# Worked example (how a unit adopts it):
#
#   let
#     syncMode = import ../../lib/sync-mode.nix { inherit lib pkgs; };
#     rootFolders = syncMode.mkPrune {
#       mode = cfg.syncMode.rootFolders;          # declared with syncMode.mkModeOption
#       unit = "${serviceName}-rootfolders";
#       what = "root folders";
#       option = "nixflix.${serviceName}.syncMode.rootFolders";
#       live = "ROOT_FOLDERS";                     # shell variable holding the GET result
#       declared = map (f: f.path) cfg.config.rootFolders;
#       key = ".path";
#       onDelete = ''
#         echo "$ROOT_FOLDERS" | jq ... | while ...; do ... -X DELETE ...; done
#       '';                                       # the unit's existing loop, verbatim
#     };
#   in
#   {
#     options.nixflix.${serviceName}.syncMode.rootFolders = syncMode.mkModeOption {
#       inherit config;
#       what = "root folders";
#       collectionOption = "nixflix.${serviceName}.config.rootFolders";
#     };
#
#     config.systemd.services."${serviceName}-rootfolders".script = ''
#       set -eu
#       ROOT_FOLDERS=$(curl ... "$BASE_URL/rootfolder")
#
#       ${rootFolders.guard}
#       ${syncMode.refuseCheckpoint}
#
#       ${rootFolders.prune}
#       # ... create/update declared objects ...
#     '';
#   }
#
# A unit with several collections runs every guard first, then a single
# refuseCheckpoint, so one failed run lists everything that blocks the sync.
# Every guard is placed before the unit's first mutating call; tests check that
# with `guardPrecedesMutations` from tests/lib/unit-test-helpers.nix.
{ lib, pkgs }:
let
  modes = [
    "delete"
    "keep"
    "refuse"
  ];
  refuseExitCode = 78;

  jq = "${pkgs.jq}/bin/jq";
  esc = lib.escapeShellArg;

  modesDescription = ''
    - `"delete"`: remove live objects that are not declared.
    - `"keep"`: create and update declared objects, never delete undeclared
      ones; the unit logs what it kept.
    - `"refuse"`: if undeclared objects exist, fail the unit before changing
      anything and list them, so they can be declared or removed by hand.
  '';
in
{
  inherit modes refuseExitCode;

  mkModeOption =
    {
      config,
      what,
      collectionOption,
    }:
    lib.mkOption {
      type = lib.types.enum modes;
      default = config.nixflix.syncMode;
      defaultText = lib.literalExpression "config.nixflix.syncMode";
      description = ''
        What to do with ${what} that exist in the service but are not declared
        in `${collectionOption}`. Defaults to `nixflix.syncMode`.

        ${modesDescription}
      '';
    };

  # Shell snippet ending the unit with exit code 78 if any refuse guard fired.
  refuseCheckpoint = ''if [ "''${NIXFLIX_SYNC_REFUSED:-0}" = 1 ]; then exit ${toString refuseExitCode}; fi'';

  mkPrune =
    {
      mode,
      unit,
      what,
      option,
      live,
      declared,
      key ? ".name",
      id ? ".id",
      label ? key,
      select ? "true",
      ignore ? [ ],
      onDelete,
    }:
    assert lib.assertOneOf "mkPrune mode for ${unit}" mode modes;
    let
      liveRef = ''"$'' + live + ''"'';

      jqArgs = "--argjson declared ${esc (builtins.toJSON declared)} --argjson ignore ${esc (builtins.toJSON ignore)}";

      # Undeclared candidates as a JSON array. `any(. == $k)` is plain element
      # equality; `index($k)` changes meaning with the type of $k and its input.
      undeclared = "($declared + $ignore) as $known | [ .[] | select(${select}) | select((${key}) as $k | $known | any(. == $k) | not) ]";

      # Newlines are flattened so one object is always one log line.
      oneLine = expr: "((${expr}) | tostring | gsub(\"[\\r\\n]\"; \" \"))";

      isArray = "printf '%s' ${liveRef} | ${jq} -e 'type == \"array\"' >/dev/null 2>&1";

      countUndeclared = "printf '%s' ${liveRef} | ${jq} ${jqArgs} ${esc "${undeclared} | length"}";

      guard = ''
        # nixflix-sync-guard: ${unit} ${what}
        if ! ${isArray}; then
          echo ${esc "nixflix: ${unit}: cannot check for undeclared ${what}: live state is not a JSON array (did the API request fail?)"} >&2
          exit 1
        fi
        _nixflix_sync_count=$(${countUndeclared})
        if [ "$_nixflix_sync_count" -gt 0 ]; then
          {
            printf '%s\n' ${esc "nixflix: ${unit}: refusing to sync: "}"$_nixflix_sync_count"${esc " ${what} exist that are not declared (${option} = \"refuse\"). Nothing was changed."}
            printf '%s' ${liveRef} | ${jq} -r ${jqArgs} ${esc "${undeclared} | .[] | \"nixflix:   - \\(${oneLine label}) (id \\(${oneLine id}))\""}
            printf '%s\n' ${esc "nixflix: declare them (see ${option}), or set it to \"keep\" or \"delete\"."}
          } >&2
          NIXFLIX_SYNC_REFUSED=1
        fi
      '';

      keep = ''
        if ${isArray}; then
          _nixflix_sync_count=$(${countUndeclared})
          if [ "$_nixflix_sync_count" -gt 0 ]; then
            _nixflix_sync_kept=$(printf '%s' ${liveRef} | ${jq} -r ${jqArgs} ${esc "${undeclared} | map(${oneLine label}) | join(\", \")"})
            printf '%s\n' ${esc "nixflix: ${unit}: keeping "}"$_nixflix_sync_count"${esc " undeclared ${what} (${option} = \"keep\"): "}"$_nixflix_sync_kept"
          fi
        else
          echo ${esc "nixflix: ${unit}: live ${what} are not a JSON array; skipping the undeclared check"} >&2
        fi
      '';
    in
    {
      delete = {
        guard = "";
        prune = onDelete;
      };
      keep = {
        guard = "";
        prune = keep;
      };
      refuse = {
        inherit guard;
        prune = "";
      };
    }
    .${mode};
}
