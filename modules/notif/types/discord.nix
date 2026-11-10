{ lib, notifLib, ... }:
with lib;
with notifLib;
let
  selectList = max: description: field (types.listOf (types.ints.between 0 max)) description;
in
mkConnectorOption {
  implementationName = "Discord";
  description = "Discord notification definition for Starr services.";
  perService = {
    sonarr.fields = {
      grabFields = selectList 12 "Fields passed in an on-grab notification: 0 Overview, 1 Rating, 2 Genres, 3 Quality, 4 Group, 5 Size, 6 Links, 7 Release, 8 Poster, 9 Fanart, 10 Indexer, 11 CustomFormats, 12 CustomFormatScore.";
      importFields = selectList 14 "Fields passed in an on-import notification: 0 Overview, 1 Rating, 2 Genres, 3 Quality, 4 Codecs, 5 Group, 6 Size, 7 Languages, 8 Subtitles, 9 Links, 10 Release, 11 Poster, 12 Fanart, 13 CustomFormats, 14 CustomFormatScore.";
      manualInteractionFields = selectList 9 "Fields passed in a manual-interaction notification: 0 Overview, 1 Rating, 2 Genres, 3 Quality, 4 Group, 5 Size, 6 Links, 7 DownloadTitle, 8 Poster, 9 Fanart.";
    };
    radarr.fields = {
      grabFields = selectList 13 "Fields passed in an on-grab notification: 0 Overview, 1 Rating, 2 Genres, 3 Quality, 4 Group, 5 Size, 6 Links, 7 Release, 8 Poster, 9 Fanart, 10 Indexer, 11 CustomFormats, 12 CustomFormatScore, 13 Tags.";
      importFields = selectList 15 "Fields passed in an on-import notification: 0 Overview, 1 Rating, 2 Genres, 3 Quality, 4 Codecs, 5 Group, 6 Size, 7 Languages, 8 Subtitles, 9 Links, 10 Release, 11 Poster, 12 Fanart, 13 Tags, 14 CustomFormats, 15 CustomFormatScore.";
      manualInteractionFields = selectList 10 "Fields passed in a manual-interaction notification: 0 Overview, 1 Rating, 2 Genres, 3 Quality, 4 Group, 5 Size, 6 Links, 7 DownloadTitle, 8 Poster, 9 Fanart, 10 Tags.";
    };
    lidarr.fields = {
      grabFields = selectList 12 "Fields passed in an on-grab notification: 0 Overview, 1 Rating, 2 Genres, 3 Quality, 4 Group, 5 Size, 6 Links, 7 Release, 8 Poster, 9 Fanart, 10 Indexer, 11 CustomFormats, 12 CustomFormatScore.";
      importFields = selectList 9 "Fields passed in an on-import notification: 0 Overview, 1 Rating, 2 Genres, 3 Quality, 4 Group, 5 Size, 6 Links, 7 Release, 8 Poster, 9 Fanart.";
    };
  };
  fields = {
    webHookUrl = secretField "Discord channel webhook URL.";
    username = secretField "The username to post as. Defaults to the Discord webhook default.";
    avatar = field types.str "Avatar used for messages from this integration.";
    author = field types.str "Override the embed author (host on Lidarr) shown for this notification.";
  };
}
