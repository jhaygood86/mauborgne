public class OneTimePadLibrary : Object {
    private Gee.Set<OneTimePad> pads_set;
    
    public signal void changed ();
    
    private static OneTimePadLibrary? _instance;

    private OneTimePadLibrary() {
        pads_set = new Gee.HashSet<OneTimePad>();
        
        load_existing_files();
    }
    
    public static OneTimePadLibrary get_default () {
        if (_instance == null) {
            _instance = new OneTimePadLibrary ();
        }

        return _instance;
    }

    public async void add(OneTimePad otp) {
        pads_set.add (otp);
        yield save (otp);
        changed ();
    }

    public async void save(OneTimePad pad) {
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
        }
    }

    public async void remove(OneTimePad pad) {
        pads_set.remove(pad);

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

        var vault_json = AegisManager.export_to_json_string(parent_window, vault_content);

        print("json to save: %s\n", vault_json);

        if (vault_json == null) {
            return;
        }

        var save_dialog = new Gtk.FileChooserNative (_("Save Aegis Vault JSON"), parent_window, Gtk.FileChooserAction.SAVE, null, null);
        save_dialog.set_current_name("aegis-vault.json");

        var response = save_dialog.run ();

        if (response == Gtk.ResponseType.ACCEPT) {
            var uri = save_dialog.get_uri();
            var file = File.new_for_uri(uri);

            yield file.replace_contents_async(vault_json.data, null, false, FileCreateFlags.NONE, null, null);
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
		        
		        var otp = new OneTimePad.from_keyfile(key_file);
		        
		        print("otp issuer: %s\n",otp.issuer);
		        
                pads_set.add(otp);
                changed ();
		    }
	    }

	    if (cancellable.is_cancelled ()) {
		    throw new IOError.CANCELLED ("Operation was cancelled");
	    }
    }
}
