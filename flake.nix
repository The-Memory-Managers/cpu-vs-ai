{
  description = "Run a zig project with raylib-zig bindings";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (
      system: let
        pkgs = nixpkgs.legacyPackages.${system};
        nativeBuildInputs = with pkgs; [
          pkg-config
        ];

        buildInputs = with pkgs; [
          alsa-lib
          xorg.libX11 xorg.libXcursor xorg.libXi xorg.libXrandr xorg.libXinerama # For x11
          libxkbcommon wayland glfw-wayland wayland-scanner # For wayland
        ];

      in {
        devShells.default = pkgs.mkShell {inherit nativeBuildInputs buildInputs;};

        packages.default = pkgs.stdenv.mkDerivation {
          pname = "template";
          version = "0.0.0";
          src = ./.;

          inherit nativeBuildInputs;
          inherit buildInputs;
          LD_LIBRARY_PATH = flake-utils.lib.makeLibraryPath buildInputs;
        };
      }
    );
}
