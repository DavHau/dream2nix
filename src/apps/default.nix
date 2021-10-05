{
  pkgs,

  callPackageDream,
  externalSources,
  dream2nixWithExternals,
  translators,
  ...
}:
rec {
  apps = { inherit cli contribute install; };

  # the unified translator cli
  cli = callPackageDream (import ./cli) {};

  # the contribute cli
  contribute = callPackageDream (import ./contribute) {};

  # install the framework to a specified location by copying the code
  install = callPackageDream (import ./install) {};
}
