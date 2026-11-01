{
  lib,
  stdenvNoCC,
  fetchurl,
  p7zip,
  makeWrapper,
  patchelf,
  alsa-lib,
  glib,
  libGL,
  glibc,
  zlib,
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "aivisspeech-engine";
  version = "1.2.0";

  src = fetchurl {
    url = "https://github.com/Aivis-Project/AivisSpeech-Engine/releases/download/${finalAttrs.version}/AivisSpeech-Engine-Linux-x64-${finalAttrs.version}.7z.001";
    hash = "sha256-pLHMeQ6aFSLYgOBj14jqLDPfkJ6I52TYrloX41l7FbU=";
  };

  nativeBuildInputs = [
    p7zip
    makeWrapper
    patchelf
  ];
  buildInputs = [
    alsa-lib
    glib
    libGL
    zlib
  ];
  dontUnpack = true;
  dontBuild = true;
  dontStrip = true;
  dontPatchELF = true;

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/opt/aivisspeech-engine" "$out/bin"
    7z x -bso0 "$src" -o"$out/opt/aivisspeech-engine"
    patchelf --set-interpreter "${glibc}/lib/ld-linux-x86-64.so.2" \
      "$out/opt/aivisspeech-engine/Linux-x64/run"
    makeWrapper "$out/opt/aivisspeech-engine/Linux-x64/run" "$out/bin/aivisspeech-engine" \
      --prefix LD_LIBRARY_PATH : "${
        lib.makeLibraryPath [
          alsa-lib
          glib
          libGL
          zlib
        ]
      }"
    runHook postInstall
  '';

  meta = {
    description = "Japanese text-to-speech HTTP engine (prebuilt release)";
    homepage = "https://github.com/Aivis-Project/AivisSpeech-Engine";
    license = lib.licenses.lgpl3Only;
    mainProgram = "aivisspeech-engine";
    platforms = [ "x86_64-linux" ];
  };
})
