public class AegisVaultContent : Object, Json.Serializable  {
    public int version { get; set;}
    public Gee.List<AegisVaultEntry> entries { get; set;}

    // ---- Mauborgne sync extensions (cloud payloads only; Aegis ignores unknown members) ----

    /** Pads deleted on some device: "{issuer}:{account}" to deletion time (Unix ms). Written as mb_deleted. */
    public Gee.Map<string, int64?>? deleted { get; set; default = null; }

    /** When the order of the entries last changed (Unix ms). Written as mb_order_modified. */
    public int64 order_modified { get; set; }

    /** The content as the JSON that goes into a vault, with the sync extensions named as the other apps expect. */
    public string to_json () {
        var node = Mauborgne.JsonHelpers.serialize_renamed (this, {
            "deleted", "mb_deleted",
            "order-modified", "mb_order_modified"
        });

        var generator = new Json.Generator ();
        generator.set_root (node);

        return generator.to_data (null);
    }

    public override unowned ParamSpec? find_property (string name) {
        var clazz = (ObjectClass)get_type ().class_ref ();

        switch (name) {
            case "mb_deleted":
                return clazz.find_property ("deleted");
            case "mb_order_modified":
                return clazz.find_property ("order-modified");
            default:
                return clazz.find_property (name);
        }
    }

    public override bool deserialize_property (string property_name, out GLib.Value value, GLib.ParamSpec pspec, Json.Node property_node) {

        switch (property_name) {
            case "deleted":
                value = Value (typeof (Gee.Map));

                if (property_node.get_node_type () == Json.NodeType.OBJECT) {
                    var map = new Gee.HashMap<string, int64?> ();

                    property_node.get_object ().foreach_member ((object, name, node) => {
                        map[name] = node.get_int ();
                    });

                    value.set_object (map);
                }

                return true;
            case "order-modified":
                value = Value (typeof (int64));
                value.set_int64 (property_node.get_node_type () == Json.NodeType.VALUE ? property_node.get_int () : 0);
                return true;
            case "version":
                var parsed_version = (int)property_node.get_int ();
                value = Value(typeof(int));
                value.set_int(parsed_version);
                return true;
            case "entries":
                var parsed_slots = deserialize_entries (property_node);
                value = Value(typeof(Gee.List));

                if (parsed_slots != null) {
                    value.set_object (parsed_slots);
                    return true;
                } else {
                    return false;
                }
        }

        return false;
    }

    public override Json.Node serialize_property (string property_name, GLib.Value value, ParamSpec pspec) {

        switch (property_name) {
            case "version":
                var version = value.get_int ();
                var node = new Json.Node (Json.NodeType.VALUE);
                node.init_int(version);
                return node;
            case "deleted":
                var node = new Json.Node (Json.NodeType.OBJECT);
                var object = new Json.Object ();
                var deleted_map = value.get_object () as Gee.Map<string, int64?>;

                if (deleted_map != null) {
                    foreach (var entry in deleted_map.entries) {
                        object.set_int_member (entry.key, entry.value);
                    }
                }

                node.init_object (object);
                return node;
            case "entries":
                var entries = value.get_object () as Gee.List<AegisVaultEntry>;
                var node = new Json.Node (Json.NodeType.ARRAY);

                var node_array = new Json.Array.sized (entries.size);

                foreach (var entry in entries) {
                    var entry_node = AegisVaultEntry.serialize (entry);
                    node_array.add_element (entry_node);
                }

                node.init_array(node_array);

                return node;
        }

        return default_serialize_property (property_name, value, pspec);
    }

    private Gee.List<AegisVaultEntry>? deserialize_entries (Json.Node entries_node) {
        if (entries_node.get_node_type () == Json.NodeType.ARRAY) {
            var entries_array = entries_node.get_array ();
            var entries_elements = entries_array.get_elements ();

            var entries = new Gee.ArrayList<AegisVaultEntry> ();

            foreach (var node in entries_elements) {
                var entry_instance_object = node.get_object ();
                var entry_type = entry_instance_object.get_string_member ("type");
                var entry_info = entry_instance_object.get_member ("info");

                if (entry_type == "totp") {
                    var entry = Json.gobject_deserialize(typeof(AegisTotpVaultEntry), node) as AegisTotpVaultEntry;

                    var info = Json.gobject_deserialize (typeof(AegisTotpVaultEntryInfo), entry_info) as AegisTotpVaultEntryInfo;
                    entry.info = info;

                    entries.add (entry);
                }

                if (entry_type == "hotp") {
                    var entry = Json.gobject_deserialize(typeof(AegisHotpVaultEntry), node) as AegisHotpVaultEntry;

                    var info = Json.gobject_deserialize (typeof(AegisHotpVaultEntryInfo), entry_info) as AegisHotpVaultEntryInfo;
                    entry.info = info;

                    entries.add (entry);
                }
            }

            return entries;
        } else {
            return null;
        }
    }

    public abstract class AegisVaultEntry : Object, Json.Serializable {
        public string uuid { get; set; }
        public string name { get; set; }
        public string issuer { get; set; }
        public string note { get; set; default = ""; }
        public string entry_type { get; set; }
        public string? icon { get; set; default = null; }

        // sync extensions: written as mb_modified and mb_display
        public int64 modified { get; set; }
        public string? display_name { get; set; default = null; }

        public static Json.Node serialize (AegisVaultEntry entry) {
            return Mauborgne.JsonHelpers.serialize_renamed (entry, {
                "entry-type", "type",
                "modified", "mb_modified",
                "display-name", "mb_display"
            });
        }

        public override unowned ParamSpec? find_property (string name) {
            var clazz = (ObjectClass)get_type ().class_ref ();

            switch (name) {
                case "type":
                    return clazz.find_property ("entry-type");
                case "mb_modified":
                    return clazz.find_property ("modified");
                case "mb_display":
                    return clazz.find_property ("display-name");
                default:
                    return clazz.find_property (name);
            }
        }

        public override Json.Node serialize_property (string property_name, Value value, ParamSpec pspec) {

            print ("serializing property: %s\n", property_name);

            if (property_name == "icon") {
                var node = new Json.Node (Json.NodeType.NULL);
                node.init_null ();
                return node;
            }

            return default_serialize_property (property_name, value, pspec);
        }
    }

    public class AegisTotpVaultEntry : AegisVaultEntry {
        public AegisTotpVaultEntryInfo info { get; set;}

        construct {
            entry_type = "totp";
        }
    }

    public class AegisHotpVaultEntry : AegisVaultEntry {
        public AegisHotpVaultEntryInfo info { get; set; }

        construct {
            entry_type = "hotp";
        }
    }

    public abstract class AegisVaultEntryInfo : Object {
        public string secret { get; set; }
        public string algo { get; set; }
        public int digits { get; set; }
    }

    public class AegisTotpVaultEntryInfo : AegisVaultEntryInfo {
        public int period { get; set; }
    }

    public class AegisHotpVaultEntryInfo : AegisVaultEntryInfo {
        public int64 counter { get; set; }
    }
}
