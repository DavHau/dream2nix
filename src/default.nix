{
  pkgs ? import <nixpkgs> {},
  externalSources ?
    if builtins.getEnv "d2nExternalSources" != "" then
      builtins.getEnv "d2nExternalSources"
    else
      ./external,
}:

let

  utils = callPackage ./utils.nix {};

  callPackage = f: args: pkgs.callPackage f (args // {
    inherit callPackage;
    inherit utils;
  });

  externals = {
    npmlock2nix = pkgs.callPackage "${externalSources}/npmlock2nix/internal.nix" {};
  };
in

rec {

  apps = callPackage ./apps { inherit externalSources location translators; };

  builders = callPackage ./builders {};

  fetchers = callPackage ./fetchers {};

  translators = callPackage ./translators { inherit externalSources externals location; };


  # the location of the dream2nix framework for self references (update scripts, etc.)
  location = ./.;


  # automatically find a suitable builder for a given generic lock
  findBuilder = genericLock:
    let
      buildSystem = genericLock.generic.buildSystem;
    in
      builders."${buildSystem}".default;


  # detect if granular or combined fetching must be used
  findFetcher = genericLock:
      if null != genericLock.generic.sourcesCombinedHash then
        fetchers.combinedFetcher
      else
        fetchers.defaultFetcher;


  parseLock = lock:
    if builtins.isPath lock || builtins.isString lock then
      builtins.fromJSON (builtins.readFile lock)
    else
      lock;


  fetchSources =
    {
      genericLock,
      builder ? findBuilder (parseLock genericLock),
      fetcher ? findFetcher (parseLock genericLock)
    }:
    let
      # is generic lock is a file, read and parse it
      genericLock' = (parseLock genericLock);
      fetched = fetcher {
        sources = genericLock'.sources;
        sourcesCombinedHash = genericLock'.generic.sourcesCombinedHash;
      };
    in
      fetched;


  # automatically build package defined by generic lock
  buildPackage = 
    {
      genericLock,
      builder ? findBuilder (parseLock genericLock),
      fetcher ? findFetcher (parseLock genericLock)
    }@args:
    let
      # is generic lock is a file, read and parse it
      genericLock' = (parseLock genericLock);
    in
    builder {
      genericLock = genericLock';
      fetchedSources = (fetchSources args).fetchedSources;
    };
   
}
