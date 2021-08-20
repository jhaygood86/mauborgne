public class OneTimePadLibrary : Object {
    private Gee.Set<OneTimePad> pads_set;
    
    public signal void changed ();
    
    public OneTimePadLibrary() {
        pads_set = new Gee.HashSet<OneTimePad>();
        
        load_existing_files();
    }
    
    public void add(OneTimePad otp) {
        pads_set.add(otp);
        changed ();
        
        var file = otp.to_keyfile ();
        var file_name = otp.get_file_name ();
        
        var dst_file_name = Path.build_filename(Environment.get_user_data_dir(), file_name);
        
        file.save_to_file(dst_file_name);
    }
    
    public OneTimePad get_pad(string issuer, string account_name) {
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
    
    private void load_existing_files () {
        var file = File.new_for_path (Environment.get_user_data_dir());
        load_existing_files_for_file(file);
    }
    
    private void load_existing_files_for_file (File file, string space = "", Cancellable? cancellable = null) throws Error {
	    FileEnumerator enumerator = file.enumerate_children (
		    "standard::*",
		    FileQueryInfoFlags.NOFOLLOW_SYMLINKS, 
		    cancellable);

	    FileInfo info = null;
	    while (cancellable.is_cancelled () == false && ((info = enumerator.next_file (cancellable)) != null)) {
		    if (info.get_file_type () == FileType.DIRECTORY) {
			    File subdir = file.resolve_relative_path (info.get_name ());
			    load_existing_files_for_file (subdir, space + " ", cancellable);
		    } else {
		    
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
