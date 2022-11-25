{
  inputs = {
    dream2nix.url = "github:nix-community/dream2nix";
    nixpkgs.follows = "dream2nix/nixpkgs";
    flake-parts.url = "github:hercules-ci/flake-parts";
    src.url = "gitlab:ternaris/rosbags";
    src.flake = false;
  };

  outputs = {
    self,
    dream2nix,
    flake-parts,
    src,
    ...
  }:
    flake-parts.lib.mkFlake {inherit self;} {
      systems = ["x86_64-linux"];
      imports = [dream2nix.flakeModuleBeta];

      perSystem = {
        config,
        system,
        ...
      }: {
        # define an input for dream2nix to generate outputs for
        dream2nix.inputs."rosbags" = {
          source = src;
          projects.rosbags = {
            name = "rosbags";
            subsystem = "python";
            translator = "pip-freeze";
            subsystemInfo = {
              system = system;
              pythonVersion = "3.10";
              requirementsFiles = [
                "requirements.txt"
                "requirements-dev.txt"
              ];
              # For now, just installed into same environment before the rest.
              buildRequires = {
                pytest-runner = "6.0.0"; # flake8-mutable
              };
            };
          };
        };
        # checks.package = config.dream2nix.outputs.rosbags.packages.default;
      };
    };
}
