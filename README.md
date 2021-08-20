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





