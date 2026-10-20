public class OneTimePadLibrary : Object {
    private Gee.Set<OneTimePad> pads_set;
    private Gee.Map<string,string> issuer_display_name_map;
    
    public signal void changed ();
    public signal void issuer_display_name_changed ();

    /**
     * The synced content changed: a pad was added, edited or deleted. Not emitted for
     * the periodic saves that only refresh a pad's file, nor for changes made by cloud sync itself.
     */
    public signal void content_changed ();

    /** Pads deleted on this or another device: "{issuer}:{account}" to deletion time (Unix ms). */
    public Gee.Map<string, int64?> deleted { get; private set; }

    // the modification time of each pad when it was last written, to tell real edits from refreshes
    private Gee.Map<OneTimePad, int64?> saved_modified;

    public static int64 TOMBSTONE_LIFETIME_MS = 90 * 24 * 60 * 60 * 1000L;
    
    private static OneTimePadLibrary? _instance;

    private OneTimePadLibrary() {
        pads_set = new Gee.HashSet<OneTimePad>();
        issuer_display_name_map = new Gee.HashMap<string,string> ();
        deleted = new Gee.HashMap<string, int64?> ();
        saved_modified = new Gee.HashMap<OneTimePad, int64?> ();

        load_existing_files();
    }
    
    public static OneTimePadLibrary get_default () {
        if (_instance == null) {
            _instance = new OneTimePadLibrary ();
        }

        return _instance;
    }

    public async void add(OneTimePad otp) {
        yield add_pad (otp, true);
        changed ();
        content_changed ();
    }

    /** Adds a pad; a user adding it (not sync) counts as a modification and cancels an earlier deletion. */
    private async void add_pad (OneTimePad otp, bool by_user) {
        var existing_pad = get_pad (otp.issuer, otp.account_name);

        if (existing_pad != null) {
            yield remove_pad (existing_pad);
        }

        if (by_user) {
            if (otp.modified_at == 0) {
                otp.touch ();
            }

            deleted.unset (otp.identity);
            save_deleted ();
        }

        pads_set.add (otp);
        yield save_pad (otp);
    }

    public async void save(OneTimePad pad) {
        var was_modified = saved_modified.has_key (pad) && saved_modified[pad] != pad.modified_at;

        yield save_pad (pad);

        if (was_modified) {
            content_changed ();
        }
    }

    private async void save_pad (OneTimePad pad) {
        if(pads_set.contains(pad)){

            yield pad.save_secret();

            var file = pad.to_keyfile ();
            var file_name = pad.get_file_name ();

            var file_name_with_issuer_in_account_name = pad.get_file_name_with_issuer_in_account_name ();
            var path_with_issuer_in_account_name = Path.build_filename(Environment.get_user_data_dir (), file_name_with_issuer_in_account_name);

            var file_with_issuer_in_account_name = File.new_for_path (path_with_issuer_in_account_name);

            if (file_with_issuer_in_account_name.query_exists ()) {
                file_with_issuer_in_account_name.delete_async.begin();
            }

            var dst_file_name = Path.build_filename(Environment.get_user_data_dir(), file_name);

            file.save_to_file(dst_file_name);

            saved_modified[pad] = pad.modified_at;
        }
    }

    /** Deletes a pad on this device's initiative, leaving a tombstone so other devices delete it too. */
    public async void remove(OneTimePad pad) {
        deleted[pad.identity] = OneTimePad.now_ms ();
        save_deleted ();

        yield remove_pad (pad);
        content_changed ();
    }

    private async void remove_pad(OneTimePad pad) {
        pads_set.remove(pad);
        saved_modified.unset (pad);

        var file_name = pad.get_file_name ();

        var dst_file_name = Path.build_filename(Environment.get_user_data_dir(), file_name);

        print("deleting file: %s\n",dst_file_name);

        var file = File.new_for_path (dst_file_name);

        try {
		    yield pad.clear_secret ();
		    yield file.delete_async ();
	    } catch (Error e) {
		    critical ("Error: %s\n", e.message);
	    }

    }

    public OneTimePad? get_pad(string issuer, string account_name) {
        foreach(var pad in pads_set) {
            if(pad.issuer == issuer && pad.account_name == account_name) {
                return pad;
            }
        }
        
        return null;
    }
    
    public string get_issuer_display_name (string issuer) {
        if (issuer_display_name_map.has_key (issuer)) {
            return issuer_display_name_map[issuer];
        }

        return issuer;
    }

    public void set_issuer_display_name (string issuer, string display_name) {
        issuer_display_name_map[issuer] = display_name;

        var issuer_file = new KeyFile ();

        issuer_display_name_map.@foreach((entry) => {
            issuer_file.set_string ("Issuer Names", entry.key, entry.value);
            return true;
        });

        var dst_file_name = Path.build_filename(Environment.get_user_data_dir(), "issuers.txt");

        issuer_file.save_to_file (dst_file_name);

        issuer_display_name_changed ();
    }

    /**
     * Copies the pads (with their secrets from the keyring) and the tombstones for cloud sync.
     * The pads are detached copies, so editing a pad while a sync runs does not change them.
     */
    public async SyncSnapshot create_sync_snapshot () {
        prune_deleted ();

        var snapshot = new SyncSnapshot ();
        var sorted = new Gee.ArrayList<OneTimePad> ();
        sorted.add_all (pads_set);

        // a stable order, so the same pads never look like a change
        sorted.sort ((a, b) => strcmp (a.identity, b.identity));

        foreach (var pad in sorted) {
            var secret = pad.secret ?? yield pad.lookup_secret ();

            if (secret != null && secret != "") {
                snapshot.pads.add (new SyncPad (new OneTimePad.clone_of (pad), secret));
            }
        }

        foreach (var entry in deleted.entries) {
            snapshot.deleted[entry.key] = entry.value;
        }

        return snapshot;
    }

    /**
     * Applies the result of a cloud sync: adds, updates and removes pads, and takes over the tombstones.
     * `local` is the snapshot the merge started from; a pad the user edited since then is left alone,
     * and the next sync deals with it.
     */
    public async void apply_sync (SyncSnapshot merged, SyncSnapshot local) {
        var merged_keys = new Gee.HashSet<string> ();

        foreach (var sync_pad in merged.pads) {
            merged_keys.add (sync_pad.pad.identity);
        }

        var local_by_key = new Gee.HashMap<string, SyncPad> ();

        foreach (var sync_pad in local.pads) {
            local_by_key[sync_pad.pad.identity] = sync_pad;
        }

        // pads the merge dropped, whether deleted elsewhere or never synced
        foreach (var sync_pad in local.pads) {
            var existing = get_pad (sync_pad.pad.issuer, sync_pad.pad.account_name);

            if (existing != null && !merged_keys.contains (sync_pad.pad.identity) && existing.modified_at == sync_pad.pad.modified_at) {
                yield remove_pad (existing);
            }
        }

        foreach (var incoming in merged.pads) {
            var existing = get_pad (incoming.pad.issuer, incoming.pad.account_name);

            if (existing == null) {
                var added = new OneTimePad.clone_of (incoming.pad);
                added.secret = incoming.secret;
                pads_set.add (added);
                yield save_pad (added);
                continue;
            }

            var before = local_by_key.has_key (incoming.pad.identity) ? local_by_key[incoming.pad.identity] : null;

            if (before != null && existing.modified_at != before.pad.modified_at) {
                continue;
            }

            if (before == null || !before.same_as (incoming)) {
                existing.copy_from (incoming.pad);

                if (before == null || before.secret != incoming.secret) {
                    existing.secret = incoming.secret;
                }

                yield save_pad (existing);
            }
        }

        deleted = new Gee.HashMap<string, int64?> ();

        foreach (var entry in merged.deleted.entries) {
            deleted[entry.key] = entry.value;
        }

        save_deleted ();
        changed ();
    }

    public Gee.Set<OneTimePad> get_set(){
        return pads_set;
    }
    
    public async void export (OneTimePad pad, Gtk.Window parent_window) {
        var pads = new Gee.ArrayList<OneTimePad> ();
        pads.add (pad);

        yield export_pads (pads, parent_window);
    }

    public async void export_all (Gtk.Window parent_window) {
        yield export_pads (pads_set, parent_window);
    }

    private async void export_pads (Gee.Collection<OneTimePad> pads, Gtk.Window parent_window) {

        var vault_content = new AegisVaultContent ();
        vault_content.version = 1;
        vault_content.entries = new Gee.ArrayList<AegisVaultContent.AegisVaultEntry> ();

        foreach (var pad in pads) {
            var vault_entry = yield pad.to_aegis_vault_entry ();
            vault_content.entries.add (vault_entry);
        }

        var vault_json = yield AegisManager.export_to_json_string(parent_window, vault_content);

        print("json to save: %s\n", vault_json);

        if (vault_json == null) {
            return;
        }

        var save_dialog = new Gtk.FileDialog () {
            title = _("Save Aegis Vault JSON"),
            initial_name = "aegis-vault.json"
        };

        try {
            var file = yield save_dialog.save (parent_window, null);

            yield file.replace_contents_async(vault_json.data, null, false, FileCreateFlags.NONE, null, null);
        } catch (Error e) {
            // dismissed by the user, or the file could not be written
            warning ("Could not save Aegis vault: %s", e.message);
        }
    }

    private string deleted_file_name () {
        return Path.build_filename (Environment.get_user_data_dir (), "deleted.txt");
    }

    /** Keys are escaped because key file keys cannot hold every character an issuer can. */
    private void save_deleted () {
        var file = new KeyFile ();

        foreach (var entry in deleted.entries) {
            file.set_int64 ("Deleted", Uri.escape_string (entry.key, null, true), entry.value);
        }

        try {
            file.save_to_file (deleted_file_name ());
        } catch (Error e) {
            warning ("Could not save the deleted pads: %s", e.message);
        }
    }

    /** Forgets deletions older than the tombstone lifetime. */
    public void prune_deleted (int64 now = OneTimePad.now_ms ()) {
        var expired = new Gee.ArrayList<string> ();

        foreach (var entry in deleted.entries) {
            if (entry.value < now - TOMBSTONE_LIFETIME_MS) {
                expired.add (entry.key);
            }
        }

        foreach (var key in expired) {
            deleted.unset (key);
        }

        if (expired.size > 0) {
            save_deleted ();
        }
    }

    private void load_existing_files () {
        var file = File.new_for_path (Environment.get_user_data_dir());
        load_existing_files_for_file(file);
    }
    
    private void load_existing_files_for_file (File file, string space = "", Cancellable? cancellable = null) throws Error {
	    FileEnumerator enumerator = file.enumerate_children (
		    "standard::*.txt",
		    FileQueryInfoFlags.NOFOLLOW_SYMLINKS, 
		    cancellable);

	    FileInfo info = null;

	    while (cancellable.is_cancelled () == false && ((info = enumerator.next_file (cancellable)) != null)) {
		    if (info.get_file_type () == FileType.REGULAR && info.get_name().has_suffix(".txt")) {

		        var src_file_name = Path.build_filename(Environment.get_user_data_dir(), info.get_name());

		        print("file: %s\n",src_file_name);
		        
		        var key_file = new KeyFile ();
		        key_file.load_from_file(src_file_name, KeyFileFlags.NONE);
		        
		        if (key_file.has_group("Deleted")) {

		            foreach (var key in key_file.get_keys ("Deleted")) {
		                deleted[Uri.unescape_string (key) ?? key] = key_file.get_int64 ("Deleted", key);
		            }

		        } else if (key_file.has_group("Issuer Names")) {

		            var issuers = key_file.get_keys ("Issuer Names");

		            foreach (var issuer in issuers) {
		                issuer_display_name_map[issuer] = key_file.get_string ("Issuer Names", issuer);
		            }

		        } else {
    		        var otp = new OneTimePad.from_keyfile(key_file);
		        
		            print("otp issuer: %s\n",otp.issuer);

                    pads_set.add(otp);
                    saved_modified[otp] = otp.modified_at;
                    changed ();
		        }
		        

		    }
	    }

	    if (cancellable.is_cancelled ()) {
		    throw new IOError.CANCELLED ("Operation was cancelled");
	    }
    }
}
