{ lib }:

{ pkgs
, skills ? []
, commands ? []
, commandsDir ? null
, memory ? {}
, mcpServers ? {}
, settings ? {}
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

  mcpServersJson =
    if mcpServers == {} then null
    else builtins.toJSON { inherit mcpServers; };

  settingsJson =
    if settings == {} then null
    else builtins.toJSON settings;

  installSkills = lib.concatMapStringsSep "\n" (skill:
    let name = baseName skill; in
    ''
      if [ -d "${skill}" ]; then
        mkdir -p "$out/commands/${name}"
        cp -r "${skill}/"* "$out/commands/${name}/"
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

  ${installSkills}
  ${installCommands}

  ${lib.optionalString (claudeMd != null) ''
    cp ${pkgs.writeText "CLAUDE.md" claudeMd} "$out/CLAUDE.md"
  ''}

  ${lib.optionalString (mcpServersJson != null) ''
    cp ${pkgs.writeText "mcp-servers.json" mcpServersJson} "$out/mcp-servers.json"
  ''}

  ${lib.optionalString (settingsJson != null) ''
    cp ${pkgs.writeText "settings.json" settingsJson} "$out/settings.json"
  ''}
''
