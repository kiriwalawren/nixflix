{
  lib,
  config,
}: let
  inherit (lib) types mkOption;
  cfg = config.nixflix.sabnzbd;
  inherit (config) nixflix;

  serverType = types.submodule {
    options = {
      name = mkOption {
        type = types.str;
        description = "Server name";
      };
      host = mkOption {
        type = types.str;
        description = "Server hostname";
      };
      port = mkOption {
        type = types.port;
        default = 563;
        description = "Server port";
      };
      username = mkOption {
        type = types.str;
        description = "Server username (can use environment variable placeholder like $USERNAME)";
      };
      password = mkOption {
        type = types.str;
        description = "Server password (can use environment variable placeholder like $PASSWORD)";
      };
      connections = mkOption {
        type = types.int;
        default = 10;
        description = "Number of connections";
      };
      ssl = mkOption {
        type = types.bool;
        default = true;
        description = "Use SSL";
      };
      priority = mkOption {
        type = types.int;
        default = 0;
        description = "Server priority (0 = highest)";
      };
      optional = mkOption {
        type = types.bool;
        default = false;
        description = "Server is optional";
      };
      backup = mkOption {
        type = types.bool;
        default = false;
        description = "Server is backup/fill server";
      };
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable this server";
      };
      retention = mkOption {
        type = types.int;
        default = 0;
        description = "Server retention in days (0 = unknown)";
      };
    };
  };

  categoryType = types.submodule {
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
        type = types.int;
        default = 3;
        description = "Post-processing level (0=None, 1=Repair, 2=Repair+Unpack, 3=Repair+Unpack+Delete)";
      };
      script = mkOption {
        type = types.str;
        default = "None";
        description = "Post-processing script";
      };
    };
  };
in
  types.submodule {
    options = {
      host = mkOption {
        type = types.str;
        default = "127.0.0.1";
        description = "Host to bind to";
      };

      port = mkOption {
        type = types.port;
        default = 8080;
        description = "Port to listen on";
      };

      url_base = mkOption {
        type = types.str;
        default =
          if nixflix.nginx.enable
          then "/sabnzbd"
          else "/";
        defaultText = lib.literalExpression ''if nixflix.nginx.enable then "/sabnzbd" else "/"'';
        description = "URL base path for the web interface";
      };

      https_port = mkOption {
        type = types.port;
        default = 0;
        description = "HTTPS port (0 to disable)";
      };

      enable_https = mkOption {
        type = types.bool;
        default = false;
        description = "Enable HTTPS";
      };

      web_dir = mkOption {
        type = types.str;
        default = "Glitter";
        description = "Web interface theme";
      };

      web_color = mkOption {
        type = types.str;
        default = "Gold";
        description = "Web interface color scheme";
      };

      language = mkOption {
        type = types.str;
        default = "en";
        description = "Interface language";
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
        description = "Allow incomplete NZB files";
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
        description = "Delete par2 files after verification";
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
        description = "Article cache limit";
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
        description = "Keep system awake during downloads";
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

      servers = mkOption {
        type = types.listOf serverType;
        default = [];
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
