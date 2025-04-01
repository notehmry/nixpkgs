{
  lib,
  config,
  pkgs,
  utils,
  ...
}:
let
  inherit (lib)
    mkIf
    mkOption
    types
    concatStringsSep
    mapAttrsToList
    optionalString
    fullDepEntry
    noDepEntry
    packEntry
    ;

  # File-systems to mount in stage-1.
  fileSystems = lib.filter utils.fsNeededForBoot config.system.build.fileSystems;

  # Determine whether zfs-mount(8) is needed.
  zfsRequiresMountHelper = lib.any (fs: lib.elem "zfsutil" fs.options) fileSystems;

  # A utility for enumerating the shared-library dependencies of a program
  findLibs = pkgs.buildPackages.writeShellScriptBin "find-libs" ''
    set -euo pipefail

    declare -A seen
    left=()

    patchelf="${pkgs.buildPackages.patchelf}/bin/patchelf"

    function add_needed {
      rpath="$($patchelf --print-rpath $1)"
      dir="$(dirname $1)"
      for lib in $($patchelf --print-needed $1); do
        left+=("$lib" "$rpath" "$dir")
      done
    }

    add_needed "$1"

    while [ ''${#left[@]} -ne 0 ]; do
      next=''${left[0]}
      rpath=''${left[1]}
      ORIGIN=''${left[2]}
      left=("''${left[@]:3}")
      if [ -z ''${seen[$next]+x} ]; then
        seen[$next]=1

        # Ignore the dynamic linker which for some reason appears as a DT_NEEDED of glibc but isn't in glibc's RPATH.
        case "$next" in
          ld*.so.?) continue;;
        esac

        IFS=: read -ra paths <<< $rpath
        res=
        for path in "''${paths[@]}"; do
          path=$(eval "echo $path")
          if [ -f "$path/$next" ]; then
              res="$path/$next"
              echo "$res"
              add_needed "$res"
              break
          fi
        done
        if [ -z "$res" ]; then
          echo "Couldn't satisfy dependency $next" >&2
          exit 1
        fi
      fi
    done
  '';

  # Additional utilities needed in stage1.
  extraUtils =
    pkgs.runCommand "extra-utils"
      {
        nativeBuildInputs = builtins.attrValues {
          inherit (pkgs.buildPackages)
            nukeReferences
            bintools
            ;
        };
        allowedReferences = [ "out" ];
      }
      ''
        set +o pipefail

        mkdir -p $out/bin $out/lib
        ln -s $out/bin $out/sbin

        copy_bin_and_libs () {
          [ -f "$out/bin/$(basename $1)" ] && rm "$out/bin/$(basename $1)"
          cp -pdv $1 $out/bin
        }

        # Copy BusyBox.
        for BIN in ${pkgs.busybox}/{s,}bin/*; do
          copy_bin_and_libs $BIN
        done

        ${optionalString zfsRequiresMountHelper ''
          # Filesystems using the "zfsutil" option are mounted regardless of the
          # mount.zfs(8) helper, but it is required to ensure that ZFS properties
          # are used as mount options.
          #
          # BusyBox does not use the ZFS helper in the first place.
          # util-linux searches /sbin/ as last path for helpers (stage-1-init.sh
          # must symlink it to the store PATH).
          # Without helper program, both `mount`s silently fails back to internal
          # code, using default options and effectively ignore security relevant
          # ZFS properties such as `setuid=off` and `exec=off` (unless manually
          # duplicated in `fileSystems.*.options`, defeating "zfsutil"'s purpose).
          copy_bin_and_libs ${lib.getOutput "mount" pkgs.util-linux}/bin/mount
          copy_bin_and_libs ${config.boot.zfs.package}/bin/mount.zfs
        ''}

        # Copy modprobe.
        copy_bin_and_libs ${pkgs.kmod}/bin/kmod
        ln -sf kmod $out/bin/modprobe

        # Copy secrets if needed.
        #
        # TODO: move out to a separate script; see #85000.
        ${optionalString (!config.boot.loader.supportsInitrdSecrets) (
          concatStringsSep "\n" (
            mapAttrsToList (
              dest: source:
              let
                source' = if source == null then dest else source;
              in
              ''
                mkdir -p $(dirname "$out/secrets/${dest}")
                # Some programs (e.g. ssh) doesn't like secrets to be
                # symlinks, so we use `cp -L` here to match the
                # behaviour when secrets are natively supported.
                cp -Lr ${source'} "$out/secrets/${dest}"
              ''
            ) config.boot.initrd.secrets
          )
        )}

        # Copy ld manually since it isn't detected correctly
        cp -pv ${pkgs.stdenv.cc.libc.out}/lib/ld*.so.? $out/lib

        # Copy all of the needed libraries in a consistent order so
        # duplicates are resolved the same way.
        find $out/bin $out/lib -type f | sort | while read BIN; do
          echo "Copying libs for executable $BIN"
          for LIB in $(${findLibs}/bin/find-libs $BIN); do
            TGT="$out/lib/$(basename $LIB)"
            if [ ! -f "$TGT" ]; then
              SRC="$(readlink -e $LIB)"
              cp -pdv "$SRC" "$TGT"
            fi
          done
        done

        # Strip binaries further than normal.
        chmod -R u+w $out
        stripDirs "$STRIP" "$RANLIB" "lib bin" "-s"

        # Run patchelf to make the programs refer to the copied libraries.
        find $out/bin $out/lib -type f | while read i; do
          nuke-refs -e $out $i
        done

        find $out/bin -type f | while read i; do
          echo "patching $i..."
          patchelf --set-interpreter $out/lib/ld*.so.? --set-rpath $out/lib $i || true
        done

        find $out/lib -type f \! -name 'ld*.so.?' | while read i; do
          echo "patching $i..."
          patchelf --set-rpath $out/lib $i
        done

        if [ -z "${toString (pkgs.stdenv.hostPlatform != pkgs.stdenv.buildPlatform)}" ]; then
        # Make sure that the patchelf'ed binaries still work.
        echo "testing patched programs..."
        $out/bin/ash -c 'echo hello world' | grep "hello world"
        ${
          if zfsRequiresMountHelper then
            ''
              $out/bin/mount -V 1>&1 | grep -q "mount from util-linux"
              $out/bin/mount.zfs -h 2>&1 | grep -q "Usage: mount.zfs"
            ''
          else
            ''
              $out/bin/mount --help 2>&1 | grep -q "BusyBox"
            ''
        }
        fi
      ''; # */

  initialScripts = {
    defines = noDepEntry ''
      stage2init=${pkgs.synit-pid1}
      targetRoot=/mnt-root
      console=tty1
      extraUtils ${extraUtils}
      export LD_LIBRARY_PATH=${extraUtils}/lib
      export PATH=${extraUtils}/bin

      ${if config.boot.initrd.verbose then ''info() {echo "$@"}'' else ''info() {}''}
      fail() {
          if [ -n "$panicOnFail" ]; then exit 1; fi

          @preFailCommands@

          # If starting stage 2 failed, allow the user to repair the problem
          # in an interactive shell.
          cat <<EOF

      An error occurred in stage 1 of the boot process, which must mount the
      root filesystem on \`$targetRoot' and then start stage 2.  Press one
      of the following keys:

      EOF
          if [ -n "$allowShell" ]; then cat <<EOF
        i) to launch an interactive shell
        f) to start an interactive shell having pid 1 (needed if you want to
           start stage 2's init manually)
      EOF
          fi
          cat <<EOF
        r) to reboot immediately
        *) to ignore the error and continue
      EOF

          read -n 1 reply

          if [ -n "$allowShell" -a "$reply" = f ]; then
              exec setsid @shell@ -c "exec @shell@ < /dev/$console >/dev/$console 2>/dev/$console"
          elif [ -n "$allowShell" -a "$reply" = i ]; then
              echo "Starting interactive shell..."
              setsid @shell@ -c "exec @shell@ < /dev/$console >/dev/$console 2>/dev/$console" || fail
          elif [ "$reply" = r ]; then
              echo "Rebooting..."
              reboot -f
          else
              info "Continuing..."
          fi
      }

      trap 'fail' 0

      # Print a greeting.
      info
      info "[1;32m<<< @distroName@ Stage 1 >>>[0m"
      info
    '';

    # Load the required kernel modules.
    modprobe = fullDepEntry ''
      # Load the required kernel modules.
      echo @extraUtils@/bin/modprobe > /proc/sys/kernel/modprobe
      for i in @kernelModules@; do
          info "loading module $(basename $i)..."
          modprobe $i
      done
    '' [ "defines" ];

    preMount = packEntry [ "modprobe" ];

    mount = fullDepEntry (lib.concatStringsSep "\n" (
      map (
        fs:
        "mount -t ${fs.fsType} ${
          optionalString (fs.options != [ ])
            "-o ${builtins.concatStringsSep "," (lib.filter (s: !(lib.strings.hasPrefix "x-" s)) fs.options)}"
        } ${if fs.device != null then fs.device else "/dev/disk/by-label/${fs.label}"} ${fs.mountPoint}"
      ) fileSystems
    )) [ "preMount" ];
  };

in
{
  options.synit.initrd = {
    stage1Scripts = mkOption {
      type = types.attrsOf (
        types.submodule {
          options = {
            deps = mkOption {
              type = types.listOf types.str;
              default = [
                "defines"
                "mount"
              ];
              description = ''
                List of dependency steps.
                The initially defined steps are `${toString (builtins.attrNames initialScripts)}`.
              '';
            };
            text = mkOption {
              type = types.lines;
              description = ''
                Ash scripts.
              '';
            };
          };
        }
      );
      description = ''
        A set of execline script fragments executed during stage1 of the initrd.
        The final script is available at {var}`system.build.bootStage1`.
      '';
    };
  };
  config = mkIf config.synit.enable {

    synit.initrd.stage1Scripts =
      initialScripts
      // (mkIf (config.networking.hostId != null) {
        setHostId = fullDepEntry ''
          hi="${config.networking.hostId}"
          echo -ne ${
            if pkgs.stdenv.hostPlatform.isBigEndian then
              ''"\x''${hi:0:2}\x''${hi:2:2}\x''${hi:4:2}\x''${hi:6:2}"''
            else
              ''"\x''${hi:6:2}\x''${hi:4:2}\x''${hi:2:2}\x''${hi:0:2}"''
          } >/etc/hostid
        '' [ "defines" ];
      });

    system.build = {
      bootStage1 = pkgs.writeTextFile {
        name = "stage-1-init.sh";
        executable = true;
        text = lib.concatStringsSep "\n" (
          lib.flatten [
            "#! ${extraUtils}/bin/ash}"
            (lib.textClosureList initialScripts [
              "defines"
              "mount"
            ])
            "exec $stage2Init"
          ]
        );
        checkPhase = ''
          echo checking script syntax
          ${pkgs.buildPackages.busybox}/bin/ash -n $target
        '';
      };
    };

  };

  meta.maintainers = with lib.maintainers; [ ehmry ];
}
