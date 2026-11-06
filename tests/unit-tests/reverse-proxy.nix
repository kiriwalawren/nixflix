{
  pkgs,
  lib,
  evalConfig,
  check,
  ...
}:
{
  # Shared cert options apply to every nixflix vhost (#332)
  reverse-proxy-custom-certificate =
    let
      prowlarr = {
        enable = true;
        config = {
          hostConfig = {
            port = 9696;
            username = "admin";
            password._secret = "/run/secrets/prowlarr-pass";
          };
          apiKey._secret = "/run/secrets/prowlarr-api";
        };
      };
      nginxConfig = evalConfig [
        {
          nixflix = {
            enable = true;
            inherit prowlarr;
            nginx = {
              enable = true;
              forceSSL = true;
              sslCertificate._secret = "/run/secrets/cert";
              sslCertificateKey._secret = "/run/secrets/key";
            };
          };
        }
      ];
      caddyConfig = evalConfig [
        {
          nixflix = {
            enable = true;
            inherit prowlarr;
            caddy = {
              enable = true;
              tls = {
                enable = true;
                certFile._secret = "/run/secrets/cert";
                keyFile._secret = "/run/secrets/key";
              };
            };
          };
        }
      ];
      plainConfig = evalConfig [
        {
          nixflix = {
            enable = true;
            inherit prowlarr;
            caddy = {
              enable = true;
              tls = {
                enable = true;
                certFile = "PLAIN-CERT";
                keyFile._secret = "/run/secrets/key";
              };
            };
          };
        }
      ];
      plainCertPath = plainConfig.config.nixflix.caddy.tls.certFilePath;
      nixflixVhosts = lib.filterAttrs (name: _: lib.hasSuffix ".nixflix" name);
      nginxVhosts = lib.attrValues (nixflixVhosts nginxConfig.config.services.nginx.virtualHosts);
      caddyVhosts = lib.attrValues (nixflixVhosts caddyConfig.config.services.caddy.virtualHosts);
    in
    pkgs.runCommand "unit-test-reverse-proxy-custom-certificate" { } ''
      ${check "nginx has nixflix vhosts" (nginxVhosts != [ ])}
      ${check "nginx vhosts use custom certificate" (
        lib.all (
          v: v.sslCertificate == "/run/secrets/cert" && v.sslCertificateKey == "/run/secrets/key"
        ) nginxVhosts
      )}
      ${check "caddy has nixflix vhosts" (caddyVhosts != [ ])}
      ${check "caddy vhosts use custom certificate" (
        lib.all (v: lib.hasInfix "tls /run/secrets/cert /run/secrets/key" v.extraConfig) caddyVhosts
      )}
      ${check "caddy vhosts do not use internal CA" (
        !(lib.any (v: lib.hasInfix "tls internal" v.extraConfig) caddyVhosts)
      )}
      ${check "plain certificate is written to the Nix store" (
        lib.hasPrefix builtins.storeDir plainCertPath
      )}
      grep -qx PLAIN-CERT ${plainCertPath} || { echo 'FAIL: plain certificate file has wrong content'; exit 1; }
      echo 'PASS: plain certificate file has its content'
      echo 'PASS: reverse-proxy-custom-certificate' > $out
    '';

  reverse-proxy-assertions =
    let
      failedFor =
        proxy:
        map (a: a.message) (
          builtins.filter (a: !a.assertion)
            (evalConfig [
              {
                nixflix = {
                  enable = true;
                }
                // proxy;
              }
            ]).config.assertions
        );
      fires = msg: proxy: builtins.elem msg (failedFor proxy);
      noneFire = proxy: builtins.all (msg: !(fires msg proxy)) (lib.attrValues msgs);

      msgs = {
        exclusiveProxies = "nixflix.nginx.enable and nixflix.caddy.enable are mutually exclusive. Choose one reverse proxy.";
        nginxPair = "nixflix.nginx.sslCertificate and nixflix.nginx.sslCertificateKey must be set together.";
        nginxAcme = "nixflix.nginx.enableACME and nixflix.nginx.sslCertificate are mutually exclusive.";
        caddyPair = "nixflix.caddy.tls.certFile and nixflix.caddy.tls.keyFile must be set together.";
        caddyTlsEnable = "nixflix.caddy.tls.certFile requires nixflix.caddy.tls.enable.";
        caddyInternal = "nixflix.caddy.tls.certFile and nixflix.caddy.tls.internal are mutually exclusive.";
      };

      cert._secret = "/run/secrets/cert";
      key._secret = "/run/secrets/key";
    in
    pkgs.runCommand "unit-test-reverse-proxy-assertions" { } ''
      ${check "nginx and caddy together fails" (
        fires msgs.exclusiveProxies {
          nginx.enable = true;
          caddy.enable = true;
        }
      )}

      ${check "nginx cert without key fails" (
        fires msgs.nginxPair {
          nginx = {
            enable = true;
            sslCertificate = cert;
          };
        }
      )}
      ${check "nginx key without cert fails" (
        fires msgs.nginxPair {
          nginx = {
            enable = true;
            sslCertificateKey = key;
          };
        }
      )}
      ${check "nginx cert with enableACME fails" (
        fires msgs.nginxAcme {
          nginx = {
            enable = true;
            enableACME = true;
            sslCertificate = cert;
            sslCertificateKey = key;
          };
        }
      )}
      ${check "nginx with cert and key passes" (noneFire {
        nginx = {
          enable = true;
          forceSSL = true;
          sslCertificate = cert;
          sslCertificateKey = key;
        };
      })}
      ${check "nginx options are ignored when nginx is disabled" (noneFire {
        nginx = {
          enableACME = true;
          sslCertificate = cert;
        };
      })}

      ${check "caddy cert without key fails" (
        fires msgs.caddyPair {
          caddy = {
            enable = true;
            tls = {
              enable = true;
              certFile = cert;
            };
          };
        }
      )}
      ${check "caddy key without cert fails" (
        fires msgs.caddyPair {
          caddy = {
            enable = true;
            tls = {
              enable = true;
              keyFile = key;
            };
          };
        }
      )}
      ${check "caddy certFile without tls.enable fails" (
        fires msgs.caddyTlsEnable {
          caddy = {
            enable = true;
            tls = {
              certFile = cert;
              keyFile = key;
            };
          };
        }
      )}
      ${check "caddy certFile with tls.internal fails" (
        fires msgs.caddyInternal {
          caddy = {
            enable = true;
            tls = {
              enable = true;
              internal = true;
              certFile = cert;
              keyFile = key;
            };
          };
        }
      )}
      ${check "caddy with tls, cert and key passes" (noneFire {
        caddy = {
          enable = true;
          tls = {
            enable = true;
            certFile = cert;
            keyFile = key;
          };
        };
      })}
      ${check "caddy options are ignored when caddy is disabled" (noneFire {
        caddy.tls = {
          internal = true;
          certFile = cert;
        };
      })}
      echo 'PASS: reverse-proxy-assertions' > $out
    '';
}
