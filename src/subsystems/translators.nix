{
  coreutils,
  dlib,
  jq,
  lib,
  nix,
  pkgs,
  python3,
  callPackageDream,
  externals,
  dream2nixWithExternals,
  utils,
  config,
  configFile,
  framework,
  ...
}: let
  b = builtins;

  l = lib // builtins;

  # adds a translateBin to a pure translator
  wrapPureTranslator = {
    subsystem,
    name,
  }: let
    bin =
      utils.writePureShellScript
      [
        coreutils
        jq
        nix
        python3
      ]
      ''
        jsonInputFile=$(realpath $1)
        outputFile=$(realpath -m $(jq '.outputFile' -c -r $jsonInputFile))

        pushd $TMPDIR

        nix eval \
          --option experimental-features "nix-command flakes"\
          --show-trace --impure --raw --expr "
          let
            dream2nix = import ${dream2nixWithExternals} {
              config = ${configFile};
            };

            translatorArgs =
              (builtins.fromJSON
                  (builtins.unsafeDiscardStringContext (builtins.readFile '''$1''')));

            dreamLock' =
              dream2nix.subsystems.${subsystem}.translators.${name}.translate
                translatorArgs;
            # simpleTranslate2 puts dream-lock in result
            dreamLock = dreamLock'.result or dreamLock';
          in
            dream2nix.utils.dreamLock.toJSON
              # don't use nix to detect cycles, this will be more efficient in python
              (dreamLock // {
                _generic = builtins.removeAttrs dreamLock._generic [ \"cyclicDependencies\" ];
              })
        " | python3 ${../apps/cli/format-dream-lock.py} > out

        tmpOut=$(realpath out)
        popd
        mkdir -p $(dirname $outputFile)
        cp $tmpOut $outputFile
      '';
  in
    bin.overrideAttrs (old: {
      name = "translator-${subsystem}-pure-${name}";
    });

  makeTranslator = translatorModule: let
    translator =
      translatorModule
      # for pure translators
      #   - import the `translate` function
      #   - generate `translateBin`
      // (lib.optionalAttrs (translatorModule.translate or null != null) {
        translate = let
          translateOriginal = callPackageDream translatorModule.translate {
            translatorName = translatorModule.name;
          };
        in
          args:
            translateOriginal
            (
              (framework.functions.translators.makeTranslatorDefaultArgs
                (translatorModule.extraArgs or {}))
              // args
              // (args.project.subsystemInfo or {})
              // {
                tree =
                  args.tree or (dlib.prepareSourceTree {inherit (args) source;});
              }
            );
        translateBin =
          wrapPureTranslator
          {inherit (translatorModule) subsystem name;};
      })
      # for impure translators:
      #   - import the `translateBin` function
      // (lib.optionalAttrs (translatorModule.translateBin or null != null) {
        translateBin =
          callPackageDream translatorModule.translateBin
          {
            translatorName = translatorModule.name;
          };
      });
  in
    translator;

  translators = framework.translatorsBySubsystem;
in {
  inherit
    translators
    makeTranslator
    ;
}
