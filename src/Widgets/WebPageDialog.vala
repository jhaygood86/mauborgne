/**
 * A web page inside the app, for signing in to or signing up with the Customer Portal.
 * Pass a redirect_prefix to catch the OAuth redirect: navigating to it is stopped and
 * reported through redirected, so nothing has to listen on that address.
 */
public class WebPageDialog : Adw.Dialog {

    public signal void redirected (string uri);

    public string start_url { get; construct; }
    public string? redirect_prefix { get; construct; }

    private WebKit.WebView web_view;

    public WebPageDialog (string title, string start_url, string? redirect_prefix = null) {
        Object (title: title, start_url: start_url, redirect_prefix: redirect_prefix);
    }

    construct {
        content_width = 520;
        content_height = 680;

        // Nothing about the Portal session is kept: signing in again later starts fresh.
        web_view = (WebKit.WebView) Object.new (typeof (WebKit.WebView),
            "network-session", new WebKit.NetworkSession.ephemeral ());
        web_view.vexpand = true;
        web_view.hexpand = true;

        web_view.decide_policy.connect (on_decide_policy);
        web_view.load_failed.connect (on_load_failed);

        var header = new Adw.HeaderBar ();
        var window_title = new Adw.WindowTitle (title, "");
        header.title_widget = window_title;

        web_view.notify["title"].connect (() => {
            if (web_view.title != null && web_view.title != "") {
                window_title.title = web_view.title;
            }
        });

        var toolbar_view = new Adw.ToolbarView ();
        toolbar_view.add_top_bar (header);
        toolbar_view.content = web_view;

        child = toolbar_view;

        web_view.load_uri (start_url);
    }

    /** Lets a test make the page navigate, standing in for the Portal's redirect. */
    internal void run_script_for_test (string script) {
        web_view.evaluate_javascript.begin (script, -1, null, null, null);
    }

    private bool is_redirect (string? uri) {
        return redirect_prefix != null && uri != null && uri.has_prefix (redirect_prefix);
    }

    private bool on_decide_policy (WebKit.PolicyDecision decision, WebKit.PolicyDecisionType type) {
        if (type != WebKit.PolicyDecisionType.NAVIGATION_ACTION && type != WebKit.PolicyDecisionType.NEW_WINDOW_ACTION) {
            return false;
        }

        var navigation = decision as WebKit.NavigationPolicyDecision;
        var uri = navigation.navigation_action.get_request ().get_uri ();

        if (is_redirect (uri)) {
            decision.ignore ();
            redirected (uri);
            return true;
        }

        if (type == WebKit.PolicyDecisionType.NEW_WINDOW_ACTION) {
            // links that want a new window open in this one
            decision.ignore ();
            web_view.load_uri (uri);
            return true;
        }

        return false;
    }

    private bool on_load_failed (WebKit.LoadEvent event, string failing_uri, Error error) {
        // nothing listens on the redirect address; seeing it fail is also how a redirect arrives
        if (is_redirect (failing_uri)) {
            redirected (failing_uri);
            return true;
        }

        return false;
    }
}

/** Shows the Customer Portal sign-in in an embedded web view and catches the OAuth redirect. */
public class WebViewAuthorizationBrowser : Object, AuthorizationBrowser {

    private const int FIRST_PORT = 49152;
    private const int PORT_COUNT = 16384;

    private Gtk.Window parent;

    public WebViewAuthorizationBrowser (Gtk.Window parent) {
        this.parent = parent;
    }

    public async AuthorizationCallback authorize (BuildAuthorizeUrl build_url) throws Error {
        // The CRM accepts any loopback port, so this address needs no registration; the web view
        // stops the navigation before anything connects.
        var redirect = "http://127.0.0.1:%d/callback".printf (FIRST_PORT + Random.int_range (0, PORT_COUNT));

        var dialog = new WebPageDialog (_("Sign in to Cloud Backup"), build_url (redirect), redirect);

        AuthorizationCallback? result = null;
        var finished = false;
        SourceFunc resume = authorize.callback;

        dialog.redirected.connect ((uri) => {
            if (result == null) {
                result = parse_callback (uri);
                dialog.force_close ();
            }
        });

        dialog.closed.connect (() => {
            if (!finished) {
                finished = true;
                resume ();
            }
        });

        dialog.present (parent);
        yield;

        if (result == null) {
            throw new LicenseSignInError.CANCELLED ("Sign-in was closed");
        }

        return result;
    }

    internal static AuthorizationCallback parse_callback (string uri) {
        string? code = null;
        string? state = null;
        string? error = null;

        try {
            var parsed = Uri.parse (uri, UriFlags.PARSE_RELAXED);
            var query = parsed.get_query ();

            if (query != null) {
                var parameters = Uri.parse_params (query);
                code = parameters.lookup ("code");
                state = parameters.lookup ("state");
                error = parameters.lookup ("error");
            }
        } catch (Error e) {
            error = "invalid_redirect";
        }

        return new AuthorizationCallback (code, state, error);
    }
}
