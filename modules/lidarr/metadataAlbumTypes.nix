# Lidarr's set of primary/secondary album types and release statuses is fixed by its API
# These are not user-configurable lists.
{
  primaryAlbumTypeDefs = [
    {
      id = 0;
      name = "Album";
      option = "enableAlbum";
    }
    {
      id = 1;
      name = "EP";
      option = "enableEP";
    }
    {
      id = 2;
      name = "Single";
      option = "enableSingle";
    }
    {
      id = 3;
      name = "Broadcast";
      option = "enableBroadcast";
    }
    {
      id = 4;
      name = "Other";
      option = "enableOther";
    }
  ];

  secondaryAlbumTypeDefs = [
    {
      id = 0;
      name = "Studio";
      option = "enableStudio";
    }
    {
      id = 1;
      name = "Compilation";
      option = "enableCompilation";
    }
    {
      id = 2;
      name = "Soundtrack";
      option = "enableSoundtrack";
    }
    {
      id = 3;
      name = "Spokenword";
      option = "enableSpokenword";
    }
    {
      id = 4;
      name = "Interview";
      option = "enableInterview";
    }
    {
      id = 6;
      name = "Live";
      option = "enableLive";
    }
    {
      id = 7;
      name = "Remix";
      option = "enableRemix";
    }
    {
      id = 8;
      name = "DJ-mix";
      option = "enableDJMix";
    }
    {
      id = 9;
      name = "Mixtape/Street";
      option = "enableMixtapeStreet";
    }
    {
      id = 10;
      name = "Demo";
      option = "enableDemo";
    }
    {
      id = 11;
      name = "Audio drama";
      option = "enableAudioDrama";
    }
  ];

  releaseStatusDefs = [
    {
      id = 0;
      name = "Official";
      option = "enableOfficial";
    }
    {
      id = 1;
      name = "Promotion";
      option = "enablePromotion";
    }
    {
      id = 2;
      name = "Bootleg";
      option = "enableBootleg";
    }
    {
      id = 3;
      name = "Pseudo-Release";
      option = "enablePseudoRelease";
    }
  ];
}
