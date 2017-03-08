/* fontfamilychooser.vala
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

    public class FontFamilyChooser : Gtk.Popover {
    
        Gtk.ListStore font_store;
        Gtk.TreeView font_view;
        Gtk.SearchEntry search_entry;
        Gtk.TreeModelFilter model_filter;
        Gtk.ScrolledWindow scrolled_window;
        
        public signal void activated ();
        
        public FontFamilyChooser (Gtk.Widget? widget) {
            Object (relative_to: widget, modal: true);
            create_font_store ();
            create_font_view ();
            var vbox = new Gtk.Box (Gtk.Orientation.VERTICAL, 10);
            scrolled_window = new Gtk.ScrolledWindow (null, null);
            scrolled_window.add (font_view);
            scrolled_window.expand = true;
            search_entry = new Gtk.SearchEntry ();
            vbox.pack_start (search_entry, false);
            vbox.pack_start (scrolled_window);
            vbox.margin = 10;
            vbox.show_all ();
            this.add (vbox);
            populate_font_store ();
            debug ("Fonts loaded");
            connect_signals ();
        }
        
        private void connect_signals () {
            this.show.connect (() => {
                search_entry.text = "";
                var path = new Gtk.TreePath.from_indices (0);
                Gdk.Rectangle rect;
                font_view.get_background_area (path, null, out rect);
                scrolled_window.height_request = 7 * rect.height;
                var family = (relative_to as Gtk.Button).label;
                select_family (family);
            });
            search_entry.search_changed.connect (model_filter.refilter);
            search_entry.activate.connect (() => {
                activated ();
            });
            font_view.row_activated.connect (() => {
                activated ();
            });
        }
        
        private void create_font_store () {
            font_store = new Gtk.ListStore (2, typeof (string), typeof (bool));            
            font_store.set_sort_column_id (0, Gtk.SortType.ASCENDING);
            font_store.set_sort_func (0, (model, a, b) => {
                string name_a, name_b;
                model.@get (a, 0, out name_a);
                model.@get (b, 0, out name_b);
                if (name_a < name_b) {
                    return -1;
                } else if (name_a > name_b) {
                    return 1;
                }
                return 0;
            });
            model_filter = new Gtk.TreeModelFilter (font_store, null);
            model_filter.set_visible_func ((model, iter) => {
                var text = search_entry.text.strip ();
                if (text.length == 0) {
                    return true;
                }
                string family;
                model.@get (iter, 0, out family);
                return text.down () in family.down ();
            });
        }
        
        private void create_font_view () {
            font_view = new Gtk.TreeView.with_model (model_filter);
            font_view.headers_visible = false;
            font_view.fixed_height_mode = true;
            font_view.activate_on_single_click = false;
            font_view.reorderable = false;
            font_view.enable_search = false;
            font_view.get_selection ().mode = Gtk.SelectionMode.BROWSE;
            var cell = new Gtk.CellRendererText ();
            font_view.insert_column_with_attributes (-1, _("Font family"), cell, "text", 0);
        }
        
        private void populate_font_store () {
            var font_map = Pango.cairo_font_map_get_default ();
            (unowned Pango.FontFamily)[] families;
            font_map.list_families (out families);
            Gtk.TreeIter iter;
            foreach (var family in families) {
                font_store.append (out iter);
                font_store.@set (iter, 0, family.get_name ().dup (), 1, family.is_monospace ());
            }
        }
        
        private void select_family (string family) {
            if (family.length == 0) {
                font_view.get_selection ().unselect_all ();
                return;
            }
            Gtk.TreeIter iter;
            var model = font_view.model;
            for (bool next = model.get_iter_first (out iter); next; next = model.iter_next (ref iter)) {
                string name;
                model.@get (iter, 0, out name);
                if (name == family) {
                    font_view.get_selection ().select_iter (iter);
                    var path = model.get_path (iter);
                    assert (path != null);
                    font_view.scroll_to_cell (path, null, true, 0.0f, 0.0f);
                    break;
                }
            }
        }
        
        public string? get_selected_family () {
            Gtk.TreeIter iter;
            if (!font_view.get_selection ().get_selected (null, out iter)) {
                return null;
            }
            string name;
            font_view.model.@get (iter, 0, out name);
            return name;
        }
        
    }
    
}
