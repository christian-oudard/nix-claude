{
  description = "Declarative configuration for Claude Code via Nix";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      lib = nixpkgs.lib;
      eachSystem = lib.genAttrs [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
    in
    {
      lib.mkClaudeConfig = import ./lib/mkClaudeConfig.nix { inherit lib; };
      lib.build = import ./lib/build.nix { inherit lib; };
      lib.options = import ./lib/options.nix { inherit lib; };

      homeManagerModules.default = import ./modules/home-manager.nix;
      homeManagerModules.claude-code = self.homeManagerModules.default;

      checks = eachSystem (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          mkClaudeConfig = import ./lib/mkClaudeConfig.nix { inherit lib; };
          build = import ./lib/build.nix { inherit lib; };
        in
        import ./tests { inherit pkgs lib mkClaudeConfig build; }
      );
    };
}
