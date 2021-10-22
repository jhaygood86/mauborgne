public errordomain AegisExportError {
    VAULT_ENCRYPTION_ERROR
}

public class AegisManager {

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

                        print("json %s\n", data);

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

    public static string? export_to_json_string(Gtk.Window parent_window, AegisVaultContent content) throws AegisExportError {
        var password_dialog = new CreatePasswordDialog (parent_window);

        var response = password_dialog.run ();

        if (response == Gtk.ResponseType.ACCEPT) {
            var vault = new AegisVault ();
            vault.version = 1;

            var key = new uchar[32];
            GCrypt.Random.nonce(key);

            var passphrase = password_dialog.password;

            var password_slot = create_password_slot ();
            var derived_key = derive_key(password_slot, passphrase);

            password_dialog.destroy ();

            print("creating json vault db contents\n");
            var content_json = get_json_string (content);
            print("%s\n",content_json);

            print ("encryypting master key using passphrase...\n");

            encrypt_master_key(password_slot, key, derived_key);

            vault.header = new AegisVault.AegisHeader ();
            vault.header.slots = new Gee.ArrayList<AegisVault.AegisRawSlot> ();

            vault.header.slots.add (password_slot);

            print ("encrypting data using master key...\n");

            encrypt_data (vault, key, content_json.data);

            return get_json_string (vault);
        } else {
            password_dialog.destroy ();
        }

        return null;
    }

    private static string get_json_string (Object object) {
        var encoded_content = Json.gobject_serialize(object);

        Json.Generator generator = new Json.Generator ();
        generator.set_root (encoded_content);

        return generator.to_data (null);
    }

    private static AegisVault.AegisPasswordSlot create_password_slot () {
        var salt = new uchar[32];
        GCrypt.Random.nonce(salt);

        var nonce = new uchar[12];
        GCrypt.Random.nonce(nonce);

        AegisVault.AegisPasswordSlot password_slot = new AegisVault.AegisPasswordSlot ();
        password_slot.uuid = Uuid.string_random();
        password_slot.n = 32768;
        password_slot.p = 1;
        password_slot.r = 8;
        password_slot.salt = bytes_to_hex (salt);
        password_slot.repaired = true;

        var key_params = new AegisVault.AegisEncryptionParams ();
        key_params.nonce = bytes_to_hex(nonce);

        password_slot.key_params = key_params;

        return password_slot;
    }

    private static uint8[]? derive_key (AegisVault.AegisPasswordSlot password_slot, string passphrase_value) {

        var buffer = new uint8[32];

        print("salt: %s\n", password_slot.salt);

        var passphrase = (uint8[])passphrase_value.to_utf8();
        var salt = hex_to_bytes(password_slot.salt);

        var error = GCrypt.KeyDerivation.derive(passphrase, GCrypt.KeyDerivation.Algorithm.SCRYPT, password_slot.n, salt, password_slot.p, buffer);

        if (error != 0) {
            critical("%s\n",error.to_string());
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
            critical("%s\n",error.to_string());
            return null;
        }

        error = aes.checktag(data_tag);

        if (error != 0) {
            critical("%s\n",error.to_string());
            return null;
        }

        return buffer;
    }

    private static void encrypt_data (AegisVault vault, uchar[] master_key, uchar[] data) throws AegisExportError {
        GCrypt.Cipher.Cipher aes;
        GCrypt.Cipher.Cipher.open(out aes, GCrypt.Cipher.Algorithm.AES256, GCrypt.Cipher.Mode.GCM, 0);

        uchar[] nonce = new uchar[12];
        GCrypt.Random.nonce(nonce);

        vault.header.params = new AegisVault.AegisEncryptionParams ();
        vault.header.params.nonce = bytes_to_hex(nonce);

        aes.set_key(master_key);
        aes.set_iv(nonce);

        print("data size: %d\n", data.length);

        uchar[] buffer = new uchar[data.length];

        var error = aes.encrypt (buffer, data);

        if (error != 0) {
            critical("encryption error: %s\n",error.to_string());
            throw new AegisExportError.VAULT_ENCRYPTION_ERROR(error.to_string());
        }

        var tag_buffer = new uchar[16];

        error = aes.gettag(tag_buffer);

        if (error != 0) {
            critical("get tag error: %s\n",error.to_string());
            throw new AegisExportError.VAULT_ENCRYPTION_ERROR(error.to_string());
        }

        var tag = bytes_to_hex(tag_buffer);

        vault.header.params.tag = tag;

        var encoded_db_contents = Base64.encode (buffer);

        vault.db = encoded_db_contents;
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
            critical(error.to_string());
            return null;
        }

        error = aes.checktag(data_tag);

        if (error != 0) {
            critical(error.to_string());
            return null;
        }

        return buffer;
    }

    private static void encrypt_master_key(AegisVault.AegisPasswordSlot password_slot, uchar[] master_key, uint8[] derived_key) throws AegisExportError {
        var nonce = hex_to_bytes (password_slot.key_params.nonce);

        GCrypt.Cipher.Cipher aes;
        GCrypt.Cipher.Cipher.open(out aes, GCrypt.Cipher.Algorithm.AES256, GCrypt.Cipher.Mode.GCM, 0);

        aes.set_key(derived_key);
        aes.set_iv (nonce);

        uchar[] buffer = new uchar[master_key.length];

        var error = aes.encrypt (buffer, master_key);

        if (error != 0) {
            critical(error.to_string());
            throw new AegisExportError.VAULT_ENCRYPTION_ERROR(error.to_string());
        }

        var tag_buffer = new uchar[16];

        error = aes.gettag(tag_buffer);

        if (error != 0) {
            critical(error.to_string());
            throw new AegisExportError.VAULT_ENCRYPTION_ERROR(error.to_string());
        }

        var tag = bytes_to_hex(tag_buffer);

        password_slot.key = bytes_to_hex(buffer);
        password_slot.key_params.tag = tag;
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

    private static string bytes_to_hex (uint8[] buffer) {
        var sb = new StringBuilder ();

        for (var i = 0;  i < buffer.length; i++) {
            sb.append_printf("%02x", buffer[i]);
        }

        return sb.str;
    }
}
