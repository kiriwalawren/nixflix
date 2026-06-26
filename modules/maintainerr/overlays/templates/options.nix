{ lib, ... }:
{
  options.nixflix.maintainerr.overlays.templates = lib.mkOption {
    type = lib.types.listOf (
      lib.types.submodule {
        options = {
          name = lib.mkOption {
            type = lib.types.str;
            description = "Template name. Used as the unique identifier for create/update/delete.";
            example = "My Custom Pill";
          };

          description = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = "Human-readable description of what the template displays.";
          };

          mode = lib.mkOption {
            type = lib.types.enum [
              "poster"
              "titlecard"
            ];
            description = "Whether this template is for poster images or title card images.";
          };

          canvasWidth = lib.mkOption {
            type = lib.types.int;
            description = "Canvas width in pixels. Typically 1000 for poster, 1920 for titlecard.";
            example = 1000;
          };

          canvasHeight = lib.mkOption {
            type = lib.types.int;
            description = "Canvas height in pixels. Typically 1500 for poster, 1080 for titlecard.";
            example = 1500;
          };

          elements = lib.mkOption {
            type = lib.types.listOf lib.types.anything;
            default = [ ];
            description = ''
              Canvas elements (shapes and variables) making up the overlay.
              Each element is a free-form attribute set matching the Maintainerr element schema.
              Elements may be of type "shape" (shapeType, fillColor, etc.) or "variable"
              (segments, fontFamily, fontSize, etc.).
            '';
            example = lib.literalExpression ''
              [
                {
                  id = "pill-bg";
                  type = "shape";
                  x = 30; y = 60; width = 400; height = 70;
                  rotation = 0; layerOrder = 0; opacity = 1; visible = true;
                  shapeType = "rectangle";
                  fillColor = "#B20710"; strokeColor = null; strokeWidth = 0; cornerRadius = 35;
                }
              ]
            '';
          };

          isDefault = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = ''
              Set this template as the default for its mode (poster or titlecard).
              Only one template per mode may be the default; if multiple templates in the
              same mode declare isDefault = true, the last one processed wins.
            '';
          };
        };
      }
    );
    default = [ ];
    description = ''
      Overlay templates to declaratively manage in Maintainerr.
      Templates present in Maintainerr but not listed here will be deleted,
      unless they are built-in presets (isPreset = true in the API), which are
      never modified or removed.
    '';
  };
}
