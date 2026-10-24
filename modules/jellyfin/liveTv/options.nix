{ lib, ... }:
with lib;
let
  secrets = import ../../../lib/secrets { inherit lib; };

  # Tuner/provider fields Jellyfin stores as plain values. No nulls: Jellyfin
  # omits null fields from what it returns, so a declared null would never
  # compare equal and every run would rewrite the tuner.
  settingValue = types.oneOf [
    types.bool
    types.int
    types.str
    (types.listOf types.str)
  ];

  tunerModule = types.submodule (
    { name, ... }: {
      options = {
        url = secrets.mkSecretOption {
          type = types.nonEmptyStr;
          example = "/var/lib/iptv/channels.m3u";
          description = ''
            The M3U playlist: a local file path or an http(s) URL. This is how
            Jellyfin identifies the tuner, so changing it replaces the tuner
            (its channels get new ids). Use `{ _secret = path; }` for a
            provider URL that carries credentials.
          '';
        };

        friendlyName = mkOption {
          type = types.str;
          default = name;
          defaultText = literalExpression "<name>";
          description = "Name of the tuner in Jellyfin's Live TV settings.";
        };

        settings = mkOption {
          type = types.attrsOf settingValue;
          default = { };
          example = literalExpression ''
            {
              tunerCount = 0;
              allowStreamSharing = true;
              enableStreamLooping = true;
              ignoreDts = true;
              readAtNativeFramerate = true;
              userAgent = "Mozilla/5.0";
            }
          '';
          description = ''
            Further `TunerHostInfo` fields, in camelCase (converted to Jellyfin's
            PascalCase). Fields not set here keep the value Jellyfin already
            holds. `type`, `url` and `friendlyName` are set by the options
            above.
          '';
        };
      };
    }
  );

  listingProviderModule = types.submodule {
    options = {
      path = secrets.mkSecretOption {
        type = types.nonEmptyStr;
        example = "/var/lib/iptv/guide.xml";
        description = ''
          The XMLTV guide: a local file path or an http(s) URL.
          This is how Jellyfin identifies the guide. Use `{ _secret = path; }`
          for a URL that carries credentials.
        '';
      };

      tuners = mkOption {
        type = types.nullOr (types.listOf types.str);
        default = null;
        example = [ "iptv" ];
        description = ''
          Names of declared tuners (attribute names in `liveTv.tuners`) this
          guide applies to. `null` applies it to every tuner, including ones
          added by hand.
        '';
      };

      settings = mkOption {
        type = types.attrsOf settingValue;
        default = { };
        example = literalExpression "{ enableNewProgramIds = true; }";
        description = ''
          Further `ListingsProviderInfo` fields, in camelCase. `type`, `path`,
          `enableAllTuners` and `enabledTuners` are set from the options above.
        '';
      };
    };
  };
in
{
  options.nixflix.jellyfin.liveTv = {
    tuners = mkOption {
      type = types.attrsOf tunerModule;
      default = { };
      example = literalExpression ''
        {
          iptv = {
            url = "/var/lib/iptv/channels.m3u";
            settings.tunerCount = 2;
          };
        }
      '';
      description = ''
        M3U tuners (IPTV playlists) for Live TV.

        Declared tuners are created or updated in place; one is only written
        when it differs from what Jellyfin holds. A tuner that was declared
        before and is no longer is removed. Tuners added by hand in the
        dashboard are never touched.
      '';
    };

    listingProviders = mkOption {
      type = types.attrsOf listingProviderModule;
      default = { };
      example = literalExpression ''
        {
          guide = {
            path = "/var/lib/iptv/guide.xml";
            tuners = [ "iptv" ];
          };
        }
      '';
      description = ''
        XMLTV guide sources for Live TV, matched to channels by `tvg-id`.

        Managed the same way as `tuners`: created or updated in place, removed
        when no longer declared, and providers added by hand are left alone.
      '';
    };
  };
}
