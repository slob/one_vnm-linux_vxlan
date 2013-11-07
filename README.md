## OpenNebula Linux VXLAN VNM

Hacked together OpenNebula driver supporting VXLAN-based Virtual Networks.

Virtual Networks require PHYSDEV=something (anything) which, I believe,
automatically sets VLAN=yes to allow the driver to run and triggers
opennebula logic that creates a unique bridge name per virtual network.

The VNM driver then sets up the bridge (named onebr<vnet-id>), the VXLAN
ip link (auto-generating a VXLAN multicast group), and bridges them all
together. libvirt attaches the guest to the bridge.

Configurables (in /var/lib/one/remotes/vnm/OpenNebulaNetwork.rb):

CONF[:vxlan_start_vni]   - offset to begin numbering VXLAN IDs from
CONF[:vxlan_transit_dev] - interface that you want to send VXLAN traffic over

eg.

```
CONF = {
  :start_vlan => 2,
  :vxlan_start_vni => 1001,
  :vxlan_transit_dev => "eth1.199"
}
```

Tested hypervisor setup:

 * debian wheezy
 * linux-image-amd64 3.10+51~bpo70+1 from backports
 * iproute2 3.11.0-1 compiled from source deb from jessie 

sudoers config on hypervisor (/etc/sudoers.d/one_vnm-linux_vxlan):

```
oneadmin ALL=(ALL) NOPASSWD: /bin/ip *
oneadmin ALL=(ALL) NOPASSWD: /sbin/brctl *
```
