{
  config,
  lib,
  dream2nix,
  ...
}: let
  l = lib // builtins;

  cfg = config.nodejs-granular;

  fetchDreamLockSources =
    import ../../../lib/internal/fetchDreamLockSources.nix
    {inherit lib;};
  getDreamLockSource = import ../../../lib/internal/getDreamLockSource.nix {inherit lib;};
  readDreamLock = import ../../../lib/internal/readDreamLock.nix {inherit lib;};
  hashPath = import ../../../lib/internal/hashPath.nix {
    inherit lib;
    inherit (config.deps) runCommandLocal nix;
  };
  hashFile = import ../../../lib/internal/hashFile.nix {
    inherit lib;
    inherit (config.deps) runCommandLocal nix;
  };

  # fetchers
  fetchers = {
    git = import ../../../lib/internal/fetchers/git {
      inherit hashPath;
      inherit (config.deps) fetchgit;
    };
    http = import ../../../lib/internal/fetchers/http {
      inherit hashFile lib;
      inherit (config.deps.stdenv) mkDerivation;
      inherit (config.deps) fetchurl;
    };
  };

  dreamLockLoaded =
    readDreamLock {inherit (config.nodejs-package-lock) dreamLock;};
  dreamLockInterface = dreamLockLoaded.interface;

  inherit (dreamLockInterface) defaultPackageName defaultPackageVersion;

  fetchedSources = fetchDreamLockSources {
    inherit (dreamLockInterface) defaultPackageName defaultPackageVersion;
    inherit (dreamLockLoaded.lock) sources;
    inherit fetchers;
  };

  # name: version: -> store-path
  getSource = getDreamLockSource fetchedSources;

  inherit
    (dreamLockInterface)
    getDependencies # name: version: -> [ {name=; version=; } ]
    # Attributes
    
    subsystemAttrs # attrset
    packageVersions
    ;

  isMainPackage = name: version:
    (dreamLockInterface.packages."${name}" or null) == version;

  nodejs = config.deps.nodejs;

  nodeSources = config.deps.runCommandLocal "node-sources" {} ''
    tar --no-same-owner --no-same-permissions -xf ${nodejs.src}
    mv node-* $out
  '';

  nodejsDeps =
    lib.mapAttrs
    (
      name: versions:
        lib.genAttrs
        versions
        (version: {...}: {
          imports = [
            (commonModule name version)
            (makeDependencyModule name version)
            cfg.overrideAll
            (cfg.overrides.${name} or {})
          ];
        })
    )
    packageVersions;

  # Generates a derivation for a specific package name + version
  makeDependencyModule = name: version: {config, ...}: {
    name = lib.replaceStrings ["@" "/"] ["__at__" "__slash__"] name;
    inherit version;
    env = {
      packageName = name;
    };
    mkDerivation = {
      src = getSource name version;
      /*
      This prevents nixpkg's setup.sh to run make during build and install
        phases.
      Dependencies from npmjs.org are delivered pre-built and cleaned,
        therefore running `make` usually leads to errors.
      The problem with this hack is it can prevent setup-hooks from setting
        buildPhase and installPhase because those are already defined here.
      */
      buildPhase = "runHook preBuild && runHook postBuild";
      installPhase = "runHook preInstall && runHook postInstall";
    };
  };

  commonModule = name: version: {config, ...}: let
    deps = getDependencies name version;

    nodeDeps =
      lib.forEach
      deps
      (dep: cfg.deps."${dep.name}"."${dep.version}".public);

    passthruDeps =
      l.listToAttrs
      (l.forEach deps
        (dep:
          l.nameValuePair
          dep.name
          cfg.deps."${dep.name}"."${dep.version}".public));

    dependenciesJson =
      l.toJSON
      (lib.listToAttrs
        (l.map
          (dep: lib.nameValuePair dep.name dep.version)
          deps));
  in {
    imports = [
      ./interface.nix
    ];

    deps = {nixpkgs, ...}:
      l.mapAttrs (_: l.mkDefault) {
        inherit
          (nixpkgs)
          jq
          makeWrapper
          moreutils
          nodejs
          python3
          stdenv
          ;
      };

    mkDerivation = {
      meta =
        subsystemAttrs.meta
        // {
          license =
            l.map (name: l.licenses.${name}) subsystemAttrs.meta.license;
        };

      passthru.dependencies = passthruDeps;

      # prevents running into ulimits
      passAsFile = ["dependenciesJson" "nodeDeps"];

      nativeBuildInputs = [
        config.deps.makeWrapper
        config.deps.jq
        config.deps.nodejs
      ];
      buildInputs = with config.deps; [jq nodejs python3];
      preConfigurePhases = ["patchPhaseNodejs"];
      preBuildPhases = ["buildPhaseNodejs"];
      preInstallPhases = ["installPhaseNodejs"];
      dontStrip = true;

      # TODO: upstream fix to nixpkgs
      # example which requires this:
      #   https://registry.npmjs.org/react-window-infinite-loader/-/react-window-infinite-loader-1.0.7.tgz
      unpackCmd =
        if
          (config.mkDerivation.src or null != null)
          && (lib.hasSuffix ".tgz" config.mkDerivation.src)
        then "tar --delay-directory-restore -xf $src"
        else null;

      unpackPhase = import ./unpackPhase.nix {};

      # - installs dependencies into the node_modules directory
      # - adds executables of direct node module dependencies to PATH
      # - adds the current node module to NODE_PATH
      # - sets HOME=$TMPDIR, as this is required by some npm scripts
      # TODO: don't install dev dependencies. Load into NODE_PATH instead
      configurePhase = import ./configurePhase.nix {
        inherit lib nodeDeps;
      };
    };

    env = {
      inherit
        dependenciesJson
        nodeDeps
        nodeSources
        ;

      inherit
        (config.nodejs-granular)
        buildScript
        installMethod
        runBuild
        ;

      # The python script wich is executed in this phase:
      #   - ensures that the package is compatible to the current system
      #   - ensures the main version in package.json matches the expected
      #   - pins dependency versions in package.json
      #     (some npm commands might otherwise trigger networking)
      #   - creates symlinks for executables declared in package.json
      # Apart from that:
      #   - Any usage of 'link:' in package.json is replaced with 'file:'
      #   - If package-lock.json exists, it is deleted, as it might conflict
      #     with the parent package-lock.json.

      # costs performance and doesn't seem beneficial in most scenarios
      patchPhaseNodejs = ''
        # delete package-lock.json as it can lead to conflicts
        rm -f package-lock.json

        # repair 'link:' -> 'file:'
        mv $nodeModules/$packageName/package.json $nodeModules/$packageName/package.json.old
        cat $nodeModules/$packageName/package.json.old | sed 's!link:!file\:!g' > $nodeModules/$packageName/package.json
        rm $nodeModules/$packageName/package.json.old

        # run python script (see comment above):
        cp package.json package.json.bak
        python $fixPackage \
        || \
        # exit code 3 -> the package is incompatible to the current platform
        #  -> Let the build succeed, but don't create lib/node_modules
        if [ "$?" == "3" ]; then
          mkdir -p $out
          echo "Not compatible with system $system" > $out/error
          exit 0
        else
          exit 1
        fi
      '';

      # Runs the install command which defaults to 'npm run postinstall'.
      # Allows using custom install command by overriding 'buildScript'.
      buildPhaseNodejs = import ./buildPhase.nix {
        inherit (config.deps) jq moreutils;
      };

      # Symlinks executables and manual pages to correct directories
      installPhaseNodejs = import ./installPhase.nix {
        inherit (config.deps) stdenv;
      };

      # python script to modify some metadata to support installation
      # (see comments below on d2nPatchPhase)
      fixPackage = "${./fix-package.py}";

      # script to install (symlink or copy) dependencies.
      installDeps = "${./install-deps.py}";

      # python script to link bin entries from package.json
      linkBins = "${./link-bins.py}";
    };

    nodejs-granular = {
      /*
      For top-level packages install dependencies as full copies, as this
      reduces errors with build tooling that doesn't cope well with
      symlinking.
      */
      installMethod = l.mkOptionDefault "symlink";

      # only run build on the main package
      runBuild = l.mkOptionDefault (isMainPackage name config.version);

      # can be overridden to define alternative install command
      # (defaults to 'npm run postinstall')
      buildScript = l.mkOptionDefault null;
    };
  };
in {
  imports = [
    ./interface.nix
    dream2nix.modules.dream2nix.mkDerivation
    dream2nix.modules.dream2nix.core
    (commonModule defaultPackageName defaultPackageVersion)
  ];
  deps = {nixpkgs, ...}:
    l.mapAttrs (_: l.mkDefault) {
      inherit (nixpkgs) mkShell;
    };
  env = {
    packageName = config.name;
  };
  mkDerivation = {
    passthru.devShell = import ./devShell.nix {
      inherit (config.deps) nodejs mkShell;
      inherit (config.env) packageName;
      pkg = config.public;
    };
  };
  nodejs-granular = {
    deps = nodejsDeps;
    runBuild = l.mkDefault true;
    installMethod = l.mkDefault "copy";
  };
}
