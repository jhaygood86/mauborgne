/**
 * Gets the user's license from the CRM via OAuth 2.0 authorization code + PKCE (public client,
 * RFC 8252), keeps it, and renews it. The license is the access token: the RS256 JWT the Customer
 * Portal shows. The Cloud Backup server verifies its signature on every request, so this app only
 * reads its expiry. A port of OAuthLicenseProvider.cs.
 */
public errordomain LicenseSignInError {
    /** The user closed the sign-in, denied access, or the wait timed out. */
    CANCELLED,
    /** Signed in, but the account holds no subscription or seat for Mauborgne: offer sign-up. */
    NO_ENTITLEMENT,
    /** Anything else: network trouble, the Portal being unavailable, a mismatched response. */
    FAILED
}

/** The query string the Portal redirected back with. */
public class AuthorizationCallback : Object {
    public string? code { get; construct; }
    public string? state { get; construct; }
    public string? error { get; construct; }

    public AuthorizationCallback (string? code, string? state, string? error) {
        Object (code: code, state: state, error: error);
    }
}

public delegate string BuildAuthorizeUrl (string redirect_uri);

/**
 * Sends the user to the Portal's authorization page and catches the redirect. The app shows the
 * Portal in an embedded web view, so there is no external browser and no listening socket.
 */
public interface AuthorizationBrowser : Object {
    /**
     * Picks a redirect URI, passes it to build_url, shows the resulting page and waits for the
     * redirect to that URI. Throws LicenseSignInError.CANCELLED if the user closes it first.
     */
    public abstract async AuthorizationCallback authorize (BuildAuthorizeUrl build_url) throws Error;
}

/** Persists the license JWT on this device. The JWT is not a password, but it names the user. */
public interface LicenseStore : Object {
    public abstract string? load ();
    public abstract void save (string license);
    public abstract void clear ();
}

/** The license kept in the user's keyring. */
public class KeyringLicenseStore : Object, LicenseStore {

    private static Secret.Schema schema = new Secret.Schema (
        "io.github.jhaygood86.mauborgne.license", Secret.SchemaFlags.NONE,
        "kind", Secret.SchemaAttributeType.STRING);

    public string? load () {
        try {
            return Secret.password_lookup_sync (schema, null, "kind", "license");
        } catch (Error e) {
            warning ("Could not read the license from the keyring: %s", e.message);
            return null;
        }
    }

    public void save (string license) {
        try {
            Secret.password_store_sync (schema, Secret.COLLECTION_DEFAULT, "Mauborgne Cloud Backup license", license, null, "kind", "license");
        } catch (Error e) {
            warning ("Could not store the license in the keyring: %s", e.message);
        }
    }

    public void clear () {
        try {
            Secret.password_clear_sync (schema, null, "kind", "license");
        } catch (Error e) {
            warning ("Could not remove the license from the keyring: %s", e.message);
        }
    }
}

public class LicenseService : Object, LicenseProvider {

    public const string DEFAULT_PORTAL_URL = "https://customer.peachstatetechnologies.com/";
    public const string DEFAULT_API_URL = "https://api.crm.peachstatetechnologies.com/";

    /** Renew once the license is this close to expiry (it is also renewed after expiry). */
    private const int64 RENEW_WINDOW_SECONDS = 14 * 24 * 60 * 60;

    /** Do not hammer the renewal endpoint: one attempt per token per interval. */
    private const int64 RENEW_RETRY_SECONDS = 60 * 60;

