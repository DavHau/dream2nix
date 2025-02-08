{
  inputs,
  cell,
}: {
  default = cell.packages.app;
  app =
    # a terrible idea
    (inputs.dream2nix.lib.makeFlakeOutputs {
      systems = [inputs.nixpkgs.system];
      source = inputs.src;
      projects = {
        prettier = {
          name = "prettier";
          subsystem = "nodejs";
          translator = "yarn-lock";
        };
      };
    })
    .packages
    .${inputs.nixpkgs.system}
    .default;
}
