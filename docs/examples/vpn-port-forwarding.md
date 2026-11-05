---
title: VPN Port Forwarding
---

# VPN Port Forwarding

When `nixflix.vpn.enable = true`, services such as [qBittorrent](../reference/torrentClients/qbittorrent/index.md)
and [slskd](../reference/slskd/index.md) are confined to the VPN's network namespace. Any port
forwarding configured on your router (WAN) no longer reaches them, because incoming connections
now arrive through the VPN tunnel instead.

To restore incoming connections, you must use a VPN provider that supports port forwarding and
configure it yourself. **Nixflix does not manage this for you.**

## ProtonVPN

ProtonVPN is more difficult to set up than most providers because the forwarded port is
randomized. The port is leased over [NAT-PMP](https://protonvpn.com/support/port-forwarding-manual-setup)
for 60 seconds, so it must be renewed in a loop, and the service's listening port must be
updated whenever ProtonVPN hands out a different one.

The examples below run `natpmpc` inside the VPN namespace every 45 seconds against ProtonVPN's
gateway (`10.2.0.1`) and push the mapped port to the service's API when it changes.

The secret paths use [sops-nix](https://github.com/Mic92/sops-nix); any file containing the
secret will work.

### qBittorrent

qBittorrent should also re-announce to trackers when its address changes:

```nix
{
  config,
  lib,
  pkgs,
  ...
}:
let
  qbCfg = config.nixflix.torrentClients.qbittorrent;
  qbPassFile = config.sops.secrets."qbittorrent/password".path;
in
{
  nixflix.torrentClients.qbittorrent.serverConfig = {
    BitTorrent.Session.ReannounceWhenAddressChanged = true;
    Preferences.WebUI.Username = "admin";
  };

  systemd.services.qbittorrent-protonvpn-port-forward =
    lib.mkIf (config.nixflix.vpn.enable && qbCfg.vpn.enable)
      {
        description = "ProtonVPN port forwarding for qBittorrent";
        after = [
          "${qbCfg.vpn.namespace}.service"
          "qbittorrent.service"
        ];
        requires = [
          "${qbCfg.vpn.namespace}.service"
          "qbittorrent.service"
        ];
        wantedBy = [ "multi-user.target" ];

        path = [
          pkgs.curl
          pkgs.jq
          pkgs.libnatpmp
          pkgs.iproute2
          pkgs.gawk
        ];

        serviceConfig = {
          Type = "simple";
          Restart = "on-failure";
          RestartSec = "5s";
          RuntimeDirectory = "qbittorrent-protonvpn-port-forward";
          RuntimeDirectoryMode = "0700";
          ExecStart =
            let
              ns = qbCfg.vpn.namespace;
              qbHost = "http://${qbCfg.connectionAddress}:${toString config.services.qbittorrent.webuiPort}";
              qbUser = qbCfg.serverConfig.Preferences.WebUI.Username;
            in
            pkgs.writeShellScript "qbittorrent-protonvpn-port-forward" ''
              QB_HOST="${qbHost}"
              QB_USER="${qbUser}"
              QB_COOKIES="$RUNTIME_DIRECTORY/cookies"

              login() {
                printf '%s' "$(cat ${qbPassFile})" | curl -s -c "$QB_COOKIES" \
                  --data-urlencode "username=$QB_USER" \
                  --data-urlencode "password@-" \
                  "$QB_HOST/api/v2/auth/login"
              }

              update_port() {
                local port status
                port="$1"
                login
                status=$(curl -s -o /dev/null -w '%{http_code}' -b "$QB_COOKIES" \
                  --data "json={\"listen_port\":$port,\"random_port\":false}" \
                  "$QB_HOST/api/v2/app/setPreferences")

                if [ "$status" != "200" ]; then
                  echo "Failed to update qBittorrent listen port to $port (HTTP $status)" >&2
                  return 1
                fi

                curl -s -b "$QB_COOKIES" \
                  --data "hashes=all" \
                  "$QB_HOST/api/v2/torrents/reannounce"
              }

              login
              CURRENT_PORT=$(curl -s -b "$QB_COOKIES" \
                "$QB_HOST/api/v2/app/preferences" | jq '.listen_port')

              while true; do
                UDP_OUT=$(ip netns exec ${ns} natpmpc -a 1 0 udp 60 -g 10.2.0.1)
                ip netns exec ${ns} natpmpc -a 1 0 tcp 60 -g 10.2.0.1

                PORT=$(echo "$UDP_OUT" | grep "Mapped public port" | awk '{print $4}')

                if [ -z "$PORT" ]; then
                  echo "Failed to get port, is the tunnel up?"
                  sleep 5
                  continue
                fi

                if [ "$PORT" != "$CURRENT_PORT" ]; then
                  echo "Port changed: $CURRENT_PORT -> $PORT, updating qBittorrent..."
                  if update_port "$PORT"; then
                    CURRENT_PORT=$PORT
                  fi
                fi

                sleep 45
              done
            '';
        };
      };
}
```

### slskd

The slskd API requires `nixflix.slskd.apiKey` to be set. Changing the listen port at runtime
also requires `remote_configuration`, which nixpkgs forces to `false` with `lib.mkForce`
(priority 50), so it must be overridden with a higher priority. Options changed through the API
are held in memory only and are not written back to the configuration file.

```nix
{
  config,
  lib,
  pkgs,
  ...
}:
let
  slskdCfg = config.nixflix.slskd;
  apiKeyFile = config.sops.secrets."slskd/api-key".path;
in
{
  nixflix.slskd.apiKey._secret = apiKeyFile;

  services.slskd.settings.remote_configuration = lib.mkOverride 40 true;

  systemd.services.slskd-protonvpn-port-forward =
    lib.mkIf (config.nixflix.vpn.enable && slskdCfg.enable && slskdCfg.vpn.enable)
      {
        description = "ProtonVPN port forwarding for slskd";
        after = [
          "${slskdCfg.vpn.namespace}.service"
          "slskd.service"
        ];
        requires = [
          "${slskdCfg.vpn.namespace}.service"
          "slskd.service"
        ];
        wantedBy = [ "multi-user.target" ];

        path = [
          pkgs.curl
          pkgs.jq
          pkgs.libnatpmp
          pkgs.iproute2
          pkgs.gawk
        ];

        serviceConfig = {
          Type = "simple";
          Restart = "on-failure";
          RestartSec = "5s";
          ExecStart =
            let
              ns = slskdCfg.vpn.namespace;
              slskdHost = "http://127.0.0.1:${toString config.services.slskd.settings.web.port}";
            in
            pkgs.writeShellScript "slskd-protonvpn-port-forward" ''
              SLSKD_HOST="${slskdHost}"
              API_KEY=$(cat ${apiKeyFile})

              read_current_port() {
                local response status body
                response=$(printf 'X-API-Key: %s\n' "$API_KEY" | ip netns exec ${ns} curl -s -w '\n%{http_code}' \
                  -H @- "$SLSKD_HOST/api/v0/options")
                status=$(echo "$response" | tail -n1)
                body=$(echo "$response" | sed '$d')

                if [ "$status" != "200" ]; then
                  echo "Failed to read slskd options (HTTP $status): $body" >&2
                  return 1
                fi

                echo "$body" | jq '.soulseek.listenPort'
              }

              update_port() {
                local port response status body
                port="$1"
                response=$(printf 'X-API-Key: %s\n' "$API_KEY" | ip netns exec ${ns} curl -s -w '\n%{http_code}' \
                  -H @- -H "Content-Type: application/json" \
                  --request PATCH --data "{\"soulseek\":{\"listenPort\":$port}}" \
                  "$SLSKD_HOST/api/v0/options")
                status=$(echo "$response" | tail -n1)
                body=$(echo "$response" | sed '$d')

                if [ "$status" != "200" ] && [ "$status" != "204" ]; then
                  echo "Failed to update slskd listen port to $port (HTTP $status): $body" >&2
                  return 1
                fi

                echo "Updated slskd listen port to $port (HTTP $status)"
              }

              CURRENT_PORT=$(read_current_port)

              while true; do
                UDP_OUT=$(ip netns exec ${ns} natpmpc -a 1 0 udp 60 -g 10.2.0.1)
                ip netns exec ${ns} natpmpc -a 1 0 tcp 60 -g 10.2.0.1

                PORT=$(echo "$UDP_OUT" | grep "Mapped public port" | awk '{print $4}')

                if [ -z "$PORT" ]; then
                  echo "Failed to get port, is the tunnel up?"
                  sleep 5
                  continue
                fi

                if [ "$PORT" != "$CURRENT_PORT" ]; then
                  echo "Port changed: $CURRENT_PORT -> $PORT, updating slskd..."
                  if update_port "$PORT"; then
                    CURRENT_PORT=$PORT
                  fi
                fi

                sleep 45
              done
            '';
        };
      };
}
```
