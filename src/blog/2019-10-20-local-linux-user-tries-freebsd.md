---
title: "2019-10-20 Local Linux user tries FreeBSD"
date: '2019-10-20T00:00:00Z'
---

I recently built a new desktop computer for myself, and decided to repurpose my old desktop computer to be [a pfSense router.](https://en.wikipedia.org/wiki/PfSense){ rel=nofollow } pfSense comes with a webserver that serves a configuration GUI accessible from any device on the LAN. The GUI also has a status dashboard that shows real-time hardware stats, service status, network utilization and firewall logs.

However I wanted to be able to access the status dashboard from the CLI, so that I could stuff it in a tmux session along with the dashboards for my other computers instead of running a whole browser instance just for it. So I set about figuring out how the web dashboard works behind the scenes and how I could replicate it to run as a CLI program over ssh.

Since pfSense is based on FreeBSD and I only had experience with Linux, it was a learning experience to find all the differences between the two - from minor differences in the parameters of well-known commands, to differences in philosophy.


<section>
<h2 id="what-does-the-status-dashboard-show">[What does the status dashboard show?](#what-does-the-status-dashboard-show)</h2>

The information that pfSense's web dashboard shows is itself pulled from shelling out to native commands or reading files:

- Version information via `/etc/version`, `/etc/version.path`, `/etc/version.buildtime` and `uname`
- Uptime via `sysctl kern.boottime`
- CPU usage via `sysctl kern.cp_time`
- Memory usage via `sysctl hw.physmem` and `sysctl vm.stats.vm.v_{inactive,cache,free}_count`
- Disk information via `sysctl kern.disks` and `df`
- Temperature sensor readings via `sysctl` with names depending on the hardware. For example, my Intel CPU's sensors are reported through `sysctl dev.cpu.{0,1,2,3}.temperature` and some additional sensors through `hw.acpi.thermal.tz{0,1}.temperature`
- Network interfaces status via `ifconfig` and `netstat`
- Services status (running or not running) via `pgrep`

</section>


<section>
<h2 id="writing-the-cli-dashboard">[Writing the CLI dashboard](#writing-the-cli-dashboard)</h2>

Now that I knew what files and shell commands my dashboard would invoke, the next step was to decide what language I should implement it in.

The program would just be writing text to stdout, including escape sequences to clear the screen and scrollback. Since that is easy in most programming languages, my choice was largely dictated by what language runtimes and compiler packages I had available.

Rust was my first choice since it is what I've been using primarily for the last few years. However the current version of pfSense (2.4.4) is based on FreeBSD 11, and I couldn't find out definitive information whether Rust supports it. Specifically, Rust had updated its FreeBSD target's C FFI and standard library some time ago to support FreeBSD 12, which in turn was because FreeBSD 12 had changed the ABI of some of its libc structures. So I wasn't sure if a program compiled against Rust's `x86_64-unknown-freebsd` target would also work on FreeBSD 11 or only on FreeBSD 12.

A bigger problem was figuring out how to actually use Rust. I didn't want to install Rust or a C toolchain on the router itself, and setting up a FreeBSD-cross-compiler toolchain on my Linux machine appeared to require that I compile the cross compiler from source. This was more effort than I was willing to put in.

C was my second choice, but again I didn't want to install a C toolchain on the router or set up a cross-compiler on my Linux machine.

I then tried shell, and hit two snags:

- The default FreeBSD shell for the root user is `tcsh`. (Other users do default to POSIX `sh`, as an HN user pointed out [here.](https://news.ycombinator.com/item?id=21567879){ rel=nofollow }) I *was* prepared to not have `bash`, but `tcsh` is quite alien in its syntax compared to regular POSIX `sh`. I decided to ignore it and just use POSIX `sh`.

- POSIX `sh` is missing a few things I'd come to take for granted in `bash`.

    There is no process substition via `<()`, so it's not possible to modify variables while chomping a command's output with a loop, like with `while read -r line; do ... done < <(command)`

    Most importantly, POSIX `sh` does not have arrays, so I had to resort to constructing variables names with indices like `FOO_$i` using string concat, and using `eval` for all reads and writes to them.

I did manage to implement the dashboard in POSIX `sh`; however its CPU usage was quite high for my taste. This was mostly because almost all the commands I was shelling out to had to be further processed using `cut` or `grep` or `sed` or `awk`, so there were a lot of processes being created and lots of strings being sliced and diced every time the dashboard refreshed.

I initially set about replacing some of the `cut`s and `grep`s and `sed`s with `awk`. But then I realized I could just as well write the whole dashboard as a single AWK script and not bother with POSIX `sh` at all.

The result is at [pfsense-dashboard-cli](https://github.com/Arnavion/pfsense-dashboard-cli){ rel=nofollow } and I'm quite satisfied with it.

It does have a dependency on `perl` to get the current time in seconds from the Unix epoch. This is because FreeBSD's `date` does not have a way to get milliseconds in the time, which is important for refreshing the dashboard once every second, which in turn is important for getting accurate network usage numbers (`(current bytes - previous bytes) / (current iteration time - previous iteration time)`; losing milliseconds in the denominator can introduce large errors in the result).

Note that `perl` is not part of a base FreeBSD install, as HN users pointed out [here](https://news.ycombinator.com/item?id=21567675){ rel=nofollow } and [here.](https://news.ycombinator.com/item?id=21568087){ rel=nofollow } However pfSense pulls it in as a dependency and it is thus available on a default pfSense install, so it doesn't violate my "don't manually install any additional packages" constraint.

</section>


<section>
<h2 id="what-did-i-learn">[What did I learn?](#what-did-i-learn)</h2>

The list of files and commands above shows some major differences between Linux and FreeBSD. A Linux program would get uptime from `/proc/uptime`, read temperature sensors from files under `/sys/class/hwmon`, and get CPU, memory and network stats from procfs and sysfs. Most of these interfaces are exposed as raw numbers and can be easily manipulated from shell with `bc` or `awk`.

In contrast, a lot of the equivalent information in FreeBSD is obtained through `sysctl` or shell commands intended for human consumption. In fact, FreeBSD does not have procfs or sysfs at all. (Apparently a simplified procfs is available for you to mount at `/proc` yourself if you want it. I did not try it, because it wouldn't have had everything I need anyway.)


<section>
<h3 id="sysctl">[`sysctl`](#sysctl)</h3>

The default way of using `sysctl` is with `-n`. However this output is meant to be human-readable and not necessarily easy to parse programmatically. For example, the uptime information from `sysctl -n kern.boottime` looks like

```
{ sec = 1570952543, usec = 411609 } Sun Oct 13 00:42:23 2019
```

... which is a strange amalgamation of a C-like structure and a formatted datetime string. While it looks easy enough to extract the first two numbers with a regex or naively splitting on spaces, an output like this makes you wonder if it's guaranteed to always be like that. For example, could it sometimes get emitted as `{ usec = ..., sec = ... } ...` instead? Compare with Linux's `/proc/uptime` - `601553.11 14266486.38` - it can be easily split on the space and needs no additional parsing.

Similarly, the temperature sensor values on Linux from files under `/sys/class/hwmon` are usually just numbers in milli-degrees Celsius. For example, `/sys/class/hwmon/hwmon0/temp1_input` might be `32750` representing 32.750 degrees Celsius. However the FreeBSD `sysctl` values look like `33.0C`, so they first need string processing to strip the `C` suffix and get the raw value.

However, as an HN user pointed out [here,](https://news.ycombinator.com/item?id=21567585){ rel=nofollow } `sysctl -b` prints the values in "raw, binary format." The exact format depends on the variable. So `sysctl -b kern.boottime` writes 16 bytes, where the first eight are the seconds and the latter eight the microseconds of the bootime, in little-endian. Similarly, `sysctl -b dev.cpu.0.temperature` writes a four-byte unsigned integer that represents the temperature in deci-Kelvin. For example, a value of 3061 means the temperature is 306.1 K, or 33.0 °C.

Of course, parsing binary from `awk` is not easy, so the script passes the output of `sysctl -b` through `od` or `hexdump` as appropriate.

</section>


<section>
<h3 id="json-via-libxo">[JSON via `libxo`](#json-via-libxo)</h3>

However, not all information is available from `sysctl`. Network usage information is only available from the `netstat` command. On Linux, network stats can be read from sysfs paths like `/sys/class/net/enp4s0/statistics/{r,t}x_bytes` which yield a single number each. However `netstat -I em0 -bn` returns a tabular display, which means the script would have to skip the first line of table headers, then split each row on whitespace, then select the second-last or fifth-last values and add them manually.

(My NICs use the `igb` driver which does have sysctls similar to the Linux `{r,t}x_bytes` files, but these only exist for the hardware interfaces and not for logical ones like the LAN bridge interface.)

But again, that same HN user pointed out that `netstat` writes its output using `libxo`, and thus `netstat -I em0 -bn --libxo json` would write JSON output. However, just like with the binary output from `sysctl`, `awk` can't parse JSON very well on its own. The best way I could think of was to use `json,pretty` so that every key-value pair goes on its own line, and then slice the lines to extract the values, but this would be worse than scraping the human-readable text output because of needing to keep extra state across lines.

So just like the `sysctl` binary output could be made easier to parse by `od` or `hexdump`, I would need a program to parse the JSON and emit it in a simpler format. On Linux I would've reached for [`jq`.](https://github.com/stedolan/jq){ rel=nofollow } pfSense by default does have a similar utility called [`uclcmd`,](https://github.com/allanjude/uclcmd){ rel=nofollow } but it's very basic. I could write a filter like `netstat -I em0 -bn --libxo json | uclcmd get -f - -j '.statistics.interface|each|.received-bytes'`, but any processing like adding the results together would have to be done by the caller, ie the `awk` script. Also, `uclcmd` doesn't have a way to extract multiple fields from a JSON object to build a new one, so a single command would not be able to extract both `"received-bytes"` and `"sent-bytes"` bytes from a single invocation of `netstat`. Lastly, `uclcmd` is very unstable (if it can't parse the filter it usually segfaults instead of printing an error message), has no documentation (I was only able to figure out how `each` is meant to be used by reading the source), and appears to be abandoned.

However, my pfSense install *does* also have `jq`, because it's a dependency of the `pfBlockerNG-devel` package which I also use. So I decided using it doesn't violate my "don't manually install any additional packages" constraint.

`smartctl` does not use `libxo`, but does have the ability to emit JSON via the `-j` flag.

</section>


<section>
<h3 id="scraping-text">[Scraping text](#scraping-text)</h3>

Other commands like `clog` and `ifconfig` do not use libxo, so the script still has to scrape their human-readable text output.

</section>

For what it's worth, some of these problems are solved by using C instead of shell. For example, the `gettimeofday` function does return the current time with milliseconds. Network stats can be obtained in strongly-typed fashion using `ioctl`, which is also how pfSense web dashboard gets them.

Apart from that, some of the FreeBSD commands are subtly different from their Linux counterparts. `pidof` doesn't exist and you have to use `pgrep -x` instead. `find -name foo` doesn't work and explicitly requires the starting directory, like `find . -name foo`, whereas it's implicitly the current directory in Linux. As mentioned above, `date` does not support `.%N` which on Linux outputs decimal seconds. And nothing recognizes `--help`, though that still means they print their helptext anyway, though their helptext is just a list of flags with no explanation and you have to read the manual to know what they do.

But that's enough complaining. Now for the good parts.

The BSDs are known for having good manuals, though pfSense does not include them so I had to look for them online. They are at [this URL.](https://www.freebsd.org/cgi/man.cgi?query=&apropos=0&sektion=0&manpath=FreeBSD+11.2-RELEASE&arch=default&format=html){ rel=nofollow } Google and DuckDuckGo would not return that URL when searching for, say, `freebsd man netstat`, and instead return outdated manuals on third-party hosting or manuals from other distros, so I've bookmarked that URL in my browser. The manuals are certainly very detailed and answered most of the questions I had, without needing to search forums like I usually have to for Linux questions.

(An HN user pointed out [here](https://news.ycombinator.com/item?id=21567568){ rel=nofollow } that DDG has a `!man` bang command - it forwards to [manpages.me](https://manpage.me){ rel=nofollow } However this site is very slow, and defaults to a newer version of FreeBSD, so I don't use it.)

And lastly, I learned that `awk` is a pretty good language for writing complex scripts while still having a simple DSL for shelling out to processes and chomping their output. It does have some idiosyncrasies though:

- Repeatedly "spawn"ing the same process (`"foo" | getline`) actually reads more lines from the first invocation of the process, until explicitly `close()`d.
- Functions can't have local variables; assigning to local variables instead sets global variables. They need to be specified as parameters of the function and ignored by the caller to be local.
- Iterating over arrays with `for-in` has a random iteration order; use an index loop to be stable.
- Splitting function calls over multiple lines requires `\` terminators at some places but not others.

Regardless, it is a godsend to be able to do string processing and arithmetic in a single program without needing to shell out to `grep` or `bc` or `numfmt` or `printf`.

FreeBSD's manual for `gawk` is at [this URL,](https://docs.freebsd.org/info/gawk/gawk.info.Index.html){ rel=nofollow } and is much more explanatory than the default `awk` manual.

My dayjob involves working with Raspberry Pis (running Raspbian). I usually ssh to them over ethernet rather than connect a serial cable or a monitor-and-keyboard to them. However if one were to change its IP address while I'm away, I would be locked out of it until I hooked up a serial cable or monitor-and-keyboard and dumped its new IP address. So I decided to write a script that would repeatedly flash the LED on the Pi in morse code corresponding to its current IP address. It was quite easy to write this script in `awk`, including the part of converting the address components to binary via division. It would've been a tad more complicated in `bash`. You can find the script [here.](https://gist.github.com/Arnavion/32bf76c0ad35318c44041a6d1f1cdb39){ rel=nofollow }

Perl would probably be another good choice to solve these kinds of problems, for both Linux and FreeBSD, but I have no experience with it. Maybe one day...

</section>
