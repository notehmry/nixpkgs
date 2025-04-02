{
  config,
  lib,
  pkgs,
  ...
}:

let
  inherit (lib)
    noDepEntry
    fullDepEntry
    ;

  stage2Scripts = {
    shebang = noDepEntry "#! ${pkgs.bash}/bin/bash";
    defines = fullDepEntry ''
      systemConfig=@systemConfig@
      export PATH=${
        lib.makeBinPath [
          pkgs.coreutils
          pkgs.util-linux
        ]
      }
    '' [ "shebang" ];

    activation = fullDepEntry ''
      # Process the kernel command line.
      for o in $(</proc/cmdline); do
          case $o in
              boot.debugtrace)
                  # Show each command.
                  set -x
                  ;;
          esac
      done

      # Print a greeting.
      echo
      echo -e "\e[1;32m<<< ${config.system.nixos.distroName} Stage 2 >>>\e[0m"
      echo

      # Normally, stage 1 mounts the root filesystem read/writable.
      # However, in some environments, stage 2 is executed directly, and the
      # root is read-only.  So make it writable here.
      if [ -z "$container" ]; then
          mount -n -o remount,rw none /
      fi

      # Likewise, stage 1 mounts /proc, /dev and /sys, so if we don't have a
      # stage 1, we need to do that here.
      if [ ! -e /proc/1 ]; then
          specialMount() {
              local device="$1"
              local mountPoint="$2"
              local options="$3"
              local fsType="$4"

              install -m 0755 -d "$mountPoint"
              mount -n -t "$fsType" -o "$options" "$device" "$mountPoint"
          }
          source ${config.system.build.earlyMountScript}
      fi

      if [ -c /dev/kmsg ] ; then
          echo "booting system configuration $systemConfig" > /dev/kmsg
      else
          echo "booting system configuration $systemConfig"
      fi

      # Make /nix/store a read-only bind mount to enforce immutability of
      # the Nix store.  Note that we can't use "chown root:nixbld" here
      # because users/groups might not exist yet.
      # Silence chown/chmod to fail gracefully on a readonly filesystem
      # like squashfs.
      chown -f 0:30000 /nix/store
      chmod -f 1775 /nix/store
      ${lib.optionalString config.boot.readOnlyNixStore ''
        # #375257: Ensure that we pick the "top" (i.e. last) mount so we don't get a false positive for a lower mount.
        if ! [[ "$(findmnt --direction backward --first-only --noheadings --output OPTIONS /nix/store)" =~ (^|,)ro(,|$) ]]; then
            if [ -z "$container" ]; then
                mount --bind /nix/store /nix/store
            else
                mount --rbind /nix/store /nix/store
            fi
            mount -o remount,ro,bind /nix/store
        fi
      ''}

      # Required by the activation script
      install -m 0755 -d /etc
      if [ ! -h "/etc/nixos" ]; then
          install -m 0755 -d /etc/nixos
      fi
      install -m 01777 -d /tmp

      # Run the script that performs all configuration activation that does
      # not have to be done at boot time.
      echo "running activation script..."
      $systemConfig/activate

      # Record the boot configuration.
      ln -sfn "$systemConfig" /run/booted-system
    '' [ "shebang" ];

    postBoot =
      let
        cmds = config.boot.postBootCommands;
      in
      fullDepEntry (lib.optionalString (cmds != "") "$SHELL ${pkgs.writeText "post-boot.sh" cmds}") [
        "activation"
      ];

    powerManagement =
      let
        cmds = config.powerManagement.powerUpCommands;
      in
      fullDepEntry (lib.optional (cmds != "") "$SHELL ${pkgs.writeText "power-management.sh" cmds}") [
        "postBoot"
      ];

    pid1Exec = fullDepEntry "exec ${lib.getExe pkgs.synit-pid1}" [ "powerManagement" ];
  };

  bootStage2 = pkgs.writeTextFile {
    name = "stage-2-init.sh";
    executable = true;
    text =
      lib.pipe
        [ "shebang" "pid1Exec" ]
        [
          (lib.textClosureList stage2Scripts)
          lib.flatten
          (lib.concatStringsSep "\n")
        ];
  };
in
{
  config.system.build = lib.mkIf config.synit.enable {
    inherit bootStage2;
  };
}