    // The license verification key. Public by design; the CRM signs licenses with the private half.
    public const string PUBLIC_KEY_PEM_BODY =
        "MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA0JUEabC+3k0Oe2arF001" +
        "5DswotC9jYBaoKWDqVDVSCObzCA0uJc9AOUUgA1Noh4HdYVZKbptqJ4h9RI5IMAA" +
        "3MwYLZJhHtkZlh1CGH8gCq7D9FHLg5LRGLUNpjX6Bj9r3Rhy5bU7Hu3JlU+5yrSV" +
        "06dKCqM7JsHnX+hdJ+EKZpiQzaQEOAWCPkvivdjmjYxCpnECVboyn6qAvgYIMCgb" +
        "QaydZMgVoIViOv0R8G7EwRP82LSnmlBaIbU+LQsYPTO3LYxQVjSrFrD0WBIeS0FT" +
        "1ZNJY4yetvNM4ps5ie8G7al888PCXptAe2g+Mk2QRsopqXFAIgkYYYkMvBBRkcft" +
        "mQIDAQAB";

    private Soup.Session http;
    private AuthorizationBrowser browser;
    private LicenseStore store;
    private string portal_url;
    private string api_url;

    private string? last_renew_token = null;
    private int64 last_renew_attempt = 0;
    private bool refreshing = false;

    public LicenseService (AuthorizationBrowser browser, LicenseStore store) {
        this.browser = browser;
        this.store = store;
        this.http = new Soup.Session () {
            user_agent = "Mauborgne/%s".printf (VERSION)
        };

        this.portal_url = with_trailing_slash (Environment.get_variable ("MAUBORGNE_PORTAL_URL") ?? DEFAULT_PORTAL_URL);
        this.api_url = with_trailing_slash (Environment.get_variable ("MAUBORGNE_API_URL") ?? DEFAULT_API_URL);
    }

    private static string with_trailing_slash (string url) {
        return url.has_suffix ("/") ? url : url + "/";
    }

    // ---- LicenseProvider -----------------------------------------------------------------

    /**
     * The stored license, renewed when due. Returns null when there is no usable license (never
     * signed in, unreadable, or the CRM says the seat or subscription is gone), which sends the user
     * to sign in. An expired license whose renewal could not be reached is still returned: the
     * server answers "expired", which is the accurate message.
     */
    public async string? get_license () throws Error {
        var token = store.load ();

        if (token == null || token == "") {
            return null;
        }

        var claims = read_claims (token);

        if (claims == null) {
            store.clear ();
            return null;
        }

        var now = new DateTime.now_utc ().to_unix ();
        var due = now >= claims.expires_at || claims.expires_at - now <= RENEW_WINDOW_SECONDS;

        if (!due || !should_attempt_renewal (token, now) || refreshing) {
            return token;
        }

        refreshing = true;
        last_renew_token = token;
        last_renew_attempt = now;

        try {
            string? renewed = null;
            var revoked = yield renew (token, out renewed);

            if (revoked) {
                return null;
            }

            return renewed ?? token;
        } finally {
            refreshing = false;
        }
    }

    // ---- sign-in -------------------------------------------------------------------------

    /** True if a license is stored (it may be expired). */
    public bool has_license () {
        var token = store.load ();

        return token != null && token != "" && read_claims (token) != null;
    }

    public void sign_out () {
        store.clear ();
        last_renew_token = null;
    }

    /**
     * Signs the user in to the Customer Portal and stores the license it issues.
     * Throws LicenseSignInError.
     */
    public async void sign_in () throws Error {
        string verifier, challenge;
        new_pkce_pair (out verifier, out challenge);

        var state = base64_url (random_bytes (24));
        var client_id = LicenseService.client_id ();
        string? used_redirect = null;

        AuthorizationCallback callback;

        callback = yield browser.authorize ((redirect) => {
            used_redirect = redirect;
            return authorize_url (client_id, redirect, challenge, state);
        });

        // A mismatched state means the redirect did not answer our request: never redeem it.
        if (callback.state != state) {
            throw new LicenseSignInError.FAILED ("The sign-in response did not match the request.");
        }

        if (callback.error != null) {
            if (callback.error == "access_denied") {
                throw new LicenseSignInError.CANCELLED ("Sign-in was declined");
            }

            throw new LicenseSignInError.FAILED ("%s", callback.error);
        }

        if (callback.code == null || callback.code == "" || used_redirect == null) {
            throw new LicenseSignInError.FAILED ("The sign-in response had no code.");
        }

        var token = yield redeem (client_id, callback.code, verifier, used_redirect);

        if (read_claims (token) == null) {
            throw new LicenseSignInError.FAILED ("The Portal returned a license this app cannot read.");
        }

        store.save (token);
        last_renew_token = null;
    }

