{
  perSystem = { pkgs, ... }: {
    devShells.go = pkgs.mkShell {
      packages = with pkgs; [
        go
        gopls
        gotools
        go-tools
      ];
    };
  };
}
