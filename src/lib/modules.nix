{
  dlib,
  lib,
}: let
  l = lib // builtins;

  # imports a module.
  importModule = {
    file,
    validator ? _: true,
    extraArgs,
  }: let
    _module = import file;
    module =
      if l.isFunction _module
      then _module ({inherit dlib lib;} // extraArgs)
      else throw "module file (${file}) must return a function that takes an attrset";
  in
    l.seq (validator module) module;

  collectSubsystemModules = modules: let
    allModules = l.flatten (l.map l.attrValues (l.attrValues modules));
    hasModule = module: modules:
      l.any
      (
        omodule:
          omodule.name
          == module.name
          && omodule.subsystem == module.subsystem
      )
      modules;
  in
    l.foldl'
    (acc: el:
      if hasModule el acc
      then acc
      else acc ++ [el])
    []
    allModules;

  validateExtraModules = f: extra:
    l.foldl'
    (acc: el: l.seq (f el) acc)
    {}
    extra;
  validateExtraModule = extra:
    true;

  makeSubsystemModules = {
    modulesCategory,
    validator,
    extraModules ? [],
  }: let
    callModule = {
      file,
      extraArgs ? {},
    }:
      importModule {inherit file validator extraArgs;};

    validatedExtraModules =
      l.seq
      (validateExtraModules validateExtraModule extraModules)
      extraModules;

    modules =
      l.genAttrs
      dlib.subsystems
      (
        subsystem: let
          modulesDir = ../subsystems + "/${subsystem}/${modulesCategory}";
          moduleNames =
            if l.pathExists modulesDir
            then dlib.dirNames modulesDir
            else [];

          loadModule = name: let
            extraArgs = {inherit subsystem name;};
            module = callModule {
              file = "${modulesDir}/${name}";
              inherit extraArgs;
            };
          in
            module // extraArgs;
        in
          l.filterAttrs
          (name: t: t.disabled or false == false)
          (l.genAttrs moduleNames loadModule)
      );
    modulesExtended =
      l.foldl'
      (
        acc: el:
          l.recursiveUpdate
          acc
          {"${el.subsystem}"."${el.name}" = callModule el;}
      )
      modules
      validatedExtraModules;

    mapModules = f:
      l.mapAttrs
      (
        subsystem: names:
          l.mapAttrs
          (name: module: f module)
          names
      )
      modulesExtended;
  in {
    modules = modulesExtended;
    inherit
      callModule
      mapModules
      ;
  };
in {
  inherit
    importModule
    makeSubsystemModules
    collectSubsystemModules
    ;
}
