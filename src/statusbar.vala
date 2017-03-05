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
	
		public StatusBar () {
			can_focus = false;
		    margin = 0;
			var msg_area = this.get_message_area ();
			msg_area.margin_top = 2;
			msg_area.margin_bottom = 2;
		}
		
		public uint display_message (string context_name, string message) {
			return push (get_context_id (context_name), message);
		}
		
		public void remove_all_messages (string context_name) {
			remove_all (get_context_id (context_name));
		}
		
	}

	public class StatusMenuButton : Gtk.MenuButton {
	
		public StatusMenuButton (string? model_name = null, string? label = null) {
			Object (relief: Gtk.ReliefStyle.NONE);
			set_image (new Gtk.Image.from_icon_name ("pan-down-symbolic", Gtk.IconSize.BUTTON));
			set_label (label ?? "");
			always_show_image = true;
			image_position = Gtk.PositionType.RIGHT;
			if (model_name != null)
				set_menu_model (App.instance.get_menu_model (model_name));
		}
	}

}

