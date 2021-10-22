public errordomain OneTimePadError {
    UNKNOWN_PAD_TYPE
}

public class OneTimePad {

    private static Secret.Schema schema;

    public OneTimePadType pad_type { get; set; }
    public string issuer { get; set; }
    public string account_name { get; set; }
    public string secret { get; set; }
    public OneTimePadAlgorithm algorithm { get; set; }
    public int digits { get; set; }
    public int64 counter { get; set; }
    public int period { get; set; }
    
    static construct {
        schema = new Secret.Schema ("io.github.jhaygood86.mauborgne", Secret.SchemaFlags.NONE,
                                    "issuer", Secret.SchemaAttributeType.STRING,
                                    "account_name", Secret.SchemaAttributeType.STRING);
    }

    public OneTimePad.from_uri(string uri) throws GLib.UriError {
    
        algorithm = OneTimePadAlgorithm.SHA1;
        digits = 6;
        period = 30;
    
        var parsed_uri = GLib.Uri.parse(uri, UriFlags.PARSE_RELAXED);
        
        if (parsed_uri.get_scheme() == "otpauth") {
            var format = parsed_uri.get_host().down ();
            
            print("format: %s\n",format);
            
            if (format == "totp") {
                pad_type = OneTimePadType.TOTP;
            }
            
            if (format == "hotp") {
                pad_type = OneTimePadType.HOTP;
            }
            
            account_name = parsed_uri.get_path();
            
            if(account_name.index_of("/") == 0){
                account_name = account_name.substring(1);
            }
            
            print("account name: %s\n",account_name);
            
            issuer = parsed_uri.get_user();
            
            print("issuer: %s\n",issuer);
            
            var uri_params = Uri.parse_params(parsed_uri.get_query());
            
            if(uri_params.contains ("secret")){
                secret = uri_params["secret"];
                print("secret: %s\n",secret);
            }
            
            if(uri_params.contains ("issuer")){
                issuer = uri_params["issuer"];
                print("issuer: %s\n",issuer);
            }
 
            if(uri_params.contains ("algorithm")){
                var algorithm_value = uri_params["algorithm"];
                
                if(algorithm_value == "SHA1"){
                    algorithm = OneTimePadAlgorithm.SHA1;
                }
                
                if(algorithm_value == "SHA256"){
                    algorithm = OneTimePadAlgorithm.SHA256;
                }
                
                if(algorithm_value == "SHA512"){
                    algorithm = OneTimePadAlgorithm.SHA512;
                }
            }
            
            if(uri_params.contains ("digits")){
                var digits_value = uri_params["digits"];
                digits = int.parse(digits_value);
            }
            
            if(uri_params.contains ("counter")){
                var counter_value = uri_params["counter"];
                counter = int64.parse(counter_value);
            }
            
            if(uri_params.contains ("period")){
                var period_value = uri_params["period"];
                period = int.parse(period_value);
            }
            
            if(issuer == null && account_name.contains(":")) {
                var account_name_parts = account_name.split(":",2);
                issuer = account_name_parts[0];
                account_name = account_name_parts[1];
            }

            account_name = get_cleaned_account_name (issuer, account_name);

            store_secret.begin(secret);
        }
    }
    
    public OneTimePad.from_keyfile(KeyFile file) throws KeyFileError {
        pad_type = (OneTimePadType)file.get_integer("PadSettings","PadType");
        issuer = file.get_string("PadSettings","Issuer");
        account_name = file.get_string("PadSettings","AccountName");

        account_name = get_cleaned_account_name (issuer, account_name);

        if (file.has_key("PadSettings", "Secret")) {
            secret = file.get_string("PadSettings","Secret");
        }

        algorithm = (OneTimePadAlgorithm)file.get_integer("PadSettings","Algorithm");
        digits = file.get_integer("PadSettings","Digits");
        counter = file.get_int64("PadSettings","Counter");
        period = file.get_integer("PadSettings","Period");
    }
    
