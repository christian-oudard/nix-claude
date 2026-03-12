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
      persistPkg = persist.packages.${system}.default;
    in
    {
      # Option A: standalone derivation (for coding-cave or manual install)
      packages.${system}.claude-config = nix-claude.lib.mkClaudeConfig {
        inherit pkgs;
        skipOnboarding = true;
        plugins.persist = {
          description = "Persistent coding sessions for Claude Code";
          skills = builtins.attrValues persist.skills;
        };
        settings = {
          hooks.Stop = [{
            matcher = "";
            hooks = [{ type = "command"; command = "${persistPkg}/bin/persist hook"; }];
          }];
        };
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
      #   # nix-claude adds plugin support (package + settings bundled with the plugin)
      #   programs.claude-code.plugins.persist = {
      #     description = "Persistent coding sessions for Claude Code";
      #     skills = builtins.attrValues persist.skills;
      #     package = persistPkg;
      #     settings = {
      #       hooks.Stop = [{
      #         matcher = "";
      #         hooks = [{ type = "command"; command = "${persistPkg}/bin/persist hook"; }];
      #       }];
      #     };
      #   };
    };
}
