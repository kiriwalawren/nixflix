{lib}:
with lib; {
  # Type that accepts either plain string or { _secret = path }
  secretOrStrType = types.oneOf [
    types.str
    (types.submodule {
      options._secret = mkOption {
        type = types.str;
        description = "Path to a file containing the secret value";
      };
    })
  ];

  # Check if value is a secret reference
  isSecretRef = value:
    (builtins.isAttrs value) && (value ? _secret) && !(value ? __unfix__);

  # Get the secret path or null
  getSecretPath = value:
    if (builtins.isAttrs value) && (value ? _secret) && !(value ? __unfix__)
    then value._secret
    else null;

  # Generate shell code to read secret
  # Returns a shell expression that can be used to set a variable
  toShellValue = varName: value:
    if (builtins.isAttrs value) && (value ? _secret) && !(value ? __unfix__)
    then "${varName}=$(cat ${escapeShellArg value._secret})"
    else "${varName}=${escapeShellArg (toString value)}";

  # Create assertion that warns about plain-text secrets
  # Note: The assertion always passes but emits a warning message
  mkSecretAssertion = fieldName: value: {
    assertion = true;  # Always true - we just want to warn, not fail
    message =
      if (builtins.isString value) && !(builtins.isAttrs value)
      then "Warning: ${fieldName} is set to a plain-text string. This will be visible in the Nix store. Consider using { _secret = /path/to/file; } instead for sensitive data."
      else "";
  };

  # For template-based configs: convert secret references to placeholders
  # This is used by SABnzbd and other services that use template files
  toPlaceholder = value:
    if (builtins.isAttrs value) && (value ? _secret) && !(value ? __unfix__)
    then "__SECRET_FILE__${toString value._secret}__"
    else toString value;

  # Process values recursively (for complex configurations like INI files)
  # Converts secret references to placeholders, booleans to "1"/"0", etc.
  processValue = value:
    if (builtins.isAttrs value) && (value ? _secret) && !(value ? __unfix__)
    then "__SECRET_FILE__${toString value._secret}__"
    else if isBool value
    then
      if value
      then "1"
      else "0"
    else if isList value
    then concatStringsSep ", " (map (v:
      if (builtins.isAttrs v) && (v ? _secret) && !(v ? __unfix__)
      then "__SECRET_FILE__${toString v._secret}__"
      else toString v
    ) value)
    else if isAttrs value
    then mapAttrs (_name: processValue) value
    else if isInt value || isFloat value || isString value
    then toString value
    else toString value;
}
