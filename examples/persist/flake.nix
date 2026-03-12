{
  description = "Example: installing the persist plugin via nix-claude";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nix-claude.url = "github:christian-oudard/nix-claude";  # or path:../..
    persist.url = "github:christian-oudard/persist";
  };

  outputs = { self, nixpkgs, nix-claude, persist }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      # Option A: standalone derivation (for coding-cave or manual install)
      packages.${system}.claude-config = nix-claude.lib.mkClaudeConfig {
        inherit pkgs;
        skipOnboarding = true;
        plugins.persist = persist.plugin.${system};
      };

      # Option B: home-manager module config (for NixOS users)
      # In your home.nix:
      #
      #   imports = [ nix-claude.homeManagerModules.default ];
      #
      #   # Built-in module handles core config
      #   programs.claude-code = {
      #     enable = true;
      #     skipOnboarding = true;
      #   };
      #
      #   # Plugin flakes export a ready-made config attrset
      #   programs.claude-code.plugins.persist = persist.plugin.${system};
    };
}
