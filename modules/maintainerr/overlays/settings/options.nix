{ lib, ... }:
let
  overlayTextModule = lib.types.submodule {
    options = {
      overlayText = lib.mkOption {
        type = lib.types.str;
        default = "Leaving";
        description = "Text to display on the overlay.";
      };
      useDays = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Use days remaining instead of a fixed text.";
      };
      textToday = lib.mkOption {
        type = lib.types.str;
        default = "today";
        description = "Text shown when the item leaves today.";
      };
      textDay = lib.mkOption {
        type = lib.types.str;
        default = "in 1 day";
        description = "Text shown when the item leaves in exactly 1 day.";
      };
      textDays = lib.mkOption {
        type = lib.types.str;
        default = "in {0} days";
        description = "Text shown when the item leaves in multiple days. Use {0} as the day count placeholder.";
      };
      enableDaySuffix = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Append an ordinal suffix to the day number (e.g. 1st, 2nd).";
      };
      enableUppercase = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Render the overlay text in uppercase.";
      };
      language = lib.mkOption {
        type = lib.types.str;
        default = "en-US";
        description = "BCP 47 language tag used for date/number formatting.";
        example = "fr-FR";
      };
      dateFormat = lib.mkOption {
        type = lib.types.str;
        default = "MMM d";
        description = "Date format string (Unicode CLDR / date-fns tokens).";
        example = "dd/MM/yyyy";
      };
    };
  };

  overlayStyleModule = lib.types.submodule {
    options = {
      fontPath = lib.mkOption {
        type = lib.types.str;
        default = "Inter-Bold.ttf";
        description = "Font file name relative to Maintainerr's fonts directory.";
      };
      fontColor = lib.mkOption {
        type = lib.types.str;
        default = "#FFFFFF";
        description = "Overlay text color as a CSS hex color.";
      };
      backColor = lib.mkOption {
        type = lib.types.str;
        default = "#B20710";
        description = "Overlay background color as a CSS hex color.";
      };
      fontSize = lib.mkOption {
        type = lib.types.number;
        default = 5.5;
        description = "Font size as a percentage of the image height.";
      };
      padding = lib.mkOption {
        type = lib.types.number;
        default = 1.5;
        description = "Padding around the overlay text as a percentage of the image height.";
      };
      backRadius = lib.mkOption {
        type = lib.types.number;
        default = 3;
        description = "Border radius of the overlay background pill.";
      };
      horizontalOffset = lib.mkOption {
        type = lib.types.number;
        default = 3;
        description = "Horizontal offset of the overlay from the edge, as a percentage.";
      };
      horizontalAlign = lib.mkOption {
        type = lib.types.enum [
          "left"
          "center"
          "right"
        ];
        default = "left";
        description = "Horizontal alignment of the overlay relative to the image.";
      };
      verticalOffset = lib.mkOption {
        type = lib.types.number;
        default = 4;
        description = "Vertical offset of the overlay from the edge, as a percentage.";
      };
      verticalAlign = lib.mkOption {
        type = lib.types.enum [
          "top"
          "center"
          "bottom"
        ];
        default = "top";
        description = "Vertical alignment of the overlay relative to the image.";
      };
      overlayBottomCenter = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Pin the overlay to the bottom center of the image, overriding alignment offsets.";
      };
    };
  };

  frameModule = lib.types.submodule {
    options = {
      useFrame = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Draw a decorative frame around the poster or title card.";
      };
      frameColor = lib.mkOption {
        type = lib.types.str;
        default = "#B20710";
        description = "Frame color as a CSS hex color.";
      };
      frameWidth = lib.mkOption {
        type = lib.types.number;
        default = 1.5;
        description = "Frame stroke width as a percentage of the image width.";
      };
      frameRadius = lib.mkOption {
        type = lib.types.number;
        default = 2;
        description = "Outer corner radius of the frame.";
      };
      frameInnerRadius = lib.mkOption {
        type = lib.types.number;
        default = 2;
        description = "Inner corner radius of the frame.";
      };
      frameInnerRadiusMode = lib.mkOption {
        type = lib.types.str;
        default = "auto";
        description = "How to compute the inner radius. Typically \"auto\" or \"manual\".";
      };
      frameInset = lib.mkOption {
        type = lib.types.str;
        default = "outside";
        description = "Whether the frame is drawn \"outside\" or \"inside\" the image boundary.";
      };
      dockStyle = lib.mkOption {
        type = lib.types.str;
        default = "pill";
        description = "Shape of the dock element (e.g. \"pill\", \"badge\", \"square\").";
      };
      dockPosition = lib.mkOption {
        type = lib.types.str;
        default = "bottom";
        description = "Position of the dock element (e.g. \"top\", \"bottom\", \"left\", \"right\").";
      };
    };
  };
in
{
  options.nixflix.maintainerr.overlays.settings = {
    enabled = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable or disable Maintainerr overlay generation globally.";
    };

    posterOverlayText = lib.mkOption {
      type = overlayTextModule;
      default = { };
      description = "Text configuration for poster overlays.";
    };

    posterOverlayStyle = lib.mkOption {
      type = overlayStyleModule;
      default = { };
      description = "Style configuration for poster overlays.";
    };

    posterFrame = lib.mkOption {
      type = frameModule;
      default = { };
      description = "Frame configuration for poster overlays.";
    };

    titleCardOverlayText = lib.mkOption {
      type = overlayTextModule;
      default = { };
      description = "Text configuration for title card overlays.";
    };

    titleCardOverlayStyle = lib.mkOption {
      type = overlayStyleModule;
      default = { };
      description = "Style configuration for title card overlays.";
    };

    titleCardFrame = lib.mkOption {
      type = frameModule;
      default = { };
      description = "Frame configuration for title card overlays.";
    };

    cronSchedule = lib.mkOption {
      type = lib.types.str;
      default = "0 */6 * * *";
      description = "Cron schedule for the overlay generation job inside Maintainerr.";
      example = "0 4 * * *";
    };
  };
}
