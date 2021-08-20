[CCode (cheader_filename = "libportal/portal.h,libportal/portal-gtk3.h", lower_case_cprefix = "xdp_")]
namespace Xdp {

    [CCode(cname = "XdpPortal", unref_function = "")]
    public class Portal {
    
        [CCode(cname = "xdp_portal_new")]
        public Portal();
        
        /* Screenshot */
        
        [CCode(cname = "xdp_portal_take_screenshot")]
        public async string take_screenshot(ParentWindow parent, ScreenshotFlags flags, GLib.Cancellable? cancellable = null) throws GLib.Error; 
    }
    
    [CCode(cname = "XdpParent", free_function = "xdp_parent_free", has_type_id = false)]
    [Compact]
    public class ParentWindow {
    
        [CCode(cname = "xdp_parent_new_gtk")]
        public static ParentWindow new_gtk(Gtk.Window window);
    }
    
    [CCode (cname = "XdpScreenshotFlags", cprefix = "XDP_SCREENSHOT_FLAG_", has_type_id = false)]
    public enum ScreenshotFlags {
        NONE = 0,
        INTERACTIVE = 1 << 0
    }
}
