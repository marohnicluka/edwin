/* document.vala
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

    public class Document : Gtk.ScrolledWindow {

/*********************\
|* STRUCTS AND ENUMS *|
\*********************/

        public enum UndoOperationType {
            INSERT,
            DELETE,
            TAG;

            public string str () {
                string str = this.to_string ();
                int index = str.last_index_of ("_");
                return str.substring (index + 1);
            }
        }
        
        public struct UndoOperation {
            public UndoOperationType type;
            public int[] offsets;
            public unowned Gtk.TextTag tag;
            public bool tag_applied;
            public uint index_within_action;
            
            public void set_offsets (Gtk.TextIter iter1, Gtk.TextIter iter2) {
                offsets = new int[2];
                offsets[0] = iter1.get_offset ();
                offsets[1] = iter2.get_offset ();
            }
            
            public void get_iter_at_offset (out Gtk.TextIter iter, int index, Gtk.TextBuffer buffer) {
                buffer.get_start_iter (out iter);
                iter.set_offset (offsets[index]);
            }
        }

/**********************\
|* FIELDS AND SIGNALS *|
\**********************/

        /* public properties */
        public File file { get; set; default = Utils.create_unsaved_document_file (); }
        public bool unsaved { get; set; default = true; }
        public PaperSize paper_size { get; set; }
        public Granite.Widgets.SourceList outline { get; construct set; }
        public double zoom { get; set; default = 1.0; }
        public bool can_undo { get; private set; default = false; }
        public bool can_redo { get; private set; default = false; }
        public bool user_action_in_progress { get; private set; default = false; }
        public bool doing_undo_redo { get { return redoable_action_in_progress || redoing_in_progress; } }
        public unowned DynamicToolBar toolbar { get { return main_window.dynamic_toolbar; } }
        public unowned SearchBar searchbar { get { return main_window.searchbar; } }
        public unowned DocumentBuffer buffer { get { return view.buffer as DocumentBuffer; } }
        bool _modified;
        public bool modified {
            get { return _modified; }
            set {
                _modified = value;
                if (!_modified) {
                    buffer.set_modified (false);
                } else {
                    debug ("Buffer was modified since the last save");
                }
            }
        }
        bool _check_spelling = false;
        public bool check_spelling {
            get { return _check_spelling; }
            set {
                _check_spelling = value;
                if (_check_spelling) {
                    spell_checker.attach (view);
                } else {
                    spell_checker.detach ();
                }
            }
        }
        public unowned string language {
            get { return spell_checker.get_language (); }
            set {
                try {
                    spell_checker.set_language (value);
                } catch (Error e) {
                    warning (e.message);
                }
            }
        }

        /* private fields */
        unowned MainWindow main_window;
        DocumentView view;
        Gtk.TextBuffer undo_buffer;
        Gtk.TextBuffer redo_buffer;
        GtkSpell.Checker spell_checker;
        bool redoing_in_progress = false;
        bool redoable_action_in_progress = false;
        uint undo_operation_counter = 0;
        uint update_toolbar_handler = 0;
        Queue<UndoOperation?> undo_stack = new Queue<UndoOperation?> ();
        Queue<UndoOperation?> redo_stack = new Queue<UndoOperation?> ();
        
        public signal void cursor_location_pages_changed (int current_page, int n_pages);

/****************\
|* CONSTRUCTION *|
\****************/

        public Document (MainWindow main_window) {
            Object (hadjustment: null, vadjustment: null);
            this.main_window = main_window;
            paper_size = new PaperSize.@default ();
            view = new DocumentView (this);
            add (view);
            undo_buffer = new Gtk.TextBuffer (buffer.tag_table);
            redo_buffer = new Gtk.TextBuffer (buffer.tag_table);
            spell_checker = new GtkSpell.Checker ();
            spell_checker.decode_language_codes = true;
            outline = new Granite.Widgets.SourceList ();
            connect_signals ();
        }
        
        ~Document () {
            if (update_toolbar_handler != 0) {
                Source.remove (update_toolbar_handler);
            }
        }
        
        private void connect_signals () {
            realize.connect (on_realize);
            spell_checker.language_changed.connect (on_language_changed);
            buffer.modified_changed.connect (on_buffer_modified_changed);
            buffer.search_finished.connect (on_search_finished);
            view.notify["has-focus"].connect (on_has_focus_changed);
        }

