public enum SyncState {
    /** Automatic sync is not turned on. */
    OFF,
    IDLE,
    SYNCING,
    /** The last attempt succeeded. */
    SYNCED,
    /** Needs the user: sign in again or re-enter the cloud password. */
    PAUSED,
    /** The last attempt failed for a reason that usually clears up (offline, server busy); it is retried. */
    OFFLINE
}

public class SyncStatus : Object {
    public SyncState state { get; construct; }
    /** Unix seconds of the last successful sync, or 0. */
    public int64 last_synced { get; construct; }
    public string text { get; construct; }

    public SyncStatus (SyncState state, int64 last_synced, string text) {
        Object (state: state, last_synced: last_synced, text: text);
    }
}

/**
 * Keeps this device's pads and the cloud backup in step. A sync pulls the cloud vault, merges it
 * with the local pads (SyncMerge), applies the result locally and uploads it if it differs.
 * A port of CloudSyncService.cs.
 *
 * Logging in to the cloud takes the cloud password every time, so while sync is on the password
 * is kept in the keyring (see SyncPasswordStore).
 */
public class CloudSyncService : Object {

    /** Wait this long after the last change before uploading, so a burst of edits is one sync. */
    public const uint DEBOUNCE_SECONDS = 5;

    /** How long to wait before trying again after a failure that usually clears up. */
    public const uint RETRY_SECONDS = 300;

    private CloudBackupService cloud;
    private OneTimePadLibrary library;
    private CloudSettings settings;
    private SyncPasswordStore passwords;

    private uint debounce_id = 0;
    private uint retry_id = 0;
    private int changes = 0;
    private bool running = false;

    public SyncStatus status { get; private set; }

    public signal void status_changed (SyncStatus status);

    public CloudSyncService (CloudBackupService cloud, OneTimePadLibrary library, CloudSettings settings, SyncPasswordStore passwords) {
        this.cloud = cloud;
        this.library = library;
        this.settings = settings;
        this.passwords = passwords;

        status = settings.sync_enabled
            ? new SyncStatus (SyncState.IDLE, 0, _("Sync is on"))
            : new SyncStatus (SyncState.OFF, 0, _("Sync is off"));

        library.content_changed.connect (on_library_changed);
    }

    public bool is_enabled {
        get { return settings.sync_enabled; }
    }

    /** Syncs now if sync is on; call once the window is up. */
    public void start () {
        if (settings.sync_enabled) {
            sync_now.begin ();
        }
    }

    /**
     * Turns sync on, remembering the password. Pass sync_now false right after a manual backup or
     * restore, which already made the cloud and this device identical.
     */
    public async void enable (string password, bool sync_now = true) {
        passwords.save (password);
        settings.sync_enabled = true;
        settings.sync_dirty = sync_now;
        update_status (SyncState.IDLE, 0, _("Sync is on"));

        if (sync_now) {
            yield this.sync_now ();
        }
    }

    public void disable () {
        cancel_timers ();
        settings.sync_enabled = false;
        settings.sync_dirty = false;
        passwords.clear ();
        update_status (SyncState.OFF, 0, _("Sync is off"));
    }

    /** Runs one sync now. Returns the resulting status; a no-op when off or already running. */
    public async SyncStatus sync_now () {
        if (!settings.sync_enabled || running) {
            return status;
        }

        running = true;

        try {
            var password = passwords.load ();

            if (password == null) {
                pause (_("Sync paused — turn it back on with your cloud password"));
                return status;
            }

            update_status (SyncState.SYNCING, status.last_synced, _("Syncing…"));
            var changes_before = AtomicInt.get (ref changes);
            var local = yield library.create_sync_snapshot ();
            SyncSnapshot? merged = null;

            var result = yield cloud.sync (password, settings.last_backup_id, settings.sync_dirty, (remote) => {
                var remote_snapshot = remote ?? new SyncSnapshot ();
                merged = Mauborgne.SyncMerge.merge (local, remote_snapshot, OneTimePad.now_ms ());

                var upload = remote == null
                    ? merged.pads.size > 0 || merged.deleted.size > 0
                    : !merged.equivalent_to (remote_snapshot);

                return new CloudSyncPlan (merged, upload);
            });

            if (result.reconciled && merged != null) {
                yield library.apply_sync (merged, local);
            }

            if (result.backup_id != null) {
                settings.last_backup_id = result.backup_id;
                settings.last_backup_updated_at = result.updated_at;
            }

            // Edits made while the sync ran are not in what was uploaded: stay dirty so they go next time.
            settings.sync_dirty = AtomicInt.get (ref changes) != changes_before;
            update_status (SyncState.SYNCED, new DateTime.now_utc ().to_unix (), _("Synced just now"));

            if (settings.sync_dirty) {
                schedule_sync ();
            }
        } catch (Error e) {
            handle_failure (e);
        } finally {
            running = false;
        }

        return status;
    }

    private void on_library_changed () {
        if (!settings.sync_enabled) {
            return;
        }

        AtomicInt.inc (ref changes);
        settings.sync_dirty = true;
        schedule_sync ();
    }

    private void schedule_sync () {
        if (debounce_id != 0) {
            Source.remove (debounce_id);
        }

        debounce_id = Timeout.add_seconds (DEBOUNCE_SECONDS, () => {
            debounce_id = 0;
            sync_now.begin ();
            return Source.REMOVE;
        });
    }

    private void schedule_retry () {
        if (retry_id != 0) {
            Source.remove (retry_id);
        }

        retry_id = Timeout.add_seconds (RETRY_SECONDS, () => {
            retry_id = 0;
            sync_now.begin ();
            return Source.REMOVE;
        });
    }

    private void cancel_timers () {
        if (debounce_id != 0) {
            Source.remove (debounce_id);
            debounce_id = 0;
        }

        if (retry_id != 0) {
            Source.remove (retry_id);
            retry_id = 0;
        }
    }

    private void handle_failure (Error e) {
        if (e is CloudBackupError.WRONG_PASSWORD) {
            passwords.clear ();
            settings.sync_enabled = false;
            update_status (SyncState.OFF, status.last_synced, _("Cloud password changed — turn sync back on"));
        } else if (e is CloudBackupError.LICENSE_INVALID || e is CloudBackupError.LICENSE_EXPIRED) {
            pause (_("Sync paused — sign in to Cloud Backup"));
        } else if (e is CloudBackupError.NOT_REGISTERED) {
            pause (_("Sync paused — no cloud backup yet"));
        } else if (e is CloudBackupError.UNAVAILABLE) {
            pause (_("Cloud sync isn't available in this build"));
        } else if (e is CloudBackupError.NETWORK) {
            update_status (SyncState.OFFLINE, status.last_synced, _("Can't reach Cloud Backup — will retry"));
            schedule_retry ();
        } else {
            warning ("Cloud sync failed: %s", e.message);
            update_status (SyncState.OFFLINE, status.last_synced, _("Sync failed — will retry"));
            schedule_retry ();
        }
    }

    private void pause (string text) {
        update_status (SyncState.PAUSED, status.last_synced, text);
    }

    private void update_status (SyncState state, int64 last_synced, string text) {
        status = new SyncStatus (state, last_synced, text);
        status_changed (status);
    }
}
