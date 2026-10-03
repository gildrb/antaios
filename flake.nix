{
  description = "Antaios - a live, self-modifying Common Lisp agent";

  # Antaios pins an exact SBCL (see sbcl.version) and its Quicklisp package
  # set is generated against a matching nixpkgs. Pin that nixpkgs here so the
  # build is reproducible; bump it in lockstep whenever sbcl.version changes.
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/d482ef84049d9b7276b83a06e4e4d76983830097";

    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
  };

  outputs = inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      # Nix builds run on Linux x86-64 (the packaged release target) and on
      # macOS arm64. nix/package.nix asserts the same platform set.
      systems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" ];

      perSystem = { pkgs, ... }:
        let
          antaios = import ./nix/package.nix {
            inherit pkgs;
            src = inputs.self;
          };
          upgradeSource = pkgs.runCommand "antaios-upgrade-regression-source" {} ''
            cp -R ${inputs.self}/. "$out"
            chmod -R u+w "$out"
            printf '%s\n' ';; Nix package upgrade regression source.' >> \
              "$out/src/core/time.lisp"
          '';
          upgradeAntaios = import ./nix/package.nix {
            inherit pkgs;
            src = upgradeSource;
          };
          imageIdentity = builtins.baseNameOf (toString antaios.imageIdentity);
          upgradeImageIdentity =
            builtins.baseNameOf (toString upgradeAntaios.imageIdentity);
        in
        {
          packages = {
            default = antaios;
            antaios = antaios;
          };

          apps.default = {
            type = "app";
            program = "${antaios}/bin/antaios";
            meta.description = "Run Antaios";
          };

          checks = {
            image-validation = antaios.imageValidation;

            startup = pkgs.runCommand "antaios-startup-check" {
              nativeBuildInputs = [
                antaios
                upgradeAntaios
                pkgs.coreutils
                pkgs.gnugrep
              ];
            } ''
              export HOME="$TMPDIR/home"
              export XDG_CONFIG_HOME="$TMPDIR/config"
              export XDG_DATA_HOME="$TMPDIR/data"
              export XDG_STATE_HOME="$TMPDIR/state"
              mkdir -p "$HOME" "$XDG_STATE_HOME/antaios"
              printf '%s\n' preserved > "$XDG_STATE_HOME/antaios/private-state"

              runtime_root="$XDG_DATA_HOME/antaios/runtimes/${pkgs.sbcl.version}"
              mkdir -p "$runtime_root/source"
              printf '%s\n' 'unmanaged source tree' > \
                "$runtime_root/source/generate-version.sh"
              chmod 000 "$runtime_root/source/generate-version.sh"

              # A stale pre-identity Nix layer and another package identity must
              # never be selected or removed by the current package.
              mkdir -p "$XDG_DATA_HOME/antaios/nix/active"
              printf '%s\n' stale > \
                "$XDG_DATA_HOME/antaios/nix/active/antaios-active.core"
              old_identity="$XDG_DATA_HOME/antaios/nix/images/old-package"
              mkdir -p "$old_identity/active" "$old_identity/recovery"
              printf '%s\n' old > "$old_identity/identity"
              for artifact in \
                active/antaios-active.core active/manifest.sexp \
                recovery/antaios-recovery.core recovery/manifest.sexp; do
                printf '%s\n' old > "$old_identity/$artifact"
              done

              image_directory="$XDG_DATA_HOME/antaios/nix/images/${imageIdentity}"
              mkdir -p "$image_directory/active" "$image_directory/recovery"
              printf '%s\n' "${antaios.imageIdentity}" > \
                "$image_directory/identity"
              printf '%s\n' truncated > \
                "$image_directory/active/antaios-active.core"
              printf '%s\n' '(:ACTIVE-IMAGE :VERSION 1)' > \
                "$image_directory/active/manifest.sexp"
              printf '%s\n' truncated > \
                "$image_directory/recovery/antaios-recovery.core"
              printf '%s\n' '(:RECOVERY-IMAGE :VERSION 2)' > \
                "$image_directory/recovery/manifest.sexp"

              first_output="$TMPDIR/first-output"
              concurrent_output="$TMPDIR/concurrent-output"
              second_output="$TMPDIR/second-output"
              antaios --version > "$first_output" &
              first_pid=$!
              antaios --version > "$concurrent_output" &
              concurrent_pid=$!
              wait "$first_pid"
              wait "$concurrent_pid"
              test "$(tail -n 1 "$first_output")" = \
                "antaios version ${antaios.antaiosSystem.version}"
              test "$(tail -n 1 "$concurrent_output")" = \
                "antaios version ${antaios.antaiosSystem.version}"
              test "$(cat "$first_output" "$concurrent_output" | \
                grep -c 'Installed preloaded active image')" = 1
              test "$(cat "$first_output" "$concurrent_output" | \
                grep -c 'Installed pristine recovery image')" = 1

              test "$(cat "$image_directory/identity")" = "${antaios.imageIdentity}"
              for artifact in \
                active/antaios-active.core active/manifest.sexp \
                recovery/antaios-recovery.core recovery/manifest.sexp; do
                test -f "$image_directory/$artifact"
                test ! -L "$image_directory/$artifact"
              done
              test -w "$image_directory/active/antaios-active.core"
              test -w "$image_directory/active/manifest.sexp"
              test -d "$old_identity"
              test -f "$XDG_DATA_HOME/antaios/nix/active/antaios-active.core"
              test "$(cat "$XDG_STATE_HOME/antaios/private-state")" = preserved
              test -d "$runtime_root/source"
              test ! -L "$runtime_root/source"
              test -e "$runtime_root/source/generate-version.sh"

              test "$(cat "${antaios.imageValidation}/image-validation")" = validated
              test -z "$(find "${antaios.imageValidation}" -type f \
                \( -name '*.core' -o -name 'manifest.sexp' \) -print -quit)"

              active_hash=$(sha256sum \
                "$image_directory/active/antaios-active.core" | cut -d ' ' -f 1)
              recovery_hash=$(sha256sum \
                "$image_directory/recovery/antaios-recovery.core" | cut -d ' ' -f 1)
              antaios --version > "$second_output"
              test "$(cat "$second_output")" = \
                "antaios version ${antaios.antaiosSystem.version}"
              test "$active_hash" = "$(sha256sum \
                "$image_directory/active/antaios-active.core" | cut -d ' ' -f 1)"
              test "$recovery_hash" = "$(sha256sum \
                "$image_directory/recovery/antaios-recovery.core" | cut -d ' ' -f 1)"
              ! grep -F 'Installed preloaded active image' "$second_output"
              ! grep -F 'Installed pristine recovery image' "$second_output"

              # Relative XDG bases are invalid and must use the HOME fallback.
              fallback_output="$TMPDIR/fallback-output"
              XDG_DATA_HOME=relative/data antaios --version > "$fallback_output"
              test "$(tail -n 1 "$fallback_output")" = \
                "antaios version ${antaios.antaiosSystem.version}"
              fallback_image="$HOME/.local/share/antaios/nix/images/${imageIdentity}"
              test -f "$fallback_image/active/antaios-active.core"
              test ! -e "$TMPDIR/relative/data/antaios/nix"

              # A second package identity sharing the same XDG roots must build
              # and select its own complete pair without touching package A or
              # the user's private state.
              upgrade_output="$TMPDIR/upgrade-output"
              "${upgradeAntaios}/bin/antaios" --version > "$upgrade_output"
              test "$(tail -n 1 "$upgrade_output")" = \
                "antaios version ${upgradeAntaios.antaiosSystem.version}"
              upgrade_directory="$XDG_DATA_HOME/antaios/nix/images/${upgradeImageIdentity}"
              test "$upgrade_directory" != "$image_directory"
              test "$(cat "$upgrade_directory/identity")" = \
                "${upgradeAntaios.imageIdentity}"
              for artifact in \
                active/antaios-active.core active/manifest.sexp \
                recovery/antaios-recovery.core recovery/manifest.sexp; do
                test -f "$upgrade_directory/$artifact"
                test ! -L "$upgrade_directory/$artifact"
              done
              test "$active_hash" = "$(sha256sum \
                "$image_directory/active/antaios-active.core" | cut -d ' ' -f 1)"
              test "$recovery_hash" = "$(sha256sum \
                "$image_directory/recovery/antaios-recovery.core" | cut -d ' ' -f 1)"
              test "$(cat "$XDG_STATE_HOME/antaios/private-state")" = preserved
              ! grep -F 'fast startup image is missing or stale' "$upgrade_output"
              ! grep -F 'Antaios bootstrap needs Quicklisp' "$upgrade_output"

              export COLORLISP_NATIVE_LIBRARY="${antaios.colorlispNativeLibrary}/lib/libcolorlisp-tree-sitter${pkgs.stdenv.hostPlatform.extensions.sharedLibrary}"
              "${antaios.runtime}/bin/sbcl" \
                --noinform \
                --no-sysinit \
                --no-userinit \
                --non-interactive \
                --eval '(require :asdf)' \
                --eval '(asdf:load-system :colorlisp)' \
                --eval '(unless (find :number (colorlisp:highlight-spans "fn main() { 42 }" :language :rust) :key (function colorlisp:span-category)) (error "Packaged ColorLisp failed to classify a Rust number."))'
              touch "$out"
            '';

            acp-startup = pkgs.runCommand "antaios-acp-startup-check" {} ''
              export HOME="$TMPDIR/home"
              export XDG_CONFIG_HOME="$TMPDIR/config"
              export XDG_DATA_HOME="$TMPDIR/data"
              export XDG_STATE_HOME="$TMPDIR/state"
              export XDG_CACHE_HOME="$TMPDIR/cache"
              mkdir -p "$HOME"
              "${antaios.runtime}/bin/sbcl" \
                --noinform --no-sysinit --no-userinit --non-interactive \
                --eval '(require :asdf)' \
                --eval '(asdf:load-system :antaios/tests)' \
                --eval '(let ((result (antaios::acp-launcher-tests--initialize "${antaios}/bin/antaios" :arguments (quote ("acp")) :directory (uiop:ensure-directory-pathname (uiop:getenv "TMPDIR"))))) (assert (equal "antaios" (agentcomms:json-get (agentcomms:json-get result "agentInfo") "name"))) (assert (agentcomms:acp-capability-enabled-p (agentcomms:json-get result "agentCapabilities") "loadSession")))'
              touch "$out"
            '';
          };
        };
    };
}
