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
        # EzXML comes from nix rather than Pkg so the sandboxed check needs no network
        (pkgs.julia.withPackages [ "EzXML" ])
        pkgs.ghdl-llvm
      ];

      # The Manifest isn't committed. Under nix it's the one nix resolved EzXML into,
      # found through the project the julia wrapper activates by default.
      linkManifest = ''
        [ -f Project.toml ] && ln -sf "$(dirname "$(julia --startup-file=no -e 'print(Base.active_project())')")/Manifest.toml" Manifest.toml
      '';
    in
    {
      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = deps pkgs;
          shellHook = linkManifest;
        };
      });

      checks = forAllSystems (pkgs: {
        e2e = pkgs.runCommand "jhdl-e2e" { nativeBuildInputs = deps pkgs; } ''
          export HOME=$TMPDIR
          cp -r ${self}/. src && chmod -R u+w src && cd src
          ${linkManifest}
          julia --project=. test/runtests.jl
          touch $out
        '';
      });

      formatter = forAllSystems (pkgs: pkgs.nixfmt-tree);
    };
}
