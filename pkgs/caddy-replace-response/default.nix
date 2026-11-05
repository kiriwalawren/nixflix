{ caddy, fetchFromGitHub }:
caddy.overrideAttrs (
  finalAttrs: prevAttrs: {
    version = "2.11.9";
    __intentionallyOverridingVersion = true;

    src = ./src;
    vendorHash = "sha256-Lgq705mAASpDRykm2mkCvqT4BjOOM3kmrvWZ8C605tA=";
    subPackages = [ "." ];

    postConfigure = ''
      chmod u+w vendor/github.com/caddyserver/caddy/v2/cmd
      rm vendor/github.com/caddyserver/caddy/v2/cmd/x509rootsfallback.go
    '';

    passthru = prevAttrs.passthru // {
      dist = fetchFromGitHub {
        owner = "caddyserver";
        repo = "dist";
        tag = "v${finalAttrs.version}";
        hash = "sha256-v9VaNgkWekTPI5nt04QoyZeJRRvymK2q0o3JxygC2JA=";
      };
    };
  }
)
