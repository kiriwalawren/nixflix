{ notifLib, ... }:
notifLib.mkConnectorOption {
  implementationName = "Web Push";
  description = "Web Push notification definition for Seerr. Seerr sends browser push notifications to each user according to their own notification settings.";
  perService.seerr = {
    agent = "webpush";
    hasTypes = false;
    toSeerr = _: { };
  };
}
