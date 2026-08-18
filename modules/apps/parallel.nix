{ pkgs, ... }:
let
  wrappedParallel = pkgs.symlinkJoin {
    name = "parallel";
    paths = [ pkgs.parallel ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram "$out/bin/parallel" --add-flags "--will-cite"
      rm "$out/bin/sem"
      makeWrapper "$out/bin/parallel" "$out/bin/sem" --add-flags "--semaphore"
    '';
    meta.mainProgram = "parallel";
  };
in
{
  parallel = {
    enable = true;
    package = wrappedParallel;
  };
}
