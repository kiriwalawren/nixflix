{
  pkgs,
  lib,
  evalConfig,
  assertTest,
  check,
  ...
}:
let
  jellyfinPlugins = import ../../lib/jellyfin-plugins.nix { inherit lib; };
  manifestHash =
    file:
    builtins.convertHash {
      hash = builtins.hashFile "sha256" file;
      hashAlgo = "sha256";
      toHashFormat = "sri";
    };
in
{
  jellyfin-plugin-package-service-generation =
    let
      plugin = pkgs.runCommand "test-plugin-1.0.0" { } ''
        mkdir -p "$out"
        touch "$out/TestPlugin.dll"
      '';
      config = evalConfig [
        {
          nixflix = {
            enable = true;

            jellyfin = {
              enable = true;
              plugins."Test Plugin".package = plugin;
              users.admin = {
                password = "testpassword";
                policy.isAdministrator = true;
              };
            };
          };
        }
      ];
      systemdUnits = config.config.systemd.services;
      tmpfilesSettings = config.config.systemd.tmpfiles.settings;
      pluginPath = "${config.config.nixflix.jellyfin.dataDir}/plugins";
    in
    pkgs.runCommand "unit-test-jellyfin-plugin-package-service-generation" { } ''
      ${check "plugin service exists" (systemdUnits ? jellyfin-plugins)}
      ${check "plugin tmpfiles directory exists" (
        builtins.hasAttr pluginPath tmpfilesSettings."10-jellyfin"
      )}

      echo 'PASS: jellyfin-plugin-package-service-generation' > $out
    '';

  jellyfin-plugin-source-assertion =
    let
      result = builtins.tryEval (
        let
          config = evalConfig [
            {
              nixflix = {
                enable = true;

                jellyfin = {
                  enable = true;
                  plugins."Broken Plugin" = {
                    package = {
                      version = "1.0.0.0";
                    };
                    config.SomeSetting = true;
                  };
                  users.admin = {
                    password = "testpassword";
                    policy.isAdministrator = true;
                  };
                };
              };
            }
          ];
        in
        config.config.system.build.toplevel.drvPath
      );
    in
    assertTest "jellyfin-plugin-source-assertion" (!result.success);

  jellyfin-plugin-repo-service-generation =
    let
      targetAbi = "${pkgs.jellyfin.version}.0";
      manifest = pkgs.writeText "jellyfin-plugin-repo-service-generation.json" (
        builtins.toJSON [
          {
            guid = "c83d86bb-a1e0-4c35-a113-e2101cf4ee6b";
            name = "Intro Skipper";
            versions = [
              {
                version = "12.0.6.0";
                inherit targetAbi;
                sourceUrl = "https://github.com/intro-skipper/intro-skipper/releases/download/12.0/v12.0.6.0/intro-skipper-v12.0.6.0.zip";
              }
            ];
          }
        ]
      );
      config = evalConfig [
        {
          nixflix = {
            enable = true;

            jellyfin = {
              enable = true;
              system.pluginRepositories = lib.mkForce {
                "Test Repo" = {
                  url = builtins.unsafeDiscardStringContext "file://${manifest}";
                  hash = manifestHash manifest;
                  enabled = true;
                };
              };
              plugins."Intro Skipper" = {
                enable = true;
                package = jellyfinPlugins.fromRepo {
                  version = "12.0.6.0";
                  hash = "sha256-g8Oiyt4NK8pyCXt2M1B7EpEL71kUGGkxtXSzKndUuOQ=";
                };
              };
              users.admin = {
                password = "testpassword";
                policy.isAdministrator = true;
              };
            };
          };
        }
      ];
      pluginService = config.config.systemd.services.jellyfin-plugins;
    in
    pkgs.runCommand "unit-test-jellyfin-plugin-repo-service-generation" { } ''
      ${check "plugin service exists for repo-managed plugin" (
        config.config.systemd.services ? jellyfin-plugins
      )}
      ${check "repo-managed plugins resolve to package sync commands" (
        lib.hasInfix "Syncing packaged plugin: Intro Skipper" pluginService.script
      )}
      ${check "resolved plugin directory name appears in service script" (
        lib.hasInfix "Intro Skipper_12.0.6.0" pluginService.script
      )}

      echo 'PASS: jellyfin-plugin-repo-service-generation' > $out
    '';

  jellyfin-plugin-repo-relaxed-version-check =
    let
      manifest = pkgs.writeText "jellyfin-plugin-relaxed-version-check.json" (
        builtins.toJSON [
          {
            guid = "486090e1-ca92-46e1-8549-9f6bb914a1d0";
            name = "LAPSE";
            versions = [
              {
                version = "2.1.3.0";
                targetAbi = "10.11.0.0";
                sourceUrl = "https://github.com/Schwponaco-org/lapse-jellyfin-plugin/releases/download/v2.0.1/lapse-jellyfin-plugin-v2.0.1.zip";
              }
            ];
          }
        ]
      );
      config = evalConfig [
        {
          nixflix = {
            enable = true;

            jellyfin = {
              enable = true;
              system.pluginRepositories = lib.mkForce {
                "LAPSE Repo" = {
                  url = builtins.unsafeDiscardStringContext "file://${manifest}";
                  hash = manifestHash manifest;
                  enabled = true;
                };
              };
              plugins."LAPSE" = {
                enable = true;
                package = jellyfinPlugins.fromRepo {
                  version = "2.1.3.0";
                  hash = "sha256-cyw017kDNA5p/qU/DSe2o/nAmiTfFexPRQDx5X5EuT8=";
                };
              };
              users.admin = {
                password = "testpassword";
                policy.isAdministrator = true;
              };
            };
          };
        }
      ];
      pluginService = config.config.systemd.services.jellyfin-plugins;
    in
    pkgs.runCommand "unit-test-jellyfin-plugin-repo-relaxed-version-check" { } ''
      ${check "Plugin with incompatible target ABI installed with relaxed version check" (
        lib.hasInfix "LAPSE_2.1.3.0" pluginService.script
      )}

      echo 'PASS: jellyfin-plugin-repo-relax-version-check' > $out
    '';

  jellyfin-plugin-repo-ambiguity-assertion =
    let
      targetAbi = "${pkgs.jellyfin.version}.0";
      manifestA = pkgs.writeText "jellyfin-plugin-repo-a.json" (
        builtins.toJSON [
          {
            guid = "11111111-1111-1111-1111-111111111111";
            name = "Collision Plugin";
            versions = [
              {
                version = "1.0.0.0";
                inherit targetAbi;
                sourceUrl = "https://example.invalid/repo-a.zip";
              }
            ];
          }
        ]
      );
      manifestB = pkgs.writeText "jellyfin-plugin-repo-b.json" (
        builtins.toJSON [
          {
            guid = "22222222-2222-2222-2222-222222222222";
            name = "Collision Plugin";
            versions = [
              {
                version = "1.0.0.0";
                inherit targetAbi;
                sourceUrl = "https://example.invalid/repo-b.zip";
              }
            ];
          }
        ]
      );
      result = builtins.tryEval (
        let
          config = evalConfig [
            {
              nixflix = {
                enable = true;

                jellyfin = {
                  enable = true;
                  apiKey = "test-api-key";
                  system.pluginRepositories = lib.mkForce {
                    "Repo A" = {
                      url = builtins.unsafeDiscardStringContext "file://${manifestA}";
                      hash = manifestHash manifestA;
                      enabled = true;
                    };
                    "Repo B" = {
                      url = builtins.unsafeDiscardStringContext "file://${manifestB}";
                      hash = manifestHash manifestB;
                      enabled = true;
                    };
                  };
                  plugins."Collision Plugin" = {
                    package = jellyfinPlugins.fromRepo {
                      version = "1.0.0.0";
                      hash = lib.fakeHash;
                    };
                  };
                  users.admin = {
                    password = "testpassword";
                    policy.isAdministrator = true;
                  };
                };
              };
            }
          ];
        in
        config.config.system.build.toplevel.drvPath
      );
    in
    assertTest "jellyfin-plugin-repo-ambiguity-assertion" (!result.success);
}