/*************\
|* CALLBACKS *|
\*************/

        private void on_buffer_modified_changed () {
            if (buffer.get_modified ()) {
                this.modified = true;
            }
        }

        private void on_realize () {
            toolbar.font_family_selected.connect (on_font_family_selected);
            toolbar.text_size_selected.connect (on_text_size_selected);
            toolbar.text_color_selected.connect (on_text_color_selected);
            toolbar.text_bold_toggled.connect (on_text_bold_toggled);
            toolbar.text_italic_toggled.connect (on_text_italic_toggled);
            toolbar.text_underline_toggled.connect (on_text_underline_toggled);
            toolbar.paragraph_alignment_selected.connect (on_paragraph_alignment_selected);
            set_defaults ();
        }
        
        private void on_language_changed (string new_lang) {

        }
        
        private void on_has_focus_changed () {
            if (view.has_focus) {
                on_focused ();
            } else {
                on_unfocused ();
            }
        }
        
        private void on_font_family_selected (string family) {
            Gtk.TextIter start, end;
            if (buffer.get_selection_bounds (out start, out end)) {
                begin_user_action ();
                buffer.remove_tags ("edwin-font-family", start, end);
                buffer.apply_tag (buffer.get_font_family_tag (family), start, end);
                end_user_action ();
            } else {
                buffer.text_properties_changed = true;
            }
        }

        private void on_text_size_selected (int size) {
            Gtk.TextIter start, end;
            if (buffer.get_selection_bounds (out start, out end)) {
                begin_user_action ();
                buffer.remove_tags ("edwin-text-size", start, end);
                buffer.apply_tag (buffer.get_text_size_tag (size * Pango.SCALE), start, end);
                end_user_action ();
            } else {
                buffer.text_properties_changed = true;
            }
        }

        private void on_text_color_selected (Gdk.RGBA color) {
            Gtk.TextIter start, end;
            if (buffer.get_selection_bounds (out start, out end)) {
                begin_user_action ();
                buffer.remove_tags ("edwin-text-color", start, end);
                buffer.apply_tag (buffer.get_text_color_tag (color), start, end);
                end_user_action ();
            } else {
                buffer.text_properties_changed = true;
            }
        }

        private void on_text_bold_toggled (bool active) {
            Gtk.TextIter start, end;
            if (buffer.get_selection_bounds (out start, out end)) {
                if (active) {
                    buffer.apply_tag (buffer.tag_bold, start, end);
                } else {
                    buffer.remove_tag (buffer.tag_bold, start, end);
                }
            } else {
                buffer.text_properties_changed = true;
            }
        }

        private void on_text_italic_toggled (bool active) {
            Gtk.TextIter start, end;
            if (buffer.get_selection_bounds (out start, out end)) {
                if (active) {
                    buffer.apply_tag (buffer.tag_italic, start, end);
                } else {
                    buffer.remove_tag (buffer.tag_italic, start, end);
                }
            } else {
                buffer.text_properties_changed = true;
            }
        }

        private void on_text_underline_toggled (bool active) {
            Gtk.TextIter start, end;
            if (buffer.get_selection_bounds (out start, out end)) {
                if (active) {
                    buffer.apply_tag (buffer.tag_underline, start, end);
                } else {
                    buffer.remove_tag (buffer.tag_underline, start, end);
                }
            } else {
                buffer.text_properties_changed = true;
            }
        }

        private void on_paragraph_alignment_selected (Gtk.Justification justification) {
            Gtk.TextIter start, end;
            if (!buffer.get_selection_bounds (out start, out end)) {
                start = buffer.cursor;
                end = buffer.cursor;
            }
            buffer.move_to_paragraph_start (ref start);
            buffer.move_to_paragraph_end (ref end);
            if (start.equal (end)) {
                buffer.text_properties_changed = true;
            } else {
                begin_user_action ();
                buffer.apply_alignment_to_range (justification, start, end);
                end_user_action ();
            }
        }
        
        private void on_search_finished (int n_matches) {
            searchbar.not_found = n_matches == 0;
            if (n_matches > 0) {
                searchbar.enable_navigation (buffer.select_first_search_match (), false);
            }
        }
        