    public OneTimePad.from_aegis_vault_entry (AegisVaultContent.AegisVaultEntry entry) throws OneTimePadError {

        AegisVaultContent.AegisVaultEntryInfo? info = null;

        if (entry is AegisVaultContent.AegisTotpVaultEntry) {
            AegisVaultContent.AegisTotpVaultEntry totp_entry = (AegisVaultContent.AegisTotpVaultEntry)entry;
            pad_type = OneTimePadType.TOTP;
            period = totp_entry.info.period;
            info = totp_entry.info;
        }

        if (entry is AegisVaultContent.AegisHotpVaultEntry) {
            AegisVaultContent.AegisHotpVaultEntry hotp_entry = (AegisVaultContent.AegisHotpVaultEntry)entry;
            pad_type = OneTimePadType.HOTP;
            counter = hotp_entry.info.counter;
            info = hotp_entry.info;
        }

        if (info == null) {
            throw new OneTimePadError.UNKNOWN_PAD_TYPE(_("Cannot determine pad type"));
        }

        issuer = entry.issuer;
        account_name = entry.name;
        secret = info.secret;

        switch (info.algo) {
            case "SHA1":
                algorithm = OneTimePadAlgorithm.SHA1;
                break;
            case "SHA256":
                algorithm = OneTimePadAlgorithm.SHA256;
                break;
            case "SHA512":
                algorithm = OneTimePadAlgorithm.SHA512;
                break;
        }

        digits = info.digits;

        account_name = get_cleaned_account_name (issuer, account_name);
    }

    public KeyFile to_keyfile() {
        var file = new KeyFile ();
        file.set_integer("PadSettings","PadType",pad_type);
        file.set_string("PadSettings","Issuer",issuer);
        file.set_string("PadSettings","AccountName",account_name);
        file.set_integer("PadSettings","Algorithm",algorithm);
        file.set_integer("PadSettings","Digits",digits);
        file.set_int64("PadSettings","Counter",counter);
        file.set_integer("PadSettings","Period",period);
        
        return file;
    }
    
    public async string to_uri () {
        var sb = new StringBuilder ();
        sb.append("otpauth://");

        switch(pad_type) {
            case TOTP:
                sb.append("totp");
                break;
            case HOTP:
                sb.append("hotp");
                break;
        }

        sb.append("/");
        sb.append(Uri.escape_string(issuer));
        sb.append(":");
        sb.append(Uri.escape_string(account_name));

        var secret_value = yield lookup_secret ();

        sb.append("?secret=");
        sb.append(secret_value);

        sb.append("&issuer=");
        sb.append(Uri.escape_string(issuer));

        if(algorithm != OneTimePadAlgorithm.SHA1){
            sb.append("&algorithm=");

            switch(algorithm) {
                case SHA1:
                    sb.append("SHA1");
                    break;
                case SHA256:
                    sb.append("SHA256");
                    break;
                case SHA512:
                    sb.append("SHA512");
                    break;
            }
        }

        if (digits != 6) {
            sb.append("&digits=");
            sb.append_printf("%d",digits);
        }

        if(pad_type == OneTimePadType.HOTP){
            sb.append("&counter=");
            sb.append_printf("%lld",counter + 1);
        }

        if(pad_type == OneTimePadType.TOTP && period != 30){
            sb.append("&period=");
            sb.append_printf("%d",period);
        }

        return (string)sb.data;
    }

    public async AegisVaultContent.AegisVaultEntry to_aegis_vault_entry () {
        AegisVaultContent.AegisVaultEntry? entry = null;
        AegisVaultContent.AegisVaultEntryInfo? info = null;

        if (pad_type == OneTimePadType.TOTP) {
            var totp_entry = new AegisVaultContent.AegisTotpVaultEntry ();
            entry = totp_entry;
            totp_entry.info = new AegisVaultContent.AegisTotpVaultEntryInfo ();
            info = totp_entry.info;

            totp_entry.info.period = period;
        }

        if (pad_type == OneTimePadType.HOTP) {
            var hotp_entry = new AegisVaultContent.AegisHotpVaultEntry ();
            entry = hotp_entry;
            hotp_entry.info = new AegisVaultContent.AegisHotpVaultEntryInfo ();
            info = hotp_entry.info;

            hotp_entry.info.counter = counter;
        }

        entry.uuid = GLib.Uuid.string_random();
        entry.name = account_name;
        entry.issuer = issuer;

        var secret_value = yield lookup_secret ();

        info.secret = secret_value;

        switch (algorithm) {
            case OneTimePadAlgorithm.SHA1:
                info.algo = "SHA1";
                break;
            case OneTimePadAlgorithm.SHA256:
                info.algo = "SHA256";
                break;
            case OneTimePadAlgorithm.SHA512:
                info.algo = "SHA512";
                break;
        }

        info.digits = digits;

        return entry;
    }

