# Sandbox profile for oneshot services that only make outbound HTTP API calls
# and read secret files. No filesystem writes are needed, so ProtectSystem=strict
# is safe. The service still runs as root because secret files are root-owned;
# that constraint goes away once LoadCredential (nixflix-a5v) is implemented.
{
  PrivateTmp = true;
  ProtectHome = true;
  ProtectSystem = "strict";
  NoNewPrivileges = true;
  RestrictNamespaces = true;
  CapabilityBoundingSet = "";
  AmbientCapabilities = "";
  ProtectProc = "invisible";
  ProcSubset = "pid";
  ProtectKernelTunables = true;
  ProtectKernelModules = true;
  ProtectKernelLogs = true;
  ProtectControlGroups = true;
  LockPersonality = true;
  RestrictRealtime = true;
  RestrictSUIDSGID = true;
  RestrictAddressFamilies = [
    "AF_UNIX"
    "AF_INET"
    "AF_INET6"
  ];
  SystemCallArchitectures = "native";
  SystemCallFilter = [
    "~@debug"
    "~@module"
    "~@raw-io"
    "~@reboot"
    "~@swap"
  ];
}
