---
title: '2020-04-18 I switched my home network to IPv6'
date: '2020-04-18T00:00:00Z'
---

As I said in [this post,](/blog/2019-10-20-local-linux-user-tries-freebsd/) I have a router running pfSense to serve my home computers. Over the last few weeks, I decided to explore how much effort it would be to enable IPv6 for the router and all the devices on the LAN. I did not know much about how IPv6 actually works at the routing level, so it was a good learning experience.

The tl;dr is that everything was pretty much turn-key, except for getting Docker to serve publicly routable IPs to its containers, and getting NAT64 working on pfSense using tayga. The documentation for the former is either outdated or doesn't take `firewalld` into account, and the documentation for the latter doesn't exist anywhere on the internet. So I hope this post helps other people trying the same thing.


<section>
## The IPv4 setup

This is my existing IPv4 setup. I've labeled the interfaces with their names (`em0` and `igb*` for the router, `enp*` for the computers, etc):

```
                           +-----+
                           | ISP |
                           +-----+
                              |
                              |
+-----------------------------o----------------------------+
|                         WAN (em0)                        |
|                                                          |
|                      pfSense Router                      |
|                                                          |
|      +--------------+--[bridge0]---+--------------+      |
|      |              |              |              |      |
| LAN1 (igb0)    LAN2 (igb1)    LAN3 (igb2)    LAN4 (igb3) |
+------------------------------------o--------------o------+
                                     |              |
                                     |              |
                                +----o----+    +----o---------------+
                                | enp0s25 |    | enp4s0    docker0  |
                                |         |    |                    |
                                | laptop  |    |      desktop       |
                                +---------+    +--------------------+
```

The `bridge0` interface is a bridge across all the LAN NICs of the router and binds to the `192.168.1.0/24` subnet. The DHCP server runs on the bridge and serves IPs from a pool in this subnet.

The desktop and laptop run openSUSE Tumbleweed, and use systemd-networkd for network management.

Lastly, the desktop runs Docker containers, which means it has its own `docker0` bridge interface that runs its own DHCP server and NAT for the Docker containers.

The goals of the exercise, in decreasing order of importance, were:

