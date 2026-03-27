{ lib }:

{ pkgs
, plugins ? []
, skills ? []
, commands ? []
, commandsDir ? null
, memory ? {}
, mcpServers ? {}
, settings ? {}
, skipOnboarding ? false
, dotClaudeJson ? {}
, statusline ? null
}:

let
  fragments = memory.fragments or [];
  separator = memory.separator or "\n\n";

  baseName = path:
    let raw = lib.last (lib.splitString "/" (toString path)); in
    # Strip 33-char nix store hash prefix (e.g. "abc123-my-skill" -> "my-skill")
    if builtins.stringLength raw > 33 && builtins.substring 32 1 raw == "-"
    then builtins.substring 33 (-1) raw
    else raw;

  # Resolve plugin: flake inputs have a `plugin` attr keyed by system
  resolvePlugin = p:
    if p ? plugin then p.plugin.${pkgs.system}
    else p;

  resolvedPlugins = map resolvePlugin plugins;

  readFragment = f:
    if builtins.isString f && !(lib.hasPrefix "/" f || lib.hasPrefix "/nix/store" f)
    then f
    else builtins.readFile f;

  claudeMd =
    if fragments == [] then null
    else lib.concatStringsSep separator (map readFragment fragments);

  commandsDirFiles =
    if commandsDir == null then []
    else
      let
        entries = builtins.readDir commandsDir;
        mdFiles = lib.filterAttrs (name: type:
          type == "regular" && lib.hasSuffix ".md" name
        ) entries;
      in
      map (name: commandsDir + "/${name}") (builtins.attrNames mdFiles);

  allCommands = commands ++ commandsDirFiles;

  # Assemble ~/.claude.json content from multiple sources
  onboardingAttrs = lib.optionalAttrs skipOnboarding {
    hasCompletedOnboarding = true;
    effortCalloutDismissed = true;
  };
  mcpServersAttrs = lib.optionalAttrs (mcpServers != {}) { inherit mcpServers; };
  mergedDotClaudeJson = onboardingAttrs // mcpServersAttrs // dotClaudeJson;
  dotClaudeJsonOut =
    if mergedDotClaudeJson == {} then null
    else builtins.toJSON mergedDotClaudeJson;

  settingsJson =
    if settings == {} then null
    else builtins.toJSON settings;

  # Install skills and commands from plugins
  installPlugins = lib.concatMapStringsSep "\n" (cfg:
    let
      hasSrc = cfg ? src && cfg.src != null;
    in
    if hasSrc then
      ''
        if [ -d "${cfg.src}/skills" ]; then
          for skill in "${cfg.src}/skills/"*/; do
            if [ -d "$skill" ]; then
              sname="$(basename "$skill")"
              mkdir -p "$out/skills/$sname"
              cp -r "$skill"* "$out/skills/$sname/"
            fi
          done
        fi
        if [ -d "${cfg.src}/commands" ]; then
          for cmd in "${cfg.src}/commands/"*.md; do
            if [ -f "$cmd" ]; then
              mkdir -p "$out/commands"
              cp "$cmd" "$out/commands/"
            fi
          done
        fi
      ''
    else
      lib.concatMapStringsSep "\n" (skill:
        let sname = baseName skill; in
        ''
          mkdir -p "$out/skills/${sname}"
          cp -r "${skill}/"* "$out/skills/${sname}/"
        ''
      ) (cfg.skills or [])
  ) resolvedPlugins;

  # Install bare skills (not through plugin system)
  installSkills = lib.concatMapStringsSep "\n" (skill:
    let name = baseName skill; in
    ''
      if [ -d "${skill}" ]; then
        mkdir -p "$out/skills/${name}"
        cp -r "${skill}/"* "$out/skills/${name}/"
      else
        mkdir -p "$out/commands"
        cp "${skill}" "$out/commands/${name}"
      fi
    ''
  ) skills;

  installCommands = lib.concatMapStringsSep "\n" (cmd:
    let name = baseName cmd; in
    ''
      mkdir -p "$out/commands"
      cp "${cmd}" "$out/commands/${name}"
    ''
  ) allCommands;

in
pkgs.runCommand "claude-config" {} ''
  mkdir -p "$out"

  ${installPlugins}
  ${installSkills}
  ${installCommands}

  ${lib.optionalString (claudeMd != null) ''
    cp ${pkgs.writeText "CLAUDE.md" claudeMd} "$out/CLAUDE.md"
  ''}

  ${lib.optionalString (dotClaudeJsonOut != null) ''
    cp ${pkgs.writeText "dot-claude.json" dotClaudeJsonOut} "$out/dot-claude.json"
  ''}

  ${lib.optionalString (settingsJson != null) ''
    cp ${pkgs.writeText "settings.json" settingsJson} "$out/settings.json"
  ''}

  ${lib.optionalString (statusline != null) ''
    cp ${pkgs.writeText "statusline.sh" statusline} "$out/statusline.sh"
    chmod +x "$out/statusline.sh"
  ''}
''
