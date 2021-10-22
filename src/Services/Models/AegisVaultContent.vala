public class AegisVaultContent : Object, Json.Serializable  {
    public int version { get; set;}
    public Gee.List<AegisVaultEntry> entries { get; set;}

    public override bool deserialize_property (string property_name, out GLib.Value value, GLib.ParamSpec pspec, Json.Node property_node) {

        switch (property_name) {
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
            case "entries":
                var entries = value.get_object () as Gee.List<AegisVaultEntry>;
                var node = new Json.Node (Json.NodeType.ARRAY);

                var node_array = new Json.Array.sized (entries.size);

                foreach (var entry in entries) {
                    var entry_node = Json.gobject_serialize (entry);
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

        public override string get_member_name (ParamSpec pspec) {
            if (pspec.name == "entry-type") {
                return "type";
            }

            return pspec.name;
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
