_: {
  fromRepo =
    {
      version,
      hash,
      repository ? null,
    }:
    {
      inherit version hash repository;
    };
}
