# Radarr and Sonarr OIDC

Radarr 7+ and Sonarr 5+ (including a separate `sonarr-anime` instance) can use
native OIDC for their web UI. Register **one confidential client per instance**
with any compatible OIDC provider. The callback URI is the externally accessed
HTTPS URL followed by `/signin-oidc` (include `urlBase`, if set). Configure the
provider to support authorization code flow and PKCE. Its issuer URL must be
reachable from the application, and the login page must be reachable from users'
browsers.

Supply the secret-file path from your own secret manager. For example, with
sops-nix (not required by nixflix):

```nix
{ config, ... }: {
  nixflix.sonarr.config.hostConfig = {
    authenticationMethod = "oidc";
    authenticationRequired = "enabled";
    username = null;
    password = null;
    oidc = {
      authority = "https://login.example.org"; # OIDC issuer/discovery URL
      clientId = "sonarr";
      clientSecret._secret = config.sops.secrets.sonarr-oidc-client-secret.path;
      userIdentifier = "user@example.org";
      # scopes defaults to "openid profile email"
    };
  };
}
```

Apply the same settings to `nixflix.radarr` or `nixflix.sonarr-anime`, with a
**different** client registration and redirect URI for each. Configure an API
key separately as usual; integrations use the API key, not browser OIDC login.
`userIdentifier` is the identity expected in the provider's claims: these
applications currently support **one user**, not multiple OIDC accounts.

The client secret is read from its file when the host-configuration service
runs; do not put a plaintext secret in Nix configuration or `settings` (which
is rendered into the world-readable Nix store). Ensure the service can read
that file. Other OIDC settings are stored by the apps in their private
`config.xml`. Back up that file and test access before disabling your previous
login route. To recover from a broken configuration, stop the app, change
`AuthenticationMethod` back to `Forms` in `config.xml`, then restart it.

OIDC is only exposed for Radarr and Sonarr. Other Arr applications retain
their existing authentication options. The issuer/provider itself is not
managed by nixflix.
