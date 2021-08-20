# mauborgne
Mauborgne 2FA OTP Generator

![Screenshot](https://raw.githubusercontent.com/jhaygood86/mauborgne/main/data/screenshot.png)

### Building and Installation

You'll need the following dependencies:

* gobject-2.0 >= 2.66
* gtk+-3.0
* libhandy-1 >=0.90.0
* granite >= 6.0.0
* libportal
* cotp

Run `meson build` to configure the build environment. Change to the build directory and run `ninja` to build

```bash
meson build --prefix=/usr
cd build
ninja
```

To install, use `ninja install`, then execute with `io.github.jhaygood86.mauborgne`

You can also build and run with flatpak, which already has all of its dependencies defined as well

```bash
flatpak-builder build  io.github.jhaygood86.mauborgne.yml --user --install --force-clean
flatpak run io.github.jhaygood86.mauborgne
```

### Special Thanks

Mauborgne utilizes the following open source software that we would like to think:http

 * **[libcotp](https://github.com/paolostivanin/libcotp)** We utilize libcotp for generating the OTP tokens
 * **[quirc](https://github.com/dlbeer/quirc/)** We utilize quirc for parsing QR Codes
 * **[elementary](https://www.elementary.io)** We are built on top of the elementary OS platform
 * **[flatpak](https://www.flatpak.org)** The future of app distribution. We also utilize their libportal to make taking screenshots easier
 * **[gnome](https://www.gnome.org)** GNOME provides core parts of the platform we depend on, including GLib and GTK+


