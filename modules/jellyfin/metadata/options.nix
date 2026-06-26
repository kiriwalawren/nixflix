{
  lib,
  ...
}:
with lib;
{
  options.nixflix.jellyfin.metadata = {
    useFileCreationTimeForDateAdded = mkOption {
      type = types.bool;
      default = false;
      description = ''
        When enabled, Jellyfin uses the file's creation timestamp as the "date added" value.
        When disabled (the default), Jellyfin uses the date the file was scanned into the library.

        Disable this when files have a creation date that predates when they were actually added
        to the system (e.g. files whose metadata records the original creation time), as this can
        interfere with automations that depend on "date added" reflecting scan time.
      '';
    };
  };
}
