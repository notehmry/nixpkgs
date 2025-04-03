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

        # Copy s6 utils.
        copy_bin_and_libs ${pkgs.s6-linux-utils}/bin/s6-mount

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

        # Copy some util-linux stuff.
        copy_bin_and_libs ${pkgs.util-linux}/sbin/blkid

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
        $out/bin/blkid -v | grep "blkid from util-linux"
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

  fileSystemsList =
    fsAttrs:
    with builtins;
    lib.pipe fsAttrs [
      attrValues
      (filter (getAttr "enable"))
      (lib.toposort utils.fsBefore)
      (getAttr "result")
    ];

  execlineMount =
    {
      fsType,
      options,
      device,
      mountPoint,
      ...
    }:
    [
      "\nforeground { mkdir -m 0755 -p"
      mountPoint
      "}"
      "\nif { s6-mount -t"
      fsType
      (lib.optionals (options != [ ]) [
        "-o"
        (lib.concatStringsSep "," (lib.filter (s: !lib.hasPrefix "x-" s) options))
      ])
      device
      mountPoint
      "}"
    ];

  initialScripts = {
    shebang = noDepEntry ''
      #! ${extraUtils}/bin/ash
    '';

    defines = fullDepEntry ''
      targetRoot=/mnt-root
      console=/dev/console
      extraUtils=${extraUtils}
      export LD_LIBRARY_PATH=${extraUtils}/lib
      export PATH=${extraUtils}/bin

      ${
        if config.boot.initrd.verbose then
          ''
            info() {
              echo "$@"
            }
          ''
        else
          ''
            info() {
            }
          ''
      }
      fail() {
          if [ -n "$panicOnFail" ]; then exit 1; fi

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
              exec setsid $SHELL -c "exec $SHELL < $console >$console 2>$console"
          elif [ -n "$allowShell" -a "$reply" = i ]; then
              echo "Starting interactive shell..."
              setsid $SHELL -c "exec $SHELL < $console >$console 2>$console" || fail
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
      info "[1;31m<[1;97m<[1;32m< [1;97m${config.system.nixos.distroName} Stage 1 [1;32m>[1;97m>[1;31m>[0m"
      info
    '' [ "shebang" ];

    specialMounts = fullDepEntry (pkgs.writeTextFile {
      name = "special-mounts.sh";
      executable = true;
      text = ''
        #! ${extraUtils}/bin/execlineb
        ${toString (map execlineMount (fileSystemsList config.boot.specialFileSystems))}
        true
      '';
    }) [ "defines" ];

    # Load the required kernel modules.
    modprobe = fullDepEntry ''
      # Load the required kernel modules.
      echo ${extraUtils}/bin/modprobe > /proc/sys/kernel/modprobe
      for i in ${toString config.boot.initrd.kernelModules}; do
          info "loading module $(basename $i)..."
          modprobe $i
      done
      find /sys -name 'modalias' -type f -exec cat '{}' + | sort -u | xargs modprobe -b -a && true
      find /sys -name 'modalias' -type f -exec cat '{}' + | sort -u | xargs modprobe -b -a && true
    '' [ "specialMounts" ];

    # Process the kernel command line.
    cmdline = fullDepEntry ''
      export stage2Init=/init
      for o in $(cat /proc/cmdline); do
          case $o in
              console=*)
                  set -- $(IFS==; echo $o)
                  params=$2
                  set -- $(IFS=,; echo $params)
                  console=/dev/$1
                  ;;
              init=*)
                  set -- $(IFS==; echo $o)
                  stage2Init=$2
                  ;;
              boot.persistence=*)
                  set -- $(IFS==; echo $o)
                  persistence=$2
                  ;;
              boot.persistence.opt=*)
                  set -- $(IFS==; echo $o)
                  persistence_opt=$2
                  ;;
              boot.trace|debugtrace)
                  # Show each command.
                  set -x
                  ;;
              boot.shell_on_fail)
                  allowShell=1
                  ;;
              boot.debug1|debug1) # stop right away
                  allowShell=1
                  fail
                  ;;
              boot.debug1devices) # stop after loading modules and creating device nodes
                  allowShell=1
                  debug1devices=1
                  ;;
              boot.debug1mounts) # stop after mounting file systems
                  allowShell=1
                  debug1mounts=1
                  ;;
              boot.panic_on_fail|stage1panic=1)
                  panicOnFail=1
                  ;;
              root=*)
                  # If a root device is specified on the kernel command
                  # line, make it available through the symlink /dev/root.
                  # Recognise LABEL= and UUID= to support UNetbootin.
                  set -- $(IFS==; echo $o)
                  if [ $2 = "LABEL" ]; then
                      root="/dev/disk/by-label/$3"
                  elif [ $2 = "UUID" ]; then
                      root="/dev/disk/by-uuid/$3"
                  else
                      root=$2
                  fi
                  ln -s "$root" /dev/root
                  ;;
              copytoram)
                  copytoram=1
                  ;;
              findiso=*)
                  # if an iso name is supplied, try to find the device where
                  # the iso resides on
                  set -- $(IFS==; echo $o)
                  isoPath=$2
                  ;;
          esac
      done
    '' [ "defines" ];

    populateDevDisk =
      fullDepEntry
        ''
          mkdir -p /dev/disk/by-label /dev/disk/by-uuid
          blkid -o export |while read line
          do
            case $line in
              DEVNAME=*) eval $line;;
              LABEL=*)
                eval $line
                ln -sv $DEVNAME "/dev/disk/by-label/$LABEL"
                ;;
              UUID=*)
                eval $line
                ln -sv $DEVNAME "/dev/disk/by-uuid/$UUID"
                ;;
            esac
          done
        ''
        [
          "specialMounts"
          "modprobe"
        ];

    preMount = packEntry [ "populateDevDisk" ];

    mount = fullDepEntry ''
      # Create the mount point if required.
      makeMountPoint() {
          local device="$1"
          local mountPoint="$2"
          local options="$3"

          local IFS=,

          # If we're bind mounting a file, the mount point should also be a file.
          if ! [ -d "$device" ]; then
              for opt in $options; do
                  if [ "$opt" = bind ] || [ "$opt" = rbind ]; then
                      mkdir -p "$(dirname "/mnt-root$mountPoint")"
                      touch "/mnt-root$mountPoint"
                      return
                  fi
              done
          fi

          mkdir -m 0755 -p "/mnt-root$mountPoint"
      }

      # Check the specified file system, if appropriate.
      checkFS() {
          local device="$1"
          local fsType="$2"

          # Only check block devices.
          if [ ! -b "$device" ]; then return 0; fi

          # Don't check ROM filesystems.
          if [ "$fsType" = iso9660 -o "$fsType" = udf ]; then return 0; fi

          # Don't check resilient COWs as they validate the fs structures at mount time
          if [ "$fsType" = btrfs -o "$fsType" = zfs -o "$fsType" = bcachefs ]; then return 0; fi

          # Skip fsck for apfs as the fsck utility does not support repairing the filesystem (no -a option)
          if [ "$fsType" = apfs ]; then return 0; fi

          # Skip fsck for nilfs2 - not needed by design and no fsck tool for this filesystem.
          if [ "$fsType" = nilfs2 ]; then return 0; fi

          # Skip fsck for inherently readonly filesystems.
          if [ "$fsType" = squashfs ]; then return 0; fi

          # Skip fsck.erofs because it is still experimental.
          if [ "$fsType" = erofs ]; then return 0; fi

          # If we couldn't figure out the FS type, then skip fsck.
          if [ "$fsType" = auto ]; then
              echo 'cannot check filesystem with type "auto"!'
              return 0
          fi

          # Device might be already mounted manually
          # e.g. NBD-device or the host filesystem of the file which contains encrypted root fs
          if mount | grep -q "^$device on "; then
              echo "skip checking already mounted $device"
              return 0
          fi

          # Optionally, skip fsck on journaling filesystems.  This option is
          # a hack - it's mostly because e2fsck on ext3 takes much longer to
          # recover the journal than the ext3 implementation in the kernel
          # does (minutes versus seconds).
          ${lib.optionalString config.boot.initrd.checkJournalingFS ''
            if test -a \
                \( "$fsType" = ext3 -o "$fsType" = ext4 -o "$fsType" = reiserfs \
                -o "$fsType" = xfs -o "$fsType" = jfs -o "$fsType" = f2fs \)
            then
                return 0
            fi
          ''}

          echo "checking $device..."

          fsck -V -a "$device"
          fsckResult=$?

          if test $(($fsckResult | 2)) = $fsckResult; then
              echo "fsck finished, rebooting..."
              sleep 3
              reboot -f
          fi

          if test $(($fsckResult | 4)) = $fsckResult; then
              echo "$device has unrepaired errors, please fix them manually."
              fail
          fi

          if test $fsckResult -ge 8; then
              echo "fsck on $device failed."
              fail
          fi

          return 0
      }

      # Function for mounting a file system.
      mountFS() {
          local device="$1"
          local mountPoint="$2"
          local options="$3"
          local fsType="$4"

          if [ "$fsType" = auto ]; then
              fsType=$(blkid -o value -s TYPE "$device")
              if [ -z "$fsType" ]; then fsType=auto; fi
          fi

          # Filter out x- options, which busybox doesn't do yet.
          local optionsFiltered="$(IFS=,; for i in $options; do if [ "''${i:0:2}" != "x-" ]; then echo -n $i,; fi; done)"
          # Prefix (lower|upper|work)dir with /mnt-root (overlayfs)
          local optionsPrefixed="$( echo "$optionsFiltered" | sed -E 's#\<(lowerdir|upperdir|workdir)=#\1=/mnt-root#g' )"

          echo "$device /mnt-root$mountPoint $fsType $optionsPrefixed" >> /etc/fstab

          checkFS "$device" "$fsType"

          # Create backing directories for overlayfs
          if [ "$fsType" = overlay ]; then
              for i in upper work; do
                   dir="$( echo "$optionsPrefixed" | grep -o "''${i}dir=[^,]*" )"
                   mkdir -m 0700 -p "''${dir##*=}"
              done
          fi

          info "mounting $device on $mountPoint..."

          makeMountPoint "$device" "$mountPoint" "$optionsPrefixed"

          # For ZFS and CIFS mounts, retry a few times before giving up.
          # We do this for ZFS as a workaround for issue NixOS/nixpkgs#25383.
          local n=0
          while true; do
              mount "/mnt-root$mountPoint" && break
              if [ \( "$fsType" != cifs -a "$fsType" != zfs \) -o "$n" -ge 10 ]; then fail; break; fi
              echo "retrying..."
              sleep 1
              n=$((n + 1))
          done

          # For bind mounts, busybox has a tendency to ignore options, which can be a
          # security issue (e.g. "nosuid"). Remounting the partition seems to fix the
          # issue.
          mount "/mnt-root$mountPoint" -o "remount,$optionsPrefixed"

          [ "$mountPoint" == "/" ] &&
              [ -f "/mnt-root/etc/NIXOS_LUSTRATE" ] &&
              lustrateRoot "/mnt-root"

          true
      }

      lustrateRoot () {
          local root="$1"

          echo
          echo -e "\e[1;33m<<< @distroName@ is now lustrating the root filesystem (cruft goes to /old-root) >>>\e[0m"
          echo

          mkdir -m 0755 -p "$root/old-root.tmp"

          echo
          echo "Moving impurities out of the way:"
          for d in "$root"/*
          do
              [ "$d" == "$root/nix"          ] && continue
              [ "$d" == "$root/boot"         ] && continue # Don't render the system unbootable
              [ "$d" == "$root/old-root.tmp" ] && continue

              mv -v "$d" "$root/old-root.tmp"
          done

          # Use .tmp to make sure subsequent invocations don't clash
          mv -v "$root/old-root.tmp" "$root/old-root"

          mkdir -m 0755 -p "$root/etc"
          touch "$root/etc/NIXOS"

          exec 4< "$root/old-root/etc/NIXOS_LUSTRATE"

          echo
          echo "Restoring selected impurities:"
          while read -u 4 keeper; do
              dirname="$(dirname "$keeper")"
              mkdir -m 0755 -p "$root/$dirname"
              cp -av "$root/old-root/$keeper" "$root/$keeper"
          done

          exec 4>&-
      }

      ${lib.concatStringsSep "\n" (
        map (
          fs:
          "mountFS ${
            if fs.device != null then fs.device else "/dev/disk/by-label/${fs.label}"
          } ${fs.mountPoint} ${builtins.concatStringsSep "," fs.options} ${fs.fsType}"
        ) fileSystems
      )}'' [ "preMount" ];

    mountMove = fullDepEntry ''
      # Restore /proc/sys/kernel/modprobe to its original value.
      echo /sbin/modprobe > /proc/sys/kernel/modprobe

      # Start stage 2.  `switch_root' deletes all files in the ramfs on the
      # current root.  The path has to be valid in the chroot not outside.
      if [ ! -e "$targetRoot/$stage2Init" ]; then
          stage2Check="$stage2Init"
          while [ "$stage2Check" != "''${stage2Check%/*}" ] && [ ! -L "$targetRoot/$stage2Check" ]; do
              stage2Check=''${stage2Check%/*}
          done
          if [ ! -L "$targetRoot/$stage2Check" ]; then
              echo "stage 2 init script ($targetRoot/$stage2Init) not found"
              fail
          fi
      fi

      mkdir -m 0755 -p $targetRoot/proc $targetRoot/sys $targetRoot/dev $targetRoot/run

      mount --move /proc $targetRoot/proc
      mount --move /sys $targetRoot/sys
      mount --move /dev $targetRoot/dev
      mount --move /run $targetRoot/run
    '' [ "mount" ];

    execStage2 =
      fullDepEntry
        ''
          exec env -i $(type -P switch_root) "$targetRoot" "$stage2Init"
        ''
        [
          "cmdline"
          "mountMove"
        ];
  };

  bootStage1 = pkgs.writeTextFile {
    name = "stage-1-init.sh";
    executable = true;
    text = lib.concatStringsSep "\n" (
      # TODO: not initialScripts, use config.synit.initrd.stage1Scripts.
      (lib.textClosureList initialScripts [
        "shebang"
        "execStage2"
      ])
    );
    checkPhase = ''
      echo checking script syntax
      ${pkgs.buildPackages.busybox}/bin/ash -n $target
    '';
  };

  # The closure of the init script of boot stage 1 is what we put in
  # the initial RAM disk.
  initialRamdisk = pkgs.makeInitrd {
    name = "initrd-${config.boot.kernelPackages.kernel.name or "kernel"}";
    inherit (config.boot.initrd) compressor compressorArgs prepend;

    contents =
      [
        {
          object = bootStage1;
          symlink = "/init";
        }
        {
          object =
            let
              # Determine the set of modules that we need to mount the root FS.
              modulesClosure = pkgs.makeModulesClosure {
                rootModules = config.boot.initrd.availableKernelModules ++ config.boot.initrd.kernelModules;
                kernel = config.system.modulesTree;
                firmware = config.hardware.firmware;
                allowMissing = false;
                inherit (config.boot.initrd) extraFirmwarePaths;
              };
            in
            "${modulesClosure}/lib";
          symlink = "/lib";
        }
        {
          object = "${pkgs.kmod-blacklist-ubuntu}/modprobe.conf";
          symlink = "/etc/modprobe.d/ubuntu.conf";
        }
        {
          object = config.environment.etc."modprobe.d/nixos.conf".source;
          symlink = "/etc/modprobe.d/nixos.conf";
        }
        {
          object = pkgs.kmod-debian-aliases;
          symlink = "/etc/modprobe.d/debian.conf";
        }
      ]
      ++ lib.optionals config.services.multipath.enable [
        {
          object =
            pkgs.runCommand "multipath.conf"
              {
                src = config.environment.etc."multipath.conf".text;
                preferLocalBuild = true;
              }
              ''
                target=$out
                printf "$src" > $out
                substituteInPlace $out \
                  --replace ${config.services.multipath.package}/lib ${extraUtils}/lib
              '';
          symlink = "/etc/multipath.conf";
        }
      ]
      ++ (lib.mapAttrsToList (symlink: options: {
        inherit symlink;
        object = options.source;
      }) config.boot.initrd.extraFiles);
  };

  # Script to add secret files to the initrd at bootloader update time
  initialRamdiskSecretAppender =
    let
      compressorExe = initialRamdisk.compressorExecutableFunction pkgs;
    in
    pkgs.writeScriptBin "append-initrd-secrets" ''
      #!${pkgs.bash}/bin/bash -e
      function usage {
        echo "USAGE: $0 INITRD_FILE" >&2
        echo "Appends this configuration's secrets to INITRD_FILE" >&2
      }

      if [ $# -ne 1 ]; then
        usage
        exit 1
      fi

      if [ "$1"x = "--helpx" ]; then
        usage
        exit 0
      fi

      ${lib.optionalString (config.boot.initrd.secrets == { }) "exit 0"}

      export PATH=${pkgs.coreutils}/bin:${pkgs.cpio}/bin:${pkgs.gzip}/bin:${pkgs.findutils}/bin

      function cleanup {
        if [ -n "$tmp" -a -d "$tmp" ]; then
          rm -fR "$tmp"
        fi
      }
      trap cleanup EXIT

      tmp=$(mktemp -d ''${TMPDIR:-/tmp}/initrd-secrets.XXXXXXXXXX)

      ${lib.concatStringsSep "\n" (
        mapAttrsToList (
          dest: source:
          let
            source' = if source == null then dest else toString source;
          in
          ''
            mkdir -p $(dirname "$tmp/.initrd-secrets/${dest}")
            cp -a ${source'} "$tmp/.initrd-secrets/${dest}"
          ''
        ) config.boot.initrd.secrets
      )}

      # mindepth 1 so that we don't change the mode of /
      (cd "$tmp" && find . -mindepth 1 | xargs touch -amt 197001010000 && find . -mindepth 1 -print0 | sort -z | cpio --quiet -o -H newc -R +0:+0 --reproducible --null) | \
        ${compressorExe} ${lib.escapeShellArgs initialRamdisk.compressorArgs} >> "$1"
    '';

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

    system.build = { inherit bootStage1 initialRamdisk initialRamdiskSecretAppender; };

  };

  meta.maintainers = with lib.maintainers; [ ehmry ];
}
