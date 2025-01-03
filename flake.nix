{
  description = "Simplified nix packaging for various programming language ecosystems";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    # TODO: go back to upstream after PRs are merged
    pyproject-nix.url = "github:pyproject-nix/pyproject.nix";

    purescript-overlay.url = "github:thomashoneyman/purescript-overlay";
    purescript-overlay.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = inputs: let
    inherit
      (builtins)
      mapAttrs
      readDir
      ;

    inherit
      (inputs.nixpkgs.lib)
      filterAttrs
      mapAttrs'
      removeSuffix
      ;

    devFlake = import ./dev-flake;

    modulesDir = ./modules;

    moduleKinds =
      filterAttrs (_: type: type == "directory") (readDir modulesDir);

    mapModules = kind:
      mapAttrs'
      (fn: _: {
        name = removeSuffix ".nix" fn;
        value = modulesDir + "/${kind}/${fn}";
      })
      (readDir (modulesDir + "/${kind}"));

    # expose core-modules at the top-level
    corePath = ./modules/dream2nix/core;
    coreDirs = filterAttrs (name: _: name != "default.nix") (readDir corePath);
    coreModules =
      mapAttrs'
      (fn: _: {
        name = removeSuffix ".nix" fn;
        value = corePath + "/${fn}";
      })
      (filterAttrs (_: type: type == "regular" || type == "directory") coreDirs);
  in {
    modules = let
      allModules = mapAttrs (kind: _: mapModules kind) moduleKinds;
    in
      allModules
      // {
        dream2nix = allModules.dream2nix or {} // coreModules;
      };

    lib = import ./lib {
      dream2nix = inputs.self;
      inherit (inputs.nixpkgs) lib;
    };

    overrides = let
      overridesDir = ./overrides;
    in
      mapAttrs
      (
        category: _type:
          mapAttrs
          (name: _type: overridesDir + "/${category}/${name}")
          (readDir (overridesDir + "/${category}"))
      )
      (readDir overridesDir);

    inherit
      (devFlake)
      checks
      devShells
      packages
      templates
      ;
  };
}
