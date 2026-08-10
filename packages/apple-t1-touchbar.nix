{
  fetchFromGitHub,
  kernel,
  lib,
  stdenv,
}:
stdenv.mkDerivation {
  pname = "apple-t1-touchbar";
  version = "0.3.0-unstable-2026-07-01";

  src = fetchFromGitHub {
    owner = "AJ-dev-i60";
    repo = "t1-touchbar";
    rev = "20d65c7b0fe6d05ea9734f869b27384a62de5109";
    hash = "sha256-nDTnPfNCAnx0NzKxt/YBt/QGnZZg8e+Z173uaWiKQUw=";
  };
  sourceRoot = "source/apple-ib-drv";

  nativeBuildInputs = kernel.moduleBuildDependencies;
  makeFlags = [
    "KVERSION=${kernel.modDirVersion}"
    "KDIR=${kernel.dev}/lib/modules/${kernel.modDirVersion}/build"
  ];

  installPhase = ''
    runHook preInstall
    install -Dm644 apple-ibridge.ko \
      "$out/lib/modules/${kernel.modDirVersion}/extra/apple-ibridge.ko"
    install -Dm644 apple-touchbar.ko \
      "$out/lib/modules/${kernel.modDirVersion}/extra/apple-touchbar.ko"
    runHook postInstall
  '';

  meta = {
    description = "Experimental Apple T1 iBridge and Touch Bar kernel modules";
    homepage = "https://github.com/AJ-dev-i60/t1-touchbar";
    license = lib.licenses.gpl2Only;
    platforms = [ "x86_64-linux" ];
  };
}
