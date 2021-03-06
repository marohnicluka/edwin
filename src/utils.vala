/* utils.vala
 *
 * Copyright 2017 Luka Marohnić
 *
 * This file is part of Edwin, a simple document writer for elementary OS.
 *
 * Edwin is free software: you can redistribute it
 * and/or modify it under the terms of the GNU General Public License as
 * published by the Free Software Foundation, either version 3 of the
 * License, or (at your option) any later version.
 *
 * Edwin is distributed in the hope that it will be
 * useful, but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General
 * Public License for more details.
 *
 * You should have received a copy of the GNU General Public License along
 * with Edwin. If not, see http://www.gnu.org/licenses/.
 */

namespace Edwin.Utils {

    public const int INCH = 72;
    
    public Gdk.RGBA get_color (string id, double alpha = 1.0) {
        var rgba = Gdk.RGBA ();
        switch (id) {
        case "page-border":
            rgba.parse ("#c6c6c6");
            break;
        case "alert":
            rgba.parse ("#ef2929");
            break;
        case "highlight":
            rgba.parse ("#fce94f");
            break;
        case "selection":
            rgba.parse ("#268bd2");
            break;
        case "selection-unfocused":
            rgba.parse ("#d3d7cf");
            break;
        case "white":
            rgba.parse ("#ffffff");
            break;
        case "transparent":
            rgba = {0, 0, 0, 0};
            return rgba;
        default:
            assert_not_reached ();
        }
        rgba.alpha = alpha;
        return rgba;
    }

    /**
     *  Get dpi for the default screen.
     */
    public double get_dpi () {
        var screen = Gdk.Screen.get_default ();
        return screen.get_resolution ();
    }

    /**
     *  Convert points to pixels with respect to the screen resolution,
     *  scaling the result value by FACTOR.
     */
    public int to_pixels (double points, double factor = 1.0) {
        return (int) Math.round (points * factor * Utils.get_dpi () / INCH);
    }
    
    /**
     *  Create and return CssProvider with given stylesheet loaded.
     */
    public Gtk.CssProvider? get_css_provider (string stylesheet) {
        var provider = new Gtk.CssProvider ();
        try {
            provider.load_from_data (stylesheet, -1);
        } catch (Error e) {
            warning (e.message);
            return null;
        }
        return provider;
    }
    
    /**
     *  Apply stylesheet to widget.
     */
    public void apply_stylesheet (Gtk.Widget widget, string stylesheet) {
        var provider = get_css_provider (stylesheet);
        if (provider != null) {
            var context = widget.get_style_context ();
            var priority = Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION;
            context.add_provider (provider, priority);
        }
    }

    public void draw_rectangle (Cairo.Context cr, Gdk.Rectangle rect, string color_id) {
        Gdk.cairo_set_source_rgba (cr, get_color (color_id));
        Gdk.cairo_rectangle (cr, rect);
        cr.stroke ();
    }
    
    public void fill_rectangle (Cairo.Context cr, Gdk.Rectangle rect, Gdk.RGBA color) {
        Gdk.cairo_set_source_rgba (cr, color);
        Gdk.cairo_rectangle (cr, rect);
        cr.fill ();
    }
    
    public void refresh_gui () {
        while (Gtk.events_pending ()) {
            Gtk.main_iteration ();
        }
    }
    
    public Gtk.Image get_icon (string name) {
        var spec = name.split ("::");
        assert (spec.length == 2);
        var base_path = App.instance.resource_path ();
        var path = Path.build_filename (base_path, "resources", "icons", spec[0], spec[1] + ".png");
        return new Gtk.Image.from_resource (path);
    }
        
    public Gtk.ToolButton create_tool_button (string icon_name, string? action_name, string? tip) {
        var image = "::" in icon_name ?
            get_icon (icon_name) : new Gtk.Image.from_icon_name (icon_name, Gtk.IconSize.BUTTON);
        var button = new Gtk.ToolButton (image, null);
        if (action_name != null) {
            button.set_action_name (action_name);
        }
        button.set_tooltip_text (tip);
        return button;
    }
        
    public Gtk.ToggleToolButton create_toggle_button (string icon_name, string? action_name, string? tip) {
        var image = "::" in icon_name ?
            get_icon (icon_name) : new Gtk.Image.from_icon_name (icon_name, Gtk.IconSize.BUTTON);
        var button = new Gtk.ToggleToolButton ();
        button.set_icon_widget (image);
        if (action_name != null) {
            button.set_action_name (action_name);
        }
        button.set_tooltip_text (tip);
        return button;
    }
    
	public void set_boolean_action_state (string action_name, bool state) {
		var action = App.instance.get_focused_window ().get_action (action_name);
		action.set_state (new Variant.boolean (state));
	}
		
    public void show_message_box (Gtk.MessageType message_type, string message_text) {
		var msgbox = new Gtk.MessageDialog (
			App.instance.get_focused_window (),
			Gtk.DialogFlags.MODAL,
			message_type,
			Gtk.ButtonsType.OK,
			message_text
		);
		msgbox.response.connect (() => msgbox.destroy ());
		msgbox.show ();
    }
    
    public File create_unsaved_document_file () {
        DateTime timestamp = new DateTime.now_local ();
		string file_name = _("Document from ") + timestamp.format ("%Y-%m-%d %H:%M:%S");
		var path = Path.build_filename (App.instance.data_home_folder_unsaved, file_name);
		return File.new_for_path (path);
    }
   
	public string get_parent_directory_path (string uri) {
		var home_dir = Environment.get_home_dir ();
		var path = Path.get_dirname (uri).replace (home_dir, "~");
		path = path.replace ("file://", "");
		if ("trash://" in path)
			path = _("Trash");
		return Uri.unescape_string (path);
	}
	
}
