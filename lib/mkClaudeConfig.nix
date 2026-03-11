{ lib }:

{ pkgs
, plugins ? {}
, skills ? []
, commands ? []
, commandsDir ? null
, memory ? {}
, mcpServers ? {}
, settings ? {}
, skipOnboarding ? false
, dotClaudeJson ? {}
}:

let
  fragments = memory.fragments or [];
  separator = memory.separator or "\n\n";

  baseName = path:
    lib.last (lib.splitString "/" (toString path));

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

  # Version hash: 12-char hash derived from plugin skill paths
  pluginVersion = name: cfg:
    let
      skillPaths = map toString (cfg.skills or []);
      hash = builtins.hashString "sha256" (builtins.concatStringsSep "\n" ([ name ] ++ skillPaths));
    in
    builtins.substring 0 12 hash;

  # Build installed_plugins.json
  pluginEntries = lib.mapAttrs (name: cfg:
    let version = pluginVersion name cfg; in
    [{
      scope = "user";
      # Placeholder path -- activation script fills in the real absolute path
      installPath = "__PLUGINS_DIR__/cache/nix-claude/${name}/${version}";
      inherit version;
      installedAt = "1970-01-01T00:00:00.000Z";
      lastUpdated = "1970-01-01T00:00:00.000Z";
    }]
  ) plugins;

  installedPluginsJson =
    if plugins == {} then null
    else builtins.toJSON {
      version = 2;
      plugins = lib.mapAttrs' (name: value:
        lib.nameValuePair "${name}@nix-claude" value
      ) pluginEntries;
    };

  # Install plugin cache directories
  installPlugins = lib.concatStringsSep "\n" (lib.mapAttrsToList (name: cfg:
    let
      version = pluginVersion name cfg;
      pluginDir = "$out/plugins/cache/nix-claude/${name}/${version}";
      description = cfg.description or "Installed via nix-claude";
      pluginJson = builtins.toJSON {
        inherit name description;
      };
    in
    ''
      mkdir -p "${pluginDir}/.claude-plugin"
      cp ${pkgs.writeText "plugin-${name}.json" pluginJson} "${pluginDir}/.claude-plugin/plugin.json"
      ${lib.concatMapStringsSep "\n" (skill:
        let sname = baseName skill; in
        ''
          mkdir -p "${pluginDir}/skills/${sname}"
          cp -r "${skill}/"* "${pluginDir}/skills/${sname}/"
        ''
      ) (cfg.skills or [])}
    ''
  ) plugins);

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

  ${lib.optionalString (installedPluginsJson != null) ''
    cp ${pkgs.writeText "installed_plugins.json" installedPluginsJson} "$out/plugins/installed_plugins.json"
  ''}

  ${lib.optionalString (claudeMd != null) ''
    cp ${pkgs.writeText "CLAUDE.md" claudeMd} "$out/CLAUDE.md"
  ''}

  ${lib.optionalString (dotClaudeJsonOut != null) ''
    cp ${pkgs.writeText "dot-claude.json" dotClaudeJsonOut} "$out/dot-claude.json"
  ''}

  ${lib.optionalString (settingsJson != null) ''
    cp ${pkgs.writeText "settings.json" settingsJson} "$out/settings.json"
  ''}
''
