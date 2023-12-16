{ pkgs ? import <nixpkgs> { } }:
pkgs.mkShell {
  buildInputs = with pkgs; [
    alsa-lib
    glfw
    libGL
    xorg.libX11
    xorg.libXi
    xorg.libXcursor
    xorg.libXrandr
  ];
}
