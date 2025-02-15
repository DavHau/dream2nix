{
  config,
  lib,
  dream2nix,
  specialArgs,
  ...
}: let
  l = lib // builtins;
  t = l.types;
  cfg = config.nodejs-granular;
  mkSubmodule = import ../../../lib/internal/mkSubmodule.nix {inherit lib specialArgs;};
in {
  options.nodejs-granular = mkSubmodule {
    imports = [
      ../overrides
    ];
    config.overrideType = {
      imports = [
        dream2nix.modules.dream2nix.mkDerivation
        dream2nix.modules.dream2nix.core
      ];
    };

    options = l.mapAttrs (_: l.mkOption) {
      buildScript = {
        type = t.nullOr (t.oneOf [t.str t.path t.package]);
        description = ''
          A command or script to execute instead of `npm run build`.
          Is only executed if `runBuild = true`.
        '';
      };
      installMethod = {
        type = t.enum [
          "symlink"
          "copy"
        ];
        description = ''
          Strategy to use for populating ./node_modules.
          Symlinking is quicker, but often introduces compatibility issues with bundlers like webpack and other build tools.
          Copying is slow, but more reliable;
        '';
      };
      runBuild = {
        type = t.bool;
        description = ''
          Whether to run a package's build script (aka. `npm run build`)
        '';
      };
      deps = {
        type = t.lazyAttrsOf (t.lazyAttrsOf (t.submoduleWith {
          modules = [
            cfg.overrideType
          ];
          inherit specialArgs;
        }));
      };
    };
  };
}
