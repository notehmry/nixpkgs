#!/usr/bin/env -S tclsh

package require syndicate
namespace import preserves::*

proc forattr {name attrs body} {
  preserves::project -unpreserve $attrs ". $name" $name
  if {$name != ""} $body
}

proc projectAttr {attrs name} {
  upvar $name val
  preserves::project -unpreserve $attrs ". $name" val
}

syndicate::spawn actor {
  set networkEntity [createAssertHandler {value handle} {
    variable machineDataspace
    preserves::project $value {^ network-dataspace / } networkDataspace machineDataspace
    if {$networkDataspace == "" || $machineDataspace == ""} {
      puts stderr "unrecognized assertion $value"
      return
    }

    # Define a command in this facet that can
    # be called from the child facets of `during`.
    proc assertMachine {value} {
      variable machineDataspace
      assert $value $machineDataspace
    }

    during {<address @ifname #? @family #? @attrs #({ })>} {
      # Modify interface addresses.
      projectAttr $attrs address
      projectAttr $attrs prefixLength

      set ifaddr "${address}/$prefixLength"
      lappend cmdAdd exec ip -echo --json address add local $ifaddr dev $ifname

      # Add address.
      catch {
        # Get information back from the kernel and assert that to the machine dataspace.
        set result [{*}$cmdAdd]
        foreach info [preserves::project $result /] {
          assertMachine "<address $ifname $family $info>"
        }
      } err
      if {$err != ""} { puts stderr "failed to add address $ifaddr to $ifname: $err" }

      # Delete address.
      set cmdDel [lreplace $cmdAdd 5 5 delete]
      onStop [list catch $cmdDel]

    } $networkDataspace

    during {<route @ifname #? @family #? @attrs #({ })>} {
      # Modify routing table.
      projectAttr $attrs address
      projectAttr $attrs prefixLength

      set prefix "$address/$prefixLength"
      lappend cmdAdd exec ip -echo --json route add to

      forattr type $attrs { lappend cmdAdd $type }
      lappend cmdAdd $prefix dev $ifname

      forattr via $attrs { lappend cmdAdd via $via }

      foreach options [preserves::project $attrs {. options}] {
        foreach key [preserves::project -unpreserve $options {.keys}] {
          preserves::project -unpreserve $options ". $key" val
          lappend cmdAdd $key $val
        }
      }

      # Add route.
      catch {
        # Get information back from the kernel and assert that to the machine dataspace.
        set result [{*}$cmdAdd]
        foreach info [preserves::project $result /] {
          assertMachine "<route $ifname $family $info>"
        }
      } err
      if {$err != ""} { puts stderr "failed to add route $prefix to $ifname: $err" }

      # Delete route.
      set cmdDel [lreplace $cmdAdd 5 5 delete]
      onStop [list catch $cmdDel]

    } $networkDataspace

  }]

  connectStdio $networkEntity

  # Flag that the actor died.
  onStop {set done 1}
}

vwait done
