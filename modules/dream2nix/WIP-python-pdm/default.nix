{
  config,
  lib,
  dream2nix,
  ...
}: let
  libpdm = import ./lib.nix {
    inherit lib libpyproject;
    python3 = config.deps.python;
    targetPlatform =
      lib.systems.elaborate config.deps.python.stdenv.targetPlatform;
  };

  libpyproject = dream2nix.inputs.pyproject-nix.lib;

  lock_data = lib.importTOML config.pdm.lockfile;
  environ = libpyproject.pep508.mkEnviron config.deps.python;

  pyproject = libpdm.loadPdmPyProject (lib.importTOML config.pdm.pyproject);

  groups_with_deps = libpdm.groupsWithDeps {
    inherit environ pyproject;
  };
  parsed_lock_data = libpdm.parseLockData {
    inherit environ lock_data;
  };
  buildSystemNames =
    map
    (name: (libpyproject.pep508.parseString name).name)
    (pyproject.pyproject.build-system.requires or []);

  commonModule = depConfig: let
    cfg = depConfig.config;
    setuptools =
      if cfg.name == "setuptools"
      then config.deps.python.pkgs.setuptools
      else if config.groups.default.packages ? setuptools
      then (lib.head (lib.attrValues config.groups.default.packages.setuptools)).public
      else config.deps.python.pkgs.setuptools;
  in {
    imports = [
      dream2nix.modules.dream2nix.buildPythonPackage
    ];
    config.mkDerivation.buildInputs =
      lib.optionals
      (! lib.hasSuffix ".whl" cfg.mkDerivation.src)
      [setuptools];
  };
in {
  imports = [
    ../overrides
    ./interface.nix
    ./lock.nix
    commonModule
  ];
  name = pyproject.pyproject.project.name;
  version = lib.mkDefault (
    if pyproject.pyproject.project ? version
    then pyproject.pyproject.project.version
    else if lib.elem "version" pyproject.pyproject.project.dynamic or []
    then "dynamic"
    else "unknown"
  );
  deps = {nixpkgs, ...}: {
    inherit
      (nixpkgs)
      autoPatchelfHook
      buildPackages
      curl
      fetchPypiLegacy
      jq
      mkShell
      pdm
      uv
      runCommand
      stdenvNoCC
      stdenv
      writeText
      unzip
      ;
  };
  overrideType = {
    imports = [commonModule];
  };
  overrideAll = {
    deps = {nixpkgs, ...}: {
      python = lib.mkDefault config.deps.python;
    };
  };
  pdm = {
    sourceSelector = lib.mkDefault libpdm.preferWheelSelector;
    inherit (config) overrides overrideAll;
    inherit (config) name paths;
    inherit (config.public) pyEnv;
    # make root package always editable
    editables = {
      ${config.name} = config.paths.package;
    };
  };
  buildPythonPackage = {
    pyproject = lib.mkDefault true;
  };
  mkDerivation = {
    buildInputs = map (name: config.deps.python.pkgs.${name}) buildSystemNames;
    propagatedBuildInputs =
      map
      (x: (lib.head (lib.attrValues x)).public)
      # all packages attrs prefixed with version
      (lib.attrValues config.groups.default.packages);
  };

  public.pyEnv = let
    pyEnv' = config.deps.python.withPackages (
      ps:
        config.mkDerivation.propagatedBuildInputs
        # the editableShellHook requires wheel and other build system deps.
        ++ config.mkDerivation.buildInputs
        ++ [config.deps.python.pkgs.wheel]
    );
  in
    pyEnv'.override (old: {
      # namespaced packages are triggering a collision error, but this can be
      # safely ignored. They are still set up correctly and can be imported.
      ignoreCollisions = true;
    });
  public.shellHook = config.pdm.editablesShellHook;

  public.devShell = config.deps.mkShell {
    shellHook = config.public.shellHook;
    packages = [
      config.public.pyEnv
      config.deps.pdm
    ];
    buildInputs =
      [
        config.groups.default.packages.tomli.public or config.deps.python.pkgs.tomli
      ]
      ++ lib.flatten (
        lib.mapAttrsToList
        (name: _path: config.groups.default.packages.${name}.evaluated.mkDerivation.buildInputs or [])
        config.pdm.editables
      );
    nativeBuildInputs = lib.flatten (
      lib.mapAttrsToList
      (name: _path: config.groups.default.packages.${name}.evaluated.mkDerivation.nativeBuildInputs or [])
      config.pdm.editables
    );
  };

  groups = let
    groupNames = lib.attrNames groups_with_deps;
    populateGroup = groupname: let
      # Get transitive closure for specific group.
      # The 'default' group is always included no matter the selection.
      transitiveGroupDeps = libpdm.closureForGroups {
        inherit parsed_lock_data groups_with_deps;
        groupNames = lib.unique ["default" groupname];
      };

      packages = lib.flip lib.mapAttrs transitiveGroupDeps (name: pkg: {
        ${pkg.version}.module = {...} @ depConfig: let
          cfg = depConfig.config;
          selector =
            if lib.isFunction cfg.sourceSelector
            then cfg.sourceSelector
            else if cfg.sourceSelector == "wheel"
            then libpdm.preferWheelSelector
            else if cfg.sourceSelector == "sdist"
            then libpdm.preferSdistSelector
            else throw "Invalid sourceSelector: ${cfg.sourceSelector}";
          source = pkg.sources.${selector (lib.attrNames pkg.sources)};
        in {
          imports = [
            ./interface-dependency.nix
            dream2nix.modules.dream2nix.buildPythonPackage
            dream2nix.modules.dream2nix.mkDerivation
            dream2nix.modules.dream2nix.package-func
            (dream2nix.overrides.python.${name} or {})
          ];
          inherit name;
          version = lib.mkDefault pkg.version;
          sourceSelector = lib.mkOptionDefault config.pdm.sourceSelector;
          buildPythonPackage.format = lib.mkDefault (
            if lib.hasSuffix ".whl" source.file
            then "wheel"
            else null
          );
          mkDerivation = {
            src = lib.mkDefault (config.deps.fetchPypiLegacy {
              pname = name;
              file = source.file;
              hash = source.hash;
              urls =
                [
                  "https://pypi.org/simple"
                ]
                ++ lib.optionals (lib.hasAttrByPath ["tool" "pdm" "source"] pyproject.pyproject) (builtins.map (source: source.url) pyproject.pyproject.tool.pdm.source);
            });
            propagatedBuildInputs =
              lib.mapAttrsToList
              (name: dep: (lib.head (lib.attrValues (config.groups.${groupname}.packages.${name}))).public)
              (libpdm.getClosure parsed_lock_data name pkg.extras);
            nativeBuildInputs =
              lib.optionals config.deps.stdenv.isLinux [config.deps.autoPatchelfHook];
            preFixup = lib.optionalString config.deps.stdenv.isLinux ''
              addAutoPatchelfSearchPath $propagatedBuildInputs
            '';
            doCheck = lib.mkDefault false;
            dontStrip = lib.mkDefault true;
          };
          # required for python.withPackages to recognize it as a python package.
          public.pythonModule = config.deps.python;
        };
      });
    in {inherit packages;};
  in
    lib.genAttrs groupNames populateGroup;
}
