public class AegisVaultContent : Object, Json.Serializable  {
    public int version { get; set;}
    public Gee.List<AegisTotpVaultEntry> entries { get; set;}

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

    private Gee.List<AegisTotpVaultEntry>? deserialize_entries (Json.Node entries_node) {
        if (entries_node.get_node_type () == Json.NodeType.ARRAY) {
            var entries_array = entries_node.get_array ();
            var entries_elements = entries_array.get_elements ();

            var entries = new Gee.ArrayList<AegisTotpVaultEntry> ();

            foreach (var node in entries_elements) {
                var entry = Json.gobject_deserialize(typeof(AegisTotpVaultEntry), node) as AegisTotpVaultEntry;
                entries.add (entry);
            }

            return entries;
        } else {
            return null;
        }
    }

    public class AegisTotpVaultEntry : Object {
        public string uuid { get; set; }
        public string name { get; set; }
        public string issuer { get; set; }
        public string note { get; set; }
        public AegisTotpVaultEntryInfo info { get; set; }
    }

    public class AegisTotpVaultEntryInfo : Object {
        public string secret { get; set; }
        public string algo { get; set; }
        public int digits { get; set; }
        public int period { get; set; }
    }
}
