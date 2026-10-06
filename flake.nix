{
  description = "JHDL: configurable GHDL testbenches from Julia";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      # ghdl-llvm rather than the default mcode backend, which only exists on x86_64-linux
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
      deps = pkgs: [
        pkgs.julia
        pkgs.ghdl-llvm
      ];
    in
    {
      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell { packages = deps pkgs; };
      });

      checks = forAllSystems (pkgs: {
        e2e = pkgs.runCommand "jhdl-e2e" { nativeBuildInputs = deps pkgs; } ''
          export HOME=$TMPDIR
          cp -r ${self}/. src && chmod -R u+w src && cd src
          julia test/runtests.jl
          touch $out
        '';
      });

      formatter = forAllSystems (pkgs: pkgs.nixfmt-rfc-style);
    };
}
