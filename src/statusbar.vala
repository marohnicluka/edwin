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
	
		public class MenuButton : Gtk.MenuButton {
		    
		    public MenuButton () {
		        can_focus = false;
		        relief = Gtk.ReliefStyle.NONE;
		        set_image (new Gtk.Image.from_icon_name ("pan-down-symbolic", Gtk.IconSize.BUTTON));
		        always_show_image = true;
		        image_position = Gtk.PositionType.RIGHT;
            }
        
        }
        
	    LanguageChooser language_chooser;
	    Gtk.Label location_pages_label;
	    Gtk.Scale zoom_scale;
	    Gtk.Label zoom_label;
	    MenuButton language_button;
	    
	    public signal void language_changed (string lang);
	    public signal void zoom_changed (double @value);
	
		public StatusBar () {
			can_focus = false;
		    margin = 0;
		    spacing = 0;
			var msg_area = this.get_message_area ();
			msg_area.margin_top = 2;
			msg_area.margin_bottom = 2;
			location_pages_label = create_label (16);
			language_button = new MenuButton ();
			zoom_scale = new Gtk.Scale.with_range (Gtk.Orientation.HORIZONTAL, 20, 200, 1);
			zoom_scale.add_mark (100, Gtk.PositionType.TOP, null);
			zoom_scale.draw_value = false;
			zoom_scale.digits = 0;
			zoom_scale.margin_left = 20;
			zoom_scale.width_request = 150;
			zoom_label = create_label (7);
			pack_start (create_separator (), false);
			pack_start (create_frame (language_button), false);
			pack_start (create_separator (), false);
			pack_start (create_frame (location_pages_label), false);
			pack_start (create_separator (), false);
			pack_start (create_frame (zoom_scale), false);
			pack_start (create_frame (zoom_label), false);
			connect_signals ();
		}
		
		private void connect_signals () {
		    language_button.realize.connect (() => {
			    language_chooser = new LanguageChooser (language_button);
			    language_button.popover = language_chooser;
		        language_chooser.activated.connect (() => {
		            var lang = language_chooser.get_selected ();
		            language_changed (lang);
		            language_chooser.hide ();
		        });
		    });
		    language_button.toggled.connect (() => {
		        if (language_button.active) {
    		        language_chooser.show ();
		        } else {
		            language_chooser.hide ();
		        }
		    });
		    zoom_scale.value_changed.connect (() => {
		        var @value = zoom_scale.get_value ();
		        zoom_label.set_label ("%d%%".printf ((int) Math.round(@value)));
		        zoom_changed (@value / 100.0);
		    });
		}
		
		private Gtk.Widget create_frame (Gtk.Widget widget) {
		    var frame = new Gtk.Frame (null);
		    //Utils.apply_stylesheet (frame, "* { padding: 0 20px 0 20px; }");
		    frame.add (widget);
		    return frame;
		}
		
		private Gtk.Widget create_separator () {
		    var sep = new Gtk.Separator (Gtk.Orientation.VERTICAL);
		    Utils.apply_stylesheet (sep, "* { border-right-color: #f7f7f7; }");
		    return sep;
		}
		
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
		    location_pages_label.set_label (_(@"Page $current_page of $n_pages"));
		}
		
		public void set_language_label (string lang) {
		    language_button.set_label (GtkSpell.Checker.decode_language_code (lang));
		}
		
		public void set_zoom (double @value) {
		    zoom_scale.set_value (@value * 100);
		}
		
	}

}

