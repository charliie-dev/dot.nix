{
  pkgs,
  # lib,
  ...
}:
{
  neovim = {
    enable = true;
    defaultEditor = true;
    sideloadInitLua = false;
    # package = pkgs.neovim-nightly;

    # Remote plugins are disabled by the Neovim configuration. Go and Node.js
    # remain packaged for deterministic bootstrap; Python is provided by mise.
    withNodeJs = false;
    withPython3 = false;
    withRuby = false;

    extraPackages = with pkgs; [
      # Native plugin and parser builds
      cargo
      gnumake
      go
      nodejs
      stdenv.cc
      tree-sitter

      # Keep these candidates until their absence is confirmed in daily use.
      # clang
      # cmake
      # gcc
      # ninja
      # pkg-config
      # lua5_1
      # luajitPackages.luarocks-nix
    ];

    # Native plugin builds currently do not need these wrapper paths. Keep the
    # previous configuration available until that is confirmed in daily use.
    # extraWrapperArgs = [
    #   "--suffix"
    #   "LIBRARY_PATH"
    #   ":"
    #   "${lib.makeLibraryPath [
    #     pkgs.bzip2
    #     pkgs.curl
    #     pkgs.libsodium
    #     pkgs.libssh
    #     pkgs.libxml2
    #     pkgs.openssl
    #     pkgs.stdenv.cc.cc
    #     pkgs.stdenv.cc.cc.lib
    #     pkgs.util-linux
    #     pkgs.xz
    #     pkgs.zlib
    #     pkgs.zstd
    #     pkgs.glib
    #     pkgs.libcxx
    #   ]}"
    #   "--suffix"
    #   "PKG_CONFIG_PATH"
    #   ":"
    #   "${lib.makeSearchPathOutput "dev" "lib/pkgconfig" [
    #     pkgs.bzip2
    #     pkgs.curl
    #     pkgs.libsodium
    #     pkgs.libssh
    #     pkgs.libxml2
    #     pkgs.openssl
    #     pkgs.stdenv.cc.cc
    #     pkgs.stdenv.cc.cc.lib
    #     pkgs.util-linux
    #     pkgs.xz
    #     pkgs.zlib
    #     pkgs.zstd
    #     pkgs.glib
    #     pkgs.libcxx
    #   ]}"
    # ];

    # lazy.nvim owns these Lua dependencies. Keep this list until the external
    # plugin builds have been confirmed without Home Manager's Lua environment.
    # extraLuaPackages =
    #   luajitPackages: with luajitPackages; [
    #     fzf-lua
    #     fzy
    #     luasnip
    #     luv
    #     sqlite
    #     jsregexp
    #   ];
  };
}
