#!@tcl@/bin/tclsh
@setLocale@

set argv [lassign $argv action]

if {[info exists env(NIXOS_NO_CHECK)] && $env(NIXOS_NO_CHECK) != 1} {
  exec -ignorestderr @preSwitchCheck@ @out@ $action
}

switch $action {
  check { exit 0 }
  boot {
    exec -ignorestderr @installBootLoader@ @toplevel@
  }
  switch {
    exec -ignorestderr @installBootLoader@ @toplevel@
    exec -ignorestderr @out@/activate @out@
  }
  test {
    exec -ignorestderr @out@/activate @out@
  }
  default {
    puts stderr "unknown or unimplemented action \"$action\""
  }
}
