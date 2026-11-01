{
  description = "AIRI desktop with Codex and AivisSpeech Engine";

  nixConfig = {
    extra-substituters = [
      "https://cache.nixos.org"
      "https://cache.numtide.com"
    ];
    extra-trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
    ];
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    airi = {
      url = "github:moeru-ai/airi";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    llm-agents.url = "github:numtide/llm-agents.nix";
  };

  outputs =
    {
      nixpkgs,
      airi,
      llm-agents,
      ...
    }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true; # AIRI includes the Live2D Cubism SDK.
      };
      airiPackage = airi.packages.${system}.airi;
      proxy = llm-agents.packages.${system}.cli-proxy-api;
      engine = pkgs.callPackage ./nix/aivisspeech-engine.nix { };
      start = pkgs.writeShellApplication {
        name = "start-airi";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.curl
        ];
        text = builtins.readFile ./scripts/start-airi.sh;
        runtimeEnv = {
          AIRI_BIN = pkgs.lib.getExe airiPackage;
          AIVIS_BIN = pkgs.lib.getExe engine;
          CODEX_PROXY_BIN = pkgs.lib.getExe proxy;
        };
      };
      login = pkgs.writeShellApplication {
        name = "airi-codex-login";
        runtimeEnv.CODEX_PROXY_BIN = pkgs.lib.getExe proxy;
        text = ''
          config_file="''${MY_AIRI_PROXY_CONFIG:-''${XDG_CONFIG_HOME:-$HOME/.config}/my-airi/cli-proxy-api.yaml}"
          if [[ ! -f "$config_file" ]]; then
            echo "Create $config_file first (see README.md)." >&2
            exit 1
          fi
          exec "$CODEX_PROXY_BIN" --config "$config_file" --codex-login "$@"
        '';
      };
    in
    {
      packages.${system} = {
        airi = airiPackage;
        aivisspeech-engine = engine;
        cli-proxy-api = proxy;
        inherit start login;
        default = start;
      };

      apps.${system} = {
        default = {
          type = "app";
          program = pkgs.lib.getExe start;
          meta.description = "Start AIRI, Codex proxy, and AivisSpeech Engine";
        };
        start = {
          type = "app";
          program = pkgs.lib.getExe start;
          meta.description = "Start AIRI, Codex proxy, and AivisSpeech Engine";
        };
        login = {
          type = "app";
          program = pkgs.lib.getExe login;
          meta.description = "Authenticate CLIProxyAPI with Codex";
        };
      };

      devShells.${system}.default = pkgs.mkShell {
        packages = [
          airiPackage
          engine
          proxy
          start
          login
        ];
      };

      checks.${system} = {
        launcher =
          pkgs.runCommand "airi-launcher-checks"
            {
              nativeBuildInputs = [
                pkgs.python3
                pkgs.bash
                pkgs.shellcheck
              ];
            }
            ''
              shellcheck ${./scripts/start-airi.sh}
              mkdir -p scripts tests
              cp ${./scripts/start-airi.sh} scripts/start-airi.sh
              cp ${./tests/test_launcher.py} tests/test_launcher.py
              python3 -B -m unittest discover -s tests -v
              touch "$out"
            '';

      };

      formatter.${system} = pkgs.nixfmt-tree;
    };
}
