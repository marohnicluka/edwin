/* searchbar.vala
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

    public class SearchBar : Gtk.SearchBar {
    
        unowned SimpleActionGroup win_actions;
        Gtk.SearchEntry search_entry = new Gtk.SearchEntry ();
        Gtk.Entry replace_entry = new Gtk.Entry ();
        Gtk.Button button_next_match = new Gtk.Button.from_icon_name ("go-down");
        Gtk.Button button_prev_match = new Gtk.Button.from_icon_name ("go-up");
        Gtk.Button button_replace = new Gtk.Button.with_label (_("Replace"));
        Gtk.Button button_replace_all = new Gtk.Button.with_label (_("Replace all"));
        
        bool _not_found = false;
        public bool not_found {
            get { return _not_found; }
            set {
                _not_found = @value;
                if (search_text.length == 0) {
                    search_entry.primary_icon_name = "edit-find-symbolic";
                } else {
                    search_entry.primary_icon_name = _not_found ? "face-sad-symbolic" : "edit-find-symbolic";
                }
                if (_not_found) {
                    enable_navigation (false, false);
                }
                var action_replace = win_actions.lookup_action ("Replace") as SimpleAction;
                var action_replace_all = win_actions.lookup_action ("ReplaceAll") as SimpleAction;
                action_replace.set_enabled (!_not_found);
                action_replace_all.set_enabled (!_not_found);
            }
        }
        public string search_text {
            get { return search_entry.text; }
            set { search_entry.text = @value; }
        }
        public string replacement_text {
            get { return replace_entry.text; }
        }
        
        public signal void search_changed ();
        public signal void stop_search ();
        public signal void focused ();

        public SearchBar (SimpleActionGroup win_actions) {
            this.win_actions = win_actions;
            show_close_button = false;
            replace_entry.placeholder_text = _("Replace with");
            button_next_match.relief = Gtk.ReliefStyle.NONE;
            button_prev_match.relief = Gtk.ReliefStyle.NONE;
            button_replace.relief = Gtk.ReliefStyle.NONE;
            button_replace_all.relief = Gtk.ReliefStyle.NONE;
            button_next_match.can_focus = false;
            button_prev_match.can_focus = false;
            button_replace.can_focus = false;
            button_replace_all.can_focus = false;
            button_next_match.set_action_name ("win.NextMatch");
            button_prev_match.set_action_name ("win.PreviousMatch");
            button_replace.set_action_name ("win.Replace");
            button_replace_all.set_action_name ("win.ReplaceAll");
            var separator = new Gtk.SeparatorToolItem ();
            separator.draw = false;
            var hbox = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            hbox.pack_start (search_entry);
            hbox.pack_start (button_prev_match, false);
            hbox.pack_start (button_next_match, false);
            hbox.pack_start (separator, false);
            hbox.pack_start (replace_entry);
            hbox.pack_start (button_replace, false);
            hbox.pack_start (button_replace_all, false);
            add (hbox);
            connect_signals ();
        }
        
        private void connect_signals () {
            connect_entry (search_entry);
            search_entry.search_changed.connect (() => {
                search_changed ();
            });
            search_entry.stop_search.connect (() => {
                stop_search ();
            });
            search_entry.grab_focus.connect (() => {
                focused ();
            });
            search_entry.key_press_event.connect (on_key_press_event);
            replace_entry.key_press_event.connect (on_key_press_event);
            replace_entry.activate.connect (() => {
                button_replace.clicked ();
            });
        }
        
        private bool on_key_press_event (Gdk.EventKey event) {
            switch (event.keyval) {
            case Gdk.Key.Down:
                button_next_match.clicked ();
                return true;
            case Gdk.Key.Up:
                button_prev_match.clicked ();
                return true;
            }
            return false;
        }
        
        public void get_navigation_enabled (out bool has_next, out bool has_prev) {
            has_next = win_actions.get_action_enabled ("NextMatch");
            has_prev = win_actions.get_action_enabled ("PreviousMatch");
        }
        
        public void enable_navigation (bool has_next, bool has_prev) {
            var action_next = win_actions.lookup_action ("NextMatch") as SimpleAction;
            var action_prev = win_actions.lookup_action ("PreviousMatch") as SimpleAction;
            action_next.set_enabled (has_next);
            action_prev.set_enabled (has_prev);
        }
        
        public new void focus () {
            search_entry.grab_focus ();
        }
        
    }

}
