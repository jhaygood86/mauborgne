namespace Mauborgne.JsonHelpers {
    /**
     * Serializes a GObject with Json.gobject_serialize, then renames the
     * resulting members. Stock json-glib always uses the GParamSpec name as
     * the JSON key, so formats that need other keys (e.g. "type") are fixed up
     * afterwards. `renames` is a flat list of old, new, old, new, ...
     */
    public Json.Node serialize_renamed (Object object, string[] renames) {
        var node = Json.gobject_serialize (object);
        var json_object = node.get_object ();

        for (int i = 0; i + 1 < renames.length; i += 2) {
            if (json_object.has_member (renames[i])) {
                var member = json_object.dup_member (renames[i]);
                json_object.remove_member (renames[i]);
                json_object.set_member (renames[i + 1], (owned) member);
            }
        }

        return node;
    }
}
