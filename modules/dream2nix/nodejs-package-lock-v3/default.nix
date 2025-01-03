{
  config,
  lib,
  dream2nix,
  ...
}: let
  l = lib // builtins;
  cfg = config.nodejs-package-lock-v3;

  inherit (config.deps) fetchurl fetchGit;

  nodejsLockUtils = import ../../../lib/internal/nodejsLockUtils.nix {inherit lib;};

  isLink = plent: plent ? link && plent.link;

  parseSource = plent:
    if isLink plent
    then
      # entry is local file
      (builtins.dirOf config.nodejs-package-lock-v3.packageLockFile) + "/${plent.resolved}"
    else if (l.hasPrefix "git+" plent.resolved)
    then let
      split = l.splitString "#" plent.resolved;
    in
      fetchGit {
        url = l.removePrefix "git+" (builtins.head split);
        shallow = true;
        allRefs = true;
        rev = builtins.head (builtins.tail split);
      }
    else
      fetchurl {
        url = plent.resolved;
        hash = plent.integrity;
      };

  getDependencies = lock: path: plent:
    l.mapAttrs (name: _descriptor: {
      dev = plent.dev or false;
      version = let
        # Need this util as dependencies no explizitly locked version
        # This findEntry is needed to find the exact locked version
        packageIdent = nodejsLockUtils.findEntry lock path name;
      in
        # Read version from package-lock entry for the resolved package
        lock.packages.${packageIdent}.version;
    })
    (plent.dependencies or {} // plent.devDependencies or {} // plent.optionalDependencies or {});

  # Takes one entry of "package" from package-lock.json
  parseEntry = lock: path: entry:
    if path == ""
    then {
      # Root level package
      name = entry.name;
      value = {
        ${entry.version or ""} = {
          dependencies = getDependencies lock path entry;
        };
      };
    }
    else let
      source = parseSource entry;
      version =
        if isLink entry
        then let
          pjs = l.fromJSON (l.readFile (source + "/package.json"));
        in
          pjs.version
        else entry.version;
    in
      # Every other package
      {
        name = l.last (builtins.split "node_modules/" path);
        value = {
          ${version} = {
            dependencies = getDependencies lock path entry;
            inherit source;
          };
        };
      };

  parse = lock:
    builtins.foldl'
    (acc: entry:
      acc
      // {
        ${entry.name} = acc.${entry.name} or {} // entry.value;
      })
    {}
    # [{name=; value=;} ...]
    (l.mapAttrsToList (parseEntry lock) lock.packages);

  pdefs = parse config.nodejs-package-lock-v3.packageLock;
in {
  imports = [
    ./interface.nix
    dream2nix.modules.dream2nix.core
  ];

  # declare external dependencies
  deps = {nixpkgs, ...}: {
    inherit
      (nixpkgs)
      fetchurl
      ;
    inherit
      (builtins)
      fetchGit
      ;
  };

  nodejs-package-lock-v3.pdefs = pdefs;
  nodejs-package-lock-v3.packageLock =
    lib.mkDefault
    (builtins.fromJSON (builtins.readFile cfg.packageLockFile));
}
