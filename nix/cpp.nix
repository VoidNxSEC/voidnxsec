{
  perSystem = { pkgs, ... }: {
    devShells.cpp = pkgs.mkShell {
      packages = with pkgs; [
        clang
        clang-tools
        cmake
      ];
    };
  };
}
