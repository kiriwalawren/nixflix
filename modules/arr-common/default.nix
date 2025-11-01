{
  config,
  lib,
  pkgs,
  usesDynamicUser ? false,
  ...
}: {
  arrConfigModule = import ./configModule.nix {inherit lib;};
  mkArrHostConfigService = import ./hostConfigService.nix {inherit lib pkgs;};
  mkArrRootFoldersService = import ./rootFoldersService.nix {inherit lib pkgs;};
  mkArrServiceModule = import ../arr-common/mkArrServiceModule.nix {inherit config lib pkgs usesDynamicUser;};
}
