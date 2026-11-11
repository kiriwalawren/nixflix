{
  system ? builtins.currentSystem,
  pkgs ? import <nixpkgs> { inherit system; },
  nixosModules,
}:
let
  seerrApiKey = "seerr555555555555555555";
  secret = name: value: { _secret = pkgs.writeText "notif-seerr-${name}" value; };

  s = {
    discordWebhook = "https://discord.com/api/webhooks/111111111111111111/discord-token";
    telegramBotToken = "123456:telegram-bot-token";
    pushbulletToken = "pushbullet-access-token";
    pushoverUserKey = "pushover-user-key";
    gotifyToken = "gotify-app-token";
    ntfyPassword = "ntfy-password";
    webhookPassword = "webhook-password";
    webhookHeader = "webhook-header-value";
    emailPassword = "email-password";
    pgpPrivateKey = "-----BEGIN PGP PRIVATE KEY BLOCK-----";
    pgpPassword = "pgp-password";
  };

  jsonPayload = ''{"event":"{{event}}","subject":"{{subject}}"}'';
in
pkgs.testers.runNixOSTest {
  name = "notif-seerr";

  nodes.machine = { lib, ... }: {
    imports = [ nixosModules ];

    virtualisation = {
      cores = 4;
      memorySize = 4096;
      diskSize = 3 * 1024;
    };

    nixflix = {
      enable = true;

      recyclarr.enable = false;

      # Gives Jellyfin a Movies library, which Seerr's initial setup requires.
      radarr = {
        enable = true;
        mediaDirs = [ "/media/movies" ];
        config = {
          hostConfig = {
            username = "admin";
            password._secret = pkgs.writeText "radarr-password" "testpass";
          };
          apiKey._secret = pkgs.writeText "radarr-apikey" "radarr333333333333333333333333333";
        };
      };

      jellyfin = {
        enable = true;
        apiKey._secret = pkgs.writeText "jellyfin-apikey" "jellyfinApiKey1111111111111111111";
        users.admin = {
          password._secret = pkgs.writeText "admin-password" "321password";
          policy.isAdministrator = true;
        };
        plugins.AniDB.enable = false;
      };

      seerr = {
        enable = true;
        apiKey._secret = pkgs.writeText "seerr-apikey" seerrApiKey;
      };

      notif = {
        discord = {
          webHookUrl = secret "discord" s.discordWebhook;
          avatar = "https://example.com/avatar.png";
          seerr = {
            enable = true;
            webhookRoleId = "222222222222222222";
            webhookThreadId = "333333333333333333";
            enableMentions = false;
            locale = "de";
            useUserLocale = false;
            embedPoster = false;
            onIssueComment = false;
          };
        };

        slack = {
          webHookUrl = "https://hooks.slack.com/services/connector";
          seerr = {
            enable = true;
            webHookUrl = "https://hooks.slack.com/services/seerr";
            locale = "es";
          };
        };

        telegram = {
          botToken = secret "telegram" s.telegramBotToken;
          chatId = "-1001234567890";
          topicId = "42";
          sendSilently = true;
          seerr = {
            enable = true;
            botUsername = "nixflix_bot";
          };
        };

        pushbullet = {
          apiKey = secret "pushbullet" s.pushbulletToken;
          channelTags = [ "nixflix" ];
          seerr.enable = true;
        };

        pushover = {
          apiKey = "pushover-api-token";
          userKey = secret "pushover" s.pushoverUserKey;
          sound = "cosmic";
          seerr.enable = true;
        };

        gotify = {
          server = "https://gotify.example.com";
          appToken = secret "gotify" s.gotifyToken;
          priority = 8;
          seerr = {
            enable = true;
            locale = "fr";
            onMediaPending = false;
          };
        };

        ntfy = {
          serverUrl = "https://ntfy.example.com";
          topics = [ "media" ];
          ntfyTags = [
            "tv"
            "warning"
          ];
          userName = "ntfy-user";
          password = secret "ntfy" s.ntfyPassword;
          priority = 4;
          seerr.enable = true;
        };

        webhook = {
          url = "https://webhook.example.com/seerr";
          username = "bob";
          password = secret "webhook-password" s.webhookPassword;
          headers = [
            {
              key = "X-Test";
              value = secret "webhook-header" s.webhookHeader;
            }
          ];
          seerr = {
            enable = true;
            inherit jsonPayload;
            supportVariables = true;
          };
        };

        email = {
          server = "smtp.example.com";
          port = 465;
          from = "seerr@example.com";
          username = "mailer";
          password = secret "email" s.emailPassword;
          seerr = {
            enable = true;
            useEncryption = 1;
            senderName = "Nixflix";
            allowSelfSigned = true;
            userEmailRequired = true;
            usePublicLogo = true;
            pgpPrivateKey = secret "pgp-key" s.pgpPrivateKey;
            pgpPassword = secret "pgp-password" s.pgpPassword;
          };
        };

        webpush.seerr.enable = true;
      };
    };

    systemd.services.jellyfin.serviceConfig.TimeoutStartSec = lib.mkForce 300;

    specialisation.disabled.configuration.nixflix.notif = {
      discord.seerr.enable = lib.mkForce false;
      slack.seerr.enable = lib.mkForce false;
    };
  };

  testScript = ''
    import base64
    import json

    BASE = "http://127.0.0.1:5055/api/v1/settings/notifications"
    AGENTS = ["discord", "email", "gotify", "ntfy", "pushbullet", "pushover", "slack", "telegram", "webhook", "webpush"]
    ALL_TYPES = 8158
    MISSING = object()

    def agent(name):
        return json.loads(machine.succeed(f"curl -sf -H 'X-Api-Key: ${seerrApiKey}' {BASE}/{name}"))

    def expect(name, enabled=True, types=MISSING, embedPoster=MISSING, **options):
        a = agent(name)
        assert a["enabled"] == enabled, f"{name}.enabled: expected {enabled}, got {a['enabled']}"
        if types is None:
            assert "types" not in a, f"{name}: expected no types, got {a.get('types')}"
        elif types is not MISSING:
            assert a.get("types") == types, f"{name}.types: expected {types}, got {a.get('types')}"
        if embedPoster is not MISSING:
            assert a["embedPoster"] == embedPoster, f"{name}.embedPoster: expected {embedPoster}, got {a['embedPoster']}"
        for key, value in options.items():
            actual = a["options"].get(key, MISSING)
            assert actual == value, f"{name}.options.{key}: expected {value!r}, got {actual!r}"
        print(f"{name}: OK")

    def check_all():
        expect("discord", types=ALL_TYPES - 512, embedPoster=False,
            webhookUrl="${s.discordWebhook}",
            botUsername="Seerr",
            botAvatarUrl="https://example.com/avatar.png",
            webhookRoleId="222222222222222222",
            webhookThreadId="333333333333333333",
            enableMentions=False,
            locale="de",
            useUserLocale=False)
        expect("slack", types=ALL_TYPES,
            webhookUrl="https://hooks.slack.com/services/seerr",
            locale="es")
        expect("telegram", types=ALL_TYPES,
            botAPI="${s.telegramBotToken}",
            chatId="-1001234567890",
            messageThreadId="42",
            sendSilently=True,
            botUsername="nixflix_bot")
        expect("pushbullet", types=ALL_TYPES,
            accessToken="${s.pushbulletToken}",
            channelTag="nixflix")
        expect("pushover", types=ALL_TYPES,
            accessToken="pushover-api-token",
            userToken="${s.pushoverUserKey}",
            sound="cosmic")
        expect("gotify", types=ALL_TYPES - 2,
            url="https://gotify.example.com",
            token="${s.gotifyToken}",
            priority=8,
            locale="fr")
        expect("ntfy", types=ALL_TYPES,
            url="https://ntfy.example.com",
            topic="media",
            tags="tv,warning",
            username="ntfy-user",
            password="${s.ntfyPassword}",
            authMethodUsernamePassword=True,
            authMethodToken=False,
            priority=4)
        expect("webhook", types=ALL_TYPES,
            webhookUrl="https://webhook.example.com/seerr",
            customHeaders=[{"key": "X-Test", "value": "${s.webhookHeader}"}],
            authHeader="Basic " + base64.b64encode(b"bob:${s.webhookPassword}").decode(),
            jsonPayload=${builtins.toJSON jsonPayload},
            supportVariables=True)
        expect("email", types=None,
            smtpHost="smtp.example.com",
            smtpPort=465,
            emailFrom="seerr@example.com",
            authUser="mailer",
            authPass="${s.emailPassword}",
            secure=True,
            requireTls=False,
            ignoreTls=False,
            senderName="Nixflix",
            allowSelfSigned=True,
            userEmailRequired=True,
            usePublicLogo=True,
            pgpPrivateKey="${s.pgpPrivateKey}",
            pgpPassword="${s.pgpPassword}")
        expect("webpush", types=None)

    start_all()
    machine.wait_for_unit("seerr-notifications.service", timeout=600)

    with subtest("every connector is applied to Seerr"):
        check_all()

    with subtest("re-running the unit changes nothing"):
        before = {name: agent(name) for name in AGENTS}
        machine.succeed("systemctl restart seerr-notifications.service")
        after = {name: agent(name) for name in AGENTS}
        for name in AGENTS:
            assert before[name] == after[name], f"{name} changed on re-run: {before[name]} -> {after[name]}"
        check_all()

    with subtest("connectors no longer targeting Seerr are disabled, keeping their settings"):
        before = {name: agent(name) for name in AGENTS}
        machine.succeed("/run/booted-system/specialisation/disabled/bin/switch-to-configuration test")
        machine.succeed("systemctl restart seerr-notifications.service")
        for name in AGENTS:
            now = agent(name)
            if name in ("discord", "slack"):
                assert now["enabled"] == False, f"{name}: expected disabled, got {now}"
                assert {**now, "enabled": True} == before[name], f"{name}: settings changed when disabled: {before[name]} -> {now}"
            else:
                assert now == before[name], f"{name} changed: {before[name]} -> {now}"
        print("discord and slack disabled, everything else unchanged")
  '';
}
