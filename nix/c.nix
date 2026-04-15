{
  perSystem = { pkgs, ... }: {
    devShells.c = pkgs.mkShell {
      packages = with pkgs; [
        gcc
        gdb
      ];
    };
  };
}
