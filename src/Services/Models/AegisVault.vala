public class AegisVault : Object {
    public int version { get; set; }
    public AegisHeader header { get; set; }
    public string db { get; set; }

    public class AegisHeader : Object, Json.Serializable {
        public AegisEncryptionParams params { get; set; }
        public Gee.List<AegisRawSlot> slots { get; set; }

        public override bool deserialize_property (string property_name, out GLib.Value value, GLib.ParamSpec pspec, Json.Node property_node) {

            // plain (unencrypted) vaults have "params": null and "slots": null
            if ((property_name == "params" || property_name == "slots") && property_node.is_null ()) {
                value = Value (pspec.value_type);
                return true;
            }

            switch (property_name) {
                case "params":
                    var parsed_params = Json.gobject_deserialize (typeof(AegisEncryptionParams), property_node) as AegisEncryptionParams;
                    value = Value(typeof(AegisEncryptionParams));
                    value.set_object (parsed_params);
                    return true;
                case "slots":
                    var parsed_slots = deserialize_slots (property_node);
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
                case "params":
                    var params = value.get_object () as AegisEncryptionParams;
                    return Json.gobject_serialize (params);
                case "slots":
                    var slots = value.get_object () as Gee.List<AegisRawSlot>;
                    var node = new Json.Node (Json.NodeType.ARRAY);

                    var node_array = new Json.Array.sized (slots.size);

                    foreach (var slot in slots) {
                        var slot_node = AegisRawSlot.serialize (slot);
                        node_array.add_element (slot_node);
                    }

                    node.init_array(node_array);

                    return node;
            }

            return default_serialize_property (property_name, value, pspec);
        }

        private Gee.List<AegisRawSlot>? deserialize_slots (Json.Node slots_node) {
            if (slots_node.get_node_type () == Json.NodeType.ARRAY) {
                var slots_array = slots_node.get_array ();
                var slots_elements = slots_array.get_elements ();

                var slots = new Gee.ArrayList<AegisRawSlot> ();

                foreach (var node in slots_elements) {
                    var slot_instance_object = node.get_object ();
                    var slot_type = slot_instance_object.get_int_member ("type");

                    print("slot type: %lld\n", slot_type);

                    if (slot_type == 0 || slot_type == 2) {
                        var raw_slot = Json.gobject_deserialize(typeof(AegisRawSlot), node) as AegisRawSlot;
                        slots.add (raw_slot);
                    }

                    if (slot_type == 1) {
                        var password_slot = Json.gobject_deserialize(typeof(AegisPasswordSlot), node) as AegisPasswordSlot;
                        slots.add (password_slot);
                    }

                }

                return slots;
            } else {
                return null;
            }
        }
    }

    public class AegisRawSlot : Object, Json.Serializable {
        public string uuid { get; set; }
        public string key { get; set; }
        public AegisEncryptionParams key_params { get; set; }
        public bool repaired { get; set; }
        public int slot_type { get; set;}

        public static Json.Node serialize (AegisRawSlot slot) {
            return Mauborgne.JsonHelpers.serialize_renamed (slot, { "key-params", "key_params", "slot-type", "type" });
        }

        public override unowned ParamSpec? find_property (string name) {
            if (name == "type") {
                name = "slot-type";
            } else if (name == "key_params") {
                name = "key-params";
            }

            var clazz = (ObjectClass)get_type ().class_ref ();
            return clazz.find_property (name);
        }
    }

    public class AegisPasswordSlot : AegisRawSlot {
        public int n { get; set; }
        public int r { get; set; }
        public int p { get; set; }
        public string salt { get; set; }

        construct {
            slot_type = 1;
        }
    }

    public class AegisEncryptionParams : Object {
        public string nonce { get; set;}
        public string tag { get; set; }
    }
}
