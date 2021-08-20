public class OneTimePad {
    public OneTimePadType pad_type { get; set; }
    public string issuer { get; set; }
    public string account_name { get; set; }
    public string secret { get; set; }
    public OneTimePadAlgorithm algorithm { get; set; }
    public int digits { get; set; }
    public int counter { get; set; }
    public int period { get; set; }
    
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
                counter = int.parse(counter_value);
            }
            
            if(uri_params.contains ("period")){
                var period_value = uri_params["period"];
                period = int.parse(period_value);
            }
            
        }
    }
    
    public OneTimePad.from_keyfile(KeyFile file){
        pad_type = (OneTimePadType)file.get_integer("PadSettings","PadType");
        issuer = file.get_string("PadSettings","Issuer");
        account_name = file.get_string("PadSettings","AccountName");
        secret = file.get_string("PadSettings","Secret");
        algorithm = (OneTimePadAlgorithm)file.get_integer("PadSettings","Algorithm");
        digits = file.get_integer("PadSettings","Digits");
        counter = file.get_integer("PadSettings","Counter");
        period = file.get_integer("PadSettings","Period");
    }
    
    public KeyFile to_keyfile() {
        var file = new KeyFile ();
        file.set_integer("PadSettings","PadType",pad_type);
        file.set_string("PadSettings","Issuer",issuer);
        file.set_string("PadSettings","AccountName",account_name);
        file.set_string("PadSettings","Secret",secret);
        file.set_integer("PadSettings","Algorithm",algorithm);
        file.set_integer("PadSettings","Digits",digits);
        file.set_integer("PadSettings","Counter",counter);
        file.set_integer("PadSettings","Period",period);
        
        return file;
    }
    
    public string get_file_name() {
        return issuer + "_" + account_name + ".txt";
    }
    
    public void save_to_file() {
        var file = to_keyfile ();
        var file_name = get_file_name();
        
    }
    
    public string get_otp_code () {
        
        Cotp.Error error = Cotp.Error.VALID;
        
        switch(pad_type) {
            case TOTP:
                return Cotp.get_totp(secret, digits, period, get_cotp_algorithm(algorithm), out error);
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
