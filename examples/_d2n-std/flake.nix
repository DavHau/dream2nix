{
  inputs = {
    std.url = "github:divnix/std";
    dream2nix.url = "github:nix-community/dream2nix";
    dream2nix.inputs.nixpkgs.follows = "std/nixpkgs";
    nixpkgs.follows = "std/nixpkgs";
    src.url = "github:prettier/prettier/2.4.1";
    src.flake = false;
  };

  outputs = {
    std,
    self,
    ...
  } @ inputs:
    std.growOn {
      inherit inputs;
      cellsFrom = ./nix;
      cellBlocks = with std.blockTypes; [
        (installables "packages" {ci.build = true;})
      ];
    }
    # compat with `nix` cli
    {
      packages = std.harvest self ["app" "packages"];
    };
}
