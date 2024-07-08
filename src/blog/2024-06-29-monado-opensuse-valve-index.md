---
title: '2024-06-29 Using Monado OpenXR runtime on OpenSUSE with the Valve Index'
date: '2024-06-29T00:00:00Z'
---

A couple of months ago, I decided to try out this whole VR thing, and maybe get some cardio in by playing Beat Saber. I purchased the Valve Index VR headset and the SteamVR 2.0 Base Stations. It required some fiddling to get it to work on the OS I use, OpenSUSE Tumbleweed, but eventually I got it to work. That was with Steam's built-in VR runtime SteamVR, so I then started looking into using the open-source Monado OpenXR Runtime instead. This post is a record of all the issues I ran into and the current state of things. If you are an OpenSUSE Tumbleweed user looking to play Steam games on a Valve Index, the information in this post may help you get started faster.


<section>
# SteamVR in a sandbox?

I don't like running closed-source software unsandboxed because it can't be trusted. Steam is especially problematic because a) it has a history of [deleting a person's home directory due to a bug,](https://github.com/ValveSoftware/steam-for-linux/issues/3671) b) games are an easy way for malicious software to be distributed (gamers are often willing to click "Allow" as many times as necessary if it lets them play their game), and c) it ends up polluting my OS install with a bunch of 32-bit library dependencies that nothing else needs.

So for the longest time I did not use OpenSUSE's `steam` package. Instead I run a podman container of a "non-oss" base image (Debian 12 + Debian's `steam` package + a bunch of other libraries for audio etc) with its `/home/arnavion` mounted from a separate `~/non-oss-root/steam` directory on the host, and some other host files mounted at the appropriate places. <sup><a name="ref1-back" href="#ref1">[1]</a></sup> I also use this container to run Discord (the web version doesn't support calls in Firefox) and used to use it for MS Teams back when it still had an Electron version.

However I could not get SteamVR to work in this container, because it did not seem to detect the headset despite all my attempts to mount the headset's USB dev nodes into the container. SteamVR has very baroque errors which just show a number and no details, which frustrate users even on "normal" setups. Even in a normal setup there are parts of SteamVR that are broken, eg it tries to launch a webview that flashes a white window and then immediately [segfaults.](https://github.com/ValveSoftware/SteamVR-for-Linux/issues/645) Since it's closed-source, I couldn't just look at its code to see what the problem was, and SteamVR is complicated enough that it made `strace` debugging too noisy to be useful.

An alternative "standard" for such sandboxing is Flatpak, and Steam does have one, however it was also unable to detect the headset.

Ultimately I had to relent and install Steam on my host OS via my distro's Steam package. At least I was able to get Beat Saber working fine. This did however strengthen my resolve to replace as much of the closed-source software with open-source alternatives as I could, hence why I discovered Monado and started trying to make it work.

</section>


<section>
## Monado

OpenGL is a standard that applications can invoke to draw triangles, and the implementation is provided by something specific to the environment, like the graphics driver on Windows or the Mesa library on Linux (which then has graphics-driver-specific backends). In the same way, OpenXR is a standard that applications can use to detect where the player's headset and controllers are and draw the appropriate binocular 3D triangles, and SteamVR is an OpenXR runtime that does so using the headset's DRM device and position tracking capabilities. [Monado](https://gitlab.freedesktop.org/monado/monado) is another OpenXR runtime that is open-source.

OpenSUSE did have a package for Monado, though it was only in [the `hardware:xr` OBS repository](https://build.opensuse.org/package/show/hardware:xr/monado) and not in the Factory OSS repo. In any case, this package had not been compiling succesfully for almost a year and nobody had cared to figure out why and fix it. The version of Monado itself was 3 years old ([v21.0.0 from 2021-01-28](https://gitlab.freedesktop.org/monado/monado/-/releases/v21.0.0)) and upstream had had numerous fixes since then but not yet cut a release. I made my own OBS package of the git tip-of-tree with an updated RPM specfile to compile it. I wouldn't have been able to contribute this back to the `hardware:xr` repository in this state, but fortunately Monado did end up releasing [v24.0.0 on 2024-06-07](https://gitlab.freedesktop.org/monado/monado/-/releases/v24.0.0) and I [upstreamed that](https://build.opensuse.org/request/show/1182011) to the `hardware:xr` repository. If you are an OpenSUSE user who wants to use Monado, this repository's package should work for you. (But if you want to use it for playing Steam games, keep reading.)

Before I tried this with Steam games, I figured I would test it first with a simple host application. Just like OpenGL has `glgears`, an application that just shows a window with three spinning gears rendered via OpenGL, Monado has its own [`xrgears`](https://gitlab.freedesktop.org/monado/demos/xrgears) that shows a 3D skybox, the same three spinning gears, and a bunch of floating pictures. OpenSUSE does not have this packaged anywhere so I've packaged it in [my own OBS repository](https://build.opensuse.org/package/show/home:Arnavion/xrgears) for now. Upstream hasn't had a new release in three years, and it seems to have had fixes since then that are necessary, so I'll wait to sr it to `hardware:xr` until upstream makes a new release.

<section>
### Direct mode

There is a nuance to how Monado uses the headset, which depends on how the compositor exposes it. One way is that the compositor exposes the headset as another monitor-like output, with its own position and resolution like a monitor would, except that its width is twice of what one eye can see because it expects the images for both eyes to be rendered side-by-side. Another way is that the compositor detects it as a "non-monitor" output and exposes it as such. The latter is preferrable and is what Monado calls "direct mode". This depends on the kernel identifying the VR headset device as a non-monitor via a list of hard-coded EDIDs, and then exposing this information to userspace. X11 or Wayland compositors can then make use of this information to expose the headset to clients like Monado accordingly.

I use the Sway Wayland compositor, which does support the `drm-lease-v1` Wayland protocol that makes it possible for clients like Monado to bind the output in direct mode, so that part should've worked fine. However running Monado would keep rendering a gray window on my regular monitors and nothing on my headset. Initially I didn't even know this was a problem; I figured the window on my monitors was supposed to be a preview of what it was also rendering to the headset, so it was just the headset rendering that was broken. However through a bunch of debugging of `monado-service` in gdb, I eventually figured out that this was actually a consequence of Monado not having the Wayland direct backend compiled-in at all so it was falling back to the non-direct Wayland backend, which expects you to move that gray window to the headset "monitor" yourself. This was because Monado's build automatically disabled the Wayland direct backend if the required build-time dependencies for it were not present, and I had not noticed the build output that indicated this backend was disabled (because I didn't know to look for it). This was also compounded by the fact that the documentation of direct mode for Wayland on Monado's website was outdated at the time and implied that the Wayland compositor side of the feature was still waiting on the protocol to be developed. I updated the Monado package build to install the Wayland direct backend's dependencies and enforce that the build fails if the dependencies change in the future and cause the backend to become disabled again. (This was before I submitted the v24.0.0 package to `hardware:xr`, so the `hardware:xr` package already has the fix.) I also submitted [an MR](https://gitlab.freedesktop.org/monado/webpage/-/merge_requests/49) to fix [the Monado doc](https://monado.freedesktop.org/direct-mode.html#wayland) so that is also up-to-date now.

</section>

Since I have SteamVR base stations, the appropriate Monado backend for base stations (aka lighthouses) is the `libsurvive` backend. I followed [this documentation](https://monado.freedesktop.org/valve-index-setup.html) for setting it up. There is also more general detail related to Monado binaries that is useful for troubleshooting, and just understanding how it all fits together, [here.](https://monado.freedesktop.org/getting-started.html)

The setup doc talks about two ways to configure libsurvive for tracking the base stations - either doing it from scratch or importing it from SteamVR's Room Setup. I tried both of these approaches but the tracking seemed to be very bad. Holding the headset still would frequently send the rendered view tumbling at a high speed, and even if it didn't do that it would frequently twitch in a random direction by many degrees, lag behind any movement of the headset, and various other problems. I found discussions with other people complaining about it too.

Fortunately Monado v24 has [a new driver](https://old.reddit.com/r/virtualreality_linux/comments/14cmh2c/) for tracking the SteamVR base stations that actually just uses the SteamVR driver itself, which has much better tracking. The Monado build does not enable this driver by default unless the build environment has a `~/.steam` directory, which would obviously not be the case for a distro package builder, so I had to configure the build to explicitly enable the driver. This build change is also in the `hardware:xr` repository's `monado` package now. Note that the `LH_DRIVER=steamvr` env var mentioned in the Reddit post is outdated and will not work with Monado v24; the correct env var is `STEAMVR_LH_ENABLE=true`.

Since libsurvive is not being used any more, its env vars can be removed. Furthermore, `XRT_COMPOSITOR_SCALE_PERCENTAGE` already defaults to `140` so it does not need to be set, so the final set of env vars for `monado-service` is:

```
STEAMVR_LH_ENABLE=true
XRT_COMPOSITOR_COMPUTE=1
```

(`XRT_COMPOSITOR_COMPUTE=1` will also become unnecessary once [it becomes the default.](https://gitlab.freedesktop.org/monado/monado/-/issues/342))

The setup doc doesn't say it, but OpenSUSE users running Monado via its systemd user service can just add a dropin to set these automatically, ie by creating `~/.config/systemd/user/monado.service.d/override.conf` with the content:

```ini
[Service]
Environment=STEAMVR_LH_ENABLE=true
Environment=XRT_COMPOSITOR_COMPUTE=1
```

I now had `xrgears` working fine. The next step was to make it work with Steam games.

</section>

<section>
## Monado for Steam Linux-native games

(At the time I did the steps I describe in this section, I didn't realize there were additional considerations for Windows-native games running under Proton. So in retrospect, this section by itself is only sufficient for running Linux-native OpenXR Steam games, and I'm not sure if any of those actually exist. To get Windows-native games working, you'll need both this section and the next section.)

I talked at the start of this post how I've had to run Steam on my host instead of a sandbox. That said, Steam itself provides some sandboxing for the games themselves. Steam runs games using [Pressure Vessel,](https://gitlab.steamos.cloud/steamrt/steam-runtime-tools/-/tree/8a0c6b1456688ed9566434f3fc088f090b69d30e/pressure-vessel) which uses [Bubblewrap](https://github.com/containers/bubblewrap) to run the game in a mount namespace with a "Steam Runtime" base image. The latest Steam Runtime v3 "Sniper" base image for example is a Debian 11 base plus a bunch of audio/video libraries preinstalled. Of course Steam does this primarily to make it easier for games to target a single Linux distro's libraries rather than the large number of distros their players might use, not for security (for example it mounts the host's `/home` as-is; separate `/home` sandboxes for each game is [not planned right now](https://gitlab.steamos.cloud/steamrt/steam-runtime-tools/-/blob/8a0c6b1456688ed9566434f3fc088f090b69d30e/docs/pressure-vessel.md#protecting-home)). This means that, among other things, `/usr` for the game process is actually the Steam runtime container image's `/usr`, not the host's. The host's `/usr` is mounted at `/run/host/usr` instead.

Monado has a client-server architecture. The host runs an application `monado-service` that actually handles the hardware drivers, and listens on a Unix domain socket `monado_comp_ipc`. The OpenXR runtime library loaded by an OpenXR application is `libopenxr_monado.so` which then connects to `monado_comp_ipc` to talk to `monado-service`. Furthermore the way that OpenXR applications look up the runtime library they should load is by having the user configure a runtime to be the default, via a file `~/.config/openxr/1/active_runtime.json`. For using Monado, this file looks like this:

```json
{
	"file_format_version" : "1.0.0",
	"runtime" : {
		"library_path" : "../../../../../usr/lib64/libopenxr_monado.so",
		"name" : "Monado"
	}
}
```

Notice how the `library_path` is relative to the location of the `active_runtime.json`. Monado recommends doing this but doesn't say why; the reason is that this allows the library to be located even if the `/home` and `/usr` that contain the `active_runtime.json` and `libopenxr_monado.so` are mounted under some arbitrary path rather than under `/`.

You might think this is exactly the case with the Steam Runtime sandbox, but alas as I said, the host's `/usr` is mounted at `/run/host/usr` but the host's `/home` is still mounted at `/home`, so this relative link still does not resolve. One way to resolve this is to put the relative path to `/run/host/usr/lib64/libopenxr_monado.so` in the manifest, but that would then break clients running on the host. A better option is to tell Steam games to use a different manifest via the `XR_RUNTIME_JSON` env var. The easiest such manifest is `/usr/share/openxr/1/openxr_monado.json` since it's already part of the `monado` package and contains a path relative to itself, `"library_path" : "../../../lib64/libopenxr_monado.so"`. This means running games with `XR_RUNTIME_JSON=/run/host/usr/share/openxr/1/openxr_monado.json` so that the relative path resolves to `/run/host/usr/lib64/libopenxr_monado.so`, which is what we want.

Next, because the client library needs access to the `monado_comp_ipc` socket, another env var is needed to mount this inside the game's mount namespace. The socket is expected to be under `$XDG_RUNTIME_DIR`, so the additional env var is `PRESSURE_VESSEL_FILESYSTEMS_RW=$XDG_RUNTIME_DIR/monado_comp_ipc`

There is one last problem. We're asking the game to load `/run/host/usr/lib64/libopenxr_monado.so` which is a library compiled for OpenSUSE, but the game is running in a Debian 11 mount namespace (the base OS of the Steam Runtime v3 "Sniper") and is likely itself compiled for Debian 11. It's usually a bad idea to mix libraries from other distributions because distributions differ in compile flags (eg `rpath` in libraries), directory layouts (eg plugins in `/usr/lib` vs `/usr/lib64` vs `/usr/libexec`, config files in `/usr/share` vs `/usr/lib` vs `/etc`) and so on. There's also the matter of the dependencies of `libopenxr_monado.so` itself - they could exist in `/run/host/usr/lib64` but the loader that the game uses would only look in `/usr/lib/...`. We could set `LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/run/host/usr/lib64`, but that could cause other libraries from the host to be loaded instead of the container's. Indeed, this last problem is exactly what happens with the `monado` package from the `hardware:xr` repository - it is compiled to link dynamically to OpenSUSE's `libcjson.so` but this library is not present in the Steam Runtime container image, so the `libopenxr_monado.so` fails to load because of missing dependencies and the game ignores it.

Fortunately `libcjson.so` is the only dependency that's missing, and Monado knows about this problem and thus makes it possible to link to its own static copy of libcjson by setting the `-DXRT_HAVE_SYSTEM_CJSON=OFF` cmake flag at build time. Unfortunately the maintainer of the OpenSUSE `monado` package [was not happy](https://build.opensuse.org/request/show/1182939) with this approach, because this still assumes that a library compiled for OpenSUSE can be loaded by a process running in Debian 11. Indeed `libopenxr_monado.so` has many other dynamically linked library dependencies apart from libcjson, which only happen to not be a problem because they happen to be provided by the Steam Runtime container image in a compatible way. Ideally one would have a separate `monado-steam` package that contains its own `libopenxr_monado.so` independent from the `monado` package (and corresponding independent `openxr_monado.json` manifest) that is compiled in the Steam Runtime build environment.

Alas, the Steam Runtime build environment is itself a container image (`registry.gitlab.steamos.cloud/steamrt/sniper/sdk`), and I was not able to find a way for an OBS build to run a build in a container that would work inside the chroot that `osc build` uses. OBS *can* build Docker images, and OBS *can* build Debian 11 packages in a Debian 11 chroot, but the situation here is neither. We want to build an OpenSUSE RPM package where the build step is to run a docker / podman container with the source directory mounted inside, then back in the build chroot use the resulting `libopenxr_monado.so` in the final package.

The SteamVR lighthouse driver I mentioned earlier has the same problem in reverse. The situation with that is that the `monado-service` binary compiled for OpenSUSE is asked to load a SteamVR library (`~/.local/share/Steam/steamapps/common/SteamVR/drivers/lighthouse/bin/linux64/driver_lighthouse.so`) that is presumably compiled for the Steam Runtime. It happens to work, but it would be nice to avoid it, but the tracking with libsurvive is so bad that there isn't a good alternative.

Just to make more progress, I made the change to compile the OpenSUSE `monado` package itself with the `-DXRT_HAVE_SYSTEM_CJSON=OFF` cmake flag only in my OBS repository's package. Later it turned out to not be necessary (keep reading), so I've since removed this change again.

In any case, at this point Beat Saber was still unable to connect to Monado and insisted that it could not find an OpenXR runtime. I eventually discovered there was more work required for Windows-native games like Beat Saber.

</section>


<section>
## Monado for Steam Windows-native games

When SteamVR originally came out in 2015 for the HTC Vive headset, SteamVR came up with an API and called it OpenVR. It was expected to be used not just for Steam games but also applications like web browsers for showing 180°/360° video, for example. But Oculus came up with its own API for its hardware, and Windows came up with WMR, so there was no standardization. In 2017, the Khronos Group started working on OpenXR to create that standardization, and also handle both VR and AR hardware with the same runtime now that AR was becoming a thing.

So old games likely require an OpenVR runtime. Newer games might require OpenXR instead. In 2020, SteamVR implemented support for OpenXR applications in addition to OpenVR applications, so both kinds of games would work in SteamVR today. Monado however is only an OpenXR implementation. We just need an OpenVR compatibility layer that converts it to OpenXR, and the most popular open-source implementation for Linux is [OpenOVR](https://gitlab.com/znixian/OpenOVR) (née OpenComposite).

Beat Saber is actually an OpenXR application, so it would seem that having OpenOVR is not necessary. However because Beat Saber is a Windows game, it uses OpenXR through Proton, and Proton has a quirk that it uses OpenVR to "initialize OpenXR games" and fails if it can't find an OpenVR runtime. I'm not sure what it means for an OpenVR runtime to "initialize OpenXR games" in a way that they end up eventually using the OpenXR runtime anyway, but this is the wording used in [this GH issue comment.](https://github.com/ValveSoftware/Proton/issues/6038#issuecomment-1590246971)

OpenOVR however does not have any stable releases, so I'm not sure it can be packaged for OpenSUSE in a way that will be accepted by any of the official repos. In any case, the `vrclient.so` library produced by OpenOVR would have the same cross-distro linkage problem I wrote about for `libopenxr_monado.so` above, so it's best to nip that problem in the bud and just compile it in a Steam Runtime SDK container. Furthermore, OpenVR has its own manifest file that tells the application the path of the library, `~/.config/openvr/openvrpaths.vrpath`. In order for OpenVR to work on both the host (for any applications that need it) and with Steam games, it's best if the library path is under `/home` too so that it's the same path in both cases. This means that my setup is to build OpenOVR with this script:

```sh
#!/bin/bash

if ! [ -d ~/src/OpenOVR ]; then
	git clone --recursive gitlab.com:znixian/OpenOVR ~/src/OpenOVR
fi

podman container run \
	--rm \
	"--volume=$HOME/src/OpenOVR:/src" \
	registry.gitlab.steamos.cloud/steamrt/sniper/sdk \
	bash -c '
		set -euo pipefail

		apt update -y
		apt dist-upgrade -y --autoremove --purge


		rm -rf /src/build
		mkdir /src/build
		cd /src/build
		cmake -DCMAKE_BUILD_TYPE=Release ..
		make -j
	'
```

... such that I end up with `~/src/OpenOVR/build/linux64/bin/vrclient.so` compiled for the Steam Runtime, then create the `~/.config/openvr/openvrpaths.vrpath.openovr` manifest with this content:

```json
{
	"config" : [
		"/home/arnavion/.local/share/Steam/config"
	],
	"external_drivers" : null,
	"jsonid" : "vrpathreg",
	"log" : [
		"/home/arnavion/.local/share/Steam/logs"
	],
	"runtime" : [
		"/home/arnavion/src/OpenOVR/build"
	],
	"version" : 1
}
```

... and finally symlink `~/.config/openvr/openvrpaths.vrpath` to `openvrpaths.vrpath.openovr`. (This strategy of symlinking `openvrpaths.vrpath` to the actual config allows for easily switching the symlink back to the original SteamVR config if needed; it is also described in the Monado setup doc mentioned above.)

Note that OpenOVR uses some C++ features that the old gcc in the Steam Runtime SDK container does not support, so I had to apply this patch to remove those features first:

```patch
diff --git a/CMakeLists.txt b/CMakeLists.txt
index 164fa89..b872224 100644
--- a/CMakeLists.txt
+++ b/CMakeLists.txt
@@ -62,7 +62,7 @@ else ()
 	# There is also -Bsymbolic set when linking the final shared library, see the bottom of this file
 	# FIXME the Vulkan functions still get exported, hopefully they won't fight with the application's ones.
     add_definitions(-fvisibility=hidden)
-	add_compile_options(-Wall -Wextra -Wpedantic -pedantic-errors -Wno-unused-parameter -Wno-missing-field-initializers -Wno-format-security)
+	add_compile_options(-Wall -Wextra -Wpedantic -Wno-unused-parameter -Wno-missing-field-initializers -Wno-format-security)
 	set(ERROR_ON_WARNING_FLAG -Werror)
 endif ()
 if (ERROR_ON_WARNING)
diff --git a/OpenOVR/Misc/Input/InteractionProfile.h b/OpenOVR/Misc/Input/InteractionProfile.h
index 02fc121..d8f4e21 100644
--- a/OpenOVR/Misc/Input/InteractionProfile.h
+++ b/OpenOVR/Misc/Input/InteractionProfile.h
@@ -165,10 +165,9 @@ public:
 	std::optional<T> GetProperty(vr::ETrackedDeviceProperty property, ITrackedDevice::TrackedDeviceType hand)
 	    const
 	{
-		using enum ITrackedDevice::TrackedDeviceType;
-		if (hand != HAND_NONE && propertiesMap.contains(property)) {
+		if (hand != ITrackedDevice::TrackedDeviceType::HAND_NONE && propertiesMap.contains(property)) {
 			hand_values_type ret = propertiesMap.at(property);
-			return std::get<T>((hand == HAND_RIGHT && ret.right.has_value()) ? ret.right.value() : ret.left);
+			return std::get<T>((hand == ITrackedDevice::TrackedDeviceType::HAND_RIGHT && ret.right.has_value()) ? ret.right.value() : ret.left);
 		} else if (hmdPropertiesMap.contains(property)) {
 			return std::get<T>(hmdPropertiesMap.at(property));
 		}
```

With this, finally, I was able to get Beat Saber working with Monado without SteamVR running.

</section>


<section>
## Base Station Power Management

The next problem is making the lighthouses go to sleep when they're not being used. SteamVR on Windows supports base station power management by communicating with the base stations via Bluetooth. It doesn't require the PC itself to have Bluetooth because it uses a Bluetooth adapter inside the VR headset. For the longest time SteamVR on Linux did not support power management, so if you search for this you will find many pages of people saying it doesn't work on Linux. SteamVR on Linux did start supporting it since 2023, though apparently only for the v2.0 lighthouses. It's not enabled by default though, so you will need to start SteamVR, open its menu, go to Devices -> Base Station Settings, and turn on power management there. This will make it so that closing SteamVR makes the base stations go to sleep.

The problem though is that the Monado setup works without launching SteamVR, so I needed an independent way to wake up the base stations and put them back to sleep. Ideally this would use the VR headset's Bluetooth adapter in the same way that SteamVR uses it, but there does not seem to be any information about how SteamVR does it. So the alternative is to use the PC's own Bluetooth adapter. My PC doesn't have one, but it does have an M.2 slot for one, and I was thinking of getting one anyway because I currently use a wired controller and headset and have been thinking of getting Bluetooth ones. So I purchased one such adapter based on the Intel AX210 chip (AX211 was not an option because I use an AMD CPU) from a noname Chinese brand on Amazon.

(If you have an Android phone, I saw mentions of [an Android app](https://github.com/jeroen1602/lighthouse_pm) to do so using the phone's Bluetooth instead. I use [a Linux phone,](/blog/2021-08-07-smartphone-life/) and while it does have Bluetooth and I do run Waydroid on it, Waydroid can't make the phone's Bluetooth available to the inner LineageOS container, so it doesn't help.)

At first I was confused that I was unable to pair the base stations with my PC, but apparently this is by design and the SteamVR 2.0 base stations are not expected to be paired first. It is sufficient to just connect to them and send the power management commands that way. (This also seems to imply that anyone within range of your base stations can turn them on or off ?!)

So to send those commands, there were two options. One was [the `lh2ctrl` script](https://github.com/risa2000/lh2ctrl) and the other was the `monado-cli lighthouse <off|on>` command using `monado-cli` from Monado. Obviously it would be easier to use the latter because I already had it, so I tried that first. However it seemed to not do anything and the lighthouses would remain off or on as they were. Under the hood, `monado-cli` talks to BlueZ over D-Bus to connect to the lighthouses and send them commands, and I was able to see using `busctl --monitor` that `monado-cli` was telling BlueZ's `bluetoothd` to connect to the lighthouses, but then it was not sending any commands to tell them to power off / on.

Just to be sure, I tried the `lh2ctrl` script, and that worked fine. I checked its code to see what it was doing, but it uses the `bluepy` Python library, which under the hood launches a C binary that uses BlueZ server code to send the Bluetooth commands itself, rather than talk to the BlueZ daemon as a D-Bus client. It did however give me enough information of how the whole thing works. The PC connects to the lighthouse, then enumerates its "characteristics" looking for one with a particular UUID, then "writes a value" to that characteristic that indicates whether it should wake up or go to sleep. Armed with this information, I was able to replicate what the `monado-cli lighthouse` command *ought* to be doing by manipulating the BlueZ D-Bus objects in [`d-feet`](https://wiki.gnome.org/Apps/DFeet) by hand. That worked, so now I started debugging the `monado-cli` command code to see what it was doing differently.

It turned out that `monado-cli` was ignoring the characteristics for power management because it expected those characteristics to support notifications, but according to BlueZ those characteristics did not do so. So `monado-cli` did not find any characteristics to write to, and just silently exited without doing anything. I don't know if this fact that the characteristics don't support notifications was a problem with all base stations, or just all SteamVR 2.0 base stations, or just the base stations I have, or my distro's BlueZ library, or something else. In any case, the power management code did not seem to require that these characteristics supported notifications; the code to find the characteristics was just common code that was also used by other code that did require the characteristics to support notifications. I made [an MR](https://gitlab.freedesktop.org/monado/monado/-/merge_requests/2269) to Monado to fix this. I've also added that MR as a patch to the `hardware:xr` repository's `monado` package.

So now it's just a matter of wiring up the `monado.service` unit to run `monado-cli lighthouse on` when it starts and run `monado-cli lighthouse off` when it stops, via `ExecStartPre` and `ExecStopPost`, to get the same effect as SteamVR. I haven't done this yet because there seems to be one more problem - sometimes `monado-cli lighthouse on` successfully tells my lighthouses to turn on, and they flash their LED as they do when the start powering on, but then they seem to give up and remain in sleep. Running `monado-cli lighthouse on` a second time fixes it. This problem only happens about one in twenty times. I haven't experienced this problem with the `lh2ctrl` script, so there is possibly some more difference between it and `monado-cli` (see the MR comments for one such difference I identified), or it might just be some firmware bug with the lighthouses and a coincidence that I don't experience it with `lh2ctrl`. I'm still investigating this.

</section>


<section>
## VR Video

Apart from playing games, I was also interested in getting 180°/360° videos working.

Since OpenVR never got standardized, browsers that implemented OpenVR via WebVR either removed it or never started implementing it. There is a corresponding WebXR that uses OpenXR, and Firefox does apparently support it on Linux while Chromium apparently does not. I tried Firefox originally before I switched from SteamVR to Monado, and that didn't work because apparently Firefox only works with Monado. I haven't tried since I switched to Monado.

What did end up working is two desktop players.

The first is [vr-video-player](https://git.dec05eba.com/vr-video-player) that uses SteamVR directly and thus works without Monado. It can either capture any X11 window, or it can play any file that mpv can play (since it uses libmpv). It has a bunch of CLI flags that allow it to show not just 180°/360° projections but also stereoscopic projection (ie where the application / video renders the two viewpoints side-by-side) and monocular projection on a curved or flat surface. Picking the right flags for a particular video requires some trial and error because I don't always find it obvious by looking at the video on a monitor what projection it uses. vr-video-player does have keyboard shortcuts to change some aspects of the projection, which I can blindly operate while wearing the headset. But changing the projection itself requires stopping and restarting vr-video-player with different CLI flags, so I have to keep taking my headset off and on to do it.

The second is [sphvr](https://gitlab.com/lubosz/sphvr) that uses OpenXR and thus requires Monado. It shows images and videos through gstreamer. Once I got Monado working, I tested this with simple images and it works. I have not tested this with video yet.

sphvr requires gulkan v0.16 and gxr v0.16, while the packages in OpenSUSE repos are still v0.15. (gulkan is in `X11:Wayland` and Factory. gxr is in `hardware:xr`.) I have the two v0.16 packages [here](https://build.opensuse.org/package/show/home:Arnavion/gulkan) and [here](https://build.opensuse.org/package/show/home:Arnavion/gxr) in my OBS repository. I've sr'd the gulkan update to `X11:Wayland` [here](https://build.opensuse.org/request/show/1182015), and it needs to be accepted and propagate to Factory before I can send the gxr sr to `hardware:xr` because gxr v0.16 requires gulkan v0.16.

Neither vr-video-player nor sphr themselves have any stable releases, so I'm not sure they can be packaged for OpenSUSE in a way that will be accepted by any of the official repos. For now I've packaged them [here](https://build.opensuse.org/package/show/home:Arnavion/vr-video-player) and [here](https://build.opensuse.org/package/show/home:Arnavion/sphvr) in my OBS repository.

</section>


<section>
## Camera

The Valve Index headset has a binocular camera, and SteamVR on Windows is apparently able to pipe the feed through to the headset screen so that you can see out into the world while still wearing the headset. There is also apparently some computer vision integration to detect objects and show outlines and such instead of a full color video. None of this works with SteamVR on Linux.

However the camera does appear as a v4l2 device showing a stereoscopic (side-by-side) combination of the two lenses. It should thus be possible to pipe this to vr-video-player or sphvr to be able to see out of the headset while wearing it. I did not try sphvr, but with vr-video-player it worked although it showed a very cross-eyed image. [This GH issue comment](https://github.com/ValveSoftware/SteamVR-for-Linux/issues/231#issuecomment-2156754932) told me how to patch vr-video-player to change the left eye offset to fix it, and indeed it works. However, rather than patch it that way (which would make the Index camera work but break regular video), I adapted it into a new CLI flag to specify the left eye offset so that both offsets can be used without having to recompile to switch.

```sh
vr-video-player --flat --no-stretch --eye-left-offset -0.5 --video 'av://v4l2:/dev/video0' --mpv-profile low-latency
```

I've added this patch to my OBS package already. I'll submit it upstream later when I have time to clean up the patch for submission.

</section>


<section>
## SteamVR in a sandbox, revisited

Since SteamVR is no longer involved other than the lighthouse driver, I wondered if it might be possible to go back to running Steam in my "non-oss" container. The original hardship with exposing the headset's USB dev nodes should not be a problem because `monado-service` would still be running on the host, so it's only a matter of mounting the `monado_comp_ipc` socket into the container. To play it safe with ABI issues, I still wanted to build Monado and OpenOVR in a Steam Runtime container.

So I modified my non-oss container image build to have an initial build stage that runs an `registry.gitlab.steamos.cloud/steamrt/sniper/sdk` container to build Monado and OpenOVR. For Monado, since I only need to build the `libopenxr_monado.so` binary, the build only needs to do:

```sh
cmake \
	-DCMAKE_BUILD_TYPE=Release \
	-DBUILD_DOC:BOOL=OFF \
	..
make -j openxr_monado
```

And for OpenOVR, the same caveat as above applies, namely that the build script has to patch it to remove new C++ features that the Steam Runtime SDK's gcc does not support.

For Monado, the container build places `$monado_dir/build/src/xrt/targets/openxr/libopenxr_monado.so` at `/usr/share/monado-steam/libopenxr_monado.so` and generates `/usr/share/monado-steam/openxr_monado_steam.json` with the content:

```json
{
	"file_format_version" : "1.0.0",
	"runtime" : {
		"library_path" : "./libopenxr_monado.so",
		"name" : "Monado"
	}
}
```

For OpenOVR, the container build places `$openovr_dir/build/bin/linux64/vrclient.so` at `/usr/share/openovr-steam/bin/linux64/vrclient.so`, and generates `~/non-oss-root/steam/.config/openvr/openvrpaths.vrpath` with the content:

```json
{
	"config" : [
		"/home/arnavion/.steam/debian-installation/config"
	],
	"external_drivers" : null,
	"jsonid" : "vrpathreg",
	"log" : [
		"/home/arnavion/.steam/debian-installation/logs"
	],
	"runtime" : [
		"/run/host/usr/share/openovr-steam"
	],
	"version" : 1
}
```

Finally, the container build defines env vars:

```
ENV PRESSURE_VESSEL_FILESYSTEMS_RW "/run/user/$uid/monado_comp_ipc"
ENV XR_RUNTIME_JSON '/run/host/usr/share/monado-steam/openxr_monado_steam.json'
ENV IPC_IGNORE_VERSION 1
```

The first two are what I would normally need to configure each VR game with individually, but setting them on the whole container makes that unnecessary. The third is because `libopenxr_monado` has a check to make sure it's compatible with the `monado-service` on the other side of the IPC socket. Because we built the client and server on different OSes and build systems, those versions happen to not match, but we know they're the same version so this env var suppresses that check.

After all this, I was finally able to play Beat Saber inside my original sandboxed Steam. I'll still need the host Steam in case I need to re-run SteamVR Room Setup or update the leftover SteamVR install, but I can just install it then. Note that I do need the leftover SteamVR install to remain on the host, since that is where the SteamVR lighthouse driver loaded by `monado-service` lives.

</section>


<section>
## Future

Apart from the few pending patches / packages mentioned above, there are a few other things I want to try:

- Beat Saber running in Monado has very low haptic feedback on the Index controllers compared to Beat Saber running in SteamVR. I need to check if this is an issue with Monado or something else.

- Monado requires the controllers to be powered on before starting Monado because it is unable to "hotplug" them. They acknowledge that this is a nice-to-have feature and would appreciate someone implementing it.

- SteamVR also does power management for the controllers, specifically it turns them off when exiting SteamVR. Monado does not have a way to do this. It's not a big deal since I can just leave them plugged in to USB power, but I did forget a few times and had to skip the next day's VR session because the controllers had run out of battery. I assume this is also based on Bluetooth somehow, so I need to investigate it.

I will update this post as I do these things.


</section>


---


<aside>
<sup>[1] <a name="ref1" href="#ref1-back">back</a></sup>

The host's `pipewire-pulse` socket is mounted as-is. The host compositor's Wayland socket is mounted with a non-standard name, and the `WAYLAND_DISPLAY` env var is not defined except for games that are trustworthy (and support Wayland in the first place). The host compositor's X11 socket is mounted from a nested Xephyr instance. D-Bus is not mounted. The host's `/dev/dri` directory is mounted so that the container's Mesa can access the host's DRM devices.

As mentioned above, Flatpak is a more standard way of doing this, especially since it also has filtering proxies for D-Bus and Wayland that makes it safe to share them with the sandboxed application. (Sharing the Wayland socket also requires the compositor to support the security-context-v1 protocol for associating Flatpak'd applications with security contexts, and then a way to restrict such contexts from using privileged protocols.) If you don't care to sandbox anything except the X11 socket, then gamescope is also an option.
</aside>
