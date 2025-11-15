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
  xml = import ./xml.nix {inherit lib;};

  networkXmlContent = xml.mkXmlContent "NetworkConfiguration" cfg.network;
  brandingXmlContent = xml.mkXmlContent "BrandingOptions" cfg.branding;
  encodingXmlContent = xml.mkXmlContent "EncodingOptions" cfg.encoding;
  systemXmlContent = xml.mkXmlContent "ServerConfiguration" cfg.system;

  dbname = "jellyfin.db";
  dbPath = "${cfg.dataDir}/data/${dbname}";
  sq = "${pkgs.sqlite}/bin/sqlite3 \"${dbPath}\"";

  permissionKindToDBInteger = {
    isAdministrator = 0;
    isHidden = 1;
    isDisabled = 2;
    enableSharedDeviceControl = 3;
    enableRemoteAccess = 4;
    enableLiveTvManagement = 5;
    enableLiveTvAccess = 6;
    enableMediaPlayback = 7;
    enableAudioPlaybackTranscoding = 8;
    enableVideoPlaybackTranscoding = 9;
    enableContentDeletion = 10;
    enableContentDownloading = 11;
    enableSyncTranscoding = 12;
    enableMediaConversion = 13;
    enableAllDevices = 14;
    enableAllChannels = 15;
    enableAllFolders = 16;
    enablePublicSharing = 17;
    enableRemoteControlOfOtherUsers = 18;
    enablePlaybackRemuxing = 19;
    forceRemoteSourceTranscoding = 20;
    enableCollectionManagement = 21;
    enableSubtitleManagement = 22;
    enableLyricManagement = 23;
  };

  subtitleModes = {
    default = 0;
    always = 1;
    onlyForced = 2;
    none = 3;
    smart = 4;
  };

  nonDBOptions = [
    "hashedPasswordFile"
    "hashedPassword"
    "mutable"
    "permissions"
    "preferences"
    "_module"
  ];

  sqliteFormat = key: value:
    if (isBool value)
    then
      (
        if value
        then "1"
        else "0"
      )
    else if (value == null)
    then "NULL"
    else if (key == "subtitleMode")
    then toString subtitleModes.${value}
    else if (isString value)
    then "'${value}'"
    else toString value;

  genUser = index: username: userOpts: let
    userId =
      if userOpts.id != null
      then userOpts.id
      else "$(${pkgs.libuuid}/bin/uuidgen | ${pkgs.coreutils}/bin/tr '[:lower:]' '[:upper:]')";

    internalId =
      if userOpts.internalId != null
      then toString userOpts.internalId
      else "$(($maxIndex + ${toString (index + 1)}))";

    password =
      if userOpts.hashedPasswordFile != null
      then "$(${pkgs.coreutils}/bin/cat '${userOpts.hashedPasswordFile}')"
      else if userOpts.hashedPassword != null
      then userOpts.hashedPassword
      else null;

    userAttrs =
      builtins.removeAttrs
      (userOpts
        // {
          inherit username password;
        })
      (nonDBOptions ++ ["id" "internalId"]);

    dbColumns = map (name: xml.toPascalCase name) (attrNames userAttrs);
    dbValues = map (name: sqliteFormat name userAttrs.${name}) (attrNames userAttrs);
  in ''
    userExists=$(${sq} "SELECT 1 FROM Users WHERE Username = '${username}'" 2>/dev/null || echo "")
    userId="${userId}"

    if [ -n "$userExists" ]; then
      userId=$(${sq} "SELECT Id FROM Users WHERE Username = '${username}'")
      echo "User ${username} already exists with ID: $userId"
    fi

    if [ ${
      if userOpts.mutable
      then "-z \"$userExists\""
      else "-n \"true\""
    } ]; then
      if [ -z "$userExists" ]; then
        echo "INSERT INTO Users (${concatStringsSep ", " dbColumns}, InternalId, Id) VALUES(${concatStringsSep ", " dbValues}, ${internalId}, '$userId');" >> "$dbcmds"
      else
        echo "UPDATE Users SET ${
      concatStringsSep ", " (
        map (
          name: "${xml.toPascalCase name} = ${sqliteFormat name userAttrs.${name}}"
        ) (attrNames userAttrs)
      )
    } WHERE Username = '${username}';" >> "$dbcmds"
      fi

      ${concatStringsSep "\n" (
      mapAttrsToList (
        permission: enabled: ''
          echo "REPLACE INTO Permissions (Kind, Value, UserId, Permission_Permissions_Guid, RowVersion) VALUES(${
            toString permissionKindToDBInteger.${permission}
          }, ${
            if enabled
            then "1"
            else "0"
          }, '$userId', NULL, 0);" >> "$dbcmds"
        ''
      )
      userOpts.permissions
    )}
    fi
  '';

  usersSetupScript =
    if (cfg.users == {})
    then ""
    else let
      usernames = attrNames cfg.users;
      userList = map (index: genUser index (elemAt usernames index) cfg.users.${elemAt usernames index}) (range 0 ((length usernames) - 1));
    in
      concatStringsSep "\n" userList;
