# mauborgne
Mauborgne 2FA OTP Generator

![Screenshot](https://raw.githubusercontent.com/jhaygood86/mauborgne/main/data/screenshot.png)

### Building and Installation

You'll need the following dependencies:

* gobject-2.0 >= 2.66
* gtk4
* libadwaita-1 >= 1.5
* libportal-gtk4
* cotp
* libsecret-1
* gee-0.8
* json-glib-1.0
* libgcrypt

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

### Translations

Translations use Weblate. Contribute at https://hosted.weblate.org/projects/maurbogne/

### Special Thanks

Mauborgne utilizes the following open source software that we would like to thank!

 * **[libcotp](https://github.com/paolostivanin/libcotp)** We utilize libcotp for generating the OTP tokens
 * **[GNOME](https://www.gnome.org)** We are built on the GNOME platform (GTK 4 and libadwaita)
 * **[flatpak](https://www.flatpak.org)** The future of app distribution. We also utilize their libportal to make taking screenshots easier
 * **[gnome](https://www.gnome.org)** GNOME provides core parts of the platform we depend on, including GLib, GTK 4 and libadwaita


