{
  pkgs ? import <nixpkgs> {},
  lib ? pkgs.lib,
}: let
  configGenerator = import ../../modules/restish-wrapper/configGenerator.nix {inherit lib;};
  inherit (configGenerator) generateConfig;

  testCases = {
    withHeadersOnly = {
      services = {
        sonarr = {
          baseUrl = "http://127.0.0.1:8989/api/v3";
          headers."X-Api-Key" = "/path/to/key";
        };
      };
      expected = builtins.fromJSON ''
        {
          "sonarr": {
            "base": "http://127.0.0.1:8989/api/v3",
            "profiles": {
              "default": {
                "base": "http://127.0.0.1:8989/api/v3",
                "headers": { "X-Api-Key": "$HEADER_SONARR_X_API_KEY" }
              }
            }
          }
        }
      '';
    };

    withQueryOnly = {
      services = {
        sabnzbd = {
          baseUrl = "http://127.0.0.1:8080/api";
          query = {
            apikey = "/path/to/apikey";
            output = "json";
          };
        };
      };
      expected = builtins.fromJSON ''
        {
          "sabnzbd": {
            "base": "http://127.0.0.1:8080/api",
            "profiles": {
              "default": {
                "base": "http://127.0.0.1:8080/api",
                "query": { "apikey": "$QUERY_SABNZBD_APIKEY", "output": "$QUERY_SABNZBD_OUTPUT" }
              }
            }
          }
        }
      '';
    };

    withBoth = {
      services = {
        test = {
          baseUrl = "http://example.com/api";
          headers."X-Api-Key" = "/path/to/key";
          query.format = "json";
        };
      };
      expected = builtins.fromJSON ''
        {
          "test": {
            "base": "http://example.com/api",
            "profiles": {
              "default": {
                "base": "http://example.com/api",
                "headers": { "X-Api-Key": "$HEADER_TEST_X_API_KEY" },
                "query": { "format": "$QUERY_TEST_FORMAT" }
              }
            }
          }
        }
      '';
    };

    multipleServices = {
      services = {
        prowlarr = {
          baseUrl = "http://127.0.0.1:9696/api/v1";
          headers."X-Api-Key" = "/path/to/prowlarr-key";
        };
        sonarr = {
          baseUrl = "http://127.0.0.1:8989/api/v3";
          headers."X-Api-Key" = "/path/to/sonarr-key";
        };
      };
    };
  };

  runTest = name: testCase: let
    generatedContent = generateConfig testCase.services;
    generated = ''
      {
        ${generatedContent}
      }
    '';
    parsed = builtins.fromJSON generated;
  in {
    inherit name;
    generated = generated;
    parsed = parsed;
    success =
      if testCase ? expected
      then parsed == testCase.expected
      else true;
  };

  results = lib.mapAttrs runTest testCases;
in {
  inherit results;

  allConfigs = lib.mapAttrs (name: test: test.generated) results;
  allPass = lib.all (test: test.success) (lib.attrValues results);
}
