{ lib }:

{ pkgs
, plugins ? []
, settings ? {}
, skills ? {}
, statusline ? null
}:

let
  # Merge settings: fold plugin settings left, then user settings override
  pluginSettings = lib.foldl' lib.recursiveUpdate {} (map (p: p.settings or {}) plugins);
  mergedSettings = lib.recursiveUpdate pluginSettings settings;
  settingsJson = builtins.toJSON mergedSettings;

  # Collect plugin packages
  pluginPackages = lib.concatMap (p:
    if p ? package && p.package != null then [ p.package ] else []
  ) plugins;

  # Collect all plugin skill paths
  pluginSkills = lib.concatMap (p: p.skills or []) plugins;

  # Install plugin skills, stripping the 33-char nix store hash prefix from dir names
  installPluginSkills = lib.concatMapStringsSep "\n" (skill: ''
    sname="$(basename "${skill}")"
    sname="''${sname:33}"
    if [ -n "$sname" ]; then
      mkdir -p "$out/skills/$sname"
      cp -r "${skill}/"* "$out/skills/$sname/"
    fi
  '') pluginSkills;

  # Install user inline skills as SKILL.md files
  installInlineSkills = lib.concatStringsSep "\n" (lib.mapAttrsToList (name: content: ''
    mkdir -p "$out/skills/${name}"
    cp ${pkgs.writeText "SKILL.md" content} "$out/skills/${name}/SKILL.md"
  '') skills);

  # Symlink plugin packages into $out/packages/
  installPackages = lib.concatMapStringsSep "\n" (pkg:
    let name = pkg.pname or (lib.getName pkg); in
    ''
      mkdir -p "$out/packages"
      ln -s "${pkg}" "$out/packages/${name}"
    ''
  ) pluginPackages;

in
pkgs.runCommand "claude-config" {} ''
  mkdir -p "$out"

  cp ${pkgs.writeText "settings.json" settingsJson} "$out/settings.json"

  ${installPluginSkills}
  ${installInlineSkills}
  ${installPackages}

  ${lib.optionalString (statusline != null) ''
    cp ${pkgs.writeText "statusline.sh" statusline} "$out/statusline.sh"
    chmod +x "$out/statusline.sh"
  ''}
''
