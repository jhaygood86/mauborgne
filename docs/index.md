## Mauborgne

Maurborgne is a 2FA OTP generator that can generate HOTP and TOTP codes in order to access various services, similar to other Authenticator apps. Your secrets are stored securely locally using libsecret, and the application does not connect to the network for any reason. The application is intentionally ran sandboxed to minimize access to outside resources so you can trust that your codes are not shared with anyone. Plus, the application is entirely open source under the GNU GPL 3 license.

### Features

- **Importing OTP pads using a built in screenshot capture of QR Codes**. This uses Flatpak Portals, so only the screenshots you explicitly allow the application to see are parsed. This is much easier than taking a photo using a camera on a smartphone
- **Exporting OTP pads by generating a QR Code**. If you wish to access the code on a different device or app, we can generate a new QR Code for you to import from
- **Import and Export using Aegis Encrypted JSON Vaults** We can securely import *and* export using the Aegis encrypted vault format. We support exporting both individual pads or ALL the pads you have locally. This is the preferred method for sharing pads between multiple devices since the file encrypts the data and requires a custom passphrase to import into another device. The Aegis app is available for Android. [Get Aegis](https://getaegis.app/) and is the preferred mobile authenticator companion to Mauborgne.
- **Secret Secrets** The pad secrets, required to generate a code, are stored securely in your operating system's wallet using libsecret and the Flatpak secrets portal

### Getting Mauborgne

Mauborgne is available for elementary OS with a suggested retail price of $10. Users of other Flatpak-compatible operating systems can install it from [Flathub](https://flathub.org/apps/details/io.github.jhaygood86.mauborgne). Please sponsor $10 if you enjoy the application

### Support or Contact

Having trouble with Maurborne? Please file an issue on [GitHub](https://github.com/jhaygood86/mauborgne/issues)