    // ---- protocol ------------------------------------------------------------------------

    private string authorize_url (string client_id, string redirect, string challenge, string state) {
        var query = "response_type=code"
            + "&client_id=" + Uri.escape_string (client_id, null, true)
            + "&redirect_uri=" + Uri.escape_string (redirect, null, true)
            + "&code_challenge=" + Uri.escape_string (challenge, null, true)
            + "&code_challenge_method=S256"
            + "&state=" + Uri.escape_string (state, null, true);

        return portal_url + "oauth/authorize?" + query;
    }

    private async string redeem (string client_id, string code, string verifier, string redirect) throws Error {
        var fields = new HashTable<string, string> (str_hash, str_equal);
        fields["grant_type"] = "authorization_code";
        fields["code"] = code;
        fields["code_verifier"] = verifier;
        fields["redirect_uri"] = redirect;
        fields["client_id"] = client_id;

        var form = Soup.Form.encode_hash (fields);

        var message = new Soup.Message.from_encoded_form ("POST", portal_url + "oauth/token", form);

        Bytes response;

        try {
            response = yield http.send_and_read_async (message, Priority.DEFAULT, null);
        } catch (Error e) {
            throw new LicenseSignInError.FAILED ("Could not reach the Customer Portal.");
        }

        var body = bytes_to_string (response);
        var status = (uint) message.status_code;

        if (status >= 200 && status < 300) {
            var token = read_string (body, "access_token");

            if (token == null) {
                throw new LicenseSignInError.FAILED ("The Portal returned no license.");
            }

            return token;
        }

        // invalid_grant covers "this contact has no subscription or seat for the software".
        var error = read_string (body, "error");

        if (error == "invalid_grant") {
            throw new LicenseSignInError.NO_ENTITLEMENT ("No subscription found");
        }

        throw new LicenseSignInError.FAILED ("%s", error ?? status.to_string ());
    }

    /** Returns true if the CRM refused for good (the stored license was cleared). */
    private async bool renew (string token, out string? renewed) throws Error {
        renewed = null;

        var body = new Json.Object ();
        body.set_string_member ("licenseKey", token);

        var node = new Json.Node (Json.NodeType.OBJECT);
        node.set_object (body);

        var generator = new Json.Generator ();
        generator.set_root (node);

        var message = new Soup.Message ("POST", api_url + "api/license/renew");
        message.set_request_body_from_bytes ("application/json", new Bytes (generator.to_data (null).data));

        Bytes response;

        try {
            response = yield http.send_and_read_async (message, Priority.DEFAULT, null);
        } catch (Error e) {
            // offline or busy: keep what we have
            return false;
        }

        switch ((uint) message.status_code) {
            case 200:
                var new_token = read_string (bytes_to_string (response), "token");

                if (new_token != null && read_claims (new_token) != null) {
                    store.save (new_token);
                    renewed = new_token;
                }

                return false;
            case 402:
                store.clear ();
                return true;
            default:
                // 204 (nothing to renew yet), 404, 5xx, ...
                return false;
        }
    }

    private bool should_attempt_renewal (string token, int64 now) {
        return last_renew_token != token || now - last_renew_attempt >= RENEW_RETRY_SECONDS;
    }

    // ---- JWT and PKCE helpers ------------------------------------------------------------

    public class LicenseClaims : Object {
        public int64 expires_at { get; construct; }
        public string? contact_id { get; construct; }
        public string? subscription_id { get; construct; }

        public LicenseClaims (int64 expires_at, string? contact_id, string? subscription_id) {
            Object (expires_at: expires_at, contact_id: contact_id, subscription_id: subscription_id);
        }
    }

