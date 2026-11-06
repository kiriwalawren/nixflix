{
  pkgs,
  lib,
  evalConfigWith,
  nixpkgs-2026-09-03,
  ...
}:
{
  # The themed Caddy must build against any nixpkgs, not only the one in flake.lock (#328)
  caddy-theme-package-builds-across-nixpkgs =
    let
      caddyFor =
        nixpkgsPath:
        (evalConfigWith nixpkgsPath [
          {
            nixflix = {
              enable = true;
              theme.enable = true;
              caddy.enable = true;
              prowlarr = {
                enable = true;
                config = {
                  hostConfig.password._secret = "/run/secrets/prowlarr-pass";
                  apiKey._secret = "/run/secrets/prowlarr-api";
                };
              };
            };
          }
        ]).config.services.caddy;

      variants = {
        locked = caddyFor pkgs.path;
        nixpkgs-2026-09-03 = caddyFor nixpkgs-2026-09-03;
      };
    in
    pkgs.runCommand "unit-test-caddy-theme-package-builds-across-nixpkgs" { } ''
      export HOME=$TMPDIR
      ${lib.concatStrings (
        lib.mapAttrsToList (name: cfg: ''
          echo "== ${name}: ${cfg.package}"
          ${cfg.package}/bin/caddy list-modules | grep -qx http.handlers.replace_response \
            || { echo "FAIL: ${name} caddy lacks http.handlers.replace_response"; exit 1; }
          grep -q 'replace {' ${cfg.configFile} \
            || { echo "FAIL: ${name} Caddyfile has no theme replace block"; exit 1; }
          ${cfg.package}/bin/caddy adapt --adapter caddyfile --config ${cfg.configFile} > /dev/null \
            || { echo "FAIL: ${name} Caddyfile does not adapt"; exit 1; }
        '') variants
      )}
      echo 'PASS: caddy-theme-package-builds-across-nixpkgs' > $out
    '';
}
