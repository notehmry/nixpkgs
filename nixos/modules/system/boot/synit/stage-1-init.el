#!@execlineb@ -P
export PATH @initramfsPath@
export LD_LIBRARY_PATH @extraUtils@/lib
background { s6-echo "\n[1;32m<[1;97m<[1;90m<[1;31m<[1;97m @distroName@ Stage 1 [1;31m>[1;90m>[1;97m>[1;32m>[0m\n" }

@specialMounts@

# Handle the kernel parameters.
if {
  redirfd -r 0 /proc/cmdline
  forstdin -E -d " " arg case -N $arg {
    init=(.*) {
      importas init 1
      s6-ln -s "${init}" /run/init
    }
  }
  exit
}

if {
  redirfd -w 1 /proc/sys/kernel/modprobe
  s6-echo @extraUtils@/bin/modprobe
}

background { s6-echo Loading modules @kernelModules@ }
if { modprobe -a @kernelModules@ }

# Autoload modules.
background { mdevd -v 3 -O 2 -f @mdevdConf@ }
importas -iu mdevd_pid !
# Coldplug twice so that all modules are loaded.
foreground { mdevd-coldplug -v 3 -O 2 }
foreground { mdevd-coldplug -v 3 -O 2 }
background { kill $mdevd_pid }

# Create symlinks in /dev/disk.
if { s6-mkdir -p /dev/disk/by-label /dev/disk/by-uuid }
if { forbacktickx -pE val { blkid --match-tag LABEL --output value }
  backtick -E dev { blkid --label $val } ln -s $dev /dev/disk/by-label/$val
}
if { forbacktickx -pE val { blkid --match-tag UUID --output value }
  backtick -E dev { blkid --uuid $val } ln -s $dev /dev/disk/by-uuid/$val
}

foreground { s6-echo starting normal mount script }
@normalMounts@

if {
  forx -pE dir { proc dev sys run }
    mkdir -m 0755 -p /mnt-root/$dir
}

# Wait for children to exit.
background { s6-echo "waiting for children to exit" }
wait { }

# Wipe the current root and exec in /mnt-root.
switch_root /mnt-root /run/init
