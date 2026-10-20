/** Where a user without a subscription can sign up for Cloud Backup. */
namespace Mauborgne.CloudBackupLinks {
    public const string SIGNUP_URL = "https://customer.peachstatetechnologies.com/Signup/CiNvjP-rrA36PRLwEgIhp5LnMARROZGc0cYBVWlLB3g";
}

public errordomain CloudBackupError {
    /** No license, or the server rejected it: send the user to sign in or sign up. */
    LICENSE_INVALID,
    LICENSE_EXPIRED,
    /** Wrong cloud password (or the identity has no password registered yet). */
    WRONG_PASSWORD,
    /** Restore or password change attempted before any password was registered. */
    NOT_REGISTERED,
    NO_BACKUP,
    TOO_MANY_ATTEMPTS,
    /** The downloaded backup failed an integrity check. */
    TAMPERED,
    /** Another device uploaded since this one last looked: pull, merge and retry. */
    CONFLICT,
    /** The server could not be reached. */
    NETWORK,
    /** The native OPAQUE library is not part of this build. */
    UNAVAILABLE,
    SERVER
}

namespace Mauborgne.CloudBackupErrors {

    /** True when the right response is to offer sign-in or sign-up. */
    public bool should_offer_signup (Error e) {
        return e is CloudBackupError.LICENSE_INVALID || e is CloudBackupError.LICENSE_EXPIRED;
    }
}

/** Supplies the CRM-issued license JWT that identifies the subscriber. */
public interface LicenseProvider : Object {
    /** The current license JWT, or null if the user has none. */
    public abstract async string? get_license () throws Error;
}

public class CloudBackupStatus : Object {
    public bool registered { get; construct; }
    public bool backup_exists { get; construct; }
    /** Unix seconds of the last backup, or 0. */
    public int64 updated_at { get; construct; }
    public string credential_id { get; construct; }
    public string? backup_id { get; construct; }

    public CloudBackupStatus (bool registered, bool backup_exists, int64 updated_at, string credential_id, string? backup_id) {
        Object (registered: registered, backup_exists: backup_exists, updated_at: updated_at,
                credential_id: credential_id, backup_id: backup_id);
    }
}

public class CloudBackupInfo : Object {
    public string backup_id { get; construct; }
    public int64 updated_at { get; construct; }

    public CloudBackupInfo (string backup_id, int64 updated_at) {
        Object (backup_id: backup_id, updated_at: updated_at);
    }
}

/**
 * backup_id changes with every backup. The app remembers the last one it saw and warns if the
 * server ever returns an older one (a replayed backup).
 */
public class CloudRestoreResult : Object {
    public SyncSnapshot snapshot { get; construct; }
    public string backup_id { get; construct; }
    public int64 updated_at { get; construct; }

    public CloudRestoreResult (SyncSnapshot snapshot, string backup_id, int64 updated_at) {
        Object (snapshot: snapshot, backup_id: backup_id, updated_at: updated_at);
    }
}

/** What a sync decided after seeing the cloud's vault: the merged content, and whether it differs from the cloud's. */
public class CloudSyncPlan : Object {
    public SyncSnapshot merged { get; construct; }
    public bool upload { get; construct; }

    public CloudSyncPlan (SyncSnapshot merged, bool upload) {
        Object (merged: merged, upload: upload);
    }
}

/**
 * The outcome of a sync. reconciled is false when nothing was exchanged because nothing had
 * changed; otherwise the reconcile callback ran last with the cloud's current vault.
 */
public class CloudSyncResult : Object {
    public string? backup_id { get; construct; }
    public int64 updated_at { get; construct; }
    public bool reconciled { get; construct; }
    public bool uploaded { get; construct; }

    public CloudSyncResult (string? backup_id, int64 updated_at, bool reconciled, bool uploaded) {
        Object (backup_id: backup_id, updated_at: updated_at, reconciled: reconciled, uploaded: uploaded);
    }
}

/** Decides what to do with the cloud's vault: merge it with the local pads. Runs on the main thread. */
public delegate CloudSyncPlan ReconcileFunc (SyncSnapshot? remote);

/** Rules for the cloud password. Longer than the Aegis export minimum on purpose: it is the last line of defense. */
namespace Mauborgne.CloudPasswordPolicy {

    public const int MIN_LENGTH = 12;

    /** Checks a new password and its confirmation. Returns an error message, or null if acceptable. */
    public string? validate_new (string password, string confirmation) {
        if (password.char_count () < MIN_LENGTH) {
            return _("Password must be at least %d characters.").printf (MIN_LENGTH);
        }

        return password == confirmation ? null : _("Passwords need to match.");
    }

    /** Checks a password being entered for an existing backup. */
    public string? validate_existing (string password) {
        return password.length == 0 ? _("Enter your cloud password.") : null;
    }
}
