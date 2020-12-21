---
title: '2020-12-05 DDG vs Google'
date: '2020-12-05T00:00:00Z'
---

I use [DuckDuckGo](https://duckduckgo.com/) as my browser's search engine, but I find I often have to drop down to using Google for search results because DDG's results don't answer the question.

Other people on the internet have the full range of experiences about this, ranging from people who swear they get adequate answers from DDG and rarely have to drop down to Google, to people like me. Usually this is attributed to people like me having gotten used to Google's knowledge of their search history, especially when they're logged in, and thus being able to fill in context that is missing from their query.

It's true that I've been using Google since it was created and DDG only since 2018, so I might be used to typing queries that work well with Google and not with DDG. I'm also always logged in to Google, though I do also have private results and search history turned off. So assuming Google really does honor it as it claims to do, it should be a fair comparison to DDG.

But rather than leave it as a vague recollection of how often I get valid results from DDG vs having to drop down to Google, I decided to quantify it by cataloging the searches I do (and feel okay with sharing publicly) and the results I got. This blog post is that catalog.

Each section's heading is the query I put in DDG. That is followed by the goal I had in mind when typing that query, the URL of the correct answer that the search engine ought to have returned, and then the search results returned by DDG and Google, with commentary about their results. I've taken the first five results for each engine unless otherwise noted.

Note that the Google results were obtained by prepending `!g` to the DDG search query, not by going to google.com and typing the query there. Also note that I do not have suggestions-as-I-type enabled in either search engine, so if DDG provided an opportunity to refine the query before I executed it, I didn't see it. I also have "safe search" off for both engines.


<section>
## `linux use hardware random generator dev urandom`

Goal: Find if it's possible to have `/dev/urandom` use a hardware random number generator, such as TPMs or PKCS#11 hardware, instead of the kernel's RNG.

Correct answer: No. At best, userspace can read entropy from such hardware and feed it to the kernel, but the RNG is still the kernel's.

### DDG

1.  >devices - When to use /dev/random vs /dev/urandom - Unix ...
    >
    >https://unix.stackexchange.com/questions/324209/when-to-use-dev-random-vs-dev-urandom
    >
    >This is somewhat of a "me too" answer, but it strengthens Tom Hale's recommendation. It squarely applies to Linux. Use /dev/urandom; Don't use /dev/random; According to Theodore Ts'o on the Linux Kernel Crypto mailing list, /dev/random has been deprecated for a decade. From Re: [RFC PATCH v12 3/4] Linux Random Number Generator:. Practically no one uses /dev/random.

1.  >On Linux's Random Number Generation - NCC Group Research
    >
    >https://research.nccgroup.com/2019/12/19/on-linuxs-random-number-generation/
    >
    >Incidentally, this is what /dev/urandom does on sane systems (e.g. FreeBSD or macOS). Applications should simply use getrandom(), and be happy. (Or not. Linux 5.3 will turn back getrandom() into /dev/urandom with its never-blocking behavior, because, quite frankly, Linus's opinions on his own mastery of RNG theory exceed his actual abilities ...

1.  >Random number generation - ArchWiki - Arch Linux
    >
    >https://wiki.archlinux.org/index.php/Random_Number_Generation
    >
    >For an Arch system, the above implies the following for /dev/urandom: Use the kernel's getrandom() system call, whenever possible. It is provided to ensure that /dev/urandom has initialized appropriately. See getrandom(2). If you use the /dev/urandom device for generating entropy for any long-term purpose, do ensure it has initialized properly.

1.  >How to Generate a Random Number in Linux - Putorius
    >
    >https://www.putorius.net/generate-random-number-linux.html
    >
    >Using dev urandom to Generate a Random Number. We used /dev/urandom in our past article "5 Methods to Generate a Random Password from the Command Line". Here we will use the same method, but selecting only digits. You can use /dev/urandom with many different commands. Most of these commands are limited because there is no easy way to specify ...

1.  >/dev/random vs /dev/urandom and are they secure? - KhacNam
    >
    >https://khacnam.net/dev-random-vs-dev-urandom-and-are-they-secure.html
    >
    >In short, /dev/random is the safest of all, then comes /dev/arandom and the least safest is /dev/urandom. Normally /dev/random and /dev/urandom are used because /dev/arandom in many terms is similar to /dev/urandom. The entropy estimation for the random number pool in short is used to determine the randomness of numbers generated.

Analysis: All results are irrelevant. They talk about `/dev/urandom` (three of them are specifically about the meme of its comparison with `/dev/random`) but not about hardware generators.

### Google

1.  >/dev/random - Wikipedia
    >
    >https://en.wikipedia.org/wiki//dev/random
    >
    >While /dev/urandom is still intended as a pseudorandom number generator ... users concerned about such an attack should use /dev/random instead. ... The Linux kernel provides support for several hardware random ...

1.  >Random number generation - ArchWiki - Arch Linux
    >
    >https://wiki.archlinux.org/index.php/Random_number_generation
    >
    >If you use the /dev/urandom device for generating entropy for any long-term purpose, do ensure it has initialized properly.
    ‎Kernel built-in RNG · ‎/dev/random

1.  >/dev/random vs /dev/urandom and are they secure? – Linux Hint
    >
    >https://linuxhint.com/dev_random_vs_dev_urandom/
    >
    >Linux has three categories of random number generators, /dev/random, ... The random numbers in these files are generated using the environmental noise from the device ... Why machines can not generate true random number on its own?

1.  >Myths about /dev/urandom - Thomas Hühn
    >
    >https://www.2uo.de/myths-about-urandom/
    >
    >The most-recommended explanation about Linux random number generation, the differences ... /dev/urandom is a pseudo random number generator, a PRNG , while ... It is true, the random number generator is constantly re-seeded using ...

1.  >Ensuring Randomness with Linux's Random Number Generator
    >
    >https://blog.cloudflare.com/ensuring-randomness-with-linuxs-random-number-generator/
    >
    >This blog post looks at Linux's internal random number generator and how it overcomes ... This is especially true for servers that run in virtualized environments that might not ... On the other hand, /dev/urandom does not block.

Analysis: The first result has the answer. The result text doesn't answer the question, but searching the page for "hardware" reveals:

>The Linux kernel provides support for several hardware random number generators, should they be installed. The raw output of such a device may be obtained from `/dev/hwrng`.
>
>With Linux kernel 3.16 and newer, the kernel itself mixes data from hardware random number generators into `/dev/random` on a sliding scale based on the definable entropy estimation quality of the HWRNG. This means that no userspace daemon, such as `rngd` from `rng-tools`, is needed to do that job. With Linux kernel 3.17+, the VirtIO RNG was modified to have a default quality defined above 0, and as such, is currently the only HWRNG mixed into `/dev/random` by default.

**Winner: Google**

</section>


<section>
## `cargo build script replace`

Goal: Figure out how to tell `cargo` to replace a third party crate's build script with something else. Based on a vague recollection that this is possible.

Correct answer: https://doc.rust-lang.org/cargo/reference/build-scripts.html#overriding-build-scripts

### DDG

1.  >The Manifest Format - The Cargo Book
    >
    >https://doc.rust-lang.org/cargo/reference/manifest.html
    >
    >The Cargo.toml file for each package is called its manifest. Every manifest file consists of the following sections: ... [replace] — Override dependencies (deprecated). [profile] — Compiler settings and optimizations. ... then the include/exclude list is used for tracking if the build script should be re-run if any of those files change.


1.  >Post-build script execution · Issue #545 · rust-lang/cargo ...
    >
    >https://github.com/rust-lang/cargo/issues/545
    >
    >Currently, cargo execute scrips before the build starts with the build field. I propose renaming build to pre_build and adding post_build (which would run after every successful build). ... If they notice a slowdown, we can always introduce the option to replace the postbuild.rs script by the other two later.

1.  >cargo-make | Rust task runner and build tool.
    >
    >https://sagiegurari.github.io/cargo-make/
    >
    >Single command or script task (for example cargo build) Tasks that come before or after the single command tasks (hooks) Tasks that define flows using dependencies; Tasks which only install some dependency; Single command tasks are named based on their command (in most cases), for example the task that runs cargo build is named build.

1.  >How can I make Cargo execute a build script and use a ...
    >
    >https://stackoverflow.com/questions/41452469/how-can-i-make-cargo-execute-a-build-script-and-use-a-target-specific-linker-at
    >
    >When I run cargo build now, my build-script build.rs is no longer executed. Since the script provides the paths for important libraries, the building process eventually fails. To reproduce the problem under Windows 10 (64-bit) with Visual Studio 12, create a project as follows:

1.  >GitHub - phil-opp/cargo-post: A `cargo` wrapper that ...
    >
    >https://github.com/phil-opp/cargo-post
    >
    >cargo-post. A cargo wrapper that executes a post build script after a successful build.. Installation cargo install cargo-post Usage. Execute cargo CMD [ARGS] and run post_build.rs afterwards:. cargo post CMD [ARGS] The post_build.rs is only run if CMD is a build command like build or xbuild.. In workspaces, you might have to pass a --package argument to cargo build to specify the package for ...

Analysis: All results are irrelevant, especially the third and fifth ones.

### Google

1.  >Build Scripts - The Cargo Book
    >
    >https://doc.rust-lang.org/cargo/reference/build-scripts.html
    >
    >The build script will be rebuilt if any of its source files or dependencies change. By default, Cargo will re-run the build script if any of the files in the package changes.

1.  >Build Script Examples - The Cargo Book
    >
    >https://doc.rust-lang.org/cargo/reference/build-script-examples.html
    >
    >Build Script Examples. The following sections illustrate some examples of writing build scripts. Some common build script functionality can be found via crates on ...

1.  >Build Scripts - The Cargo Book - MIT
    >
    >http://web.mit.edu/rust-lang_v1.25/arch/amd64_ubuntu1404/share/doc/rust/html/cargo/reference/build-scripts.html
    >
    >Cargo does not aim to replace other tools that are well-optimized for these tasks, but it does integrate with them with the build configuration option. [package] # ...

1.  >Add a way for build scripts to be re-run if specific environment ...
    >
    >https://github.com/rust-lang/cargo/issues/2776
    >
    >I hit an error building rust-openssl, and it looks like it's not fixable ... for build scripts to be re-run if specific environment variables change #2776.

1.  >How can I force `build.rs` to run again without cleaning my ...
    >
    >https://stackoverflow.com/questions/49077147/how-can-i-force-build-rs-to-run-again-without-cleaning-my-whole-project
    >
    >Normally build scripts are re-run if any file inside the crate root ... call of the build script by replacing the build = "build.rs" line in Cargo.toml with ...

Analysis: First result is the correct one. The text isn't relevant, but since it's the general page for build scripts it does have the answer, in the "Overriding build scripts" section.

**Winner: Google**

</section>


<section>
## `tray icons dbus`

Goal: Find the name of the dbus API for showing tray icons.

Correct answer: https://www.freedesktop.org/wiki/Specifications/StatusNotifierItem/

### DDG

1.  >How to show all system tray icons on Windows 10
    >
    >https://www.addictivetips.com/windows-tips/show-all-system-tray-icons-on-windows-10/
    >
    >The system tray is a little section on the Taskbar where system icons such as the speaker, network, and action center icons appear. Of course since it's Windows 10, Microsoft doesn't keep this space to itself. Any app that wants to can add an icon to the system tray and you can access said app from this icon. Sometimes apps run entirely in the system tray, and other times, their icons are ...

1.  >No tray icon on Linux (electron@^8) · Issue #21445 ...
    >
    >https://github.com/electron/electron/issues/21445
    >
    >As above-referenced chromimum issue says StatusNotifier/DBus support got added and something got removed. So I looked up things on the internet and got the tray icon well displayed but only on Manjaro XFCE so far (have not tried anything KDE based yet though, might be working well there):

1.  >CMST - A Connman GUI front end with system tray icon ...
    >
    >https://bbs.archlinux.org/viewtopic.php?id=175600
    >
    >I'm afraid that QT was the only way I was going to be able to create the system tray icon and deal with the DBus stuff. The QT dependency is limited to one package, not the entire QT install. Dependencies are: connman qt5-base. I do have some screenshots at this link:

1.  >Some tray mouse click handlers not processed and tray menu ...
    >
    >https://github.com/electron/electron/issues/21576
    >
    >Hm, I believe this may actually be a GNOME issue. Looking at the output of dbus-monitor shows that only a double-click on the tray icon (which also briefly shows the menu) will send a org.kde.StatusNotifierItem.Activate method call to the application. Single clicks only cause a query of the menu items via the com.canonical.dbusmenu interface.. To test this you can manually send the method call ...

1.  >Adding a Pidgin Trayicon to DWM | daniel's devel blog
    >
    >https://danielkaes.wordpress.com/2009/12/03/adding-a-pidgin-trayicon-to-dwm/
    >
    >What I always wanted to have is some kind of tray icon which informs me about new incoming messages. The cool thing about pidgin and the whole underlying purple library is their great support for dbus. So instead of ripping off code from awesome to get full freedesktop compliant tray icons I wrote a small python script to add an icon to my dwm ...

1.  >blueman: tray icon too small, and whithout icons with ...
    >
    >https://github.com/mate-desktop/mate-panel/issues/521
    >
    >na-tray name), but only items that can be displayed through SNI. Here you see 5 icons in tray, from left to right, dropbox, fusion-icon, kaffeine, volume applet, nm-applet. dropbox, fusion-icon and kaffeine are smaller with your merged PR and they are smaller than volume applet and nm-applet. The last 2 ones have the same size as before.

1.  >How to Customize the System Tray Icons in Windows 10
    >
    >https://lifehacker.com/how-to-customize-the-system-tray-icons-in-windows-10-1724097781
    >
    >In Windows 7 and 8, you could customize icons in the "system tray" to permanently show on the taskbar, or hide them away in the pop-up drawer. These options have moved in Windows 10.

Analysis:

- "Including results for system tray icon" so it includes results for Windows that are obviously irrelevant. I've taken the first seven results instead of the first five to compensate.

- Fourth result includes the KDE-specific dbus API "org.kde.StatusNotifierItem" that was later promoted to the standard FDO one. This is close. Even then, this is a GitHub issue for some software that uses tray icons, rather than a link to the KDE spec.

- Sixth result mentions the API by its abbreviation ("SNI"), though this is of course only obvious in hindsight. And this is still a GitHub issue for some software that uses tray icons.

### Google

1.  >WIP: dbus tray icons for Linux - Code Review - Qt-Project.org
    >
    >https://codereview.qt-project.org/c/qt/qtbase/+/98744
    >
    >Links. Reply. WIP: dbus tray icons for Linux Implementing org.kde.StatusNotifier DBus interface http://www.freedesktop.org/wiki/Specifications/StatusNotifierItem/ ...

1.  >System Tray Protocol Specification
    >
    >https://specifications.freedesktop.org/systemtray-spec/systemtray-spec-latest.html
    >
    >Note that this probably is not the same window that's used to contain the system tray icons. Tray icon. The tray icon is a window ...

1.  >How to design a status icon library in 2019 | TingPing's blog
    >
    >https://blog.tingping.se/2019/09/07/how-to-design-a-modern-status-icon.html
    >
    >If you want to set a tray you can't use X11 because not everybody uses X11. So you need a different solution and on Linux that is a DBus ...

1.  >Make Tray icons more robust on Linux · Issue #748 · getferdi/ferdi ...
    >
    >https://github.com/getferdi/ferdi/pull/748/files
    >
    >Initialize System Tray. const trayIcon = new Tray();. // Initialize DBus interface. const dbus = new DBus(trayIcon);. // Initialize ipcApi. ipcApi({. mainWindow,.

1.  >Tray icons for flatpak apps - Learn - NixOS Discourse
    >
    >https://discourse.nixos.org/t/tray-icons-for-flatpak-apps/1894
    >
    >5 Starting updater. (discord:4): GConf-WARNING **: 14:19:39.820: Client failed to connect to the D-BUS daemon: Using X11 for dbus ...

1.  >D-Bus-based protocol notification area API • KDE Community ...
    >
    >https://forum.kde.org/viewtopic.php?f=43&t=90392
    >
    >Here we can see a "new, D-Bus-based protocol that replaces the old ... Which software I should start to get access to tray icons from my Qt ...

1.  >419673 - Add StatusNotifier DBus implementation and remove ...
    >
    >https://bugs.chromium.org/p/chromium/issues/detail?id=419673
    >
    >Btw, the systray icon following the SNI spec has three states - "Active", "Passive" and "NeedsAttention". The Chrome icon after the notification ...

Analysis:

- First result's text mentions the KDE-specific dbus API, but also contains a link to the FDO spec which is the correct answer.

- Second result is a FDO spec but it's for the old XEmbed API, not the new dbus one.

- Third result is a blog. It mentions the KDE-specific API by name, but would require reading the blog to find it, and doesn't directly have a link to the spec.

- Other results are for software that uses tray icons.

**Winner: Google**

</section>


<section>
## `zig release-safe`

Goal: Discovered a random repository on GitHub written in zig that told the user to build it with `zig build -Drelease-safe=true ...`. Wanted to find out if this is a specific compilation flag for zig (and if so, what does it mean), or whether this is some custom define only for that repository's build.

Correct answer: This is a standard zig compilation flag, as documented at https://ziglang.org/documentation/master/#ReleaseSafe

### DDG

1.  >0.2.0 Release Notes · The Zig Programming Language
    >
    >https://ziglang.org/download/0.2.0/release-notes.html
    >
    >Zig --release-fast 485 Mb/s Zig --release-safe 377 Mb/s Zig 11 Mb/s -- Blake2b. Zig --release-fast 616 Mb/s Zig --release-safe 573 Mb/s Zig 18 Mb/s Sha3 Hashing Functions. Marc writes: Initially we had a comptime bug which did not allow us to unroll the inner Sha3 functions. Once this was fixed we saw a large, near 3x speed boost.

1.  >in release-safe mode, in functions that return an error ...
    >
    >https://github.com/ziglang/zig/issues/426
    >
    >Then you'll have some release-safe parts of your code even in release-fast mode. In release-safe mode, we do optimization but we turn on debug safety checks to prevent undefined behavior, such as integer overflow checking. ... Because Zig is so adamant about edge cases - for example insisting that memory allocation can fail - it is very common ...

1.  >0.6.0 Release Notes · The Zig Programming Language
    >
    >https://ziglang.org/download/0.6.0/release-notes.html
    >
    >Note that the presence of -O2,-O3 will cause zig to select release-fast, -Os will cause zig to select release-small, and optimization flags plus -fsanitize=undefined will cause zig to select release-safe.

1.  >make Debug and ReleaseSafe modes fully safe · Issue #2301 ...
    >
    >https://github.com/ziglang/zig/issues/2301
    >
    >It would be possible to say something like, "Debug and ReleaseSafe builds of Zig code are safe (in that they crash rather than have undefined behavior), except for inline assembly and extern function ABI mismatch", or some short list of exceptions. If the cost of these protections is high, that's what we have @setRuntimeSafety for (see #978).

1.  >Seg-fault with --release-safe --library c -target wasm32 ...
    >
    >https://github.com/ziglang/zig/issues/2831
    >
    >Even simple programs fail: export fn foo() u32 { return 2; } $ zig build-lib test.zig --library c -target wasm32-freestanding $ zig build-lib test.zig --library c --release-fast -target wasm32-freestanding $ zig build-lib test.zig --libr...

Analysis: While all results are relevant to Zig (release notes for two arbitrary versions and GitHub issues), and reference the flag in a way that indicates it is a standard compilation flag, none of them are for the documentation of the flag itself.

### Google

1.  >Documentation - The Zig Programming Language
    >
    >https://ziglang.org/documentation/master/
    >
    >Debug; ReleaseFast; ReleaseSafe; ReleaseSmall ... zig test test.zig 1/1 test "pointer alignment safety"... incorrect alignment /deps/zig/docgen_tmp/test.zig:10:63: ...

1.  >The Zig Programming Language
    >
    >https://ziglang.org/
    >
    >Zig has four build modes, and they can all be mixed ... Parameter, Debug · ReleaseSafe · ReleaseFast ...

1.  >Questions about Zig's memory safety, runtime performance ...
    >
    >https://www.reddit.com/r/Zig/comments/d9e2s2/questions_about_zigs_memory_safety_runtime/
    >
    >So Zig only has safety guarantees if I compile with --release-safe . Is that correct? If so, how does that even work? Is it like Rust's borrowing system? Is it a golang ...

1.  >make Debug and ReleaseSafe modes fully safe · Issue #2301 ...
    >
    >https://github.com/ziglang/zig/issues/2301
    >
    >It's always going to be possible to do unsafe things in Zig, because we have inline assembly, @intToPtr, and ability to call extern functions with ...

1.  >Introduction to the Zig Programming Language - Andrew Kelley
    >
    >https://github.com/ziglang/zig/issues/2301
    >
    >Zig has the concept of a debug build vs a release build. Here is a ... Release Safe; Release Small.

Analysis: First result is the correct one, though its excerpts are not the best - the first excerpt is for the table of contents and does identify the flag, and the other two exceerpts are irrelevant. The second result also has a better first excerpt; in fact this text is also present in the first link so it should've been used for the first result too.

**Winner: Google**

</section>


<section>
## `Bouncing PON`

Goal: Found this term in a forum thread regarding trouble with fiber internet, and wanted to know what it means.

Correct answer: No best one, but https://en.wikipedia.org/wiki/Passive_optical_network is quite good since what it means for a PON to "bounce" can be inferred.

### DDG

1.  >(pornography)

1.  >(pornography)

1.  >Bouncing Balls | Novel Games
    >
    >https://www.novelgames.com/en/bouncing/
    >
    >In the arcade classic of Bouncing Balls, your goal is to form groups of 3 or more balls of the same color so that they can be destroyed. When the game starts, multiple rows of color balls will slowly move downward from the top. A color ball is placed inside the launcher at the bottom of the play area, while the next ball will also be displayed.

1.  >(pornography)

1.  >(pornography)

Analysis:

- "Including results for bouncing porn", with expected consequences. The third result appears to be from dropping "PON" and just considering "bouncing".

- If searching for just "PON", then the correct answer is the second result, and the rest of the results are other things named that or with that abbreviation, though thankfully not pornography.

- If searching for "Bouncing PON fiber", the first and third results appear to be from dropping both "PON" and "fiber" and just considering "bouncing". The other three are related to the right PON, though none of them is the Wikipedia page.

### Google

1.  >GP4 pack PON / LOS Alarm Errors - ONT bouncing - Login
    >
    >https://calix.force.com/CalixCommunity/s/article/GP4-pack-PON--LOS-Alarm-Errors--ONT-bouncing-1
    >
    >Symptoms:GP4 pack PON / LOS Alarm Errors - ONT bouncing. LOS was observed on all 4 PONS supporting ONTs. PON port reset not effective ...

1.  >Passive optical network - Wikipedia
    >
    >https://en.wikipedia.org/wiki/Passive_optical_network
    >
    >A passive optical network (PON) is a fiber-optic telecommunications technology for delivering broadband network access to end-customers. Its architecture ...

1.  >AlBeezy Bounce Pon Cocky (Official Audio) - YouTube
    >
    >https://www.youtube.com/watch?v=TyfwRUxdyTU
    >
    >AlBeezy Bounce Pon Cocky Free Download -- https://bit.ly/2DoFLGL Subscribe: http://bit.ly/2BnymGX Pre - Save Kingdom Now ...

1.  >Bounce Pon Cocky [Explicit] by Albeezy on Amazon Music ...
    >
    >https://www.amazon.com/Bounce-Pon-Cocky-Explicit-Albeezy/dp/B07R4TC115
    >
    >Check out Bounce Pon Cocky [Explicit] by Albeezy on Amazon Music. Stream ad-free or purchase CD's and MP3s now on Amazon.com.

1.  >Bounce Pon Di Dick Challenge by Chukuloo 4star on ...
    >
    >https://soundcloud.com/p-chukuloo-twiss/bounce-pon-di-dick-challenge
    >
    >Bounce Pon Di Dick Challenge. 0.00 | 1:06. Previous track Play or pause track Next track. Enjoy the full SoundCloud experience with our free app. Get it on ...

Analysis: First two results are relevant. The rest are for songs with similar names, which are expected results.

**Winner: Google**

(Reminder: I have "safe search" off for both engines.)

</section>


<section>
## `legal term proof of evidence possession`

Goal: Find the legal term for the proof that must be provided for a piece of evidence that possessed after a crime, in order for the evidence to be to be admissible in court.

Correct answer: "Chain of custody"

### DDG

1.  >Proof legal definition of Proof
    >
    >https://legal-dictionary.thefreedictionary.com/proof
    >
    >It is distinguishable from evidence in that proof is a broad term comprehending everything that may be adduced at a trial, whereas evidence is a narrow term describing certain types of proof that can be admitted at trial. The phrase burden of proof includes two distinct concepts, the Burden of Persuasion and the Burden of Going Forward.

1.  >Criminal Discovery: The Right to Evidence Disclosure ...
    >
    >https://www.lawyers.com/legal-info/criminal/criminal-law-basics/criminal-law-right-to-evidence-disclosure.html
    >
    >Exculpatory Evidence The Constitution does, however, require that the prosecution disclose to the defense exculpatory evidence within its possession or control. "Exculpatory" generally means evidence that tends to contradict the defendant's supposed guilt or that supports lesser punishment.

1.  >Possession (law) - Wikipedia
    >
    >https://en.wikipedia.org/wiki/Possession_(law)
    >
    >In civil law countries, possession is not a right but a (legal) fact which enjoys certain protection by the law. It can provide evidence of ownership but it does not in itself satisfy the burden of proof. For example, ownership of a house is never proven by mere possession of a house.

1.  >Evidence - Browse Legal Terms - Legal Dictionary
    >
    >https://legaldictionary.net/evidence/
    >
    >In the legal system, evidence is any type of proof presented at trial, for the purpose of convincing the judge and/or jury that alleged facts of the case are true. This may include anything from witness testimony to documents, and objects, to photographs.

1.  >EVIDENCE - Admissibility - Prejudicial evidence - Methods ...
    >
    >https://www.thelawyersdaily.ca/articles/23234/evidence-admissibility-prejudicial-evidence-methods-of-proof
    >
    >The anecdotal testimony of a police officer regarding the likelihood of possession of the steroids for personal use exceeded the proper bounds of opinion evidence and culminated in a subtle reversal of the burden of proof on the steroids charge.

Analysis: All results are irrelevant.

### Google

1.  >The Legal Concept of Evidence (Stanford Encyclopedia of ...
    >
    >https://plato.stanford.edu/entries/evidence-legal/
    >
    >It may seem obvious that there must be a legal concept of evidence that is ... approach to evidence and proof that are distinctive to law (Rescher and ... that judges are already in possession of the (commonsense) resources to ...

1.  >Burden of proof (law) - Wikipedia
    >
    >https://en.wikipedia.org/wiki/Burden_of_proof_(law)
    >
    >Burden of proof is a legal duty that encompasses two connected but separate ideas that apply ... Thus the concept of burden of proof works differently in different countries: ie ... The "some credible evidence" standard is used as a legal placeholder to ... Possession of the keys is usually sufficient to prove control, even if the ...

1.  >Proof, Burden of Proof, and Presumptions. - Legal Information ...
    >
    >https://www.law.cornell.edu/constitution-conan/amendment-14/section-1/proof-burden-of-proof-and-presumptions
    >
    >In Clark, the Court weighed competing interests to hold that such evidence ... In that case, the Court struck down a presumption that a person possessing an ... as a whole, jury instructions that define “reasonable doubt” as requiring a “moral ...

1.  >"Chain of Custody" for Evidence | Nolo
    >
    >https://www.nolo.com/legal-encyclopedia/what-chain-custody.html
    >
    >Proving that an exhibit being offered into evidence is exactly what it purports to be—the actual drugs found on the defendant or the very calculator stolen from the store—requires proof of who had possession of the exhibit at all times between the time officers seized it and the trial.

1.  >Legal Definitions – Federal Bar Association
    >
    >https://www.fedbar.org/in-the-media/legal-definitions/
    >
    >Adverse possession – Acquiring title to land by possessing the land for a certain ... The term also refers to the allocation of percentages of negligence between ... Preponderance of the Evidence – The burden of proof in a civil case whereby a ...

Analysis: The fourth result has the answer.

**Winner: Google**

</section>
