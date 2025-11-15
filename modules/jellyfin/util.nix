{lib, ...}:
with lib; {
  toPascalCase = str: let
    firstChar = substring 0 1 str;
    rest = substring 1 (-1) str;
  in
    (toUpper firstChar) + rest;
}
