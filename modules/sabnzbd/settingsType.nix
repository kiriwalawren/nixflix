{
  lib,
  config,
}:
let
  inherit (lib) types mkOption;
  secrets = import ../../lib/secrets { inherit lib; };
  cfg = config.nixflix.sabnzbd;
  inherit (config) nixflix;

  enumFromAttrs =
    enum_values:
    types.coercedTo (types.enum (lib.attrNames enum_values)) (name: enum_values.${name}) (
      types.enum (lib.attrValues enum_values)
    );

  serverType = types.submodule {
    freeformType = types.anything;
    options = {
      name = mkOption {
        type = types.str;
        example = "Example News Provider";
        description = "The name of the server.";
      };
      displayname = mkOption {
        type = types.str;
        default = "";
        example = "Example News Provider";
        description = "Human-friendly description of the server.";
      };
      host = mkOption {
        type = types.str;
        example = "news.example.com";
        description = "Hostname of the server.";
      };
      port = mkOption {
        type = types.port;
        default = 563;
        example = 443;
        description = "Port of the server.";
      };
      username = secrets.mkSecretOption {
        description = "Username for server authentication.";
      };
      password = secrets.mkSecretOption {
        description = "Password for server authentication.";
      };
      connections = mkOption {
        type = types.int;
        default = 10;
        example = 50;
        description = "Number of parallel connections permitted by the server.";
      };
      timeout = mkOption {
        type = types.int;
        default = 60;
        description = "Time, in seconds, to wait for a response before attempting error recovery.";
      };
      ssl = mkOption {
        type = types.bool;
        default = true;
        description = "Whether the server supports TLS.";
      };
      ssl_verify = mkOption {
        type = enumFromAttrs {
          "none" = 0;
          "allow injection" = 2;
          "strict" = 3;
        };
        default = 2;
        description = "Certificate verification level.";
      };
      priority = mkOption {
        type = types.int;
        default = 0;
        description = "Priority of this server. Servers are queried in order of priority, from highest (0) to lowest (100).";
      };
      optional = mkOption {
        type = types.bool;
        default = false;
        description = "In case of connection failures, temporarily disable this server.";
      };
      required = mkOption {
        type = types.bool;
        default = false;
        description = "In case of connection failures, wait for the server to come back online instead of skipping it.";
      };
      backup = mkOption {
        type = types.bool;
        default = false;
        description = "Use this server as a backup/fill server.";
      };
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable this server by default.";
      };
      retention = mkOption {
        type = types.int;
        default = 0;
        description = "Server retention in days (0 = unknown).";
      };
      expire_date = mkOption {
        type = types.str;
        default = "";
        description = "If notifications are enabled and an expiry date is set, warn 5 days before expiry.";
      };
    };
  };

  categoryType = types.submodule {
    freeformType = types.anything;
    options = {
      name = mkOption {
        type = types.str;
        description = "Category name";
      };
      dir = mkOption {
        type = types.str;
        default = "";
        description = "Directory name for this category";
      };
      priority = mkOption {
        type = types.int;
        default = 0;
        description = "Category priority";
      };
      pp = mkOption {
        type = enumFromAttrs {
          "Default" = "";
          "Download" = 0;
          "Repair" = 1;
          "Repair+Unpack" = 2;
          "Repair+Unpack+Delete" = 3;
        };
        default = 3;
        description = "Post-processing level";
      };
      script = mkOption {
        type = types.str;
        default = "None";
        description = "Post-processing script";
      };
    };
  };

  miscType = types.submodule {
    freeformType = types.anything;
    options = {
      host = mkOption {
        type = types.str;
        default = "127.0.0.1";
        example = "0.0.0.0";
        description = "Address for the Web UI to listen on for incoming connections.";
      };

      host_whitelist = mkOption {
        type = types.str;
        default = if nixflix.nginx.enable then "sabnzbd.localhost" else "";
        defaultText = lib.literalExpression ''if nixflix.nginx.enable then "sabnzbd.localhost" else ""'';
        description = ''
          Hostname verification whitelist. SABnzbd refuses connections from hostnames not in this list.
          Automatically includes `sabnzbd.localhost` when nginx is enabled.
        '';
      };

      api_key = secrets.mkSecretOption {
        description = "API key for SABnzbd.";
      };

      nzb_key = secrets.mkSecretOption {
        description = "NZB key for adding downloads via URL.";
      };

      port = mkOption {
        type = types.port;
        default = 8080;
        example = 12345;
        description = "Port for the Web UI to listen on for incoming connections.";
      };

      url_base = mkOption {
        type = types.str;
        default = "";
        description = ''
          When using a reverse proxy (or just if you feel like it), you can change the base-URL of SABnzbd that is used during redirects.
          Trailing slash is not allowed. Leading slash is required unless the base URL is an empty string.
          SABnzbd will forcefully restart after changing this setting, you will need to reload the page after the restart completes.
        '';
      };

      https_port = mkOption {
        type = types.port;
        default = 0;
        description = "HTTPS port for the Web UI (0 to disable HTTPS).";
      };

      enable_https = mkOption {
        type = types.bool;
        default = false;
        description = "Whether to enable HTTPS for the web UI.";
      };

      https_cert = mkOption {
        type = types.str;
        default = "";
        example = lib.literalExpression ''config.security.acme.certs."example.com".directory + "/fullchain.pem"'';
        description = "Path to the TLS certificate for the web UI. If not set and HTTPS is enabled, a self-signed certificate is generated.";
      };

      https_key = mkOption {
        type = types.str;
        default = "";
        example = lib.literalExpression ''config.security.acme.certs."example.com".directory + "/key.pem"'';
        description = "Path to the TLS key for the web UI. If not set and HTTPS is enabled, a self-signed key is generated.";
      };

      bandwidth_max = mkOption {
        type = types.str;
        default = "";
        example = "50MB/s";
        description = "Maximum bandwidth in bytes/sec (supports prefixes). Use in conjunction with bandwidth_perc.";
      };

      bandwidth_perc = mkOption {
        type = types.int;
        default = 0;
        example = 50;
        description = "Percentage of bandwidth_max that SABnzbd is allowed to use. 0 means no limit.";
      };

      html_login = mkOption {
        type = types.bool;
        default = true;
        description = ''
          HTML based login form, uncheck for basic authentication.
          Both offer similar security but password managers might not be able to fill basic authentication automatically.
        '';
      };

      inet_exposure = mkOption {
        type = enumFromAttrs {
          none = 0;
          "api (add nzbs)" = 1;
          "api (no config)" = 2;
          "api (full)" = 3;
          "api+web (auth needed)" = 4;
          "api+web (locally no auth)" = 5;
        };
        default = 0;
        description = "Controls access restrictions from non-local IP addresses.";
      };

      email_endjob = mkOption {
        type = enumFromAttrs {
          never = 0;
          always = 1;
          "on error" = 2;
        };
        default = 0;
        description = "Whether to send emails on job completion.";
      };

      email_full = mkOption {
        type = types.bool;
        default = false;
        description = "Whether to send alerts for full disks.";
      };

      email_rss = mkOption {
        type = types.bool;
        default = false;
        description = "Whether to send alerts for jobs added by RSS feeds.";
      };

      email_server = mkOption {
        type = types.str;
        default = "";
        description = "SMTP server for email alerts (server:port format).";
      };

      email_to = mkOption {
        type = types.str;
        default = "";
        description = "Receiving address for email alerts.";
      };

      email_from = mkOption {
        type = types.str;
        default = "";
        description = "'From:' field for emails (needs to be an address).";
      };

      email_account = mkOption {
        type = types.str;
        default = "";
        description = "Username for SMTP authentication.";
      };

      email_pwd = secrets.mkSecretOption {
        default = "";
        description = "Password for SMTP authentication.";
      };

      web_dir = mkOption {
        type = types.str;
        default = "Glitter";
        description = "Web interface theme.";
      };

      web_color = mkOption {
        type = types.str;
        default = "Gold";
        description = "Web interface color scheme.";
      };

      language = mkOption {
        type = types.str;
        default = "en";
        description = "Interface language.";
      };

      permissions = mkOption {
        type = types.str;
        default = "775";
        description = "File permissions for downloaded files";
      };

      propagation_delay = mkOption {
        type = types.int;
        default = 0;
        description = ''
          Posts will be pause until they are at least this age.
          Setting job priority to Force will skip the delay.
        '';
      };

      download_dir = mkOption {
        type = types.str;
        default = "${cfg.downloadsDir}/incomplete";
        defaultText = lib.literalExpression ''nixflix.sabnzbd.downloadsDir + "/incomplete"'';
        description = "Incomplete downloads directory";
      };

      complete_dir = mkOption {
        type = types.str;
        default = "${cfg.downloadsDir}/complete";
        defaultText = lib.literalExpression ''nixflix.sabnzbd.downloadsDir + "/complete"'';
        description = "Complete downloads directory";
      };

      dirscan_dir = mkOption {
        type = types.str;
        default = "${cfg.downloadsDir}/watch";
        defaultText = lib.literalExpression ''nixflix.sabnzbd.downloadsDir + "/watch"'';
        description = "Directory to watch for NZB files";
      };

      dirscan_speed = mkOption {
        type = types.int;
        default = 5;
        description = "Directory scan speed in seconds";
      };

      nzb_backup_dir = mkOption {
        type = types.str;
        default = "${cfg.downloadsDir}/nzb-backup";
        defaultText = lib.literalExpression ''nixflix.sabnzbd.downloadsDir + "/nzb-backup"'';
        description = "NZB backup directory";
      };

      admin_dir = mkOption {
        type = types.str;
        default = "${cfg.downloadsDir}/admin";
        defaultText = lib.literalExpression ''nixflix.sabnzbd.downloadsDir + "/admin"'';
        description = "Admin directory";
      };

      log_dir = mkOption {
        type = types.str;
        default = "${cfg.downloadsDir}/logs";
        defaultText = lib.literalExpression ''nixflix.sabnzbd.downloadsDir + "/logs"'';
        description = "Log directory";
      };

      ignore_samples = mkOption {
        type = types.bool;
        default = false;
        description = "Ignore sample files";
      };

      top_only = mkOption {
        type = types.bool;
        default = true;
        description = "Only get articles from top of queue";
      };

      pre_check = mkOption {
        type = types.bool;
        default = true;
        description = "Check before download";
      };

      direct_unpack = mkOption {
        type = types.bool;
        default = true;
        description = "Unpack during download";
      };

      fail_on_crc = mkOption {
        type = types.bool;
        default = true;
        description = "Fail on CRC errors";
      };

      ignore_unrar_errors = mkOption {
        type = types.bool;
        default = false;
        description = "Ignore unrar errors";
      };

      allow_incomplete_nzb = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Sometimes you get an incomplete NZB file (partial content, incorrect syntax etc.)
          You can enable this option to allow SABnzbd to salvage as much as possible from the NZB.
          The job will enter the queue in paused mode.
        '';
      };

      enable_all_par = mkOption {
        type = types.bool;
        default = false;
        description = "Download all par2 files";
      };

      action_on_unwanted_extensions = mkOption {
        type = types.int;
        default = 1;
        description = "Action on unwanted extensions (0=None, 1=Abort, 2=Delete)";
      };

      no_smart_dupes = mkOption {
        type = types.int;
        default = 4;
        description = "Smart duplicate detection";
      };

      auto_sort = mkOption {
        type = types.str;
        default = "";
        description = "Automatically sort queue";
      };

      fail_hopeless_jobs = mkOption {
        type = types.bool;
        default = true;
        description = "Abort jobs that cannot be completed";
      };

      pause_on_pwrar = mkOption {
        type = types.int;
        default = 1;
        description = "Action when encrypted RAR is downloaded";
      };

      unwanted_extensions = mkOption {
        type = types.str;
        default = "";
        description = "Unwanted extensions";
      };

      unwanted_extensions_mode = mkOption {
        type = types.int;
        default = 0;
        description = "Unwanted extension mode (0=Blacklist, 1=Whitelist";
      };

      safe_postproc = mkOption {
        type = types.bool;
        default = true;
        description = "Post process only verified jobs";
      };

      sfv_check = mkOption {
        type = types.bool;
        default = true;
        description = "Enable SFV-based checks";
      };

      enable_recursive = mkOption {
        type = types.bool;
        default = true;
        description = "Enable recursive unpacking";
      };

      deobfuscate_final_filenames = mkOption {
        type = types.bool;
        default = true;
        description = "Deobfuscate final filenames";
      };

      flat_unpack = mkOption {
        type = types.bool;
        default = true;
        description = "Ignore any folders inside archives";
      };

      check_new_rel = mkOption {
        type = types.bool;
        default = true;
        description = "Check for new releases";
      };

      nomedia = mkOption {
        type = types.bool;
        default = true;
        description = "Create .nomedia files";
      };

      enable_par_cleanup = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Normally SABnzbd will clean up par2 files after verify/repair. You can disable this by using 0.
          Disabling this will also force all par2 files to be downloaded.
        '';
      };

      reorder_files = mkOption {
        type = types.bool;
        default = true;
        description = "Reorder files for optimal unpacking";
      };

      article_tries = mkOption {
        type = types.int;
        default = 3;
        description = "Number of attempts per article";
      };

      connection_limit = mkOption {
        type = types.int;
        default = 100;
        description = "Maximum number of connections";
      };

      cache_limit = mkOption {
        type = types.str;
        default = "512M";
        example = "500M";
        description = "Size of the RAM cache, in bytes (prefixes supported). SABnzbd recommends 25% of available RAM.";
      };

      pause_on_post_processing = mkOption {
        type = types.bool;
        default = false;
        description = "Pause download during post-processing";
      };

      pause_on_failure = mkOption {
        type = types.bool;
        default = false;
        description = "Pause queue on download failure";
      };

      retry_on_failure = mkOption {
        type = types.bool;
        default = true;
        description = "Retry failed downloads";
      };

      warn_dupl_jobs = mkOption {
        type = types.bool;
        default = true;
        description = "Warn about duplicate jobs";
      };

      max_queue_size = mkOption {
        type = types.int;
        default = 3000;
        description = "Maximum queue size";
      };

      warn_empty_nzb = mkOption {
        type = types.bool;
        default = true;
        description = "Warn about empty NZB files";
      };

      keep_awake = mkOption {
        type = types.bool;
        default = false;
        description = "Disable to stop SABnzbd's attempts to keep the system awake while the queue isn't empty.";
      };

      require_modern_tls = mkOption {
        type = types.bool;
        default = true;
        description = "Require modern TLS";
      };

      enable_https_verification = mkOption {
        type = types.bool;
        default = true;
        description = "Enable HTTPS certificate verification";
      };

      disable_api_key = mkOption {
        type = types.bool;
        default = false;
        description = "Disable API key requirement";
      };

      anon_redirect = mkOption {
        type = types.bool;
        default = false;
        description = "Anonymous redirect";
      };

      enable_log_rotate = mkOption {
        type = types.bool;
        default = true;
        description = "Enable log rotation";
      };

      max_log_size = mkOption {
        type = types.str;
        default = "10M";
        description = "Maximum log file size";
      };

      log_level = mkOption {
        type = types.int;
        default = 1;
        description = "Log level (0=None, 1=Info, 2=Debug)";
      };

      enable_debug = mkOption {
        type = types.bool;
        default = false;
        description = "Enable debug logging";
      };
    };
  };
