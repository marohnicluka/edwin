/* statusbar.vala
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

namespace Edwin {

	public class StatusBar : Gtk.Statusbar {
	
	    Gtk.Label location_pages_label;
	    Gtk.Label input_type_label;
	
		public StatusBar () {
			can_focus = false;
		    margin = 0;
		    spacing = 0;
			var msg_area = this.get_message_area ();
			msg_area.margin_top = 2;
			msg_area.margin_bottom = 2;
			location_pages_label = create_label ();
			input_type_label = create_label (4);
			pack_start (create_separator (), false);
			pack_start (create_frame (location_pages_label), false);
			pack_start (create_separator (), false);
			pack_start (create_frame (input_type_label), false);
		}
		
		private Gtk.Widget create_frame (Gtk.Widget widget) {
		    var frame = new Gtk.Frame (null);
		    Utils.apply_stylesheet (frame, "* { padding: 0 20px 0 20px; }");
		    frame.add (widget);
		    return frame;
		}
		
		private Gtk.Widget create_separator () {
		    var sep = new Gtk.Separator (Gtk.Orientation.VERTICAL);
		    Utils.apply_stylesheet (sep, "* { border-right-color: #f7f7f7; }");
		    return sep;
		}
		
		/*
		private Gtk.MenuButton menu_button (string? model_name = null, string? label = null) {
		    var button = new Gtk.MenuButton ();
		    button.relief = Gtk.ReliefStyle.NONE;
		    button.set_image (new Gtk.Image.from_icon_name ("pan-down-symbolic", Gtk.IconSize.BUTTON));
		    button.set_label (label ?? "");
		    button.always_show_image = true;
		    button.image_position = Gtk.PositionType.RIGHT;
		    if (model_name != null) {
			    button.set_menu_model (App.instance.get_menu_model (model_name));
    	    }
	        return button;
        }
        */
        
        private Gtk.Label create_label (int width_chars = 0) {
            var label = new Gtk.Label ("");
		    Utils.apply_stylesheet (label, "* { padding: 0; }");
		    if (width_chars > 0) {
		        label.width_chars = width_chars;
		    }
		    label.valign = Gtk.Align.BASELINE;
		    return label;
        }
		
		public uint display_message (string context_name, string message) {
			return push (get_context_id (context_name), message);
		}
		
		public void remove_all_messages (string context_name) {
			remove_all (get_context_id (context_name));
		}
		
		public void update_location_pages (int current_page, int n_pages) {
		    location_pages_label.set_label (_(@"$current_page / $n_pages"));
		}
		
		public void update_input_type_label (bool overwrite) {
		    input_type_label.set_label (overwrite ? "OVR" : "INS");
		}
		
	}

}

