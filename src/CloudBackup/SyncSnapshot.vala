/** A pad together with its secret, as synced. */
public class SyncPad : Object {
    public OneTimePad pad { get; construct; }
    public string secret { get; construct; }

    public SyncPad (OneTimePad pad, string secret) {
        Object (pad: pad, secret: secret);
    }

    public SyncPad with_pad (OneTimePad new_pad) {
        return new SyncPad (new_pad, secret);
    }

    internal bool same_as (SyncPad other) {
        return secret == other.secret
            && pad.pad_type == other.pad.pad_type
            && pad.issuer == other.pad.issuer
            && pad.account_name == other.pad.account_name
            && pad.account_name_display == other.pad.account_name_display
            && pad.algorithm == other.pad.algorithm
            && pad.digits == other.pad.digits
            && pad.counter == other.pad.counter
            && pad.period == other.pad.period
            && pad.note == other.pad.note
            && pad.modified_at == other.pad.modified_at;
    }
}

/**
 * Everything cloud sync compares and merges: the pads, the tombstones of deleted pads,
 * and when the order last changed. The same shape is stored in the encrypted cloud vault
 * (the mb_* extensions on AegisVaultContent).
 */
public class SyncSnapshot : Object {
    public Gee.List<SyncPad> pads { get; set; default = new Gee.ArrayList<SyncPad> (); }

    /** "{issuer}:{account}" to deletion time (Unix ms). */
    public Gee.Map<string, int64?> deleted { get; set; default = new Gee.HashMap<string, int64?> (); }

    public int64 order_modified { get; set; }

    public AegisVaultContent to_content () {
        var content = new AegisVaultContent ();
        content.version = 1;
        content.entries = new Gee.ArrayList<AegisVaultContent.AegisVaultEntry> ();

        foreach (var sync_pad in pads) {
            content.entries.add (sync_pad.pad.build_aegis_vault_entry (sync_pad.secret));
        }

        if (deleted.size > 0) {
            content.deleted = new Gee.HashMap<string, int64?> ();

            foreach (var entry in deleted.entries) {
                content.deleted[entry.key] = entry.value;
            }
        }

        content.order_modified = order_modified;

        return content;
    }

    public static SyncSnapshot from_content (AegisVaultContent content) {
        var snapshot = new SyncSnapshot ();

        if (content.entries != null) {
            foreach (var entry in content.entries) {
                string? secret = null;

                if (entry is AegisVaultContent.AegisTotpVaultEntry) {
                    secret = ((AegisVaultContent.AegisTotpVaultEntry) entry).info.secret;
                } else if (entry is AegisVaultContent.AegisHotpVaultEntry) {
                    secret = ((AegisVaultContent.AegisHotpVaultEntry) entry).info.secret;
                }

                try {
                    // an entry of a type we do not know is not ours to sync
                    snapshot.pads.add (new SyncPad (new OneTimePad.from_aegis_vault_entry (entry), secret ?? ""));
                } catch (OneTimePadError e) {
                    warning ("Skipping a backup entry: %s", e.message);
                }
            }
        }

        if (content.deleted != null) {
            foreach (var entry in content.deleted.entries) {
                snapshot.deleted[entry.key] = entry.value;
            }
        }

        snapshot.order_modified = content.order_modified;

        return snapshot;
    }

    /**
     * True when both snapshots hold the same synced state. The order of the pads is not
     * compared: this app has no order of its own, so a different order is never a reason to upload.
     */
    public bool equivalent_to (SyncSnapshot other) {
        if (pads.size != other.pads.size || deleted.size != other.deleted.size) {
            return false;
        }

        foreach (var entry in deleted.entries) {
            if (!other.deleted.has_key (entry.key) || other.deleted[entry.key] != entry.value) {
                return false;
            }
        }

        var by_identity = new Gee.HashMap<string, SyncPad> ();

        foreach (var sync_pad in other.pads) {
            by_identity[sync_pad.pad.identity] = sync_pad;
        }

        foreach (var sync_pad in pads) {
            if (!by_identity.has_key (sync_pad.pad.identity) || !sync_pad.same_as (by_identity[sync_pad.pad.identity])) {
                return false;
            }
        }

        return order_modified == other.order_modified;
    }
}
