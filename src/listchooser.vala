/* chooser.vala
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

    public abstract class ListChooser : Gtk.Popover {
    
        const int NUMBER_OF_VISIBLE_ITEMS = 7;
    
        protected Gtk.ListStore list_store;
        protected Gtk.TreeView tree_view;
        protected Gtk.SearchEntry search_entry;
        protected Gtk.TreeModelFilter model_filter;
        protected Gtk.ScrolledWindow scrolled_window;
        protected int id_column_index = 0;
        
        public signal void activated ();
        
        public ListChooser (Gtk.Widget? widget) {
            Object (relative_to: widget, modal: true);
            create_list_store ();
            create_tree_view ();
            var vbox = new Gtk.Box (Gtk.Orientation.VERTICAL, 10);
            scrolled_window = new Gtk.ScrolledWindow (null, null);
            scrolled_window.add (tree_view);
            scrolled_window.expand = true;
            search_entry = new Gtk.SearchEntry ();
            vbox.pack_start (search_entry, false);
            vbox.pack_start (scrolled_window);
            vbox.margin = 10;
            vbox.show_all ();
            this.add (vbox);
            populate ();
            connect_signals ();
        }
        
        private void connect_signals () {
            this.show.connect (() => {
                search_entry.text = "";
                var path = new Gtk.TreePath.from_indices (0);
                Gdk.Rectangle rect;
                tree_view.get_background_area (path, null, out rect);
                scrolled_window.height_request = NUMBER_OF_VISIBLE_ITEMS * rect.height;
                select (get_initial_id ());
            });
            search_entry.search_changed.connect (model_filter.refilter);
            search_entry.activate.connect (() => {
                activated ();
            });
            tree_view.row_activated.connect (() => {
                activated ();
            });
        }
        
        private void create_list_store () {
            list_store = new Gtk.ListStore (2, typeof (string), typeof (string));            
            list_store.set_sort_column_id (0, Gtk.SortType.ASCENDING);
            list_store.set_sort_func (0, (model, a, b) => {
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
            model_filter = new Gtk.TreeModelFilter (list_store, null);
            model_filter.set_visible_func ((model, iter) => {
                var text = search_entry.text.strip ();
                if (text.length == 0) {
                    return true;
                }
                string item;
                model.@get (iter, 0, out item);
                return text.down () in item.down ();
            });
        }
        
        private void create_tree_view () {
            tree_view = new Gtk.TreeView.with_model (model_filter);
            tree_view.headers_visible = false;
            tree_view.fixed_height_mode = true;
            tree_view.activate_on_single_click = false;
            tree_view.reorderable = false;
            tree_view.enable_search = false;
            tree_view.get_selection ().mode = Gtk.SelectionMode.BROWSE;
            var cell = new Gtk.CellRendererText ();
            tree_view.insert_column_with_attributes (-1, null, cell, "text", 0);
        }
        
        private void select (string which_id) {
            if (which_id.length == 0) {
                tree_view.get_selection ().unselect_all ();
                return;
            }
            Gtk.TreeIter iter;
            var model = tree_view.model;
            for (bool next = model.get_iter_first (out iter); next; next = model.iter_next (ref iter)) {
                string id;
                model.@get (iter, id_column_index, out id);
                if (id == which_id) {
                    tree_view.get_selection ().select_iter (iter);
                    var path = model.get_path (iter);
                    assert (path != null);
                    tree_view.scroll_to_cell (path, null, true, 0.0f, 0.0f);
                    break;
                }
            }
        }
        
        public string? get_selected () {
            Gtk.TreeIter iter;
            if (!tree_view.get_selection ().get_selected (null, out iter)) {
                return null;
            }
            string id;
            tree_view.model.@get (iter, id_column_index, out id);
            return id;
        }
        
        protected abstract string get_initial_id ();
        protected abstract void populate ();
        
    }
    
}