    /** Reads the claims of a license JWT, or null if it is not one. The signature is not checked here. */
    public static LicenseClaims? read_claims (string token) {
        var parts = token.split (".");

        if (parts.length != 3) {
            return null;
        }

        var parser = new Json.Parser ();

        try {
            var header = bytes_to_string (new Bytes (base64_url_decode (parts[0])));
            parser.load_from_data (header);

            var header_root = parser.get_root ();

            if (header_root == null || header_root.get_node_type () != Json.NodeType.OBJECT
                || !header_root.get_object ().has_member ("alg") || header_root.get_object ().get_string_member ("alg") != "RS256") {
                return null;
            }

            parser.load_from_data (bytes_to_string (new Bytes (base64_url_decode (parts[1]))));
        } catch (Error e) {
            return null;
        }

        var root = parser.get_root ();

        if (root == null || root.get_node_type () != Json.NodeType.OBJECT) {
            return null;
        }

        var claims = root.get_object ();

        if (!claims.has_member ("exp") || claims.get_member ("exp").get_value_type () != typeof (int64)) {
            return null;
        }

        return new LicenseClaims (claims.get_int_member ("exp"), claim_text (claims, "contactId"), claim_text (claims, "subscriptionId"));
    }

    private static string? claim_text (Json.Object claims, string name) {
        if (!claims.has_member (name)) {
            return null;
        }

        var node = claims.get_member (name);

        if (node.get_node_type () != Json.NodeType.VALUE) {
            return null;
        }

        if (node.get_value_type () == typeof (string)) {
            return node.get_string ();
        }

        if (node.get_value_type () == typeof (int64)) {
            return node.get_int ().to_string ();
        }

        return null;
    }

    /**
     * The CRM derives the client id from the app's embedded public key, which is how it knows which
     * software (and signing key) the license is for: base64url(SHA-256(DER SubjectPublicKeyInfo)).
     * The PEM body is that DER, base64 encoded.
     */
    public static string client_id (string public_key_body = PUBLIC_KEY_PEM_BODY) {
        var der = Base64.decode (public_key_body);
        var digest = new uint8[32];
        GCrypt.Hash.hash_buffer (GCrypt.Hash.Algorithm.SHA256, digest, der);

        return base64_url (digest);
    }

    /** A code verifier (43 chars) and its S256 challenge. */
    public static void new_pkce_pair (out string verifier, out string challenge) {
        verifier = base64_url (random_bytes (32));
        challenge = pkce_challenge (verifier);
    }

    public static string pkce_challenge (string verifier) {
        var digest = new uint8[32];
        GCrypt.Hash.hash_buffer (GCrypt.Hash.Algorithm.SHA256, digest, verifier.data);

        return base64_url (digest);
    }

    private static uint8[] random_bytes (int length) {
        var bytes = new uint8[length];
        GCrypt.Random.randomize (bytes);

        return bytes;
    }

    public static string base64_url (uint8[] data) {
        return Base64.encode (data).replace ("=", "").replace ("+", "-").replace ("/", "_");
    }

    public static uint8[] base64_url_decode (string text) {
        var standard = text.replace ("-", "+").replace ("_", "/");

        while (standard.length % 4 != 0) {
            standard += "=";
        }

        return Base64.decode (standard);
    }

    private static string bytes_to_string (Bytes bytes) {
        var data = bytes.get_data ();
        var builder = new StringBuilder.sized (data.length);
        builder.append_len ((string) data, data.length);

        return builder.str;
    }

    private static string? read_string (string json, string name) {
        var parser = new Json.Parser ();

        try {
            parser.load_from_data (json);
        } catch (Error e) {
            return null;
        }

        var root = parser.get_root ();

        if (root == null || root.get_node_type () != Json.NodeType.OBJECT) {
            return null;
        }

        var object = root.get_object ();

        if (!object.has_member (name) || object.get_member (name).get_value_type () != typeof (string)) {
            return null;
        }

        return object.get_string_member (name);
    }
}
