#!/usr/bin/env -S tclsh

package require syndicate

proc forattr {name attrs body} {
  preserves::project -unpreserve $attrs ". $name" $name
  if {$name != ""} $body
}

syndicate::spawn actor {
  set networkEntity [createAssertHandler {value handle} {
    preserves::project $value {^ network . 0} networkDataspace
    if {$networkDataspace == ""} return

    during {<addr @ifname #? #_ @address #? @prefixLength #?>} {
      # Modify interface addresses.
      set ifaddr "[preserves::unpreserve $address]/$prefixLength"
      lappend cmdAdd exec ip address add local $ifaddr dev $ifname

      # Add address.
      catch $cmdAdd err
      if {$err != ""} { puts stderr "failed to add address $ifaddr to $ifname: $err" }

      # Delete address.
      set cmdDel [lreplace $cmdAdd 3 3 delete]
      onStop [list catch $cmdDel]

    } $networkDataspace

    during {<route @ifname #? #_ @address #? @prefixLength #? @attrs #({ })>} {
      # Modify routing table.
      set prefix "[preserves::unpreserve $address]/$prefixLength"
      lappend cmdAdd exec ip route add to

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
      catch $cmdAdd err
      if {$err != ""} { puts stderr "failed to add route $prefix to $ifname: $err" }

      # Delete route.
      set cmdDel [lreplace $cmdAdd 3 3 delete]
      onStop [list catch $cmdDel]

    } $networkDataspace

  }]

  connectStdio $networkEntity

  # Flag that the actor died.
  onStop {set done 1}
}

vwait done
