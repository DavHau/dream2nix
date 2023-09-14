{
  config,
  lib,
  dream2nix,
  ...
}: let
  l = lib // builtins;
  cfg = config.pip;
  python = config.deps.python;
  metadata = config.lock.content.fetchPipMetadata;

  # filter out ignored dependencies
  targets = cfg.targets;

  writers = import ../../../pkgs/writers {
    inherit lib;
    inherit
      (config.deps)
      bash
      coreutils
      gawk
      path
      writeScript
      writeScriptBin
      ;
  };

  drvs =
    l.mapAttrs (
      name: info: {
        imports = [
          commonModule
          dependencyModule
          # include community overrides
          (dream2nix.overrides.python.${name} or {})
        ];
        config = {
          inherit name;
          inherit (info) version;
        };
      }
    )
    metadata.sources;

  dependencyModule = {config, ...}: {
    # deps.python cannot be defined in commonModule as this would trigger an
    #   infinite recursion.
    deps = {inherit python;};
    buildPythonPackage.format = l.mkDefault (
      if l.hasSuffix ".whl" config.mkDerivation.src
      then "wheel"
      else "setuptools"
    );
  };

  fetchers = {
    url = info: l.fetchurl {inherit (info) url sha256;};
    git = info: config.deps.fetchgit {inherit (info) url sha256 rev;};
  };

  commonModule = {config, ...}: {
    imports = [
      dream2nix.modules.dream2nix.mkDerivation
      ../buildPythonPackage
    ];
    config = {
      deps = {nixpkgs, ...}:
        l.mapAttrs (_: l.mkOverride 1001) {
          inherit
            (nixpkgs)
            autoPatchelfHook
            bash
            coreutils
            gawk
            gitMinimal
            mkShell
            path
            stdenv
            unzip
            writeScript
            writeScriptBin
            ;
          inherit (nixpkgs.pythonManylinuxPackages) manylinux1;
        };
      mkDerivation = {
        src = l.mkDefault (fetchers.${metadata.sources.${config.name}.type} metadata.sources.${config.name});
        doCheck = l.mkDefault false;
        dontStrip = l.mkDefault true;

        nativeBuildInputs =
          [config.deps.unzip]
          ++ (l.optionals config.deps.stdenv.isLinux [config.deps.autoPatchelfHook]);
        buildInputs =
          l.optionals config.deps.stdenv.isLinux [config.deps.manylinux1];
        # This is required for autoPatchelfHook to find .so files from other
        # python dependencies, like for example libcublas.so.11 from nvidia-cublas-cu11.
        preFixup = lib.optionalString config.deps.stdenv.isLinux ''
          addAutoPatchelfSearchPath ${toString (config.mkDerivation.propagatedBuildInputs)}
        '';
        propagatedBuildInputs = let
          depsByExtra = extra: targets.${extra}.${config.name} or [];
          defaultDeps = targets.default.${config.name} or [];
          deps = defaultDeps ++ (l.concatLists (l.map depsByExtra cfg.buildExtras));
        in
          l.map (name: cfg.drvs.${name}.public.out) deps;
      };
    };
  };
in {
  imports = [
    commonModule
    ./interface.nix
    ../pip-hotfixes
  ];

  deps = {nixpkgs, ...}:
    l.mapAttrs (_: l.mkOverride 1002) {
      # This is imported directly instead of depending on dream2nix.packages
      # with the intention to keep modules independent.
      fetchPipMetadataScript = import ../../../pkgs/fetchPipMetadata/script.nix {
        inherit lib;
        inherit (cfg) pypiSnapshotDate pipFlags pipVersion requirementsList requirementsFiles nativeBuildInputs;
        inherit (config.deps) writePureShellScript nix;
        inherit (config.paths) findRoot;
        inherit (nixpkgs) gitMinimal nix-prefetch-scripts python3 writeText;
        pythonInterpreter = "${python}/bin/python";
      };
      setuptools = config.deps.python.pkgs.setuptools;
      inherit (nixpkgs) nix fetchgit;
      inherit (writers) writePureShellScript;
    };

  # Keep package metadata fetched by Pip in our lockfile
  lock.fields.fetchPipMetadata = {
    script = config.deps.fetchPipMetadataScript;
  };

  # if any of the invalidationData changes, the lock file will be invalidated
  #   and the user will be promted to re-generate it.
  lock.invalidationData = {
    pip = {
      inherit
        (config.pip)
        pypiSnapshotDate
        pipFlags
        pipVersion
        requirementsList
        requirementsFiles
        ;
      pythonVersion = config.deps.python.version;
    };
  };

  pip = {
    drvs = drvs;
    rootDependencies =
      l.genAttrs (targets.default.${config.name} or []) (_: true);
  };

  mkDerivation = {
    propagatedBuildInputs = let
      rootDeps = lib.filterAttrs (_: x: x == true) cfg.rootDependencies;
    in
      l.attrValues (l.mapAttrs (name: _: cfg.drvs.${name}.public.out) rootDeps);
  };

  public.devShell = let
    pyEnv' = config.deps.python.withPackages (ps: config.mkDerivation.propagatedBuildInputs);
    pyEnv = pyEnv'.override (old: {
      # namespaced packages are triggering a collision error, but this can be
      # safely ignored. They are still set up correctly and can be imported.
      ignoreCollisions = true;
    });
  in
    pyEnv.env;
}
