{
  nix-search-tv = {
    enable = true;
    enableTelevisionIntegration = true;
    settings = {
      experimental = {
        render_docs_indexes = {
          nvf = "https://notashelf.github.io/nvf/options.html";
        };
      };
    };
  };
}
