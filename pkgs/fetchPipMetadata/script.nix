# fetchPipMetadata downloads python packages specified by executing
#   `pip download` on a source tree, or a list of requirements.
# TODO: ignore if packages are yanked
{
  lib,
  writeText,
  # Use the nixpkgs default python version for the proxy script.
  # The python version select by the user below might be too old for the
  #   dependencies required by the proxy
  python3,
  # Specify the python version for which the packages should be downloaded.
  # Pip needs to be executed from that specific python version.
  # Pip accepts '--python-version', but this works only for wheel packages.
  pythonInterpreter,
  # list of strings of requirements.txt entries
  requirementsList ? [],
  # list of requirements.txt files
  requirementsFiles ? [],
  pipFlags ? [],
  pipVersion ? "24.0",
  env ? {},
  wheelVersion ? "0.43.0",
  nativeBuildInputs ? [],
  # executable that returns the project root
  findRoot,
  nix,
  gitMinimal,
  writePureShellScript,
  nix-prefetch-scripts,
  openssh,
  fetchFromGitHub,
  fetchurl,
  rustPlatform,
}: let
  package = import ./package.nix {
    inherit
      lib
      python3
      gitMinimal
      nix-prefetch-scripts
      ;
  };

  path = [nix gitMinimal openssh] ++ nativeBuildInputs;

  args = writeText "pip-args" (builtins.toJSON {
    # add some variables to the derivation to integrate them into finalAttrs
    inherit
      pipVersion
      pipFlags
      pythonInterpreter
      requirementsFiles
      requirementsList
      wheelVersion
      ;
  });

  script =
    writePureShellScript
    path
    ''
      ${
        lib.foldlAttrs
        (acc: name: value: acc + "\nexport " + lib.toShellVar name value)
        ""
        env
      }
      ${package}/bin/fetch_pip_metadata \
        --json-args-file "${args}" \
        --project-root "$(${findRoot})"
    '';
in
  script
