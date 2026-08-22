{ lib }:
with lib;
{
  users,
  isAdmin,
}:
let
  adminUsers = filterAttrs (_: isAdmin) users;
  sortedAdminNames = sort (a: b: a < b) (attrNames adminUsers);
  name = head sortedAdminNames;
in
{
  inherit name;
  user = adminUsers.${name};
}
