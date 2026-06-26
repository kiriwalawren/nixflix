{ lib, ... }:
let
  enumFromAttrs =
    enum_values:
    lib.types.coercedTo (lib.types.enum (lib.attrNames enum_values)) (name: enum_values.${name}) (
      lib.types.enum (lib.attrValues enum_values)
    );

  customValModule = lib.types.submodule {
    options = {
      ruleTypeId = lib.mkOption {
        type = lib.types.int;
        description = "Type of the custom value (0=number, 1=date, 2=list, 3=boolean).";
      };

      value = lib.mkOption {
        type = lib.types.str;
        description = "Custom value serialized as a string.";
      };
    };
  };

  ruleModule = lib.types.submodule {
    options = {
      customVal = lib.mkOption {
        type = lib.types.nullOr customValModule;
        default = null;
        description = "Custom value override for the rule condition.";
      };

      operator = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          Logical operator joining this rule to the previous one in the section.
          null for the first rule in a section; "0"=AND, "1"=OR.
        '';
      };

      firstVal = lib.mkOption {
        type = lib.types.listOf lib.types.int;
        description = "[categoryId, propertyId] of the primary property to evaluate.";
      };

      lastVal = lib.mkOption {
        type = lib.types.nullOr (lib.types.listOf lib.types.int);
        default = null;
        description = "[categoryId, propertyId] of a secondary property to compare against. null when comparing against customVal.";
      };

      action = lib.mkOption {
        type = enumFromAttrs {
          "BIGGER" = 0;
          "SMALLER" = 1;
          "EQUALS" = 2;
          "NOT_EQUALS" = 3;
          "CONTAINS" = 4;
          "BEFORE" = 5;
          "AFTER" = 6;
          "IN_LAST" = 7;
          "IN_NEXT" = 8;
          "NOT_CONTAINS" = 9;
          "CONTAINS_PARTIAL" = 10;
          "NOT_CONTAINS_PARTIAL" = 11;
          "CONTAINS_ALL" = 12;
          "NOT_CONTAINS_ALL" = 13;
          "COUNT_EQUALS" = 14;
          "COUNT_NOT_EQUALS" = 15;
          "COUNT_BIGGER" = 16;
          "COUNT_SMALLER" = 17;
          "EXISTS" = 18;
          "NOT_EXISTS" = 19;
        };
        description = "Comparison action (RulePossibility).";
      };

      section = lib.mkOption {
        type = lib.types.int;
        description = "Section index. Rules within a section are ANDed; sections are ORed.";
      };
    };
  };

  collectionModule = lib.types.submodule {
    options = {
      visibleOnRecommended = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Show this collection on the recommended page.";
      };

      visibleOnHome = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Show this collection on the home page.";
      };

      deleteAfterDays = lib.mkOption {
        type = lib.types.nullOr lib.types.int;
        default = null;
        description = "Days media stays in the collection before arrAction is triggered. null to disable automatic action.";
      };

      manualCollection = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Use an existing manually-managed Jellyfin collection instead of one created by Maintainerr.";
      };

      manualCollectionName = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Name of the manual collection when manualCollection is true.";
      };

      keepLogsForMonths = lib.mkOption {
        type = lib.types.int;
        default = 6;
        description = "Number of months to retain handled-media logs.";
      };

      overlayEnabled = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable collection overlays.";
      };
    };
  };

  ruleGroupModule = lib.types.submodule {
    options = {
      name = lib.mkOption {
        type = lib.types.str;
        description = "Rule group name as it appears in Maintainerr.";
        example = "Movies To Delete";
      };

      description = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Description of the rule group.";
      };

      library = lib.mkOption {
        type = lib.types.str;
        description = "Jellyfin library title to target. Resolved to an ID at runtime via GET /api/media-server/libraries.";
        example = "Movies";
      };

      isActive = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether this rule group is active.";
      };

      dataType = lib.mkOption {
        type = lib.types.enum [
          "movie"
          "show"
          "season"
          "episode"
        ];
        description = "Media type this rule group operates on.";
      };

      useRules = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether to use the rules engine (false = manual collection only).";
      };

      ruleHandlerCronSchedule = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Custom cron schedule for this rule group. null uses the global Maintainerr schedule.";
        example = "0 4 * * *";
      };

      arrAction = lib.mkOption {
        type = enumFromAttrs {
          "DELETE" = 0;
          "UNMONITOR_DELETE_ALL" = 1;
          "UNMONITOR_DELETE_EXISTING" = 2;
          "UNMONITOR" = 3;
          "DO_NOTHING" = 4;
          "DELETE_SHOW_IF_EMPTY" = 5;
          "UNMONITOR_SHOW_IF_EMPTY" = 6;
          "CHANGE_QUALITY_PROFILE" = 7;
        };
        default = "DO_NOTHING";
        description = "Action taken on media when deleteAfterDays elapses (ServarrAction).";
      };

      listExclusions = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Add handled media to the Maintainerr exclusion list.";
      };

      forceSeerr = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Force deletion through Jellyseerr even when media has no active request.";
      };

      radarrServerName = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Name of the Radarr server configured in nixflix.maintainerr.settings.radarr to associate with this rule group. Resolved to an integer ID at runtime.";
        example = "Radarr";
      };

      sonarrServerName = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Name of the Sonarr server configured in nixflix.maintainerr.settings.sonarr to associate with this rule group. Resolved to an integer ID at runtime.";
        example = "Sonarr";
      };

      collection = lib.mkOption {
        type = collectionModule;
        default = { };
        description = "Collection display and lifecycle settings.";
      };

      rules = lib.mkOption {
        type = lib.types.listOf ruleModule;
        default = [ ];
        description = "Rules to evaluate. Rules within a section are ANDed; sections are ORed.";
      };
    };
  };
in
{
  options.nixflix.maintainerr.rules = lib.mkOption {
    type = lib.types.listOf ruleGroupModule;
    default = [ ];
    description = ''
      Rule groups to declaratively manage in Maintainerr.
      Rule groups present in Maintainerr but not listed here will be deleted.

      Note: changing dataType, library, manualCollection, or manualCollectionName
      on an existing rule group causes Maintainerr to clear all media currently in
      that collection.
    '';
    example = lib.literalExpression ''
      [
        {
          name = "Movies To Delete";
          description = "Deletes movies that have been watched or around too long.";
          library = "Movies";
          dataType = "movie";
          radarrServerName = "Radarr";
          collection.deleteAfterDays = 14;
          rules = [
            {
              customVal = { ruleTypeId = 3; value = "1"; };
              operator = null;
              firstVal = [ 6 42 ];
              action = "EQUALS";
              section = 0;
            }
          ];
        }
      ]
    '';
  };
}
