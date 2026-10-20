/**
 * The backup key hierarchy. The OPAQUE export_key (known only to the client) yields a wrap key,
 * which protects a fresh random backup key per backup. The server stores only the wrapped blob,
 * so it can neither decrypt a vault nor tamper with one unnoticed.
 *
 * A port of CloudBackupCrypto.cs from the Windows and Android apps; the byte formats must match.
 */
namespace Mauborgne.CloudCrypto {

    public const int KEY_SIZE = 32;
    private const int NONCE_SIZE = 12;
    private const int TAG_SIZE = 16;
    private const int HASH_SIZE = 32;

    private const string WRAP_INFO = "mauborgne cloud wrap v1";
    private const string AAD_PREFIX = "mauborgne-cloud-backup-v1";

    /** What a wrapped blob protects: the vault password and the vault's expected hash. */
    public class UnwrappedKey : Object {
        public uint8[] backup_key;
        public uint8[] vault_hash;

        public UnwrappedKey (owned uint8[] backup_key, owned uint8[] vault_hash) {
            this.backup_key = (owned) backup_key;
            this.vault_hash = (owned) vault_hash;
        }
    }

    /** NFKC-normalised UTF-8, so the same passphrase works on every platform. */
    public uint8[] password_bytes (string password) {
        var normalized = password.normalize (-1, NormalizeMode.ALL_COMPOSE);

        // g_utf8_normalize with NFKC is NormalizeMode.ALL_COMPOSE
        var bytes = new uint8[normalized.length];
        Memory.copy (bytes, normalized.data, normalized.length);

        return bytes;
    }

    private uint8[] sha256 (uint8[] data) {
        var digest = new uint8[HASH_SIZE];
        GCrypt.Hash.hash_buffer (GCrypt.Hash.Algorithm.SHA256, digest, data);

        return digest;
    }

    public uint8[] hash_vault (string vault_json) {
        return sha256 (vault_json.data);
    }

    private uint8[] hmac_sha256 (uint8[] key, uint8[] data) {
        GCrypt.Hash hash;
        GCrypt.Hash.open (out hash, GCrypt.Hash.Algorithm.SHA256, GCrypt.Hash.Flag.HMAC);
        hash.set_key (key);
        hash.write (data);

        var mac = new uint8[HASH_SIZE];
        Memory.copy (mac, hash.read (GCrypt.Hash.Algorithm.SHA256), HASH_SIZE);

        return mac;
    }

    /** HKDF-SHA256 (RFC 5869). An empty salt means a key of hash-length zeros. */
    public uint8[] hkdf_sha256 (uint8[] ikm, uint8[] salt, uint8[] info, int length) {
        var key = salt.length > 0 ? salt : new uint8[HASH_SIZE];
        var prk = hmac_sha256 (key, ikm);

        var output = new uint8[length];
        var previous = new uint8[0];
        var produced = 0;
        uint8 counter = 1;

        while (produced < length) {
            var block = new ByteArray ();
            block.append (previous);
            block.append (info);
            block.append ({ counter });

            previous = hmac_sha256 (prk, block.data);

            var take = int.min (HASH_SIZE, length - produced);
            Memory.copy ((uint8*) output + produced, previous, take);
            produced += take;
            counter++;
        }

        zero (prk);

        return output;
    }

    public uint8[] derive_wrap_key (uint8[] export_key) {
        return hkdf_sha256 (export_key, new uint8[0], WRAP_INFO.data, KEY_SIZE);
    }

    /** A fresh 32-byte key to use, base64-encoded, as the Aegis vault password. */
    public uint8[] new_backup_key () {
        var key = new uint8[KEY_SIZE];
        GCrypt.Random.randomize (key);

        return key;
    }

    /** 22 URL-safe characters; matches the Worker's accepted id shape. */
    public string new_backup_id () {
        var bytes = new uint8[16];
        GCrypt.Random.randomize (bytes);

        return Base64.encode (bytes).replace ("=", "").replace ("+", "-").replace ("/", "_");
    }

    public string aegis_password (uint8[] backup_key) {
        return Base64.encode (backup_key);
    }

