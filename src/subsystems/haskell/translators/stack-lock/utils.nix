{
  inputs,
  lib,
  dlib,
  pkgs,
}: let
  l = lib // builtins;

  flakeCompat = import (builtins.fetchTarball {
    url = "https://github.com/edolstra/flake-compat/tarball/b4a34015c698c7793d592d66adbab377907a2be8";
    sha256 = "1qc703yg0babixi6wshn5wm2kgl5y1drcswgszh4xxzbrwkk9sv7";
  });
in rec {
  cabal2jsonSrc = builtins.fetchTarball {
    url = "https://github.com/NorfairKing/cabal2json/tarball/8b864d93e3e99eb547a0d377da213a1fae644902";
    sha256 = "0zd38mzfxz8jxdlcg3fy6gqq7bwpkfann9w0vd6n8aasyz8xfbpj";
  };

  cabal2jsonFlake = flakeCompat {
    src = cabal2jsonSrc;
  };

  cabal2json = cabal2jsonFlake.defaultNix.packages.${pkgs.system}.cabal2json;

  # parse cabal file via IFD
  fromCabal = file: name: let
    file' = l.path {path = file;};
    jsonFile = pkgs.runCommand "${name}.cabal.json" {} ''
      ${cabal2json}/bin/cabal2json ${file'} > $out
    '';
  in
    l.fromJSON (l.readFile jsonFile);

  fromYaml = file: let
    file' = l.path {path = file;};
    jsonFile = pkgs.runCommand "yaml.json" {} ''
      ${pkgs.yaml2json}/bin/yaml2json < ${file'} > $out
    '';
  in
    l.fromJSON (l.readFile jsonFile);

  batchCabal2Json = candidates: let
    candidatesJsonStr = l.toJSON candidates;
    convertOne = name: version: ''
      cabalFile=${inputs.all-cabal-hashes}/${name}/${version}/${name}.cabal
      if [ -e $cabalFile ]; then
        echo "converting cabal to json: ${name}-${version}"
        mkdir -p $out/${name}/${version}
        ${cabal2json}/bin/cabal2json \
          $cabalFile \
          > $out/${name}/${version}/cabal.json
      else
        echo could not find $cabalFile
        echo $(dirname $(dirname $cabalFile))
        ls $(dirname $(dirname $cabalFile))
        echo all-cabal-hashes might be outdated
        exit 1
      fi
    '';
  in
    pkgs.runCommand "cabal-json-files" {}
    (l.concatStringsSep "\n"
      (l.map (c: convertOne c.name c.version) candidates));

  batchCabalData = candidates: let
    batchJson = batchCabal2Json candidates;
  in
    l.mapAttrs
    (name: _:
      l.mapAttrs
      (version: _: l.fromJSON (l.readFile "${batchJson}/${name}/${version}/cabal.json"))
      (l.readDir "${batchJson}/${name}"))
    (l.readDir batchJson);
}
