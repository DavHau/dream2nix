{
  pkgs,

  externalSources,
  location,
  translators,
  ...
}:
let
  callPackage = pkgs.callPackage;
in
{

  # the unified translator cli
  cli = callPackage ({ python3, writeScript, ... }:
    writeScript "cli" ''
      export d2nExternalSources=${externalSources}

      translatorsJsonFile=${translators.translatorsJsonFile} \
      dream2nixSrc=${../.} \
        ${python3}/bin/python ${./cli.py} "$@"
    ''
  ) {};

  # install the framework to a specified location by copying the code
  install = callPackage ({ writeScript, }:
    writeScript
      "install"
      ''
        target="$1"
        if [[ "$target" == "" ]]; then
          echo "specify target"
          exit 1
        fi

        mkdir -p "$target"
        if [ -n "$(ls -A $target)" ]; then
          echo "target directory not empty"
          exit 1
        fi

        cp -r ${location}/* $target/
        mkdir $target/external
        cp -r ${externalSources}/* $target/external/
        chmod -R +w $target
      ''
  ) {};
}
