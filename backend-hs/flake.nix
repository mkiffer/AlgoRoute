{
  description = "AlgoRoute backend — Haskell rewrite (dev shell + AWS Lambda package)";

  # Pinned external dependencies. flake.lock records their exact revisions.
  inputs = {
    nixpkgs.url     = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  # eachDefaultSystem replicates the outputs for every common platform
  # (x86_64/aarch64 × linux/darwin) so `system` is filled in automatically.
  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs   = nixpkgs.legacyPackages.${system};
        hsPkgs = pkgs.haskellPackages;

        # Normal dynamically-linked build, for local running and development.
        # `./.` is this flake's own directory (backend-hs/), which is where
        # backend-hs.cabal lives — callCabal2nix reads that .cabal file and
        # derives a Nix build from it automatically.
        backend = hsPkgs.callCabal2nix "backend-hs" ./. { };

        # Fully static build for AWS Lambda: pkgsStatic links against musl
        # instead of glibc, producing a self-contained binary the Lambda
        # custom runtime can execute with no shared-library dependencies.
        staticBackend = pkgs.pkgsStatic.haskellPackages.callCabal2nix "backend-hs" ./. { };

        # Lambda deployment artifact: the static `backend-hs` binary renamed
        # to `bootstrap` (the entrypoint name the provided.al2* runtime looks
        # for) and packaged into a single zip.
        lambdaZip = pkgs.runCommand "lambda.zip" { } ''
          cp ${staticBackend}/bin/backend-hs bootstrap
          ${pkgs.zip}/bin/zip $out bootstrap
        '';
      in
      {
        # `nix develop` → shell with the full Haskell toolchain:
        # compiler, build tool, IDE server, linter, and formatter.
        devShells.default = pkgs.mkShell {
          packages = with hsPkgs; [
            ghc
            cabal-install
            haskell-language-server
            hlint
            fourmolu
            # Live-recompiling watcher: `ghcid -c "cabal repl backend-hs"`
            # shows type errors on every save, which is a much faster loop
            # than re-running `cabal build` by hand.
            ghcid
            # Generates test/SpecTree.hs from the *Spec.hs files. Needed by
            # the `spec` test-suite stanza's build-tool-depends.
            hspec-discover
          ];
        };

        # `nix build`          → local backend binary (./result/bin/…).
        packages.default = backend;
        # `nix build .#lambda` → deployable Lambda zip (./result).
        packages.lambda = lambdaZip;
      }
    );
}
