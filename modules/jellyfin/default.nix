{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  inherit (config) nixflix;
  inherit (config.nixflix) globals;
  cfg = config.nixflix.jellyfin;
  stateDir = "${nixflix.stateDir}/jellyfin";

  # Convert camelCase to PascalCase
  toPascalCase = str: let
    firstChar = substring 0 1 str;
    rest = substring 1 (-1) str;
  in
    (toUpper firstChar) + rest;

  # Recursive function to convert Nix attrs to XML
  attrsToXml = indent: attrs:
    concatStringsSep "\n" (
      mapAttrsToList (name: value: let
        tagName = toPascalCase name;
        valueStr =
          if isBool value
          then
            (
              if value
              then "true"
              else "false"
            )
          else if isInt value
          then toString value
          else if isList value
          then concatStringsSep "," value
          else if isAttrs value
          then "\n${attrsToXml (indent + "  ") value}${indent}"
          else toString value;
      in
        if isAttrs value
        then "${indent}<${tagName}>${valueStr}</${tagName}>"
        else "${indent}<${tagName}>${valueStr}</${tagName}>")
      attrs
    );

  networkXmlContent = ''
    <?xml version="1.0" encoding="utf-8"?>
    <NetworkConfiguration xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema">
    ${attrsToXml "  " cfg.network}
    </NetworkConfiguration>
  '';
in {
  options.nixflix.jellyfin = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = "Whether to enable Jellyfin media server";
    };

    package = mkOption {
      type = types.package;
      default = pkgs.jellyfin;
      defaultText = literalExpression "pkgs.jellyfin";
      description = "Jellyfin package to use";
    };

    user = mkOption {
      type = types.str;
      default = "jellyfin";
      description = "User under which the service runs";
    };

    group = mkOption {
      type = types.str;
      default = globals.libraryOwner.group;
      defaultText = literalExpression "config.nixflix.globals.libraryOwner.group";
      description = "Group under which the service runs";
    };

    dataDir = mkOption {
      type = types.path;
      default = stateDir;
      defaultText = literalExpression ''"''${config.nixflix.stateDir}/jellyfin"'';
      description = "Directory containing the Jellyfin data files";
    };

    configDir = mkOption {
      type = types.path;
      default = "${stateDir}/config";
      defaultText = literalExpression ''"''${config.nixflix.stateDir}/jellyfin/config"'';
      description = ''
        Directory containing the server configuration files,
        passed with `--configdir` see [configuration-directory](https://jellyfin.org/docs/general/administration/configuration/#configuration-directory)
      '';
    };

    cacheDir = mkOption {
      type = types.path;
      default = "/var/cache/jellyfin";
      description = ''
        Directory containing the jellyfin server cache,
        passed with `--cachedir` see [#cache-directory](https://jellyfin.org/docs/general/administration/configuration/#cache-directory)
      '';
    };

    logDir = mkOption {
      type = types.path;
      default = "${stateDir}/log";
      defaultText = literalExpression ''"''${config.nixflix.stateDir}/jellyfin/log"'';
      description = ''
        Directory where the Jellyfin logs will be stored,
        passed with `--logdir` see [#log-directory](https://jellyfin.org/docs/general/administration/configuration/#log-directory)
      '';
    };

    apiKeyPath = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = ''
        Path to file containing the Jellyfin API key.
        This is optional and currently not used for configuration,
        but available for future API-based configuration enhancements.
      '';
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Open ports in the firewall for Jellyfin.
        TCP ports 8096 and 8920, UDP ports 1900 and 7359.
      '';
    };

    vpn = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Whether to route Jellyfin traffic through the VPN.
          When false (default), Jellyfin bypasses the VPN.
          When true, Jellyfin routes through the VPN (requires nixflix.mullvad.enable = true).
        '';
      };
    };

    network = {
      autoDiscovery = mkOption {
        type = types.bool;
        default = true;
        description = "Enable auto-discovery";
      };

      baseUrl = mkOption {
        type = types.str;
        default =
          if nixflix.serviceNameIsUrlBase
          then "/jellyfin"
          else "";
        defaultText = literalExpression ''if config.nixflix.serviceNameIsUrlBase then "/jellyfin" else ""'';
        description = "Base URL for Jellyfin (URL prefix)";
      };

      certificatePassword = mkOption {
        type = types.str;
        default = "";
        description = "Certificate password";
      };

      certificatePath = mkOption {
        type = types.str;
        default = "";
        description = "Path to certificate file";
      };

      enableHttps = mkOption {
        type = types.bool;
        default = false;
        description = "Enable HTTPS";
      };

      enableIPv4 = mkOption {
        type = types.bool;
        default = true;
        description = "Enable IPv4";
      };

      enableIPv6 = mkOption {
        type = types.bool;
        default = false;
        description = "Enable IPv6";
      };

      enablePublishedServerUriByRequest = mkOption {
        type = types.bool;
        default = false;
        description = "Enable published server URI by request";
      };

      enableRemoteAccess = mkOption {
        type = types.bool;
        default = true;
        description = "Enable remote access";
      };

      enableUPnP = mkOption {
        type = types.bool;
        default = false;
        description = "Enable UPnP";
      };

      ignoreVirtualInterfaces = mkOption {
        type = types.bool;
        default = true;
        description = "Ignore virtual interfaces";
      };

      internalHttpPort = mkOption {
        type = types.ints.between 0 65535;
        default = 8096;
        description = "Internal HTTP port";
      };

      internalHttpsPort = mkOption {
        type = types.ints.between 0 65535;
        default = 8920;
        description = "Internal HTTPS port";
      };

      isRemoteIPFilterBlacklist = mkOption {
        type = types.bool;
        default = false;
        description = "Is remote IP filter a blacklist";
      };

      knownProxies = mkOption {
        type = types.listOf types.str;
        default = [];
        description = "List of known proxies";
      };

      localNetworkAddresses = mkOption {
        type = types.bool;
        default = false;
        description = "Local network addresses";
      };

      localNetworkSubnets = mkOption {
        type = types.listOf types.str;
        default = [];
        description = "List of local network subnets";
      };

      publicHttpPort = mkOption {
        type = types.ints.between 0 65535;
        default = 8096;
        description = "Public HTTP port";
      };

      publicHttpsPort = mkOption {
        type = types.ints.between 0 65535;
        default = 8920;
        description = "Public HTTPS port";
      };

      publishedServerUriBySubnet = mkOption {
        type = types.listOf types.str;
        default = [];
        description = "List of published server URIs by subnet";
      };

      remoteIpFilter = mkOption {
        type = types.listOf types.str;
        default = [];
        description = "Remote IP filter list";
      };

      requireHttps = mkOption {
        type = types.bool;
        default = false;
        description = "Require HTTPS";
      };

      virtualInterfaceNames = mkOption {
        type = types.listOf types.str;
        default = ["veth"];
        description = "List of virtual interface names";
      };
    };
  };

  config = mkIf (nixflix.enable && cfg.enable) {
    assertions = [
      {
        assertion = cfg.vpn.enable -> config.nixflix.mullvad.enable;
        message = "Cannot enable VPN routing for Jellyfin (nixflix.jellyfin.vpn.enable = true) when Mullvad VPN is disabled. Please set nixflix.mullvad.enable = true.";
      }
    ];

    users.users.${cfg.user} = {
      inherit (cfg) group;
      isSystemUser = true;
      home = cfg.dataDir;
      uid = mkForce globals.uids.jellyfin;
    };

    users.groups.${cfg.group} = optionalAttrs (globals.gids ? ${cfg.group}) {
      gid = mkForce globals.gids.${cfg.group};
    };

    systemd.tmpfiles.rules = [
      "d '${cfg.dataDir}' 0750 ${cfg.user} ${cfg.group} - -"
      "d '${cfg.configDir}' 0750 ${cfg.user} ${cfg.group} - -"
      "d '${cfg.cacheDir}' 0750 ${cfg.user} ${cfg.group} - -"
      "d '${cfg.logDir}' 0750 ${cfg.user} ${cfg.group} - -"
    ];

    environment.etc."jellyfin/network.xml.template".text = networkXmlContent;

    systemd.services.jellyfin = {
      description = "Jellyfin Media Server";
      after = ["network-online.target"];
      wants = ["network-online.target"];
      wantedBy = ["multi-user.target"];

      serviceConfig =
        {
          Type = "simple";
          User = cfg.user;
          Group = cfg.group;
          WorkingDirectory = cfg.dataDir;
          Restart = "on-failure";
          TimeoutSec = 15;
          SuccessExitStatus = "0 143";

          ExecStartPre = "${pkgs.coreutils}/bin/install -m 640 /etc/jellyfin/network.xml.template '${cfg.configDir}/network.xml'";

          ExecStart =
            if (config.nixflix.mullvad.enable && !cfg.vpn.enable)
            then
              pkgs.writeShellScript "jellyfin-vpn-bypass" ''
                exec /run/wrappers/bin/mullvad-exclude ${getExe cfg.package} \
                  --datadir '${cfg.dataDir}' \
                  --configdir '${cfg.configDir}' \
                  --cachedir '${cfg.cacheDir}' \
                  --logdir '${cfg.logDir}'
              ''
            else "${getExe cfg.package} --datadir '${cfg.dataDir}' --configdir '${cfg.configDir}' --cachedir '${cfg.cacheDir}' --logdir '${cfg.logDir}'";

          NoNewPrivileges = true;
          LockPersonality = true;

          ProtectControlGroups = true;
          ProtectHostname = true;
          ProtectKernelLogs = true;
          ProtectKernelModules = true;
          ProtectKernelTunables = true;
          PrivateTmp = true;

          RestrictAddressFamilies = ["AF_UNIX" "AF_INET" "AF_INET6" "AF_NETLINK"];
          RestrictNamespaces = true;
          RestrictRealtime = true;
          RestrictSUIDSGID = true;

          # Needed for hardware acceleration
          PrivateDevices = false;
          PrivateUsers = true;
          RemoveIPC = true;

          SystemCallArchitectures = "native";
          SystemCallFilter = [
            "~@clock"
            "~@aio"
            "~@chown"
            "~@cpu-emulation"
            "~@debug"
            "~@keyring"
            "~@memlock"
            "~@module"
            "~@mount"
            "~@obsolete"
            "~@privileged"
            "~@raw-io"
            "~@reboot"
            "~@setuid"
            "~@swap"
          ];
          SystemCallErrorNumber = "EPERM";
        }
        // optionalAttrs (config.nixflix.mullvad.enable && !cfg.vpn.enable) {
          AmbientCapabilities = "CAP_SYS_ADMIN";
          Delegate = mkForce true;
        };
    };

    networking.firewall = mkIf cfg.openFirewall {
      allowedTCPPorts = [cfg.network.internalHttpPort cfg.network.internalHttpsPort];
      allowedUDPPorts = [1900 7359];
    };

    services.nginx = mkIf nixflix.nginx.enable {
      virtualHosts.localhost.locations."${cfg.network.baseUrl}" = {
        proxyPass = "http://127.0.0.1:${toString cfg.network.internalHttpPort}";
        recommendedProxySettings = true;
        extraConfig = ''
          proxy_set_header X-Forwarded-Host $host;
          proxy_set_header X-Forwarded-Server $host;
          proxy_set_header X-Forwarded-Proto $scheme;
          proxy_redirect off;

          proxy_set_header X-Real-IP $remote_addr;
          proxy_buffering off;
        '';
      };
    };
  };
}
