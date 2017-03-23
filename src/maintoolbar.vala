/* maintoolbar.vala
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

    public class MainToolBar : Gtk.HeaderBar {

        public Granite.Widgets.AppMenu app_menu;
        public Gtk.ToolButton button_new;
        public Gtk.ToolButton button_open;
        public Gtk.ToolButton button_undo;
        public Gtk.ToolButton button_redo;
        public Gtk.ToolButton button_save;
        public Gtk.ToolButton button_page_setup;
        public Gtk.ToolButton button_print_preview;
        public Gtk.ToolButton button_print;
        public Gtk.ToolButton button_export;
        public Gtk.ToolButton button_properties;
        public Gtk.ToggleToolButton button_search;
        public Gtk.ToggleToolButton button_spelling;
        public Gtk.Button button_preview_close;
        bool _preview_mode = false;
        public bool preview_mode {
            get { return _preview_mode; }
            set {
                _preview_mode = value;
                enable_preview (_preview_mode);
            }
        }
        
        public signal void preview_close_request (); 

        public MainToolBar () {
            Object (show_close_button: true);
            get_style_context ().add_class ("primary-toolbar");
            var menu = new Gtk.Menu.from_model (App.instance.get_menu_model ("AppMenu"));
            app_menu = new Granite.Widgets.AppMenu.with_app (App.instance, menu);
            app_menu.show_about.connect (App.instance.show_about);
            pack_end (app_menu);
            button_preview_close = new Gtk.Button.with_label (_("Close preview"));
            button_preview_close.get_style_context ().add_class ("back-button");
            button_preview_close.no_show_all = true;
            button_preview_close.margin = 3;
            button_new = Utils.create_tool_button ("document-new", "win.NewDocument",
                _("Add a new document"));
            button_open = Utils.create_tool_button ("document-open", "win.OpenDocument",
                _("Open a saved document"));
            button_save = Utils.create_tool_button ("document-save", "win.SaveDocument",
                _("Save document"));
            button_export = Utils.create_tool_button ("document-export", "win.Export",
                _("Export"));
            button_print_preview = Utils.create_tool_button ("document-print", "win.PrintPreview",
                _("Print preview"));
            button_print = Utils.create_tool_button ("document-print", "win.Print",
                _("Print document"));
            button_page_setup = Utils.create_tool_button ("document-page-setup", "win.PageSetup",
                _("Page setup"));
            button_properties = Utils.create_tool_button ("gtk-properties", "win.DocumentProperties",
                _("Document properties"));
            button_undo = Utils.create_tool_button ("edit-undo", "win.Undo",
                _("Undo"));
            button_redo = Utils.create_tool_button ("edit-redo", "win.Redo",
                _("Redo"));
            button_search = Utils.create_toggle_button ("edit-find", "win.Search",
                _("Search"));
            button_spelling = Utils.create_toggle_button ("tools-check-spelling", "win.CheckSpelling",
                _("Check spelling"));
            pack_start (button_preview_close);
            pack_start (button_new);
            pack_start (button_open);
            pack_start (new Gtk.SeparatorToolItem ());
            pack_start (button_page_setup);
            pack_start (button_properties);
            pack_start (new Gtk.SeparatorToolItem ());
            pack_start (button_undo);
            pack_start (button_redo);
            pack_end (new Gtk.SeparatorToolItem ());
            pack_end (button_export);
            pack_end (button_print_preview);
            pack_end (button_print);
            pack_end (button_save);
            pack_end (new Gtk.SeparatorToolItem ());
            pack_end (button_search);
            pack_end (button_spelling);
            connect_signals ();
        }
        
        private void connect_signals () {
            button_preview_close.clicked.connect (() => {
                preview_mode = false;
                preview_close_request ();
            });
            realize.connect (() => {
                enable_widget (button_print, false);
            });
        }
        
        private void enable_widget (Gtk.Widget widget, bool enable) {
            widget.visible = enable;
            if (widget is Gtk.Actionable) {
                var action_name = (widget as Gtk.Actionable).get_action_name ();
                if (action_name != null) {
                    assert (action_name.has_prefix ("win."));
                    var window = App.instance.get_focused_window ();
                    window.action_set_enabled (action_name.substring (4), enable);
                }
            }
        }
        
        private void enable_preview (bool enable) {
            enable_widget (button_new, !enable);
            enable_widget (button_open, !enable);
            enable_widget (button_page_setup, !enable);
            enable_widget (button_properties, !enable);
            enable_widget (button_undo, !enable);
            enable_widget (button_redo, !enable);
            enable_widget (button_spelling, !enable);
            enable_widget (button_print_preview, !enable);
            enable_widget (button_print, enable);
            enable_widget (button_preview_close, enable);
        }

    }

}
