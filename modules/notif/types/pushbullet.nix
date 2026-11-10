{ lib, notifLib, ... }:
with lib;
with notifLib;
mkConnectorOption {
  implementationName = "Pushbullet";
  description = "Pushbullet notification definition for Starr services.";
  perService = {
    seerr = {
      agent = "pushbullet";
      mappedFields = [
        "apiKey"
        "channelTags"
      ];
      toSeerr =
        r:
        seerrOptions r { accessToken = "apiKey"; }
        // {
          channelTag =
            if (r.channelTags or null) == null then
              null
            else if r.channelTags == [ ] then
              ""
            else
              head r.channelTags;
        };
      required = _: [ "apiKey" ];
      checks = r: [
        {
          assertion = length (r.channelTags or [ ]) <= 1;
          message = "Seerr's Pushbullet agent sends to a single channel tag; set `nixflix.notif.pushbullet.seerr.channelTags` to at most one tag.";
        }
      ];
    };
    sonarr.unsupportedTriggers = [ "onRename" ];
    radarr.unsupportedTriggers = [ "onRename" ];
    lidarr.unsupportedTriggers = [
      "onRename"
      "onTrackRetag"
    ];
  };
  fields = {
    apiKey = secretField "Pushbullet access token.";
    deviceIds = field (types.listOf types.str) "Device IDs to send to. If unset, all devices receive notifications.";
    channelTags = field (types.listOf types.str) "Channel tags to send notifications to.";
    senderId = field types.str "Device ID to send notifications from. If unset, notifications are sent from yourself.";
  };
}
