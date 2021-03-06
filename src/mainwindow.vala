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
        public Gtk.Stack stack;
        public Gtk.Viewport preview_viewport;
        public Document document;
        public Gtk.UIManager ui;
        public SearchBar searchbar;
        public Gtk.Paned paned;
        public MainToolBar main_toolbar;
        public DynamicToolBar dynamic_toolbar;
        public DocumentPreview document_preview;
        public SimpleActionGroup win_actions;
        
        public MainWindow (App app) {
            this.app = app;
            set_application (this.app);
            this.title = this.app.app_cmd_name;
            this.window_position = Gtk.WindowPosition.CENTER;
            this.set_size_request (1130, 700);
            this.hide_titlebar_when_maximized = false;
            this.icon_name = "accessories-text-editor";
            init_actions ();
            init_layout ();
            init_stylesheet ();
            connect_signals ();
        }
        
        private void init_stylesheet () {
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
        
        private void init_layout () {
            stack = new Gtk.Stack ();
            main_toolbar = new MainToolBar ();
            set_titlebar (main_toolbar);
            create_new_document ();
            searchbar = new SearchBar (win_actions);
            dynamic_toolbar = new DynamicToolBar ();
            var vbox = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            var document_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            var preview_scrolled = new Gtk.ScrolledWindow (null, null);
            paned = new Gtk.Paned (Gtk.Orientation.HORIZONTAL);
            vbox.pack_start (searchbar, false);
            document_box.pack_start (dynamic_toolbar, false);
            document_box.pack_start (document);
            paned.add1 (document.outline);
            paned.add2 (document_box);
            paned.position = 200;
            stack.add_named (paned, "editor");
            preview_viewport = new Gtk.Viewport (null, null);
            preview_scrolled.add (preview_viewport);
            preview_scrolled.expand = true;
            stack.add_named (preview_scrolled, "preview");
            stack.visible_child_name = "editor";
            vbox.pack_start (stack);
            add (vbox);
        }
        
        private void connect_signals () {
            this.realize.connect (() => {
                action_set_enabled ("Undo", false);
                action_set_enabled ("Redo", false);
                update_title ();
                document.focus ();
            });
            dynamic_toolbar.return_focus_to_document.connect (() => {
                document.focus ();
            });
            document.notify["can-undo"].connect (() => {
                action_set_enabled ("Undo", document.can_undo);
            });
            document.notify["can-redo"].connect (() => {
                action_set_enabled ("Redo", document.can_redo);
            });
            document.notify["file"].connect (() => {
                debug ("Updating window title");
                update_title ();
            });
            document.notify["modified"].connect (() => {
                if (document.modified) {
                    var name = main_toolbar.title;
                    main_toolbar.set_title (@"*$name");
                } else {
                    update_title ();
                }
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
            main_toolbar.preview_close_request.connect (() => {
                close_document_preview ();
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
        
        public void create_new_document () {
            document = new Document (this);
        }
        
        public void show_document (Document doc) {
            
        }
        
        public void close_document_preview (Gtk.TextIter? where_to_focus = null) {
            document.focus ();
            if (where_to_focus != null) {
                document.buffer.place_cursor (where_to_focus);
            }
            var box = preview_viewport.get_child ();
            assert (box is Gtk.EventBox);
            box.destroy ();
            stack.visible_child_name = "editor";
        }
        
        public void update_title () {
            if (document.unsaved) {
                main_toolbar.set_title (_("Unsaved document"));
                main_toolbar.set_subtitle (null);
            } else {
                var basename = document.file.get_basename ();
                main_toolbar.set_title (basename.substring (0, basename.last_index_of (".")));
                main_toolbar.set_subtitle (Utils.get_parent_directory_path (document.file.get_uri ()));
            }
        }
        
        public void save_document (string? uri = null) {
            var file = uri == null ? document.file : File.new_for_uri (uri);
            if (file.query_exists ()) try {
                file.@delete ();
            } catch (Error e) {
                warning (e.message);
                return;
            }
            debug ("Saving document...");
            document.save.begin (file, (obj, res) => {
                bool result = document.save.end (res);
                if (result) {
                    if (uri != null) {
                        document.unsaved = false;
                        document.file = file;
                    }
                    document.modified = false;
                    debug ("Document saved successfully");
                } else {
                    debug ("Failed to save document");
                    Utils.show_message_box (Gtk.MessageType.ERROR, _("Failed to save document."));
                }
            });
        }
        
        public void on_quit () {
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
            if (document.unsaved) {
                action_save_document_as ();
            } else {
                save_document ();
            }
        }
        
        private void action_save_document_as () {
            debug ("Save document as");
            var file_chooser = new Gtk.FileChooserDialog (
                _("Save document as"), this, Gtk.FileChooserAction.SAVE,
                _("Cancel"), Gtk.ResponseType.CANCEL,
                _("Save"), Gtk.ResponseType.ACCEPT);
            file_chooser.local_only = true;
            file_chooser.do_overwrite_confirmation = true;
            var file_filter = new Gtk.FileFilter ();
            file_filter.set_filter_name (_("Documents"));
            file_filter.add_pattern ("*.edw");
            file_chooser.add_filter (file_filter);
            if (file_chooser.run () == Gtk.ResponseType.ACCEPT) {
                save_document (file_chooser.get_uri ());
            }
            file_chooser.close ();
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
            document_preview = new DocumentPreview (document);
            document_preview.request_document_focus.connect ((where) => {
                main_toolbar.preview_mode = false;
                close_document_preview (where);
            });
            var box = new Gtk.EventBox ();
            Utils.apply_stylesheet (box, "* { background-color: #efefef; }");
            document_preview.valign = Gtk.Align.CENTER;
            document_preview.halign = Gtk.Align.CENTER;
            box.add (document_preview);
            preview_viewport.add (box);
            box.show_all ();
            main_toolbar.preview_mode = true;
            stack.visible_child_name = "preview";
        }
        
        private void action_print () {
            debug ("Print");
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
        
        private void action_text_bold () {
            debug ("Change bold state");
            dynamic_toolbar.flip_bold_state ();
        }
        
        private void action_text_italic () {
            debug ("Change italic state");
            dynamic_toolbar.flip_italic_state ();
        }
        
        private void change_state_search (SimpleAction action, Variant @value) {
            debug ("Change find state");
            action.set_state (@value);
            bool active = action.state.get_boolean ();
            searchbar.search_mode_enabled = active;
            main_toolbar.button_search.active = active;
        }
        
        private void change_state_check_spelling (SimpleAction action, Variant @value) {
            debug ("Change spellcheck state");
            action.set_state (@value);
            bool active = action.state.get_boolean ();
            document.check_spelling = active;
            main_toolbar.button_spelling.active = active;
        }
        
        const GLib.ActionEntry[] win_entries = {
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
            {"Find", action_find},
            {"NextMatch", action_next_match},
            {"PreviousMatch", action_prev_match},
            {"Replace", action_replace},
            {"ReplaceAll", action_replace_all},
            {"TextBold", action_text_bold},
            {"TextItalic", action_text_italic},
            /* toggles */
            {"Search", null, null, "false", change_state_search},
            {"CheckSpelling", null, null, "false", change_state_check_spelling},
        };
        
    }
    
}
