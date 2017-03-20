/* mainwindow.vala
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

    public class MainWindow : Gtk.Window {
    
        public unowned App app;
        public Document document;
        public Gtk.UIManager ui;
        public Granite.Widgets.AppMenu app_menu;
        public Gtk.HeaderBar header_bar;
        public SearchBar searchbar;
        public Gtk.ToolButton button_new;
        public Gtk.ToolButton button_open;
        public Gtk.ToolButton button_undo;
        public Gtk.ToolButton button_redo;
        public Gtk.ToolButton button_save;
        public Gtk.ToolButton button_page_setup;
        public Gtk.ToolButton button_print;
        public Gtk.ToolButton button_export;
        public Gtk.ToolButton button_properties;
        public Gtk.ToggleToolButton button_search;
        public Gtk.ToggleToolButton button_spelling;
        public ToolBar toolbar;
        public StatusBar statusbar;
        public SimpleActionGroup win_actions;
        
        public MainWindow (App app) {
            this.app = app;
            set_application (this.app);
            this.title = this.app.app_cmd_name;
            this.window_position = Gtk.WindowPosition.CENTER;
            this.set_size_request (1130, 700);
            this.hide_titlebar_when_maximized = false;
            this.icon_name = "accessories-text-editor";
            init_stylesheet ();
            init_actions ();
            init_header_bar ();
            init_layout ();
            connect_signals ();
        }
        
        private void init_stylesheet () {
            var rgba = Gdk.RGBA ();
            rgba.parse ("#efefef");
            override_background_color (0, rgba);
            var provider = new Gtk.CssProvider ();
            var base_path = App.instance.resource_path ();
            var path = Path.build_filename (base_path, "resources", "styles", "edwin.css");
            provider.load_from_resource (path);
            var priority = Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION;
            var screen = Gdk.Screen.get_default ();
            Gtk.StyleContext.add_provider_for_screen (screen, provider, priority);
        }
        
        private void init_actions () {
            win_actions = new SimpleActionGroup ();
            win_actions.add_action_entries (win_entries, this);
            insert_action_group ("win", win_actions);
        }
        
        private void init_header_bar () {
            header_bar = new Gtk.HeaderBar ();
            header_bar.get_style_context ().add_class ("primary-toolbar");
            header_bar.title = this.title;
            header_bar.show_close_button = true;
            set_titlebar (header_bar);
            /* create main menu */
            var menu = new Gtk.Menu.from_model (app.get_menu_model ("AppMenu"));
            app_menu = new Granite.Widgets.AppMenu.with_app (app, menu);
            app_menu.show_about.connect (app.show_about);
            header_bar.pack_end (app_menu);
            /* add buttons */
            button_new = Utils.create_tool_button ("document-new", "NewDocument",
                _("Add a new document"));
            button_open = Utils.create_tool_button ("document-open", "OpenDocument",
                _("Open a saved document"));
            button_save = Utils.create_tool_button ("document-save", "SaveDocument",
                _("Save document"));
            button_export = Utils.create_tool_button ("document-export", "Export",
                _("Export"));
            button_print = Utils.create_tool_button ("document-print", "Print",
                _("Print document"));
            button_page_setup = Utils.create_tool_button ("document-page-setup", "PageSetup",
                _("Page setup"));
            button_properties = Utils.create_tool_button ("gtk-properties", "DocumentProperties",
                _("Document properties"));
            button_undo = Utils.create_tool_button ("edit-undo", "Undo",
                _("Undo"));
            button_redo = Utils.create_tool_button ("edit-redo", "Redo",
                _("Redo"));
            button_search = Utils.create_toggle_button ("edit-find", "Search",
                _("Search"));
            button_spelling = Utils.create_toggle_button ("tools-check-spelling", "CheckSpelling",
                _("Check spelling"));
            /* pack buttons */
            header_bar.pack_start (button_new);
            header_bar.pack_start (button_open);
            header_bar.pack_start (new Gtk.SeparatorToolItem ());
            header_bar.pack_start (button_page_setup);
            header_bar.pack_start (button_properties);
            header_bar.pack_start (new Gtk.SeparatorToolItem ());
            header_bar.pack_start (button_undo);
            header_bar.pack_start (button_redo);
            header_bar.pack_end (new Gtk.SeparatorToolItem ());
            header_bar.pack_end (button_export);
            header_bar.pack_end (button_print);
            header_bar.pack_end (button_save);
            header_bar.pack_end (new Gtk.SeparatorToolItem ());
            header_bar.pack_end (button_search);
            header_bar.pack_end (button_spelling);
        }
        
        private void init_layout () {
            searchbar = new SearchBar (win_actions);
            toolbar = new ToolBar ();
            statusbar = new StatusBar ();
            document = new Document (this);
            statusbar.set_zoom (document.zoom);
            var vbox = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            var scrolled = new Gtk.ScrolledWindow (null, null);
            scrolled.add (document);
            vbox.pack_start (searchbar, false);
            vbox.pack_start (toolbar, false);
            vbox.pack_start (scrolled);
            vbox.pack_start (statusbar, false);
            this.add (vbox);
        }
        
        private void connect_signals () {
            this.realize.connect (() => {
                action_set_enabled ("Undo", false);
                action_set_enabled ("Redo", false);
                document.focus ();
            });
            toolbar.return_focus_to_document.connect (() => {
                document.focus ();
            });
            document.notify["can-undo"].connect (() => {
                action_set_enabled ("Undo", document.can_undo);
            });
            document.notify["can-redo"].connect (() => {
                action_set_enabled ("Redo", document.can_redo);
            });
            document.cursor_location_pages_changed.connect ((n, total) => {
                //debug ("Cursor moved to page %d of %d", n, total);
                statusbar.update_location_pages (n + 1, total);
            });
            searchbar.notify["search-mode-enabled"].connect (() => {
                bool active = searchbar.search_mode_enabled;
                if (!active) {
                    document.focus ();
                } else {
                    searchbar.not_found = true;
                    searchbar.focus ();
                }
                Utils.set_boolean_action_state ("Search", active);
            });
            searchbar.focused.connect (() => {
                Gtk.TextIter start, end;
                if (document.buffer.get_selection_bounds (out start, out end)) {
                    searchbar.search_text = start.get_text (end);
                }
            });
            searchbar.search_changed.connect (document.search);
            searchbar.stop_search.connect (document.clear_search);
            statusbar.language_changed.connect ((lang) => {
                document.language = lang;
            });
            statusbar.zoom_changed.connect ((@value) => {
                document.zoom = @value;
            });
        }
        
        public SimpleAction get_action (string name) {
            var action = win_actions.lookup_action (name);
            assert (action != null);
            return action as SimpleAction;
        }
        
        public void action_set_enabled (string name, bool enabled) {
            get_action (name).set_enabled (enabled);
        }
        
        public void show_document (Document doc) {
            
        }
        
        private void action_quit () {
            this.destroy ();
        }
        
        private void action_new_document () {
            debug ("Creating new document");
        }
        
        private void action_open_document () {
            debug ("Open document");
        }
        
        private void action_save_document () {
            debug ("Save document");
        }
        
        private void action_save_document_as () {
            debug ("Save document as");
        }
        
        private void action_undo () {
            debug ("Undo");
            document.undo ();
        }
        
        private void action_redo () {
            debug ("Redo");
            document.redo ();
        }
        
        private void action_export () {
            debug ("Export");
        }
        
        private void action_page_setup () {
            debug ("Page setup");
        }
        
        private void action_document_properties () {
            debug ("Document properties");
        }
        
        private void action_print_preview () {
            debug ("Print preview");
        }
        
        private void action_print () {
            debug ("Print");
        }
        
        private void action_preferences () {
            debug ("Accessing preferences");
        }
        
        private void action_next_match () {
            debug ("Fetch next search match");
            document.next_match ();
        }
        
        private void action_prev_match () {
            debug ("Fetch previous search match");
            document.prev_match ();
        }
        
        private void action_replace () {
            debug ("Replace current search match");
            document.replace ();
        }
        
        private void action_replace_all () {
            debug ("Replace all search matches");
            document.replace_all ();
        }
        
        private void action_find () {
            debug ("Find text");
            if (searchbar.search_mode_enabled) {
                searchbar.focus ();
            } else {
                searchbar.search_mode_enabled = true;
            }
        }
        
        private void change_state_search (SimpleAction action, Variant @value) {
            debug ("Change find state");
            action.set_state (@value);
            bool active = action.state.get_boolean ();
            searchbar.search_mode_enabled = active;
            button_search.active = active;
        }
        
        private void change_state_check_spelling (SimpleAction action, Variant @value) {
            debug ("Change spellcheck state");
            action.set_state (@value);
            bool active = action.state.get_boolean ();
            document.check_spelling = active;
            button_spelling.active = active;
        }
        
        private void change_state_text_bold (SimpleAction action) {
            debug ("Change bold state");
        }
        
        private void change_state_text_italic (SimpleAction action) {
            debug ("Change italic state");
        }
        
        const GLib.ActionEntry[] win_entries = {
            {"Quit", action_quit},
            {"NewDocument", action_new_document},
            {"OpenDocument", action_open_document},
            {"SaveDocument", action_save_document},
            {"SaveDocumentAs", action_save_document_as},
            {"Export", action_export},
            {"Undo", action_undo},
            {"Redo", action_redo},
            {"Export", action_export},
            {"Print", action_print},
            {"PrintPreview", action_print_preview},
            {"PageSetup", action_page_setup},
            {"DocumentProperties", action_document_properties},
            {"Preferences", action_preferences},
            {"Find", action_find},
            {"NextMatch", action_next_match},
            {"PreviousMatch", action_prev_match},
            {"Replace", action_replace},
            {"ReplaceAll", action_replace_all},
            /* toggles */
            {"Search", null, null, "false", change_state_search},
            {"CheckSpelling", null, null, "false", change_state_check_spelling},
            {"TextBold", null, null, "false", change_state_text_bold},
            {"TextItalic", null, null, "false", change_state_text_italic},
        };
        
    }
    
}