1. [Get a publicly routable IPv6 address for the router.](#level-1-ipv6-for-the-router)

1. [Get publicly routable IPv6 addresses for all the physical machines behind the router.](#level-2-ipv6-for-all-the-physical-machines-behind-the-router)

1. [Get publicly routable IPv6 addresses for all Docker containers on the desktop.](#level-3-ipv6-for-all-the-docker-containers)

1. [Disable IPv4 on the LAN completely.](#level-4-turn-off-ipv4)

Note that publicly routable doesn't mean publicly *reachable*. The router would still be running a firewall and default to dropping incoming connections on the WAN. The advantage of having publicly routable IPs is merely to have a single globally valid address for every resource.

</section>


<section>
## Interlude

(This section explains basic IPv6 terminology and prefix delegation. Skip to the next section if you already know this.)

An IPv6 address is made up of eight segments, where each segment is a 16-bit value. The string representation puts each segment with one to four hex digits (leading zeros stripped). Segments are separated by `:`. A single run of consecutive segments that are all `0` can be replaced with `::`. Thus the address represented by `2001:db8:0:1::2:3` is the same as the address represented by `2001:0db8:0000:0001:0000:0000:0002:0003`

Just like IPv4, a range of addresses is represented with CIDR notation. The `2001:db8::/32` range is reserved for examples, which is why I'll use it throughout this post.

Devices that want to get addresses from a router send out solicitation requests, to which the router responds by advertising itself using Router Advertisement (RA) messages. The RA message contains the information about the DHCPv6 server, if one exists on the network. The devices may then get addresses from the DHCPv6 server, which may be static or random, or they may use [SLAAC](https://en.wikipedia.org/wiki/IPv6_address#Stateless_address_autoconfiguration) to construct addresses for themselves based on the prefix advertised in the RA message plus their MAC address.

When it comes to the mechanism of how routers talk to gateways (upstream routers), it's worth differentiating between link prefixes and routing prefixes. The router first gets an IP for itself from the gateway, say `2001:db8:0:1:2:3:4:5/64`. This IP is called the link prefix, and the /64 here just represents the length of the prefix. The router then requests the gateway to delegate another range of addresses to it that it can serve them to its downstream devices. The gateway might decide to give `2001:db8:0:2::/64` to the router. This is the routed prefix. The gateway only needs to remember that all traffic for all addresses in the `2001:db8:0:2::/64` range should be routed to the router at `2001:db8:0:1:2:3:4:5`; it does not need to store individual routes for addresses within that range. This process where a device obtains a routed prefix from an upstream router so that it can itself act as a router is called prefix delegation.

When subnetting IPv6, one usually does not make subnets smaller than /64. Within a /64, the router and the devices can discover each other using [NDP.](https://en.wikipedia.org/wiki/Neighbor_Discovery_Protocol) Splitting a subnet across multiple links requires proxying the NDP messages across the disjoint links, which is doable but more trouble than it's worth.

This means if the routed prefix is only a /64, then the router can only create one /64 subnet. If you wanted more subnets, you have to work with upstream to have them delegate your a prefix that's larger, say a /60 or /56 or /48. For example, if your router gets a /60, then it has the ability to make more than one /64 subnet, 2^(64 - 60) = 16 subnets to be precise.

</section>


<section>
## Level 1: IPv6 for the router

My ISP does not yet support IPv6, so I set up a tunnel with [Hurricane Electric.](https://tunnelbroker.net/) Setting it up with pfSense was just a straightforward matter of following [Netgate's documentation](https://docs.netgate.com/pfsense/en/latest/interfaces/using-ipv6-with-a-tunnel-broker.html) - I added a GIF interface which then functions as a second WAN interface for the other services on the router. At this point I was using just a /64 that HE hands out by default.

</section>


<section>
## Level 2: IPv6 for all the physical machines behind the router

Just like the Netgate documentation, I enabled the DHCPv6 server on the `bridge0` interface. I did not want to add static mappings for the two devices, but I also wanted them to have fixed addresses instead of periodically rotating their addresses so that I could add DNS records for them. So I set the router's RA daemon to run in "Stateless DHCP" mode. This meant the devices would use SLAAC, which as I said above meant they would get deterministic addresses.

For systemd-networkd, this means the network file for the `enp4s0` interface looks like:

```
[Match]
Name=enp4s0

[Network]
DHCP=yes
```

</section>


<section>
## Level 3: IPv6 for all the Docker containers

Here, all hell broke loose.

Recall that the desktop has an `enp4s0` interface connected to the router, and a `docker0` bridge created by Docker automatically. Ideally, you'd be able to configure the Docker daemon to set up routes such that containers can talk to the DHCPv6 server over the `enp4s0` interface. However while it may be possible for custom Docker networks I create myself (using the macvlan driver), I did not find any way to do this for the default network it creates.

The other way is to use prefix delegation and delegate a whole /64 to the Docker host. In this case, the host acts as a router for the containers. Assuming the host is able to get a prefix `2001:db8:0:f002::/64` delegated to it, you would configure Docker to use it by setting the `fixed-cidr-v6` field in `/etc/docker/daemon.json`. You'd also add the DNS server's IPv6 address:

```json
{
  ...
  "dns": [
    "2001:db8:0:1::1",
    "192.168.1.1",
  ],
  "ipv6": true,
  "fixed-cidr-v6": "2001:db8:0:f002::/64"
}
```

So how does one get the host to request a prefix delegation from the router? Recall that the first step is to request a larger prefix than /64 from the ISP. In my case, HE does let you opt in to get a /48, so I did that and updated the LAN bridge IP to be under the new /48 prefix. I then configured the DHCPv6 server to reserve one `2001:db8:0:f002::/64` subnet under the /48 for prefix delegation.

As for the desktop, the documentation for systemd-networkd does have [an example of prefix delegation:](https://www.freedesktop.org/software/systemd/man/systemd.network.html#id-1.34.4)

```
# /etc/systemd/network/55-ipv6-pd-upstream.network
[Match]
Name=enp1s0

[Network]
DHCP=ipv6

# /etc/systemd/network/56-ipv6-pd-downstream.network
[Match]
Name=enp2s0

[Network]
IPv6PrefixDelegation=dhcpv6
```

Translating this to the desktop's setup, the first file is for the `enp4s0` network and the second for the `docker0` network. The file for `enp4s0` already matches what I have (`DHCP=yes` means both `ipv4` and `ipv6`), so that's fine. But I don't have a network file for the `docker0` interface since it's supposed to be managed by Docker, not systemd-networkd.

After a bunch of fiddling around, it did not seem to me that it was possible to have systemd-networkd request a prefix delegation without also having it manage the interface that the routed prefix would be bound to. I decided to use `dhclient` directly. To test, I ran `dhclient -d -P -v enp4s0` where `-d` tells the program to run in the foreground instead of forking a background daemon, and `-P` tells it to make a prefix delegation request. It successfully requested a prefix, and I could see the DHCPv6 lease in the pfSense status screen. Excited, I created two `alpine` containers and ran `ip a` in them, and was delighted to see they'd bound to addresses within the delegated /64.

I then had one of the containers run `nc -l -p 8080`, a simple netcat server, and had the other container run `nc <IP of the first container> 8080`, a netcat client to connect to the server. I hoped to see a successful connection. Instead, the client exited almost immediately. I re-ran the containers with `--privileged`, installed `strace` with `apk add`, and ran both the server and client `nc` processes under `strace -fe network,read,write`. This showed me that the server successfully bound to `[::]:8080`, but the client failed its `connect()` call with `EACCES`

`EACCESS` sounds like a permissions issue, but it didn't make sense. You could get `EACCES` if you were trying to bind to a low port (less than 1024), but the `nc` in the containers was running as `root` so that wasn't the problem. You could get `EACCES` if the container did not have some sort of network caps, but this was happening with `--privileged` containers so that wasn't the problem either. Just to be sure, I also gave the containers the `NET_ADMIN` cap, with no change.

I then attempted to connect to the netcat server with a client `nc` running on the *host*, and that succeeded! So the issue was certainly not with the server or its listening socket.

I said above that I'd verified the DHCPv6 lease for the delegated prefix in pfSense. Now I decided to also check the pf routes table. Recall that the upstream router needs to associated the routed prefix with the IP of the subrouter, which in this case means pfSense should've added a route to its routes table to associate the delegated prefix with the IP it leased to the `dhclient` instance. I was surprised to see there was no such route.

After some searching, I found the code in pfSense that creates the routes in response to prefix delegation requests at `/usr/local/sbin/prefixes.php`. It parses the lease out of `/var/dhcpd/var/db/dhcpd6.leases` and munges it into a `/sbin/route add` command. Specifically, if both an `ia-na` section and an `ia-pd` section are found for the same DUID, then the link address from the `ia-na` section and the routed prefix from the `ia-pd` section are used for the `route` command.

When I checked the leases file, I saw an `ia-pd` section but no `ia-na` section. It made sense - the subrouter was using SLAAC after all. In a way, pfSense's implementation makes sense. Without a stateful lease for the subrouter, the upstream router cannot necessarily add a route for it.

So I added a static DHCPv6 mapping for the host's DUID (with the same IP it had derived for itself for SLAAC to avoid having to change other things), and switched the RA daemon to use "Managed" mode. I also noticed that the DUID used by `dhclient` was different from the DUID used by systemd-networkd, so I edited the `/var/lib/dhcp6/dhclient.leases` file to have the same DUID as systemd-networkd's. The DUID that systemd-networkd uses is deterministic (based on the `/etc/machine-id`) so it would not need anything special to remain in sync. After restarting the network on the enp4s0 interface, I saw the managed mode take effect. I restarted the `dhclient` process and it acquired the lease again, but there was *still* no `ia-na` section in the `dhcpd6.leases` file, and there was still no route added for the delegated prefix.

In hindsight, it was obvious why there is no `ia-na` section in the leases file, because the IP was given via static assignment. But in this case pfSense could've preloaded the DUID-to-link-address map from the static DHCPv6 mappings instead of requiring the `ia-na` section. I may file a bug for this later.

At any rate, it looked I would have to use stateful DHCPv6 without static mappings, so I removed the static mapping for the host from the router, then restarted the network and `dhclient` again. As expected, this time the host did obtain a random address from the DHCP pool, and I did finally see the `ia-na` section in the leases file. I also saw the route created for the delegated prefix successfully.

But I still wanted a static IPv6 address for the desktop, so I was not happy with this state of affairs. Luckily the desktop's motherboard has two NICs, `enp4s0` and `enp6s0`. So I decided to have `enp4s0` continue to use SLAAC so that I could add a DNS entry for its deterministic address, and have `enp6s0` be the one to use stateful DHCPv6 with a separate dynamic address. So I found another LAN cable and plugged it into LAN2 (`igb1`).

That said, all the LAN NICs in the router were bridged, as I'd described at the start of this post, so there is only one instance of DHCPv6 server and RA daemon. I could not have the two LAN NICs behave differently with respect to the DHCPv6 mode.

I had to destroy the bridge and make each of the four LAN NICs into separate subnets, each with their own DHCPv6 server and RA daemon. In hindsight, this was a better design anyway, since it's closer to how the subnetting *should* be done.

So now my network topology looks like this:

```
                           +-----+
                           | ISP |
                           +-----+
                              |
                              |
+-----------------------------o----------------------------+
|                         WAN (em0)                        |
|                                                          |
|                      pfSense Router                      |
|                                                          |
| LAN1 (igb0)    LAN2 (igb1)    LAN3 (igb2)    LAN4 (igb3) |
+------o--------------o--------------o--------------o------+
                      |              |              |
                      |              |              |
                      |         +----o----+         |
                      |         | enp0s25 |         |
                      |         |         |         |
                      |         | laptop  |         |
                      |         +---------+         |
                      |                             |
                      |                             |
                  +---o-----------------------------o---+
                  | enp6s0        docker0        enp4s0 |
                  |                                     |
                  |               desktop               |
                  +-------------------------------------+
```

Each LAN NIC in the router is now its own subnet instead of being bridged. LAN2's DHCPv6 server also has an additional /64 prefix available to delegate, and its RA daemon runs in "Managed" mode.

On the desktop, I added a network file for `enp6s0` so that systemd-networkd would manage it:

```
[Match]
Name=enp6s0

[Network]
DHCP=ipv6
```

Of course, I also switched `dhclient` to run on `enp6s0` instead of `enp4s0`. One thing that tripped me up here was that `dhclient -P -v enp6s0` still kept renewing the lease for `enp4s0`. I eventually discovered this is because `dhclient` renews all the leases it sees in its leases file regardless of which interfaces it was give in its command line. So I also had to manually clear the `enp4s0` leases from the `/var/lib/dhcp6/dhclient.leases` file.

Now that I had a functioning prefix delegation and also a valid route, I tested the Docker containers again. But still the exact same thing happened - the client failed its `connect()` syscall with `EACCES`. I now turned to [`man connect`,](https://linux.die.net/man/2/connect) which says:

>EACCES
>
>    For UNIX domain sockets, which are identified by pathname: Write permission is denied on the socket file, or search
>    permission is denied for one of the directories in the path prefix. (See also path_resolution(7).)
>
>EACCES, EPERM
>
>    The user tried to connect to a broadcast address without having the socket broadcast flag enabled or the connection
>    request failed because of a local firewall rule.

"The connection request failed because of a local firewall rule" is the only one that could apply.

As an aside, openSUSE has both `iptables` and `nftables` available, and also defaults to using `firewalld` for the firewall. However, unlike the upstream `firewalld` code, the package in openSUSE defaults to using its `iptables` backend instead of its `nftables` backend. This is because Docker itself uses `iptables`, and works by putting its rules ahead of all existing rules. So if `firewalld` defined its rules using `nftables`, they would run in addition to Docker's rules and override them. That said, openSUSE also has the `iptables-backend-nft` package which causes all invocations of `iptables` to define rules using `nftables` anyway. Thus both `firewalld` and Docker end up defining rules that are visible using the `nft` CLI. This is the configuration I run, since I find the `nft` CLI easier to use than `iptables` and `ip6tables`. For example, flushing all rules with `nft` is just `nft flush ruleset`, but needs [fourteen commands for `iptables`](https://serverfault.com/a/200658)

So back to the problem, I decided to flush all the host's routing tables with `nft flush ruleset` and see what would happen. With an empty routing table, the kernel should not block any packets from being routed to wherever they need to be. Running the test again, it succeeded! The netcat client container was able to connect to the server container and they were able to send TCP messages back and forth. I also tried to connect to the server container from the laptop that was on a different subnet and that also worked, demonstrating that the routing was set up correctly even for hosts in different subnets to talk to each other.

The question was now to figure out which rule was causing the problem. After some cycles of restoring all rules with `firewall-cmd --reload` and flushing individual tables and chains with `nft flush table ...` and `nft flush chain ...`, I eventually realized the issue was with the `ip6 filter FORWARD` chain. These were the relevant rules in the output of `nft -a -n list table ip6 filter`:

```
chain FORWARD { # handle 2
        type filter hook forward priority 0; policy accept;
        # xt_conntrack counter packets 8531 bytes 8223657 accept # handle 12
        iifname "lo" counter packets 0 bytes 0 accept # handle 13
        counter packets 31 bytes 2352 jump FORWARD_direct # handle 15
        counter packets 31 bytes 2352 jump RFC3964_IPv4 # handle 36
        counter packets 31 bytes 2352 jump FORWARD_IN_ZONES # handle 17
        counter packets 0 bytes 0 jump FORWARD_OUT_ZONES # handle 19
        # xt_conntrack counter packets 0 bytes 0 drop # handle 20
        counter packets 0 bytes 0 # xt_REJECT # handle 21
}

chain FORWARD_IN_ZONES { # handle 16
        iifname "enp6s0" counter packets 11 bytes 800 goto FWDI_internal # handle 76
        iifname "docker0" counter packets 20 bytes 1552 goto FWDI_internal # handle 73
        counter packets 0 bytes 0 goto FWDI_public # handle 160
}

chain FWDI_internal { # handle 51
        counter packets 31 bytes 2352 accept # handle 163
        counter packets 0 bytes 0 jump FWDI_internal_pre # handle 57
        counter packets 0 bytes 0 jump FWDI_internal_log # handle 58
        counter packets 0 bytes 0 jump FWDI_internal_deny # handle 59
        counter packets 0 bytes 0 jump FWDI_internal_allow # handle 60
        counter packets 0 bytes 0 jump FWDI_internal_post # handle 61
        meta l4proto 58 counter packets 0 bytes 0 accept # handle 80
}
```

I had added the `enp6s0` and `docker0` interfaces to the `internal` zone in `firewalld`, which is why they connect to the `FWDI_internal` chain.

Removing the REJECT rule with `nft delete rule ip6 filter FORWARD handle 21` was enough to make the tests work. But the more appropriate way to do this would be to add ACCEPT rules to the `FWDI_internal` chain since that is specific to the `internal` zone's interfaces. Indeed, running:

```sh
nft add rule ip6 filter FWDI_internal meta l4proto 6 counter packets 0 bytes 0 accept
nft add rule ip6 filter FWDI_internal meta l4proto 17 counter packets 0 bytes 0 accept
```

... was also sufficient to make the tests work. (The existing rule for protocol 58 was for IPv6-ICMP. The rules I added were for protocol 6 which is TCP and 17 which is UDP.)

I initially considered putting these commands in a script and putting in the `docker.service` systemd service's `ExecStartPost`. But this would be brittle since any reload of the firewall would break Docker until Docker itself was restarted. A better way was to have firewalld add the rule, by adding a "direct" rule:

```sh
firewall-cmd --permanent --direct --add-rule ipv6 filter FWDI_internal 99 -j ACCEPT -p all

# equivalent to having firewalld run   ip6tables -A -j ACCEPT -p all   against the FWDI_internal chain.
```

I verified the tests still ran. The last step was to automate the `dhclient` command to run every time Docker started. For this I made a separate `docker-dhcp-pd.service` service:

```
[Unit]
Description=DHCPv6-PD for Docker
After=network.target

[Service]
Type=forking
ExecStart=/sbin/dhclient -P -v -pf /var/run/dhclient-enp6s0.pid enp6s0
PIDFile=/var/run/dhclient-enp6s0.pid
Restart=always
RestartSec=5s

[Install]
WantedBy=default.target
```

Notice that it does not have the `-d` flag so that it *does* fork and run as a background daemon. To make systemd aware of it, it's necessary to set `Type=Forking`. Lastly, I gave it a unique PID file so that it wouldn't conflict with other instances for different instances if I ever needed to run them.

Finally, I used `systemctl edit docker` to make it depend on the new service:

```
[Unit]
Requires=docker-dhcp-pd.service
After=docker-dhcp-pd.service
```

After flushing and reloading the firewall rules, and a clean restart of all the services, I once again ran the tests and they were successful. Two containers on the host were able to connect to each other, the containers were able to connect to the host and vice versa, and the laptop on another subnet was also able to connect to the containers.

One last problem was that containers could not connect to the router's DNS server's IPv6 address. To be precise, they would connect and send their query, but the server would immediately respond with REFUSED. I use pfSense's default DNS server, unbound, and I found it disallows queries from hosts it does not recognize. By default it only allows hosts in the DHCP ranges of each NIC, so it does not include hosts in the NICs' delegated prefixes. I solved this by adding an "Access List" in the Services/DNS Resolver/Access Lists section with a network that covered the entire /48 I had.

</section>


<section>
## Level 4: Turn off IPv4, aka "How to run tayga on pfSense"

This last one is the most idealistic. The idea was to disable IPv4 DHCP on the LAN entirely so that all devices would only get IPv6 addresses. By default, you would think this would mean the devices wouldn't be able to access IPv4-only servers on the internet, but two technologies help with this. Since IPv4 addresses are 32 bits, they easily fit in the lower 32 bits of any IPv6 address. Thus one can take a /96 that isn't being used by an actual address and use it to map IPv4 addresses to IPv6 addresses. The standard prefix reserved for this is `64:ff9b::/96` (though you can also use any /96 that belongs to you and isn't already used by any other subnet).

So you need a DNS server that maps IPv4 addresses to IPv6 addresses under `64:ff9b::/96` and returns synthesized AAAA records with those addresses, which is called DNS64. Then you need a stateful NAT that translates IP packets from IPv6 packets with `64:ff9b::/96` to the underlying IPv4 address, which is called NAT64. Ideally both of these would run on the router so that none of the other devices would need an IPv4 address themselves to perform this translation.

Enabling DNS64 on pfSense is straightforward - [this document](https://github.com/NLnetLabs/unbound/blob/master/doc/README.DNS64) lists the config options to set. For pfSense, these options go in the "Custom options" textarea on the DNS resolver settings page.

```
server:module-config: "dns64 validator iterator"
server:dns64-prefix: 64:ff9b::/96
```

After restarting the unbound service, DNS queries started returning these mapped addresses as expected. For example, `nslookup ipinfo.io` returned both `216.239.36.21` and `64:ff9b::d8ef:2415` and you can see `d8ef:2415` indeed corresponds to `216.239.36.21`. Note that DNS64 only takes effect for domains that don't already have AAAA records. So `nslookup example.org` will not return a synthesized AAAA record, only the real one.

Enabling NAT64 was less straightforward. Ideally it would be done by the firewall since doing stateful NAT is already the firewall's job. Unfortunately pfSense uses pf, and FreeBSD's pf does not support NAT64. FreeBSD's pf is forked from OpenBSD's pf, and OpenBSD's pf *does* have NAT64 support, but the patches apparently cannot be backported to FreeBSD because the two codebases have diverged a lot since the fork. FreeBSD's ipfw firewall does support it, but pfSense does not use it.

The other way to do NAT64 is to use a user-space daemon. A popular software package for this is [tayga.](http://www.litech.org/tayga/) There are a few tutorials on the internet for setting up tayga in a Linux VM and configuring pfSense to route the prefixed traffic to the VM which then converts it and route it back. But I wanted it to run on the router because I did not want any other LAN device to have an IPv4 address. As it happens, tayga is in the FreeBSD repository too, so it can be installed after enabling the FreeBSD repo.

```sh
# Enable the FreeBSD repo. pkg reads the files in alphabetical order,
# so the override needs to be named such that it comes after the existing files placed by pfSense.
# The z_ prefix does that.
ln -s /etc/pkg/FreeBSD.conf /usr/local/etc/pkg/repos/z_overrides.conf

# Verify that the FreeBSD repo is now enabled.
pkg -vv

# Install the tayga package. This may require updating pkg itself first
# since the one in FreeBSD's repo is newer than the one in pfSense's repo.
pkg install tayga
```

Setting tayga up needed some more work. OPNSense recently added some support for running tayga as a plugin, so I was able to copy some of the work they did. [This GitHub comment](https://github.com/opnsense/core/issues/167#issuecomment-587166184) and [this GitHub comment](https://github.com/opnsense/plugins/pull/1700#issuecomment-589350662) were very useful, as was the actual implementation of the plugin [here.](https://github.com/opnsense/plugins/tree/master/net/tayga/)

I configured tayga by editing `/usr/local/etc/tayga.conf`:

```
tun-device nat64
ipv4-addr 192.168.255.1
ipv6-addr 2001:db8:0:5::1
prefix 64:ff9b::/96
dynamic-pool 192.168.255.0/24
data-dir /var/db/tayga
```

All the settings here are default except for `ipv6-addr` and `prefix`. `ipv6-addr` is optional if `prefix` is not `64:ff9b::/96`, but I wanted `prefix` to be that value. Thus I had to set `ipv6-addr` to an address that is routed to my router but is not already used. Thus it had to be under the /48 I received from HE but not any of the /64s my LAN NICs were already using.

The next step was to add tayga as a service. I created `/usr/local/etc/rc.d/tayga` based on the OPNSense script:

```sh
#!/bin/sh
#
# $FreeBSD$
#
# PROVIDE: tayga
# REQUIRE: SERVERS
# KEYWORD: shutdown
#

. /etc/rc.subr

name='tayga'

start_cmd='tayga_start'
stop_cmd='tayga_stop'
rcvar='tayga_enable'

load_rc_config 'tayga'
pidfile="/var/run/${name}.pid"
command="/usr/local/sbin/${name}"
command_args="-p ${pidfile}"

[ -z "$tayga_enable" ] && tayga_enable='YES'

tayga_start() {
    "$command" $command_args
    while ! ifconfig 'nat64'; do sleep 1; done
    ifconfig 'nat64' inet '192.168.254.1/32' '192.168.255.1'
    ifconfig 'nat64' inet6 '2001:db8:0:5::1/128'
    route -6 add '64:ff9b::/96' -interface 'nat64'
    route -4 add '192.168.255.0/24' -interface 'nat64'
}

tayga_stop() {
    if [ -n "$rc_pid" ]; then
        echo 'stopping tayga'
        kill -2 "${rc_pid}"
        ifconfig 'nat64' destroy
    else
        echo "${name} is not running."
    fi
}

run_rc_command "$1"
```

The name of the interface, and the addresses used for the ` ifconfig 'nat64' inet`, `ifconfig 'nat64' inet6`, `route -6 add` and `route -4 add` commands, match the values in `tayga.conf`. Then I `chmod +x`'d the file, and ran `service tayga start` to start it. `ifconfig nat64` showed the interface with the IPs attached to it, and the routes were visible in pfSense's web UI.

Then, in the pfSense web UI, the interface assignments page showed the `nat64` address as available to be assigned. I did that and it was assigned the default name OPT4. Then I added a firewall rule for the OPT4 interface with action "Pass", address family "IPv4+IPv6", protocol "Any" and "any" source and destination. I also went to Firewall/NAT/Outbound and added a custom mapping for interface "WAN" (the interface corresponding to `em0`, connected to my ISP), address family "IPv4+IPv6", protocol "any", source "Network" with range `192.168.255.0/24` (the range configured in `tayga.conf`) and destination "Any". I also switched the "Outbound NAT Mode" setting from "Automatic" to "Hybrid" so that the custom rule would take effect.

I could now see that `curl -6` on my desktop was able to fetch IPv4-only hosts.

Unfortunately, there was a problem with setting it up this way. The interface had to be assigned in pfSense so that I could add the firewall and outbound NAT rules for it, but this means the interface is registered in pfSense's `config.xml` even though it's dynamically generated when the `tayga` service starts. When I rebooted the router, it noticed that the `nat64` interface no longer existed, and went into reconfiguration mode where I would have to set up all the interfaces again. The second GitHub comment mentions this problem too:

>I also noticed that this causes issues on reboots. The nat64 interface probably doesn't exist yet when OPNsense configures its interfaces during startup. So saving the interface in the OPNsense config might not be the best choice.

So I needed a way to add the firewall and NAT rules without registering the interface with pfSense, ideally from the tayga service's start action itself. First, I investigated whether it was possible to use the `/usr/local/bin/easyrule` script that pfSense provides for scripting the firewall rules, but this also requires the interface to be registered with pfSense so it wouldn't have worked. Then I checked whether it would be possible to use `pfctl` directly. The rules file that pfSense uses is at `/tmp/rules.debug`, and among other things it contains:

```
nat-anchor "natrules/*"
anchor "userrules/*"
```

So it's indeed possible to add rules under those anchors and have them be picked up by pf automatically. I extracted all the rules related to `nat64` and `192.168.255.0` from `/tmp/rules.debug`, ie the rules that pfSense had added when the interface was registered through the UI, and edited the `tayga_start` function to add those rules using `pfctl`:

```diff
     ifconfig 'nat64' inet6 '2001:db8:0:5::1/128'
     route -6 add '64:ff9b::/96' -interface 'nat64'
     route -4 add '192.168.255.0/24' -interface 'nat64'
+
+    ll_addr="$(ifconfig nat64 | awk 'match($0, /^\tinet6 (fe80:.*)%nat64 /) { print $2; }' | sed -e 's/%nat64$//')"
+    printf "
+scrub on nat64 all fragment reassemble
+block drop in log on ! nat64 inet6 from 2001:db8:0:5::1 to any
+block drop in log on nat64 inet6 from $ll_addr to any
+block drop in log on ! nat64 inet from 192.168.254.1 to any
+pass in quick on nat64 inet all flags S/SA keep state
+pass in quick on nat64 inet6 all flags S/SA keep state
+" | pfctl -a userrules/tayga -f -
+
+    wan_addr="$(ifconfig em0 | awk '/^\tinet / { print $2 }' | head -n1)"
+    if [ -n "$wan_addr" ]; then
+        printf "
+nat on em0 inet from 192.168.255.0/24 to any -> $wan_addr port 1024:65535
+" | pfctl -a natrules/tayga -f -
+    fi
```

(Note: Every invocation of `pfctl` for a particular anchor specified by `-a` deletes any previous rules in the anchor. So if you need to delete the rules, simply run the commands with `echo ''` instead of `printf '...'`)

The source IP used in the first `block` rule is the `ipv6-addr` from `tayga.conf`.

In the NAT rule, `em0` is the IPv4 WAN interface. I'm not sure how to make it so that the rule updates dynamically if the interface changes IPs. For now I'd have to restart the tayga service when that happened.

Then I removed the firewall rule, outbound NAT rule, and finally the whole interface from pfSense. I then restarted the tayga service, and was still able to see the synthesized AAAA records. Lastly, I changed the `enp4s0` network file to only request DHCPv6:

```diff
 [Match]
 Name=enp4s0
 
 [Network]
-DHCP=yes
+DHCP=ipv6
```

... and restarted the network. I confirmed that processes on the desktop were able to continue working, as were Docker containers.

I now had a network that was completely IPv6, yet was still able to interoperate with the IPv4 internet.

Alas...

</section>


<section>
## Epilogue

... it turned out a few things I use regularly don't work in a pure IPv6 + NAT64 environment.

One of them is [Steam.](https://github.com/ValveSoftware/steam-for-linux/issues/3372) The precise reason is unknown.

The other is bittorrent. The bittorrent tracker messages include IP addresses inside them, so a firewall cannot rewrite any IPv4 addresses inside the messages with the prefix (unless it used deep packet inspection or was application protocol-aware). Therefore the bittorrent client ends up with IPv4 IPs that it cannot use and becomes unable to find any peers to connect to. It could be possible to have a bittorrent client that lets the user configure it with the prefix, so that it can itself convert IPv4 addresses to IPv6 addresses. But the client I use does not have such a capability and I did not find any other that might.

This is poetic in a way, since regular IPv4-to-IPv4 NAT also has these problems.

As a result, I did unfortunately have to roll back the IPv6-only idealism and let `enp4s0` also obtain an IPv4 address. I *have* left the NAT64 setup running for now, so that applications that don't have a problem working with the NATted IPs can continue doing so.

</section>
