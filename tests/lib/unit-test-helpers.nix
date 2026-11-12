{
  system,
  pkgs,
  nixosModules,
}:
let
  inherit (pkgs) lib;
in
{
  # Test helper to assert conditions
  assertTest =
    name: cond:
    pkgs.runCommand "unit-test-${name}" { } ''
      ${lib.optionalString (!cond) "echo 'FAIL: ${name}' && exit 1"}
      echo 'PASS: ${name}' > $out
    '';

  check = name: cond: ''
    ${lib.optionalString (!cond) "echo 'FAIL: ${name}' && exit 1"}
    echo 'PASS: ${name}'
  '';

  # True when a script contains the `# nixflix-sync-guard` marker (lib/sync-mode.nix)
  # before its first mutating call, so a refused sync cannot change anything.
  #
  # Mutating: HTTP POST/PUT/DELETE/PATCH (raw curl and the jellyfin-livetv
  # `api` helper), SABnzbd's set_config/del_config, systemctl stop/start/
  # restart, rm/mkdir/mv/cp/chown/chmod, and redirects into a file named by a
  # variable or an absolute path (not /dev/...). Top-level shell function
  # DEFINITIONS are skipped; a CALL of a function whose body mutates (directly
  # or through another such function) counts as a mutation, except
  # `<fn> GET ...`, the read form of the method-taking helpers.
  guardPrecedesMutations =
    script:
    let
      mutation = "-X (POST|PUT|DELETE|PATCH)|api (POST|PUT|DELETE|PATCH)|set_config|del_config|systemctl (stop|start|restart)|(^|[[:space:];&|(])(rm -|mkdir |mv |cp |chown |chmod )|>>? ?\"[$]|>>? ?'/|>>? ?/[^d]";
      matches = re: text: builtins.length (builtins.split re text) > 1;

      lines = lib.splitString "\n" script;
      defName =
        l:
        let
          m = builtins.match "([A-Za-z_][A-Za-z0-9_]*)\\(\\) *\\{.*" l;
        in
        if m == null then null else builtins.head m;

      # { top = lines outside definitions; fns = name -> body lines; cur }
      parsed =
        builtins.foldl'
          (
            st: l:
            if st.cur != null then
              if l == "}" then
                st // { cur = null; }
              else
                st
                // {
                  fns = st.fns // {
                    ${st.cur} = st.fns.${st.cur} ++ [ l ];
                  };
                }
            else
              let
                name = defName l;
              in
              if name == null then
                st // { top = st.top ++ [ l ]; }
              else
                st
                // {
                  fns = st.fns // {
                    ${name} = [ l ];
                  };
                  cur = if lib.hasSuffix "}" (lib.trim l) then null else name;
                }
          )
          {
            top = [ ];
            fns = { };
            cur = null;
          }
          lines;

      calls =
        name: l:
        builtins.match "(.*[^A-Za-z0-9_])?${name}([^A-Za-z0-9_].*)?" l != null
        && builtins.match "(.*[^A-Za-z0-9_])?${name} +GET([^A-Za-z0-9_].*)?" l == null;
      callsAny = names: l: lib.any (n: calls n l) names;

      directlyMutating = builtins.attrNames (
        lib.filterAttrs (_: body: lib.any (matches mutation) body) parsed.fns
      );
      # Functions that call a mutating function mutate too.
      closure =
        known:
        let
          more = builtins.filter (n: !(builtins.elem n known) && lib.any (callsAny known) parsed.fns.${n}) (
            builtins.attrNames parsed.fns
          );
        in
        if more == [ ] then known else closure (known ++ more);
      mutatingFns = closure directlyMutating;

      isMutation = l: matches mutation l || callsAny mutatingFns l;
      firstMutation = lib.lists.findFirstIndex isMutation null parsed.top;
      beforeFirstMutation =
        if firstMutation == null then parsed.top else lib.take firstMutation parsed.top;
    in
    lib.any (lib.hasInfix "# nixflix-sync-guard") beforeFirstMutation;

  # Helper to evaluate a NixOS configuration without building
  evalConfig =
    modules:
    import "${pkgs.path}/nixos/lib/eval-config.nix" {
      inherit system;
      modules = [
        nixosModules
        {
          # Minimal NixOS config stubs needed for evaluation
          nixpkgs.hostPlatform = system;
        }
      ]
      ++ modules;
    };
}