    public Variant to_variant_identifier () {
        return new Variant("(ss)", issuer, account_name);
    }

    public string get_file_name() {
        return issuer + "_" + account_name + ".txt";
    }
    
    public string get_file_name_with_issuer_in_account_name () {
        return issuer + "_" + issuer + ":" + account_name + ".txt";
    }

    public async string get_otp_code () {

        if (secret != null) {
            yield store_secret(secret);
            secret = null;
        }

        var secret_value = yield lookup_secret ();
        
        Cotp.Error error = Cotp.Error.VALID;
        
        switch(pad_type) {
            case TOTP:
                return Cotp.get_totp(secret_value, digits, period, get_cotp_algorithm(algorithm), out error);
            case HOTP:
                return Cotp.get_hotp(secret_value, ++counter, digits, get_cotp_algorithm(algorithm), out error);
        }
        
        print("Error Code: %d",error);
        
        return "";
    }
    
    public int get_remaining_time () {
        var current_date_time = new DateTime.now_utc();
        var time = current_date_time.to_unix();
        
        var base_period = (time / period);
        var next_time = (base_period + 1) * period;
        
        return (int)(next_time - time);
    }
    
    public async bool clear_secret () {
        var attributes = get_secret_attributes ();

        return yield Secret.password_clearv (schema, attributes, null);
    }

    private static Cotp.Algorithm get_cotp_algorithm(OneTimePadAlgorithm algorithm) {
        switch (algorithm) {
            case OneTimePadAlgorithm.SHA1:
                return Cotp.Algorithm.SHA1;
            case OneTimePadAlgorithm.SHA256:
                return Cotp.Algorithm.SHA256;
            case OneTimePadAlgorithm.SHA512:
                return Cotp.Algorithm.SHA512;
        }
        
        return 0;
    }

    private async void store_secret(string secret_value) {

        var attributes = get_secret_attributes ();

        var secret_label = issuer + ": " + account_name;

        yield Secret.password_storev(schema, attributes, Secret.COLLECTION_DEFAULT, secret_label, secret_value, null);
    }

    private async string lookup_secret () {
        var attributes = get_secret_attributes ();

        var secret_value = yield Secret.password_lookupv(schema, attributes, null);

        if (secret_value == null) {
            var attributes_with_issuer_in_account_name = get_secret_attributes (true);
            secret_value = yield Secret.password_lookupv(schema, attributes_with_issuer_in_account_name, null);

            if (secret_value != null) {
                yield store_secret (secret_value);
                yield Secret.password_clearv (schema, attributes_with_issuer_in_account_name, null);
            }
        }

        return secret_value;
    }

    private GLib.HashTable<string,string> get_secret_attributes (bool use_issuer_in_account_name = false) {

        var account_name_for_lookup = account_name;

        if (use_issuer_in_account_name) {
            account_name_for_lookup = issuer + ":" + account_name;
        }

        var attributes = new GLib.HashTable<string,string> (str_hash, str_equal);
        attributes["issuer"] = issuer;
        attributes["account_name"] = account_name_for_lookup;

        return attributes;
    }

    private string get_cleaned_account_name(string issuer, string account_name) {

        var prefix = issuer + ":";
        var prefix_length = prefix.char_count ();

        if(account_name.has_prefix(prefix)) {
            return account_name.substring(prefix_length);
        }

        return account_name;
    }
}

public enum OneTimePadType {
    TOTP = 0,
    HOTP = 1
}

public enum OneTimePadAlgorithm {
    SHA1 = 0,
    SHA256 = 1,
    SHA512 = 2
}
