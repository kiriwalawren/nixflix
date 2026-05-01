{
  lib,
  config,
}:
let
  cfg = config.nixflix;

  # --- Caddy helpers ---
  inherit (cfg.caddy) tls;
  tlsDirective = if tls.enable && tls.internal then "tls internal" else "";

  # When TLS is disabled, prefix with http:// to prevent Caddy from
  # automatically enabling HTTPS. "tls off" is not valid Caddyfile syntax.
  caddyHostPrefix = if !tls.enable then "http://" else "";

  # --- Shared theme.park helpers ---
  themeParkUrl = service: "https://theme-park.dev/css/base/${service}/${cfg.theme.name}.css";

  # Services that inject the stylesheet into <head> instead of <body>
  themeParkTags = {
    overseerr = "</head>";
    sabnzbd = "</head>";
  };

  mkNginxVirtualHost =
    {
      port,
      upstreamHost ? "127.0.0.1",
      themeParkService ? null,
      extraConfig ? "",
      stripHeaders ? [ ],
      websocketUpgrade ? false,
      disableBuffering ? false,
    }:
    let
      themeParkTag =
        if themeParkService == null then "</body>" else themeParkTags.${themeParkService} or "</body>";
      themeConfig = lib.optionalString (themeParkService != null && cfg.theme.enable) ''
        proxy_set_header Accept-Encoding "";
        sub_filter '${themeParkTag}' '<link rel="stylesheet" type="text/css" href="${themeParkUrl themeParkService}">${themeParkTag}';
        sub_filter_once on;
      '';
      hideHeaders = lib.concatMapStringsSep "\n" (h: ''proxy_hide_header "${h}";'') stripHeaders;
      bufferingConfig = lib.optionalString disableBuffering ''
        proxy_buffering off;
      '';
    in
    lib.mkIf cfg.nginx.enable {
      inherit (cfg.nginx) forceSSL;
      useACMEHost = if cfg.nginx.enableACME then cfg.nginx.domain else null;

      locations."/" = {
        proxyPass = "http://${upstreamHost}:${toString port}";
        recommendedProxySettings = true;
        proxyWebsockets = websocketUpgrade;
        extraConfig = ''
          proxy_redirect off;
          ${bufferingConfig}
          ${hideHeaders}
          ${themeConfig}
          ${extraConfig}
        '';
      };
    };

  mkCaddyVirtualHost =
    {
      port,
      upstreamHost ? "127.0.0.1",
      themeParkService ? null,
      extraConfig ? "",
      stripHeaders ? [ ],
      disableBuffering ? false,
    }:
    let
      themeParkTag =
        if themeParkService == null then "</body>" else themeParkTags.${themeParkService} or "</body>";
    in
    lib.mkIf cfg.caddy.enable {
      extraConfig = ''
        ${tlsDirective}

        reverse_proxy http://${upstreamHost}:${toString port} ${lib.optionalString disableBuffering ''
          {
            flush_interval -1
          }
        ''}

        ${lib.concatMapStringsSep "\n" (h: "header_down -${h}") stripHeaders}

        ${lib.optionalString (themeParkService != null && cfg.theme.enable) ''
          replace {
            ${themeParkTag} "<link rel=\"stylesheet\" type=\"text/css\" href=\"${themeParkUrl themeParkService}\">${themeParkTag}"
          }
          header_up -Accept-Encoding
        ''}

        ${extraConfig}
      '';
    };
in
{
  ## Returns a NixOS config fragment with nginx, caddy, and hosts entries
  ## for a single reverse-proxied service.
  mkVirtualHost =
    {
      hostname,
      expose,
      port,
      upstreamHost ? "127.0.0.1",
      themeParkService ? null,
      extraConfig ? "",
      stripHeaders ? [ ],
      websocketUpgrade ? false,
      disableBuffering ? false,
    }:
    let
      proxyArgs = {
        inherit
          port
          upstreamHost
          themeParkService
          extraConfig
          stripHeaders
          disableBuffering
          ;
      };
    in
    {
      services.nginx.virtualHosts.${hostname} = lib.mkIf expose (
        mkNginxVirtualHost (proxyArgs // { inherit websocketUpgrade; })
      );

      services.caddy.virtualHosts."${caddyHostPrefix}${hostname}" = lib.mkIf expose (
        mkCaddyVirtualHost proxyArgs
      );

      networking.hosts = lib.mkIf (
        expose && cfg.reverseProxy.enable && cfg.reverseProxy.addHostsEntries
      ) { "127.0.0.1" = [ hostname ]; };
    };
}
