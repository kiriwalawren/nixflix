{ pkgs }:
{
  "apple-music".package = pkgs.pkgsCross.wasi32.navidromePlugins.apple-music;
  "audiomuseai".package = pkgs.pkgsCross.wasi32.navidromePlugins.audiomuseai;
  "discord-rich-presence" = {
    package = pkgs.pkgsCross.wasi32.navidromePlugins.discord-rich-presence;
    apiId = "discord-rich-presence-plugin";
  };
  "listenbrainz-daily-playlist".package =
    pkgs.pkgsCross.wasi32.navidromePlugins.listenbrainz-daily-playlist;
  "lyrics" = {
    package = pkgs.pkgsCross.wasi32.navidromePlugins.lyrics-plugin;
    apiId = "nd-lyrics";
  };
}
