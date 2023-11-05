# This is currently only used for legacy modules ported to v1.
# The dream-lock concept might be deprecated together with this module at some
#   point.
{lib, ...}: let
  l = builtins // lib;

  getDreamLockSource = fetchedSources: pname: version:
    if
      fetchedSources
      ? "${pname}"."${version}"
      && fetchedSources."${pname}"."${version}" != "unknown"
    then fetchedSources."${pname}"."${version}"
    else
      throw ''
        The source for ${pname}#${version} is not defined.
        This can be fixed via an override. Example:
        ```
          dream2nix.make[Flake]Outputs {
            ...
            sourceOverrides = oldSources: {
              "${pname}"."${version}" = builtins.fetchurl { ... };
            };
            ...
          }
        ```
      '';
in
  getDreamLockSource
