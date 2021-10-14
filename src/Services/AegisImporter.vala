public class AegisImporter {

    public static AegisVaultContent? import_from_json_file (string filename, Gtk.Window parent_window) {
        Json.Parser parser = new Json.Parser ();
        parser.load_from_file(filename);

        var node = parser.get_root ();

        AegisVault encrypted_vault = Json.gobject_deserialize (typeof(AegisVault), node) as AegisVault;

        // check if encrypted
        if (encrypted_vault.header.params.nonce == null && encrypted_vault.header.params.tag == null) {
            var data = Base64.decode(encrypted_vault.db);

            parser.load_from_data((string)data);
            node = parser.get_root ();

            return Json.gobject_deserialize(typeof(AegisVaultContent), node) as AegisVaultContent?;
        } else {
            var password_dialog = new PasswordDialog (parent_window);

            while (true) {
                var response = password_dialog.run ();

                if (response == Gtk.ResponseType.ACCEPT) {
                    var master_key = decrypt_master_key (encrypted_vault, password_dialog.password);

                    if (master_key == null) {
                        password_dialog.show_error(_("Unable to lock vault. Please try a different password"));
                    } else {
                        password_dialog.destroy ();

                        var data = (string)decrypt_data (encrypted_vault, master_key);

                        parser.load_from_data(data);
                        node = parser.get_root ();

                        var content = Json.gobject_deserialize(typeof(AegisVaultContent), node) as AegisVaultContent?;

                        return content;
                    }


                } else {
                    password_dialog.destroy ();
                    return null;
                }
            }
        }


        return null;
    }

    private static uint8[]? derive_key (AegisVault.AegisPasswordSlot password_slot, string passphrase_value) {

        var buffer = new uint8[32];

        var passphrase = (uint8[])passphrase_value.to_utf8();
        var salt = hex_to_bytes(password_slot.salt);

        var error = GCrypt.KeyDerivation.derive(passphrase, GCrypt.KeyDerivation.Algorithm.SCRYPT, password_slot.n, salt, password_slot.p, buffer);

        if (error != 0) {
            print(error.to_string());
            return null;
        }

        return buffer;
    }

    private static uchar[]? decrypt_data (AegisVault vault, uchar[] master_key) {
        GCrypt.Cipher.Cipher aes;
        GCrypt.Cipher.Cipher.open(out aes, GCrypt.Cipher.Algorithm.AES256, GCrypt.Cipher.Mode.GCM, 0);

        var nonce = hex_to_bytes(vault.header.params.nonce);

        var error = aes.set_key (master_key);

        if (error != 0) {
            print(error.to_string());
        }

        error = aes.set_iv (nonce);

        if (error != 0) {
            print(error.to_string());
            return null;
        }

        var db_contents = Base64.decode (vault.db);

        var data_tag = hex_to_bytes(vault.header.params.tag);

        uchar[] buffer = new uchar[db_contents.length];

        error = aes.decrypt (buffer, db_contents);

        if (error != 0) {
            print(error.to_string());
            return null;
        }

        error = aes.checktag(data_tag);

        if (error != 0) {
            print(error.to_string());
            return null;
        }

        return buffer;
    }

    private static uchar[]? decrypt_master_key (AegisVault vault, string passphrase) {
        var password_slot = get_password_slot (vault);
        var derived_key = derive_key (password_slot, passphrase);

        var nonce = hex_to_bytes (password_slot.key_params.nonce);
        var data_key = hex_to_bytes(password_slot.key);
        var data_tag = hex_to_bytes(password_slot.key_params.tag);

        GCrypt.Cipher.Cipher aes;
        GCrypt.Cipher.Cipher.open(out aes, GCrypt.Cipher.Algorithm.AES256, GCrypt.Cipher.Mode.GCM, 0);

        aes.set_key (derived_key);
        aes.set_iv (nonce);

        uchar[] buffer = new uchar[data_key.length];

        var error = aes.decrypt (buffer, data_key);

        if (error != 0) {
            print(error.to_string());
            return null;
        }

        error = aes.checktag(data_tag);

        if (error != 0) {
            print(error.to_string());
            return null;
        }

        return buffer;
    }

    private static AegisVault.AegisPasswordSlot? get_password_slot (AegisVault vault) {

        var slots = vault.header.slots;

        for (int i = 0; i < slots.size; i++) {

            var slot = slots[i];

            if (slot is AegisVault.AegisPasswordSlot) {
                return (AegisVault.AegisPasswordSlot)slot;
            }
        }

        return null;
    }

    private static uint8[]? hex_to_bytes(string hexstring) {

        if(hexstring == null)
           return null;

        var slength = hexstring.length;

        if((slength % 2) != 0) // must be even
           return null;

        var dlength = slength / 2;

        var data = new uint8[dlength];

        var index = 0;

        while (index < slength) {
            char c = hexstring[index];
            uint8 value = 0;
            if(c >= '0' && c <= '9')
              value = (c - '0');
            else if (c >= 'A' && c <= 'F')
              value = (10 + (c - 'A'));
            else if (c >= 'a' && c <= 'f')
              value = (10 + (c - 'a'));
            else {
              return null;
            }

            data[(index/2)] += value << (((index + 1) % 2) * 4);

            index++;
        }

        return data;
    }
}