in {
  imports = [
    ./options
  ];

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
      "d '${cfg.system.metadataPath}' 0750 ${cfg.user} ${cfg.group} - -"
      "d '${cfg.dataDir}/data' 0750 ${cfg.user} ${cfg.group} - -"
    ];

    environment.etc = {
      "jellyfin/network.xml.template".text = networkXmlContent;
      "jellyfin/branding.xml.template".text = brandingXmlContent;
      "jellyfin/encoding.xml.template".text = encodingXmlContent;
      "jellyfin/system.xml.template".text = systemXmlContent;
    };

    systemd.services.jellyfin = {
      description = "Jellyfin Media Server";
      after = ["network-online.target"];
      wants = ["network-online.target"];
      wantedBy = ["multi-user.target"];

      restartTriggers = [
        networkXmlContent
        brandingXmlContent
        encodingXmlContent
        systemXmlContent
      ];

      serviceConfig =
        {
          Type = "simple";
          User = cfg.user;
          Group = cfg.group;
          WorkingDirectory = cfg.dataDir;
          Restart = "on-failure";
          TimeoutSec = 15;
          SuccessExitStatus = "0 143";

          ExecStartPre = pkgs.writeShellScript "jellyfin-setup-config" ''
            set -eu

            ${pkgs.coreutils}/bin/install -m 640 /etc/jellyfin/network.xml.template '${cfg.configDir}/network.xml'
            ${pkgs.coreutils}/bin/install -m 640 /etc/jellyfin/branding.xml.template '${cfg.configDir}/branding.xml'
            ${pkgs.coreutils}/bin/install -m 640 /etc/jellyfin/encoding.xml.template '${cfg.configDir}/encoding.xml'
            ${pkgs.coreutils}/bin/install -m 640 /etc/jellyfin/system.xml.template '${cfg.configDir}/system.xml'

            ${optionalString cfg.system.isStartupWizardCompleted ''
              if [ ! -f "${cfg.configDir}/migrations.xml" ]; then
                echo "First run detected - generating migrations.xml"
                ${pkgs.xmlstarlet}/bin/xmlstarlet ed -L -u "//IsStartupWizardCompleted" -v "false" '${cfg.configDir}/system.xml'

                ${getExe cfg.package} --datadir '${cfg.dataDir}' --configdir '${cfg.configDir}' --cachedir '${cfg.cacheDir}' --logdir '${cfg.logDir}' &
                JELLYFIN_PID=$!

                echo "Waiting for migrations.xml to be generated..."
                until [ -f "${cfg.configDir}/migrations.xml" ]; do
                  sleep 1
                done
                sleep 3

                echo "Stopping temporary Jellyfin instance..."
                kill -15 $JELLYFIN_PID || true
                wait $JELLYFIN_PID || true

                echo "Restoring IsStartupWizardCompleted to true"
                ${pkgs.xmlstarlet}/bin/xmlstarlet ed -L -u "//IsStartupWizardCompleted" -v "true" '${cfg.configDir}/system.xml'
              fi
            ''}

            ${optionalString (cfg.users != {}) ''
              if [ ! -e "${dbPath}" ]; then
                echo "Database does not exist, starting Jellyfin to create it..."
                ${getExe cfg.package} --datadir '${cfg.dataDir}' --configdir '${cfg.configDir}' --cachedir '${cfg.cacheDir}' --logdir '${cfg.logDir}' &
                JELLYFIN_PID=$!

                echo "Waiting for database to be created..."
                until [ -f "${dbPath}" ]; do
                  sleep 1
                done
                sleep 3

                echo "Stopping Jellyfin..."
                kill -15 $JELLYFIN_PID || true
                wait $JELLYFIN_PID || true
              fi

              dbcmds=$(${pkgs.coreutils}/bin/mktemp)
              trap "${pkgs.coreutils}/bin/rm -f $dbcmds" EXIT

              echo "BEGIN TRANSACTION;" > "$dbcmds"

              maxIndex=$(${sq} 'SELECT InternalId FROM Users ORDER BY InternalId DESC LIMIT 1' 2>/dev/null || echo "0")
              if [ -z "$maxIndex" ]; then
                maxIndex="0"
              fi

              ${usersSetupScript}

              echo "COMMIT TRANSACTION;" >> "$dbcmds"
              echo "Executing user setup SQL..."
              ${pkgs.sqlite}/bin/sqlite3 "${dbPath}" < "$dbcmds"
            ''}
          '';

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
          SystemCallFilter = mkForce [];
          NoNewPrivileges = mkForce false;
          ProtectControlGroups = mkForce false;
        };
    };

    networking.firewall = mkIf cfg.openFirewall {
      allowedTCPPorts = [cfg.network.internalHttpPort cfg.network.internalHttpsPort];
      allowedUDPPorts = [1900 7359];
    };

    services.nginx = mkIf nixflix.nginx.enable {
      virtualHosts.localhost.locations = {
        "${cfg.network.baseUrl}" = {
          proxyPass = "http://127.0.0.1:${toString cfg.network.internalHttpPort}";
          recommendedProxySettings = true;
          extraConfig = ''
            proxy_redirect off;

            proxy_set_header X-Real-IP $remote_addr;
            proxy_buffering off;
          '';
        };
        "${cfg.network.baseUrl}/socket" = {
          proxyPass = "http://127.0.0.1:${toString cfg.network.internalHttpPort}";
          recommendedProxySettings = true;
          extraConfig = ''
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";
          '';
        };
      };
    };
  };
}
