/*
This example uses an alternative builder
(available builders see: src/subsystems/nodejs/builders )
Building 'Prettier@2.4.1'.
*/
{
  inputs = {
    dream2nix.url = "github:nix-community/dream2nix";
    src.url = "github:prettier/prettier/2.4.1";
    src.flake = false;
  };

  outputs = {
    self,
    dream2nix,
    src,
  }:
    (dream2nix.lib.makeFlakeOutputs {
      systems = ["x86_64-linux" "aarch64-darwin"];
      config.projectRoot = ./.;
      source = src;
      projects = ./projects.toml;
    })
    // {
      checks.x86_64-linux.prettier = self.packages.x86_64-linux.prettier;
    };
}
