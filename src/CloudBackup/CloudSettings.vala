/** Where the last backup this device saw is remembered, to notice a replayed older one, and the sync switches. */
public interface CloudSettings : Object {
    public abstract string? last_backup_id { owned get; set; }

    /** Unix seconds; 0 if unknown. */
    public abstract int64 last_backup_updated_at { get; set; }

    /** Automatic cloud sync is on. */
    public abstract bool sync_enabled { get; set; }

    /** Local changes have been made that the cloud has not seen. */
    public abstract bool sync_dirty { get; set; }
}

public class GSettingsCloudSettings : Object, CloudSettings {
    private Settings settings;

    public GSettingsCloudSettings (Settings settings) {
        this.settings = settings;
    }

    public string? last_backup_id {
        owned get {
            var id = settings.get_string ("cloud-last-backup-id");
            return id == "" ? null : id;
        }
        set {
            settings.set_string ("cloud-last-backup-id", value ?? "");
        }
    }

    public int64 last_backup_updated_at {
        get { return settings.get_int64 ("cloud-last-backup-updated-at"); }
        set { settings.set_int64 ("cloud-last-backup-updated-at", value); }
    }

    public bool sync_enabled {
        get { return settings.get_boolean ("cloud-sync-enabled"); }
        set { settings.set_boolean ("cloud-sync-enabled", value); }
    }

    public bool sync_dirty {
        get { return settings.get_boolean ("cloud-sync-dirty"); }
        set { settings.set_boolean ("cloud-sync-dirty", value); }
    }
}

/** Settings that live only in memory, for tests. */
public class MemoryCloudSettings : Object, CloudSettings {
    private string? _last_backup_id = null;

    public string? last_backup_id {
        owned get { return _last_backup_id; }
        set { _last_backup_id = value; }
    }

    public int64 last_backup_updated_at { get; set; }
    public bool sync_enabled { get; set; }
    public bool sync_dirty { get; set; }
}

/**
 * Keeps the cloud password while automatic sync is on, because every sync logs in again. It sits in
 * the user's keyring, so it is as protected as the pad secrets themselves.
 */
public interface SyncPasswordStore : Object {
    public abstract string? load ();
    public abstract void save (string password);
    public abstract void clear ();
}

public class KeyringSyncPasswordStore : Object, SyncPasswordStore {

    private static Secret.Schema schema = new Secret.Schema (
        "io.github.jhaygood86.mauborgne.cloudsync", Secret.SchemaFlags.NONE,
        "kind", Secret.SchemaAttributeType.STRING);

    public string? load () {
        try {
            return Secret.password_lookup_sync (schema, null, "kind", "sync-password");
        } catch (Error e) {
            warning ("Could not read the sync password from the keyring: %s", e.message);
            return null;
        }
    }

    public void save (string password) {
        try {
            Secret.password_store_sync (schema, Secret.COLLECTION_DEFAULT, "Mauborgne cloud sync password", password, null, "kind", "sync-password");
        } catch (Error e) {
            warning ("Could not store the sync password in the keyring: %s", e.message);
        }
    }

    public void clear () {
        try {
            Secret.password_clear_sync (schema, null, "kind", "sync-password");
        } catch (Error e) {
            warning ("Could not remove the sync password from the keyring: %s", e.message);
        }
    }
}

public class MemorySyncPasswordStore : Object, SyncPasswordStore {
    private string? password = null;

    public string? load () {
        return password;
    }

    public void save (string password) {
        this.password = password;
    }

    public void clear () {
        password = null;
    }
}
