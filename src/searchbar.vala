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
                    button_next_match.sensitive = false;
                    button_prev_match.sensitive = false;
                }
                button_replace.sensitive = !_not_found;
                button_replace_all.sensitive = !_not_found;
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
        public signal void next_match ();
        public signal void prev_match ();
        public signal void replace ();
        public signal void replace_all ();

        public SearchBar () {
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
            button_next_match.clicked.connect (() => {
                next_match ();
            });
            button_prev_match.clicked.connect (() => {
                prev_match ();
            });
            button_replace.clicked.connect (() => {
                replace ();
            });
            button_replace_all.clicked.connect (() => {
                replace_all ();
            });
        }
        
        public void set_has_next_match (bool has_next) {
            button_next_match.sensitive = has_next;
        }
        
        public void set_has_prev_match (bool has_prev) {
            button_prev_match.sensitive = has_prev;
        }
        
        public void get_navigation_enabled (out bool has_next, out bool has_prev) {
            has_next = button_next_match.sensitive;
            has_prev = button_prev_match.sensitive;
        }
        
        public void enable_navigation (bool has_next, bool has_prev) {
            set_has_next_match (has_next);
            set_has_prev_match (has_prev);
        }
        
    }

}
