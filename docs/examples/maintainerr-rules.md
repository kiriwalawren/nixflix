---
title: Maintainerr Rules
---

# Maintainerr Rules

Maintainerr rules are complex enough that the easiest way to configure them is to
build them through the UI first, retrieve the resulting JSON from the API, and then
declare them in Nix.

## Workflow

1. Enable Maintainerr and rebuild so the service is running.
1. Open the Maintainerr UI and create your rule groups through the **Rules** page.
   Configure the library, data type, collection settings, and individual rule conditions
   to your liking.
1. Once you are happy with the rules, retrieve them from the API:

    ```bash
    curl -s http://localhost:6246/api/rules | jq .
    ```

1. For each rule group, convert the JSON to a Nix attribute set and add it to
   `nixflix.maintainerr.rules`. See [Conversion Notes](#conversion-notes) below
   for how each field maps.

1. Rebuild. The `maintainerr-rules` service will create or update the declared rule
   groups and delete any that are no longer listed.

## Conversion Notes

The Nix structure maps directly to the API response with a few differences:

**`library`** — set this to the human-readable library title (e.g. `"Movies"`), not
the raw `libraryId` GUID from the API response. The service resolves the title to an
ID at runtime via `GET /api/media-server/libraries`.

**`arrAction`** — taken from `collection.arrAction` in the API response.

**`listExclusions` / `forceSeerr`** — taken from `collection.listExclusions` and
`collection.forceSeerr` in the API response.

**`radarrServerName` / `sonarrServerName`** — set these to the server name as
configured in `nixflix.maintainerr.settings.radarr` / `nixflix.maintainerr.settings.sonarr`
(e.g. `"Radarr"`, `"Sonarr"`, `"Sonarr Anime"`), not the integer `radarrSettingsId` /
`sonarrSettingsId` from the API response. The service resolves the name to an ID at
runtime.

**`rules`** — each entry in the `rules` array of the API response contains a
`ruleJson` string. Parse that string and use its fields directly:

```bash
# Pretty-print all ruleJson values for a rule group
curl -s http://localhost:6246/api/rules | jq '.[0].rules[].ruleJson | fromjson'
```

Fields that match their defaults can be omitted:

| Field | Default |
|-------|---------|
| `isActive` | `true` |
| `useRules` | `true` |
| `ruleHandlerCronSchedule` | `null` |
| `arrAction` | `0` |
| `listExclusions` | `true` |
| `forceSeerr` | `false` |
| `radarrServerName` | `null` |
| `sonarrServerName` | `null` |
| `collection.visibleOnRecommended` | `true` |
| `collection.visibleOnHome` | `true` |
| `collection.deleteAfterDays` | `null` |
| `collection.manualCollection` | `false` |
| `collection.manualCollectionName` | `""` |
| `collection.keepLogsForMonths` | `6` |
| `collection.overlayEnabled` | `false` |
| rule `operator` | `null` |
| rule `customVal` | `null` |
| rule `lastVal` | `null` |

## Example

```nix
nixflix.maintainerr.rules = [
  {
    name = "Movies To Delete";
    description = "Deletes movies that have been watched or have been around for too long.";
    library = "Movies";
    dataType = "movie";
    radarrServerName = "Radarr";
    collection = {
      deleteAfterDays = 14;
      overlayEnabled = true;
    };
    rules = [
      {
        customVal = { ruleTypeId = 3; value = "1"; };
        firstVal = [ 6 42 ];
        action = 2;
        section = 0;
      }
      {
        customVal = { ruleTypeId = 0; value = "23328000"; };
        operator = "1";
        firstVal = [ 6 0 ];
        action = 5;
        section = 0;
      }
      {
        operator = "0";
        firstVal = [ 6 39 ];
        action = 19;
        section = 1;
      }
    ];
  }
  {
    name = "Shows To Ignore";
    description = "Shows with empty folders that are not yet ended.";
    library = "Shows";
    dataType = "show";
    arrAction = 4;
    sonarrServerName = "Sonarr";
    rules = [
      {
        customVal = { ruleTypeId = 0; value = "0"; };
        firstVal = [ 2 1 ];
        action = 2;
        section = 0;
      }
      {
        customVal = { ruleTypeId = 3; value = "0"; };
        operator = "0";
        firstVal = [ 2 7 ];
        action = 2;
        section = 0;
      }
      {
        operator = "0";
        firstVal = [ 6 40 ];
        action = 19;
        section = 1;
      }
    ];
  }
];
```

## Rule Logic Reference

Rules within the same `section` are **ANDed** together; different sections are **ORed**.
The first rule in each section must have `operator = null`; subsequent rules use
`operator = "0"` (AND) or `operator = "1"` (OR).

`action` values correspond to `RulePossibility` in the Maintainerr source:

| Value | Name |
|-------|------|
| 0 | BIGGER |
| 1 | SMALLER |
| 2 | EQUALS |
| 3 | NOT_EQUALS |
| 4 | CONTAINS |
| 5 | BEFORE |
| 6 | AFTER |
| 7 | IN_LAST |
| 8 | IN_NEXT |
| 9 | NOT_CONTAINS |
| 10 | CONTAINS_PARTIAL |
| 11 | NOT_CONTAINS_PARTIAL |
| 12 | CONTAINS_ALL |
| 13 | NOT_CONTAINS_ALL |
| 14 | COUNT_EQUALS |
| 15 | COUNT_NOT_EQUALS |
| 16 | COUNT_BIGGER |
| 17 | COUNT_SMALLER |
| 18 | EXISTS |
| 19 | NOT_EXISTS |

`arrAction` values correspond to `ServarrAction`:

| Value | Name |
|-------|------|
| 0 | DELETE |
| 1 | UNMONITOR_DELETE_ALL |
| 2 | UNMONITOR_DELETE_EXISTING |
| 3 | UNMONITOR |
| 4 | DO_NOTHING |
| 5 | DELETE_SHOW_IF_EMPTY |
| 6 | UNMONITOR_SHOW_IF_EMPTY |
| 7 | CHANGE_QUALITY_PROFILE |