/*******************\
|* PRIVATE METHODS *|
\*******************/

        private void on_focused () {
            if (searchbar.search_mode_enabled) {
                clear_search ();
                searchbar.search_text = "";
            }
        }
        
        private void on_unfocused () {
        
        }

        private UndoOperation create_undo_operation (int type, Gtk.TextIter iter1, Gtk.TextIter iter2) {
            var op = UndoOperation ();
            op.type = (UndoOperationType) type;
            op.set_offsets (iter1, iter2);
            op.index_within_action = undo_operation_counter;
            if (user_action_in_progress || redoable_action_in_progress) {
                undo_operation_counter++;
            }
            return op;
        }
        
        private void push_undo_operation (UndoOperation op) {
            if (redoable_action_in_progress) {
                redo_stack.push_tail (op);
                can_redo = true;
            } else {
                undo_stack.push_tail (op);
                can_undo = true;
            }
        }

        private void apply_undo_operation (UndoOperation op, Gtk.TextBuffer chunk_buffer) {
            Gtk.TextIter start, end, chunk_start, chunk_end;
            switch (op.type) {
            case UndoOperationType.INSERT:
                op.get_iter_at_offset (out start, 0, buffer);
                op.get_iter_at_offset (out end, 1, buffer);
                buffer.@delete (ref start, ref end);
                buffer.place_cursor (start);
                break;
            case UndoOperationType.DELETE:
                op.get_iter_at_offset (out end, 0, buffer);
                buffer.move_mark (buffer.pasted_start_mark, end);
                op.get_iter_at_offset (out chunk_start, 1, chunk_buffer);
                chunk_buffer.get_end_iter (out chunk_end);
                buffer.insert_range (ref end, chunk_start, chunk_end);
                chunk_buffer.@delete (ref chunk_start, ref chunk_end);
                buffer.get_iter_at_mark (out start, buffer.pasted_start_mark);
                buffer.place_cursor (end);
                break;
            case UndoOperationType.TAG:
                op.get_iter_at_offset (out start, 0, buffer);
                op.get_iter_at_offset (out end, 1, buffer);
                if (op.tag_applied) {
                    buffer.remove_tag (op.tag, start, end);
                } else {
                    buffer.apply_tag (op.tag, start, end);
                }
                buffer.place_cursor (end);
                break;
            default:
                assert_not_reached ();
            }
        }

        private void update_toolbar () {
            Gtk.TextIter start, end;
            Gtk.TextAttributes attributes;
            Pango.FontDescription font_desc;
            Gdk.RGBA color;
            bool has_underline;
            int justification;
            if (buffer.get_selection_bounds (out start, out end)) {
                start.forward_char ();
                attributes = buffer.get_attributes_before (start);
                font_desc = attributes.font;
                has_underline = attributes.appearance.underline == Pango.Underline.SINGLE;
                color = buffer.get_text_color (start);
                justification = buffer.get_paragraph_justification (start);
                var iter = start;
                buffer.move_to_tag_toggle (ref iter, true, "edwin-font-family");
                if (iter.compare (end) < 0) {
                    font_desc.set_family ("");
                }
                iter.assign (start);
                buffer.move_to_tag_toggle (ref iter, true, "edwin-text-size");
                if (iter.compare (end) < 0) {
                    font_desc.set_size (0);
                }
                iter.assign (start);
                buffer.move_to_tag_toggle (ref iter, true, "edwin-text-color");
                if (iter.compare (end) < 0) {
                    color.alpha = 0;
                }
                start.backward_char ();
                iter.assign (start);
                if (font_desc.get_weight () == Pango.Weight.BOLD &&
                    iter.forward_to_tag_toggle (buffer.tag_bold) &&
                    iter.compare (end) < 0)
                {
                    font_desc.set_weight (Pango.Weight.NORMAL);
                }
                iter.assign (start);
                if (font_desc.get_style () == Pango.Style.ITALIC &&
                    iter.forward_to_tag_toggle (buffer.tag_italic) &&
                    iter.compare (end) < 0)
                {
                    font_desc.set_style (Pango.Style.NORMAL);
                }
                iter.assign (start);
                if (has_underline &&
                    iter.forward_to_tag_toggle (buffer.tag_underline) &&
                    iter.compare (end) < 0)
                {
                    has_underline = false;
                }
                iter.assign (start);
                while (buffer.forward_paragraph (ref iter)) {
                    if (buffer.get_paragraph_justification (iter) != justification) {
                        justification = -1;
                        break;
                    }
                }
            } else {
                attributes = buffer.get_attributes_before (buffer.cursor);
                font_desc = attributes.font;
                has_underline = attributes.appearance.underline == Pango.Underline.SINGLE;
                color = buffer.get_text_color (buffer.cursor);
                justification = buffer.get_paragraph_justification (buffer.cursor);
            }
            toolbar.set_text_font_desc (font_desc);
            toolbar.set_underline_state (has_underline);
            toolbar.set_text_color (color);
            toolbar.set_paragraph_alignment (justification);
        }

        private void set_defaults () {
            var lang = Environment.get_variable ("LANG");
            language = lang.substring (0, lang.index_of ("."));
            var attributes = view.get_default_attributes ();
            toolbar.set_text_font_desc (attributes.font);
            toolbar.set_text_color (view.default_text_color);
            toolbar.set_paragraph_alignment (attributes.justification);
            Gtk.TextIter iter;
            buffer.get_start_iter (out iter);
            buffer.place_cursor (iter);
        }

