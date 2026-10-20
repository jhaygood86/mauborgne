/**
 * Merges this device's pads with the cloud's. Deterministic and symmetric enough that two devices
 * merging each other's results converge:
 *
 *  - per pad, the side with the newer modified_at wins (a tie keeps the local pad);
 *    a counter-based pad always takes the larger counter, since counters only move forward;
 *  - a deletion wins over a pad unless the pad was modified after it was deleted;
 *  - the order comes from whichever side changed it last. This app never changes the order,
 *    so on a tie the cloud's order is kept, and pads it has not seen are appended;
 *  - tombstones older than TOMBSTONE_LIFETIME_MS are forgotten.
 *
 * A port of SyncMerge.cs from the Windows and Android apps.
 */
namespace Mauborgne.SyncMerge {

    public const int64 TOMBSTONE_LIFETIME_MS = 90 * 24 * 60 * 60 * 1000L;

    public SyncSnapshot merge (SyncSnapshot local, SyncSnapshot remote, int64 now_ms) {
        var local_by_key = index (local);
        var remote_by_key = index (remote);

        var keys = new Gee.HashSet<string> ();
        keys.add_all (local_by_key.keys);
        keys.add_all (remote_by_key.keys);
        keys.add_all (local.deleted.keys);
        keys.add_all (remote.deleted.keys);

        var survivors = new Gee.HashMap<string, SyncPad> ();
        var deleted = new Gee.HashMap<string, int64?> ();
        var cutoff = now_ms - TOMBSTONE_LIFETIME_MS;

        foreach (var key in keys) {
            var l = local_by_key.has_key (key) ? local_by_key[key] : null;
            var r = remote_by_key.has_key (key) ? remote_by_key[key] : null;

            var winner = pick (l, r);
            var tombstone = int64.max (deleted_at (local, key), deleted_at (remote, key));

            if (winner != null && winner.pad.modified_at > tombstone) {
                survivors[key] = winner;
            } else if (tombstone > cutoff) {
                deleted[key] = tombstone;
            } else if (winner != null && tombstone == 0) {
                survivors[key] = winner;
            }
        }

        // this app has no order of its own, so the cloud's wins unless ours is strictly newer
        var local_wins_order = local.order_modified > remote.order_modified;
        var first = local_wins_order ? local : remote;
        var second = local_wins_order ? remote : local;

        var ordered = new Gee.ArrayList<SyncPad> ();
        var placed = new Gee.HashSet<string> ();

        foreach (var source in new SyncSnapshot[] { first, second }) {
            foreach (var sync_pad in source.pads) {
                var key = sync_pad.pad.identity;

                if (survivors.has_key (key) && placed.add (key)) {
                    ordered.add (survivors[key]);
                }
            }
        }

        var merged = new SyncSnapshot ();
        merged.pads = ordered;
        merged.deleted = deleted;
        merged.order_modified = int64.max (local.order_modified, remote.order_modified);

        return merged;
    }

    private Gee.Map<string, SyncPad> index (SyncSnapshot snapshot) {
        var map = new Gee.HashMap<string, SyncPad> ();

        foreach (var sync_pad in snapshot.pads) {
            map[sync_pad.pad.identity] = sync_pad;
        }

        return map;
    }

    private int64 deleted_at (SyncSnapshot snapshot, string key) {
        return snapshot.deleted.has_key (key) ? snapshot.deleted[key] : 0;
    }

    private SyncPad? pick (SyncPad? l, SyncPad? r) {
        if (l == null || r == null) {
            return l ?? r;
        }

        var winner = r.pad.modified_at > l.pad.modified_at ? r : l;
        var other = winner == l ? r : l;

        if (winner.pad.pad_type == OneTimePadType.HOTP && other.pad.counter > winner.pad.counter) {
            var pad = new OneTimePad.clone_of (winner.pad);
            pad.counter = other.pad.counter;

            return winner.with_pad (pad);
        }

        return winner;
    }
}