in
types.submodule {
  freeformType = types.anything;
  options = {
    misc = mkOption {
      type = miscType;
      default = { };
      description = "SABnzbd [misc] section settings";
    };

    servers = mkOption {
      type = types.listOf serverType;
      default = [ ];
      description = "List of usenet servers";
    };

    categories = mkOption {
      type = types.listOf categoryType;
      default =
        lib.optional (nixflix.radarr.enable or false) {
          name = "radarr";
          dir = "radarr";
          priority = 0;
          pp = 3;
          script = "None";
        }
        ++ lib.optional (nixflix.sonarr.enable or false) {
          name = "sonarr";
          dir = "sonarr";
          priority = 0;
          pp = 3;
          script = "None";
        }
        ++ lib.optional (nixflix.sonarr-anime.enable or false) {
          name = "sonarr-anime";
          dir = "sonarr-anime";
          priority = 0;
          pp = 3;
          script = "None";
        }
        ++ lib.optional (nixflix.lidarr.enable or false) {
          name = "lidarr";
          dir = "lidarr";
          priority = 0;
          pp = 3;
          script = "None";
        }
        ++ lib.optional (nixflix.prowlarr.enable or false) {
          name = "prowlarr";
          dir = "prowlarr";
          priority = 0;
          pp = 3;
          script = "None";
        }
        ++ [
          {
            name = "*";
            priority = 0;
            pp = 3;
            script = "None";
          }
        ];
      defaultText = lib.literalExpression ''
        lib.optional (nixflix.radarr.enable or false) {
          name = "radarr"; dir = "radarr"; priority = 0; pp = 3; script = "None";
        }
        ++ lib.optional (nixflix.sonarr.enable or false) {
          name = "sonarr"; dir = "sonarr"; priority = 0; pp = 3; script = "None";
        }
        ++ lib.optional (nixflix.sonarr-anime.enable or false) {
          name = "sonarr-anime"; dir = "sonarr-anime"; priority = 0; pp = 3; script = "None";
        }
        ++ lib.optional (nixflix.lidarr.enable or false) {
          name = "lidarr"; dir = "lidarr"; priority = 0; pp = 3; script = "None";
        }
        ++ lib.optional (nixflix.prowlarr.enable or false) {
          name = "prowlarr"; dir = "prowlarr"; priority = 0; pp = 3; script = "None";
        }
        ++ [
          { name = "*"; priority = 0; pp = 3; script = "None"; }
        ]
      '';
      example = lib.literalExpression ''
        [
          {
            name = "radarr";
            dir = "radarr";
            priority = 0;
            pp = 3;
            script = "None";
          }
          {
            name = "sonarr";
            dir = "sonarr";
            priority = 0;
            pp = 3;
            script = "None";
          }
        ]
      '';
      description = ''
        Download categories. By default, categories are automatically created based on enabled services,
        using the service name as the category name (radarr, sonarr, sonarr-anime, lidarr, prowlarr).

        A catch-all "*" category is always included.
      '';
    };
  };
}