/******************\
|* PUBLIC METHODS *|
\******************/

        public async bool save (File file) {
            Gtk.TextIter start, end;
            buffer.get_bounds (out start, out end);
            var data = buffer.serialize (buffer, buffer.serialize_format, start, end);
            long written = 0;
            new Thread<void*> (null, () => {
                try {
                    var dos = new DataOutputStream (file.create (FileCreateFlags.REPLACE_DESTINATION));
                    while (written < data.length) {
                        written += dos.write (data[written:data.length]);
                    }
                } catch (Error e) {
                    warning (e.message);
                }
                Idle.add (save.callback);
                return null;
            });
            yield;
            return written == data.length;
        }
        
        public bool load (File file)
            requires (buffer.text.length == 0)
        {
            try {
                uint8[] data;
                FileUtils.get_data (file.get_path (), out data);
                Gtk.TextIter iter;
                buffer.get_start_iter (out iter);
                begin_user_action ();
                buffer.deserialize (buffer, buffer.deserialize_format, iter, data);
                end_user_action ();
                return true;
            } catch (Error e) {
                warning (e.message);
                return false;
            }
        }

        public void push_undo_operation_insert (Gtk.TextIter start, Gtk.TextIter end) {
            var op = create_undo_operation (UndoOperationType.INSERT, start, end);
            push_undo_operation (op);
        }

        public void push_undo_operation_delete (Gtk.TextIter start, Gtk.TextIter end) {
            Gtk.TextIter chunk_start, chunk_end;
            var chunk_buffer = redoable_action_in_progress ? redo_buffer : undo_buffer;
            chunk_buffer.get_end_iter (out chunk_end);
            var op = create_undo_operation (UndoOperationType.DELETE, start, chunk_end);
            chunk_buffer.insert_range (ref chunk_end, start, end);
            chunk_buffer.get_bounds (out chunk_start, out chunk_end);
            buffer.tag_table.@foreach ((tag) => {
                if (tag.name != null && buffer.tag_is_internal (tag)) {
                    chunk_buffer.remove_tag (tag, chunk_start, chunk_end);
                }
            });
            push_undo_operation (op);
        }

        public void push_undo_operation_tag (Gtk.TextIter start, Gtk.TextIter end, Gtk.TextTag tag, bool tag_applied) {
            var op = create_undo_operation (UndoOperationType.TAG, start, end);
            op.tag = tag;
            op.tag_applied = tag_applied;
            push_undo_operation (op);
        }
        
        public void schedule_update_toolbar () {
            if (update_toolbar_handler != 0) {
                Source.remove (update_toolbar_handler);
            }
            update_toolbar_handler = Timeout.add (150, () => {
                update_toolbar ();
                update_toolbar_handler = 0;
                return false;
            });
        }

        public void on_text_changed () {
            if (!doing_undo_redo && redo_stack.length > 0) {
                redo_stack.clear ();
                redo_buffer.text = "";
                can_redo = false;
            }
        }
        
        public void begin_user_action () {
            user_action_in_progress = true;
            undo_operation_counter = 0;
        }

        public void end_user_action () {
            user_action_in_progress = false;
            undo_operation_counter = 0;
        }
        
        public void undo () {
            if (!can_undo) {
                return;
            }
            end_user_action ();
            redoable_action_in_progress = true;
            UndoOperation? op = null;
            do {
                op = undo_stack.pop_tail ();
                assert (op != null);
                apply_undo_operation (op, undo_buffer);
            } while (op.index_within_action > 0);
            redoable_action_in_progress = false;
            undo_operation_counter = 0;
            can_undo = undo_stack.length > 0;
        }

        public void redo () {
            if (!can_redo) {
                return;
            }
            begin_user_action ();
            redoing_in_progress = true;
            UndoOperation? op = null;
            do {
                op = redo_stack.pop_tail ();
                assert (op != null);
                apply_undo_operation (op, redo_buffer);
            } while (op.index_within_action > 0);
            end_user_action ();
            redoing_in_progress = false;
            can_redo = redo_stack.length > 0;
        }

        public new void focus () {
            view.grab_focus ();
        }
        
        public void search () {
            Gtk.TextIter start, end;
            buffer.get_bounds (out start, out end);
            buffer.begin_search_in_range (searchbar.search_text, start, end);
        }
        
        public void clear_search () {
            buffer.clear_search ();
            searchbar.enable_navigation (false, false);
            searchbar.not_found = true;
            
        }

        public void next_match () {
            buffer.unfocus_current_search_match ();
            bool has_next;
            assert (buffer.select_next_search_match (out has_next));
            searchbar.enable_navigation (has_next, true);
        }

        public void prev_match () {
            buffer.unfocus_current_search_match ();
            bool has_prev;
            assert (buffer.select_prev_search_match (out has_prev));
            searchbar.enable_navigation (true, has_prev);
        }
        
        public void replace () {
            begin_user_action ();
            var replacement = searchbar.replacement_text;
            bool has_next, has_prev;
            searchbar.get_navigation_enabled (out has_next, out has_prev);
            if (!buffer.replace_current_search_match (replacement, ref has_next, ref has_prev)) {
                clear_search ();   
            } else {
                searchbar.enable_navigation (has_next, has_prev);
            }
            end_user_action ();
        }
        
        public void replace_all () {
            begin_user_action ();
            var replacement = searchbar.replacement_text;
            buffer.replace_all_search_matches (replacement);
            clear_search ();
            end_user_action ();
        }
        
        public void scroll_to_cursor () {
            view.scroll_to_cursor ();
        }

    }

}
