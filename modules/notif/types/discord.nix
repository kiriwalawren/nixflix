{
  lib,
  secrets,
  notifLib,
  ...
}:
with lib;
with notifLib;
let
  selectList = max: description: field (types.listOf (types.ints.between 0 max)) description;

  username =
    serviceName: config:
    secrets.mkSecretOption {
      nullable = true;
      default = if config.username != null then config.username else serviceName;
      defaultText = literalExpression ''if config.nixflix.notif.discord.username != null then config.nixflix.notif.discord.username else "${serviceName}"'';
      description = "The username ${serviceName} posts as.";
    };

  sonarrFields = {
    grabFields = selectList 12 "Fields passed in an on-grab notification: 0 Overview, 1 Rating, 2 Genres, 3 Quality, 4 Group, 5 Size, 6 Links, 7 Release, 8 Poster, 9 Fanart, 10 Indexer, 11 CustomFormats, 12 CustomFormatScore.";
    importFields = selectList 14 "Fields passed in an on-import notification: 0 Overview, 1 Rating, 2 Genres, 3 Quality, 4 Codecs, 5 Group, 6 Size, 7 Languages, 8 Subtitles, 9 Links, 10 Release, 11 Poster, 12 Fanart, 13 CustomFormats, 14 CustomFormatScore.";
    manualInteractionFields = selectList 9 "Fields passed in a manual-interaction notification: 0 Overview, 1 Rating, 2 Genres, 3 Quality, 4 Group, 5 Size, 6 Links, 7 DownloadTitle, 8 Poster, 9 Fanart.";
  };
in
mkConnectorOption {
  implementationName = "Discord";
  description = "Discord notification definition for Starr services.";
  perService = {
    sonarr.fields = config: sonarrFields // { username = username "Sonarr" config; };
    sonarr-anime.fields = config: sonarrFields // { username = username "Sonarr Anime" config; };
    radarr.fields = config: {
      username = username "Radarr" config;
      grabFields = selectList 13 "Fields passed in an on-grab notification: 0 Overview, 1 Rating, 2 Genres, 3 Quality, 4 Group, 5 Size, 6 Links, 7 Release, 8 Poster, 9 Fanart, 10 Indexer, 11 CustomFormats, 12 CustomFormatScore, 13 Tags.";
      importFields = selectList 15 "Fields passed in an on-import notification: 0 Overview, 1 Rating, 2 Genres, 3 Quality, 4 Codecs, 5 Group, 6 Size, 7 Languages, 8 Subtitles, 9 Links, 10 Release, 11 Poster, 12 Fanart, 13 Tags, 14 CustomFormats, 15 CustomFormatScore.";
      manualInteractionFields = selectList 10 "Fields passed in a manual-interaction notification: 0 Overview, 1 Rating, 2 Genres, 3 Quality, 4 Group, 5 Size, 6 Links, 7 DownloadTitle, 8 Poster, 9 Fanart, 10 Tags.";
    };
    lidarr.fields = config: {
      username = username "Lidarr" config;
      grabFields = selectList 12 "Fields passed in an on-grab notification: 0 Overview, 1 Rating, 2 Genres, 3 Quality, 4 Group, 5 Size, 6 Links, 7 Release, 8 Poster, 9 Fanart, 10 Indexer, 11 CustomFormats, 12 CustomFormatScore.";
      importFields = selectList 9 "Fields passed in an on-import notification: 0 Overview, 1 Rating, 2 Genres, 3 Quality, 4 Group, 5 Size, 6 Links, 7 Release, 8 Poster, 9 Fanart.";
    };
  };
  fields = {
    webHookUrl = secretField "Discord channel webhook URL.";
    username = secretField "The username every service posts as. When null, each service posts as its own name (for example `Sonarr Anime`).";
    avatar = field types.str "Avatar used for messages from this integration.";
    author = field types.str "Override the embed author (host on Lidarr) shown for this notification.";
  };
}
