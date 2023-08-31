# evaluate packages from `/**/modules/drvs` and export them via `flake.packages`
{
  self,
  inputs,
  ...
}: {
  perSystem = {
    system,
    config,
    lib,
    pkgs,
    ...
  }: let
    inherit
      (lib)
      flip
      foldl
      mapAttrs'
      mapAttrsToList
      ;
    inherit
      (builtins)
      readDir
      ;

    # A module imported into every package setting up the eval cache
    setup = {config, ...}: {
      lock.repoRoot = self;
      eval-cache.repoRoot = self;
      eval-cache.enable = true;
      deps.npm = inputs.nixpkgs.legacyPackages.${system}.nodejs.pkgs.npm.override (old: rec {
        version = "8.19.4";
        src = builtins.fetchTarball {
          url = "https://registry.npmjs.org/npm/-/npm-${version}.tgz";
          sha256 = "0xmvjkxgfavlbm8cj3jx66mlmc20f9kqzigjqripgj71j6b2m9by";
        };
      });
    };

    # evaluates the package behind a given module
    makeDrv = modules: let
      evaled = lib.evalModules {
        modules = modules ++ [self.modules.dream2nix.core];
        specialArgs.packageSets = {
          nixpkgs = inputs.nixpkgs.legacyPackages.${system};
          writers = config.writers;
        };
        specialArgs.dream2nix = self;
      };
    in
      evaled.config.public;

    examplePackagesDirs = readDir (self + "/examples/packages");

    readExamples = dirName: let
      examplesPath = self + /examples/packages + "/${dirName}";
      examples = readDir examplesPath;
    in
      flip mapAttrs' examples
      (name: _: {
        name = "example-package-${name}";
        value = examplesPath + "/${name}";
      });

    allExamples = mapAttrsToList (dirName: _: readExamples dirName) examplePackagesDirs;

    exampleModules = foldl (a: b: a // b) {} allExamples;

    # TODO: remove this line once everything is migrated to the new structure
    allModules' = self.modules.drvs or {} // exampleModules;

    allModules = flip mapAttrs' allModules' (name: module: {
      inherit name;
      value = [
        module
        setup
        {
          lock.lockFileRel = "/locks/${name}/lock-${system}.json";
          eval-cache.cacheFileRel = "/locks/${name}/cache-${system}.json";
        }
      ];
    });
  in {
    # map all modules in /examples to a package output in the flake.
    checks =
      lib.mapAttrs (_: drvModules: makeDrv drvModules)
      allModules;
  };
}