    private uint8[] additional_data (string credential_id, string backup_id) {
        var builder = new ByteArray ();
        builder.append (AAD_PREFIX.data);
        builder.append ({ 0 });
        builder.append (credential_id.data);
        builder.append ({ 0 });
        builder.append (backup_id.data);

        return builder.data;
    }

    /**
     * nonce | tag | AES-256-GCM(wrap_key, backup_key || SHA-256(vault)), bound to this
     * account and backup id so a blob cannot be moved to another account or backup.
     */
    public uint8[] wrap (uint8[] wrap_key, uint8[] backup_key, uint8[] vault_hash, string credential_id, string backup_id) {
        var plaintext = new uint8[KEY_SIZE + HASH_SIZE];
        Memory.copy (plaintext, backup_key, KEY_SIZE);
        Memory.copy ((uint8*) plaintext + KEY_SIZE, vault_hash, HASH_SIZE);

        var nonce = new uint8[NONCE_SIZE];
        GCrypt.Random.randomize (nonce);

        GCrypt.Cipher.Cipher aes;
        GCrypt.Cipher.Cipher.open (out aes, GCrypt.Cipher.Algorithm.AES256, GCrypt.Cipher.Mode.GCM, 0);
        aes.set_key (wrap_key);
        aes.set_iv (nonce);
        aes.authenticate (additional_data (credential_id, backup_id));

        var ciphertext = new uint8[plaintext.length];
        aes.encrypt (ciphertext, plaintext);

        var tag = new uint8[TAG_SIZE];
        aes.gettag (tag);

        zero (plaintext);

        var output = new uint8[NONCE_SIZE + TAG_SIZE + ciphertext.length];
        Memory.copy (output, nonce, NONCE_SIZE);
        Memory.copy ((uint8*) output + NONCE_SIZE, tag, TAG_SIZE);
        Memory.copy ((uint8*) output + NONCE_SIZE + TAG_SIZE, ciphertext, ciphertext.length);

        return output;
    }

    /** Returns null if the blob was altered, moved, or the wrap key is wrong. */
    public UnwrappedKey? unwrap (uint8[] wrap_key, uint8[] blob, string credential_id, string backup_id) {
        if (blob.length != NONCE_SIZE + TAG_SIZE + KEY_SIZE + HASH_SIZE) {
            return null;
        }

        var nonce = new uint8[NONCE_SIZE];
        Memory.copy (nonce, blob, NONCE_SIZE);

        var tag = new uint8[TAG_SIZE];
        Memory.copy (tag, (uint8*) blob + NONCE_SIZE, TAG_SIZE);

        var ciphertext = new uint8[KEY_SIZE + HASH_SIZE];
        Memory.copy (ciphertext, (uint8*) blob + NONCE_SIZE + TAG_SIZE, ciphertext.length);

        GCrypt.Cipher.Cipher aes;
        GCrypt.Cipher.Cipher.open (out aes, GCrypt.Cipher.Algorithm.AES256, GCrypt.Cipher.Mode.GCM, 0);
        aes.set_key (wrap_key);
        aes.set_iv (nonce);
        aes.authenticate (additional_data (credential_id, backup_id));

        var plaintext = new uint8[ciphertext.length];
        aes.decrypt (plaintext, ciphertext);

        if (aes.checktag (tag) != 0) {
            zero (plaintext);
            return null;
        }

        var backup_key = new uint8[KEY_SIZE];
        Memory.copy (backup_key, plaintext, KEY_SIZE);

        var vault_hash = new uint8[HASH_SIZE];
        Memory.copy (vault_hash, (uint8*) plaintext + KEY_SIZE, HASH_SIZE);

        zero (plaintext);

        return new UnwrappedKey ((owned) backup_key, (owned) vault_hash);
    }

    /** Compares without stopping at the first difference, so timing reveals nothing. */
    public bool fixed_time_equals (uint8[] a, uint8[] b) {
        if (a.length != b.length) {
            return false;
        }

        uint8 difference = 0;

        for (int i = 0; i < a.length; i++) {
            difference |= a[i] ^ b[i];
        }

        return difference == 0;
    }

    public void zero (uint8[]? secret) {
        if (secret != null) {
            Memory.set (secret, 0, secret.length);
        }
    }
}
