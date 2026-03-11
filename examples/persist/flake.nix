{
  description = "Example: installing the persist plugin via nix-claude";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nix-claude.url = "github:your-user/nix-claude";  # or path:../..
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
        skills = builtins.attrValues persist.skills;
        settings = {
          hooks.Stop = [{
            matcher = "";
            hooks = [{
              type = "command";
              command = "${persistPkg}/bin/persist hook";
            }];
          }];
        };
      };

      # Option B: home-manager module config (for NixOS users)
      # In your home.nix:
      #
      #   imports = [ nix-claude.homeManagerModules.default ];
      #
      #   programs.claude-code = {
      #     enable = true;
      #     skills = builtins.attrValues persist.skills;
      #     settings = {
      #       hooks.Stop = [{
      #         matcher = "";
      #         hooks = [{
      #           type = "command";
      #           command = "${persistPkg}/bin/persist hook";
      #         }];
      #       }];
      #     };
      #   };
      #
      #   home.packages = [ persistPkg ];
    };
}
