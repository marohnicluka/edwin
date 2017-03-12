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

    public delegate bool TextRangeFunc (Gtk.TextIter start, Gtk.TextIter end);

    public const int PAGE_BREAKING_TIMEOUT = 250; // miliseconds
    public const int SCROLL_TIMEOUT = 5; // miliseconds
    public const int SCROLL_DURATION = 100; // miliseconds

    public class Document : Gtk.Viewport {

/*********************\
|* STRUCTS AND ENUMS *|
\*********************/

        public struct SectionBreak {
            public unowned Gtk.TextMark mark;
            public unowned Gtk.TextTag tag;
        }
        
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

/*************************\
|* FIELDS AND PROPERTIES *|
\*************************/

        /* public properties */
        public PaperSize paper_size { get; set; }
        public bool can_undo { get; private set; default = false; }
        public bool can_redo { get; private set; default = false; }
        private bool _check_spelling = false;
        public bool check_spelling {
            get { return _check_spelling; }
            set {
                _check_spelling = value;
                if (_check_spelling) {
                    spell_checker.attach (text_view);
                } else {
                    spell_checker.detach ();
                }
            }
        }

        /* private fields */
        TextView text_view;
        Gtk.TextBuffer undo_buffer;
        Gtk.TextBuffer redo_buffer;
        Gtk.EventBox text_view_box;
        GtkSpell.Checker spell_checker;
        unowned MainWindow main_window;
        unowned Gtk.TextMark insert_start_mark;
        unowned Gtk.TextMark pasted_start_mark;
        int cursor_movement_direction = 0;
        int justification_before_insert = 0;
        bool text_properties_changed = false;
        bool insertion_in_progress = false;
        bool pasting_in_progress = false;
        bool redoing_in_progress = false;
        bool user_action_in_progress = false;
        bool redoable_action_in_progress = false;
        bool deletion_in_progress = false;
        bool user_is_deleting = false;
        bool user_is_typing = false;
        uint scroll_handler = 0;
        uint update_toolbar_handler = 0;
        uint section_break_serial = 0;
        uint undo_operation_counter = 0;
        List<SectionBreak?> section_breaks = new List<SectionBreak?> ();
        Queue<UndoOperation?> undo_stack = new Queue<UndoOperation?> ();
        Queue<UndoOperation?> redo_stack = new Queue<UndoOperation?> ();
        /* tags */
        unowned Gtk.TextTag tag_bold;
        unowned Gtk.TextTag tag_italic;
        unowned Gtk.TextTag tag_underline;
        unowned Gtk.TextTag tag_aligned_left;
        unowned Gtk.TextTag tag_aligned_right;
        unowned Gtk.TextTag tag_centered;
        unowned Gtk.TextTag tag_justified;
        unowned Gtk.TextTag tag_enumerate;
        unowned Gtk.TextTag tag_itemize;
        unowned Gtk.TextTag tag_skip;
        unowned Gtk.TextTag tag_no_page_break;
        HashTable<string, unowned Gtk.TextTag> font_family_tags;
        HashTable<int, unowned Gtk.TextTag> text_size_tags;
        HashTable<Gdk.RGBA?, unowned Gtk.TextTag> text_color_tags;

        /* often used */
        public unowned Gtk.TextBuffer buffer {
            get { return text_view.buffer; }
        }
        public unowned ToolBar toolbar {
            get { return main_window.toolbar; }
        }
        public Gtk.TextIter cursor {
            get {
                Gtk.TextIter iter;
                buffer.get_iter_at_mark (out iter, buffer.get_insert ());
                return iter;
            }
        }
        public int section_skip_after {
            get { return (3 * paper_size.top_margin) / 2; }
        }
        public Gdk.RGBA default_text_color {
            get { return text_view.get_style_context ().get_color (0); }
        }

        /* signals */
        public signal void page_breaking_done ();

/****************\
|* CONSTRUCTION *|
\****************/

        public Document (MainWindow main_window) {
            Object (hadjustment: null, vadjustment: null);
            this.main_window = main_window;
            paper_size = new PaperSize.@default ();
            create_widgets ();
            create_spell_checker ();
            create_tags_and_marks ();
            this.realize.connect (on_realize);
        }

        private void create_widgets () {
            text_view = new TextView (this);
            text_view.shape (paper_size);
            text_view_box = new Gtk.EventBox ();
            text_view_box.add (text_view);
            this.add (text_view_box);
        }
        
        private void create_spell_checker () {
            spell_checker = new GtkSpell.Checker ();
            try {
                spell_checker.set_language (Environment.get_variable ("LANG"));
                spell_checker.decode_language_codes = true;
            } catch (Error e) {
                warning (e.message);
            }
        }

        private void create_tags_and_marks () {
            /* tags */
            tag_bold = buffer.create_tag ("bold",
                "weight", Pango.Weight.BOLD);
            tag_italic = buffer.create_tag ("italic",
                "style", Pango.Style.ITALIC);
            tag_underline = buffer.create_tag ("underline",
                "underline", Pango.Underline.SINGLE);
            tag_aligned_left = buffer.create_tag ("aligned-left",
                "justification", Gtk.Justification.LEFT);
            tag_aligned_right = buffer.create_tag ("aligned-right",
                "justification", Gtk.Justification.RIGHT);
            tag_centered = buffer.create_tag ("centered",
                "justification", Gtk.Justification.CENTER);
            tag_justified = buffer.create_tag ("justified",
                "justification", Gtk.Justification.FILL);
            tag_enumerate = buffer.create_tag ("enumerate");
            tag_itemize = buffer.create_tag ("itemize");
            /* internal tags */
            tag_skip = buffer.create_tag ("internal:skip");
            tag_no_page_break = buffer.create_tag ("internal:no-page-break");
            font_family_tags = new HashTable<string, unowned Gtk.TextTag> (str_hash, str_equal);
            text_size_tags = new HashTable<int, unowned Gtk.TextTag> (direct_hash, direct_equal);
            text_color_tags = new HashTable<Gdk.RGBA?, unowned Gtk.TextTag> (
                (key) => { return key.hash (); },
                (a, b) => { return a.equal (b); }
            );
            /* marks */
            Gtk.TextIter where;
            buffer.get_start_iter (out where);
            insert_start_mark = buffer.create_mark (null, where, true);
            pasted_start_mark = buffer.create_mark (null, where, true);
            /* buffers that record text deletions
            /* used for undo/redo operations
             */
            undo_buffer = new Gtk.TextBuffer (buffer.tag_table);
            redo_buffer = new Gtk.TextBuffer (buffer.tag_table);
        }

/*************\
|* CALLBACKS *|
\*************/

        private void on_realize () {
			var win = this.get_view_window ();
			var events = win.get_events ();
			win.set_events (events & ~Gdk.EventMask.FOCUS_CHANGE_MASK);
            text_view.move_cursor.connect (on_move_cursor);
            text_view.key_press_event.connect (on_key_press_event);
            text_view.paste_clipboard.connect (on_paste_clipboard);
            text_view.drag_begin.connect (on_drag_begin);
            text_view.drag_end.connect (on_drag_end);
            text_view.backspace.connect (on_backspace);
            text_view.delete_from_cursor.connect (on_delete_from_cursor);
            buffer.notify["cursor-position"].connect (on_cursor_position_changed);
            buffer.notify["has-selection"].connect (on_has_selection_changed);
            buffer.notify["text"].connect (on_text_changed);
            buffer.delete_range.connect (on_delete_range);
            buffer.delete_range.connect_after (on_delete_range_after);
            buffer.insert_text.connect (on_insert_text);
            buffer.mark_set.connect (on_mark_set);
            buffer.insert_text.connect_after (on_insert_text_after);
            buffer.paste_done.connect (on_paste_done);
            buffer.apply_tag.connect (on_apply_tag);
            buffer.remove_tag.connect (on_remove_tag);
            buffer.modified_changed.connect (on_modified_changed);
            toolbar.font_family_selected.connect (on_font_family_selected);
            toolbar.text_size_selected.connect (on_text_size_selected);
            toolbar.text_color_selected.connect (on_text_color_selected);
            toolbar.text_bold_toggled.connect (on_text_bold_toggled);
            toolbar.text_italic_toggled.connect (on_text_italic_toggled);
            toolbar.text_underline_toggled.connect (on_text_underline_toggled);
            toolbar.paragraph_alignment_selected.connect (on_paragraph_alignment_selected);
            set_defaults ();
        }
        
        private void on_backspace () {
            if (!user_is_deleting) {
                begin_user_action ();
                user_is_deleting = true;
                user_is_typing = false;
            }
        }
        
        private void on_delete_from_cursor (Gtk.DeleteType type, int count) {
            on_backspace ();
        }
        
        private void on_modified_changed () {

        }
        
        private void on_text_changed () {
            if (!redoable_action_in_progress && !redoing_in_progress) {
                redo_stack.clear ();
                redo_buffer.text = "";
                can_redo = false;
            }
        }
        
        private void on_drag_begin (Gdk.DragContext context) {
            debug ("Drag started");
            begin_user_action ();
        }
        
        private void on_drag_end (Gdk.DragContext context) {
            debug ("Drag ended");
            end_user_action ();
        }

        private void on_paste_clipboard () {
            pasting_in_progress = true;
            buffer.move_mark (pasted_start_mark, cursor);
            begin_user_action ();
        }

        private void on_paste_done (Gtk.Clipboard clipboard) {
            pasting_in_progress = false;
            Gtk.TextIter pasted_start;
            buffer.get_iter_at_mark (out pasted_start, pasted_start_mark);
            restore_section_breaks (pasted_start, cursor);
            end_user_action ();
        }
        
        private void on_apply_tag (Gtk.TextTag tag, Gtk.TextIter start, Gtk.TextIter end) {
            print ("TAG: %s\n", tag.name);
            if (tag.name == null || !tag.name.has_prefix ("gtkspell")) {
                push_undo_operation_tag (start, end, tag, true);
            }
            on_text_changed ();
        }

        private void on_remove_tag (Gtk.TextTag tag, Gtk.TextIter start, Gtk.TextIter end) {
            if (tag.name == null || !tag.name.has_prefix ("gtkspell")) {
                push_undo_operation_tag (start, end, tag, false);
            }
            on_text_changed ();
        }

        private void on_font_family_selected (string family) {
            Gtk.TextIter start, end;
            if (buffer.get_selection_bounds (out start, out end)) {
                remove_tags ("font-family", start, end);
                buffer.apply_tag (get_font_family_tag (family), start, end);
            } else {
                text_properties_changed = true;
            }
        }

        private void on_text_size_selected (int size) {
            Gtk.TextIter start, end;
            if (buffer.get_selection_bounds (out start, out end)) {
                remove_tags ("text-size", start, end);
                buffer.apply_tag (get_text_size_tag (size * Pango.SCALE), start, end);
            } else {
                text_properties_changed = true;
            }
        }

        private void on_text_color_selected (Gdk.RGBA color) {
            Gtk.TextIter start, end;
            if (buffer.get_selection_bounds (out start, out end)) {
                remove_tags ("text-color", start, end);
                buffer.apply_tag (get_text_color_tag (color), start, end);
            } else {
                text_properties_changed = true;
            }
        }

        private void on_text_bold_toggled (bool active) {
            Gtk.TextIter start, end;
            if (buffer.get_selection_bounds (out start, out end)) {
                if (active) {
                    buffer.apply_tag (tag_bold, start, end);
                } else {
                    buffer.remove_tag (tag_bold, start, end);
                }
            } else {
                text_properties_changed = true;
            }
        }

        private void on_text_italic_toggled (bool active) {
            Gtk.TextIter start, end;
            if (buffer.get_selection_bounds (out start, out end)) {
                if (active) {
                    buffer.apply_tag (tag_italic, start, end);
                } else {
                    buffer.remove_tag (tag_italic, start, end);
                }
            } else {
                text_properties_changed = true;
            }
        }

        private void on_text_underline_toggled (bool active) {
            Gtk.TextIter start, end;
            if (buffer.get_selection_bounds (out start, out end)) {
                if (active) {
                    buffer.apply_tag (tag_underline, start, end);
                } else {
                    buffer.remove_tag (tag_underline, start, end);
                }
            } else {
                text_properties_changed = true;
            }
        }

        private void on_paragraph_alignment_selected (Gtk.Justification justification) {
            Gtk.TextIter start, end;
            if (!buffer.get_selection_bounds (out start, out end)) {
                start = cursor;
                end = cursor;
            }
            move_to_paragraph_start (ref start);
            move_to_paragraph_end (ref end);
            if (start.equal (end)) {
                text_properties_changed = true;
            } else {
                begin_user_action ();
                apply_alignment_to_range (justification, start, end);
                end_user_action ();
            }
        }

        private void on_mark_set (Gtk.TextIter location, Gtk.TextMark mark) {
            if (buffer.has_selection &&
                mark == buffer.get_insert () || mark == buffer.get_selection_bound ())
            {
                on_selection_range_changed ();
            }
        }

        private void on_has_selection_changed () {

        }

        private void on_selection_range_changed () {
            schedule_update_toolbar ();
        }

        private bool on_key_press_event (Gdk.EventKey event) {
            bool ctrl = (event.state & Gdk.ModifierType.CONTROL_MASK) != 0;
            switch (event.keyval) {
            case Gdk.Key.Return:
                if (ctrl) {
                    Gtk.TextIter start, end;
                    begin_user_action ();
                    if (buffer.get_selection_bounds (out start, out end)) {
                        buffer.@delete (ref start, ref end);
                    }
                    buffer.insert_at_cursor ("\n", -1);
                    var n = create_section_break (cursor);
                    buffer.insert_at_cursor ("\n", -1);
                    buffer.get_iter_at_mark (out start, section_breaks.nth_data (n).mark);
                    buffer.apply_tag (section_breaks.nth_data (n).tag, start, cursor);
                    end_user_action ();
                    return true;
                }
                break;
            }
            if (event.str.get_char ().isgraph () && !user_is_typing) {
                begin_user_action ();
                user_is_typing = true;
                user_is_deleting = false;
            }
            if (event.str.get_char ().isspace ()) {
                begin_user_action ();
            }
            return false;
        }

        private void on_move_cursor (Gtk.MovementStep step, int count, bool extend_selection) {
            cursor_movement_direction = count;
        }

        private void on_cursor_position_changed () {
            Gtk.TextIter selection_bound;
            var iter = cursor;
            if (iter_at_section_break (iter) && cursor_movement_direction != 0) {
                iter.forward_chars (Utils.sgn (cursor_movement_direction));
                if (buffer.has_selection) {
                    buffer.move_mark (buffer.get_insert (), iter);
                } else {
                    buffer.place_cursor (iter);
                }
            } else if (iter.has_tag (tag_skip) && !iter.toggles_tag (tag_skip)) {
                int test = cursor_movement_direction;
                if (buffer.has_selection) {
                    buffer.get_iter_at_mark (out selection_bound, buffer.get_selection_bound ());
                    test = selection_bound.compare (iter);
                }
                if (test < 0) {
                    iter.backward_to_tag_toggle (tag_skip);
                } else {
                    iter.forward_to_tag_toggle (tag_skip);
                }
                if (buffer.has_selection) {
                    buffer.move_mark (buffer.get_insert (), iter);
                } else {
                    buffer.place_cursor (iter);
                }
            }
            if (!insertion_in_progress) {
                text_properties_changed = false;
                user_is_typing = false;
            }
            if (!deletion_in_progress) {
                user_is_deleting = false;
            }
            if (user_action_in_progress && !insertion_in_progress && !deletion_in_progress) {
                end_user_action ();
            }
            cursor_movement_direction = 0;
            schedule_scroll_to_cursor ();
            if (!buffer.has_selection) {
                schedule_update_toolbar ();
            }
        }

        private void on_delete_range (Gtk.TextIter start, Gtk.TextIter end) {
            if (iter_at_section_break (start)) {
                start.backward_char ();
            }
            if (iter_at_section_break (end)) {
                end.forward_char ();
            }
            deletion_in_progress = true;
            push_undo_operation_delete (start, end);
        }

        private void on_delete_range_after (Gtk.TextIter start, Gtk.TextIter end) {
            int count = 0;
            start.get_marks ().@foreach ((mark) => {
                if (mark.name != null && mark.name.has_prefix ("section-break")) {
                    remove_section_break_at_mark (mark);
                    count++;
                }
            });
            debug ("%d section breaks deleted", count);
            deletion_in_progress = false;
            schedule_scroll_to_cursor ();
        }

        private void on_insert_text (ref Gtk.TextIter iter, string text, int len) {
            buffer.move_mark (insert_start_mark, iter);
            insertion_in_progress = true;
            if (!pasting_in_progress) {
                justification_before_insert = text_properties_changed ?
                    toolbar.get_paragraph_alignment () :
                    get_paragraph_justification (iter);
            }
        }

        private void on_insert_text_after (ref Gtk.TextIter end, string text, int len) {
            Gtk.TextIter start;
            buffer.get_iter_at_mark (out start, insert_start_mark);
            push_undo_operation_insert (start, end);
            if (!redoable_action_in_progress && !redoing_in_progress) {
                bool modified;
                var attributes = get_attributes_before (start, out modified);
                if (modified || text_properties_changed) {
                    var font_desc = text_properties_changed ?
                        toolbar.get_text_font_desc () :
                        attributes.font;
                    var family_tag = get_font_family_tag (font_desc.get_family ());
                    var size_tag = get_text_size_tag (font_desc.get_size ());
                    var color_tag = get_text_color_tag (text_properties_changed ?
                        toolbar.get_text_color () :
                        get_text_color (start));
                    bool has_bold_tag = font_desc.get_weight () == Pango.Weight.BOLD;
                    bool has_italic_tag = font_desc.get_style () == Pango.Style.ITALIC;
                    bool has_underline_tag = text_properties_changed ?
                        toolbar.get_underline_state () :
                        attributes.appearance.underline == Pango.Underline.SINGLE;
                    apply_tag_with_id (family_tag, "font-family", start, end);
                    apply_tag_with_id (size_tag, "text-size", start, end);
                    apply_tag_with_id (color_tag, "text-color", start, end);
                    if (has_bold_tag) {
                        buffer.apply_tag (tag_bold, start, end);
                    }
                    if (has_italic_tag) {
                        buffer.apply_tag (tag_italic, start, end);
                    }
                    if (has_underline_tag) {
                        buffer.apply_tag (tag_underline, start, end);
                    }
                }
                if (!pasting_in_progress) {
                    var iter = end;
                    move_to_paragraph_end (ref iter);
                    apply_alignment_to_range (justification_before_insert, start, iter);
                }
            }
            insertion_in_progress = false;
            text_properties_changed = false;
            schedule_scroll_to_cursor ();
        }

/*******************\
|* PRIVATE METHODS *|
\*******************/

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

        private void push_undo_operation_insert (Gtk.TextIter start, Gtk.TextIter end) {
            var op = create_undo_operation (UndoOperationType.INSERT, start, end);
            push_undo_operation (op);
        }

        private void push_undo_operation_delete (Gtk.TextIter start, Gtk.TextIter end) {
            Gtk.TextIter chunk_start, chunk_end;
            var chunk_buffer = redoable_action_in_progress ? redo_buffer : undo_buffer;
            chunk_buffer.get_end_iter (out chunk_end);
            var op = create_undo_operation (UndoOperationType.DELETE, start, chunk_end);
            chunk_buffer.insert_range (ref chunk_end, start, end);
            chunk_buffer.get_bounds (out chunk_start, out chunk_end);
            buffer.tag_table.@foreach ((tag) => {
                if (tag.name != null && tag.name.has_prefix ("gtkspell")) {
                    chunk_buffer.remove_tag (tag, chunk_start, chunk_end);
                }
            });
            push_undo_operation (op);
        }

        private void push_undo_operation_tag (Gtk.TextIter start, Gtk.TextIter end, Gtk.TextTag tag, bool tag_applied) {
            var op = create_undo_operation (UndoOperationType.TAG, start, end);
            op.tag = tag;
            op.tag_applied = tag_applied;
            push_undo_operation (op);
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
                buffer.move_mark (pasted_start_mark, end);
                op.get_iter_at_offset (out chunk_start, 1, chunk_buffer);
                chunk_buffer.get_end_iter (out chunk_end);
                buffer.insert_range (ref end, chunk_start, chunk_end);
                chunk_buffer.@delete (ref chunk_start, ref chunk_end);
                buffer.get_iter_at_mark (out start, pasted_start_mark);
                restore_section_breaks (start, end);
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

        private void apply_alignment_to_range (int justification, Gtk.TextIter start, Gtk.TextIter end) {
            if (start.equal (end)) {
                return;
            }
            if (start.has_tag (tag_aligned_left)) {
                buffer.remove_tag (tag_aligned_left, start, end);
            } else if (start.has_tag (tag_aligned_right)) {
                buffer.remove_tag (tag_aligned_right, start, end);
            } else if (start.has_tag (tag_centered)) {
                buffer.remove_tag (tag_centered, start, end);
            } else if (start.has_tag (tag_justified)) {
                buffer.remove_tag (tag_justified, start, end);
            }
            if (justification != text_view.get_default_attributes ().justification) {
                switch (justification) {
                case Gtk.Justification.LEFT:
                    buffer.apply_tag (tag_aligned_left, start, end);
                    break;
                case Gtk.Justification.RIGHT:
                    buffer.apply_tag (tag_aligned_right, start, end);
                    break;
                case Gtk.Justification.CENTER:
                    buffer.apply_tag (tag_centered, start, end);
                    break;
                case Gtk.Justification.FILL:
                    buffer.apply_tag (tag_justified, start, end);
                    break;
                }
            }
        }

        private void schedule_update_toolbar () {
            if (update_toolbar_handler != 0) {
                Source.remove (update_toolbar_handler);
            }
            update_toolbar_handler = Timeout.add (150, () => {
                update_toolbar ();
                update_toolbar_handler = 0;
                return false;
            });
        }

        private Gtk.TextAttributes get_attributes_before (Gtk.TextIter where, out bool modified = null) {
            modified = false;
            var attributes = text_view.get_default_attributes ();
            var iter = where;
            if (iter.backward_char ()) {
                if (iter_at_section_break (iter)) {
                    iter.backward_chars (2);
                }
                modified = iter.get_attributes (attributes);
            }
            return attributes;
        }

        private Gtk.Justification get_paragraph_justification (Gtk.TextIter where) {
            var iter = where;
            move_to_paragraph_start (ref iter);
            while (iter.ends_line () && iter.backward_char ());
            var attributes = text_view.get_default_attributes ();
            iter.get_attributes (attributes);
            return attributes.justification;
        }

        private Gdk.RGBA get_text_color (Gtk.TextIter where) {
            var iter = where;
            Gdk.RGBA color = default_text_color;
            if (!iter.backward_char ()) {
                return color;
            }
            text_color_tags.@foreach ((col, tag) => {
                if (iter.has_tag (tag)) {
                    color = col;
                }
            });
            return color;
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
                attributes = get_attributes_before (start);
                font_desc = attributes.font;
                has_underline = attributes.appearance.underline == Pango.Underline.SINGLE;
                color = get_text_color (start);
                justification = get_paragraph_justification (start);
                var iter = start;
                move_to_tag_toggle (ref iter, true, "font-family");
                if (iter.compare (end) < 0) {
                    font_desc.set_family ("");
                }
                iter.assign (start);
                move_to_tag_toggle (ref iter, true, "text-size");
                if (iter.compare (end) < 0) {
                    font_desc.set_size (0);
                }
                iter.assign (start);
                move_to_tag_toggle (ref iter, true, "text-color");
                if (iter.compare (end) < 0) {
                    color.alpha = 0;
                }
                start.backward_char ();
                iter.assign (start);
                if (font_desc.get_weight () == Pango.Weight.BOLD &&
                    iter.forward_to_tag_toggle (tag_bold) &&
                    iter.compare (end) < 0)
                {
                    font_desc.set_weight (Pango.Weight.NORMAL);
                }
                iter.assign (start);
                if (font_desc.get_style () == Pango.Style.ITALIC &&
                    iter.forward_to_tag_toggle (tag_italic) &&
                    iter.compare (end) < 0)
                {
                    font_desc.set_style (Pango.Style.NORMAL);
                }
                iter.assign (start);
                if (has_underline &&
                    iter.forward_to_tag_toggle (tag_underline) &&
                    iter.compare (end) < 0)
                {
                    has_underline = false;
                }
                iter.assign (start);
                while (forward_paragraph (ref iter) && iter.compare (end) < 0) {
                    if (get_paragraph_justification (iter) != justification) {
                        justification = -1;
                        break;
                    }
                }
            } else {
                attributes = get_attributes_before (cursor);
                font_desc = attributes.font;
                has_underline = attributes.appearance.underline == Pango.Underline.SINGLE;
                color = get_text_color (cursor);
                justification = get_paragraph_justification (cursor);
            }
            toolbar.set_text_font_desc (font_desc);
            toolbar.set_underline_state (has_underline);
            toolbar.set_text_color (color);
            toolbar.set_paragraph_alignment (justification);
        }

        private void set_defaults () {
            var attributes = text_view.get_default_attributes ();
            toolbar.set_text_font_desc (attributes.font);
            toolbar.set_text_color (default_text_color);
            toolbar.set_paragraph_alignment (attributes.justification);
        }

        private unowned Gtk.TextTag get_font_family_tag (string family) {
            unowned Gtk.TextTag? tag = font_family_tags.lookup (family);
            if (tag == null) {
                tag = buffer.create_tag (@"font-family:$family",
                    "family", family);
                font_family_tags.insert (family, tag);
            }
            return tag;
        }

        private unowned Gtk.TextTag get_text_size_tag (int size) {
            unowned Gtk.TextTag? tag = text_size_tags.lookup (size);
            if (tag == null) {
                tag = buffer.create_tag (@"text-size:%d".printf (size / Pango.SCALE),
                    "size", size);
                text_size_tags.insert (size, tag);
            }
            return tag;
        }

        private unowned Gtk.TextTag get_text_color_tag (Gdk.RGBA color) {
            unowned Gtk.TextTag? tag = text_color_tags.lookup (color);
            if (tag == null) {
                tag = buffer.create_tag (@"text-color:%s".printf (color.to_string ()),
                    "foreground-rgba", color);
                text_color_tags.insert (color, tag);
            }
            return tag;
        }

        private void remove_tags (string id, Gtk.TextIter start, Gtk.TextIter end) {
            buffer.tag_table.@foreach ((tag) => {
                if (tag.name != null && tag.name.has_prefix (id)) {
                    buffer.remove_tag (tag, start, end);
                }
            });
        }

        private bool move_to_tag_toggle (ref Gtk.TextIter iter, bool forward, string id, int dir = 0, out unowned Gtk.TextTag toggled_tag = null) {
            do {
                SList<weak Gtk.TextTag> tags, tmp_tags;
                switch (dir) {
                case -1:
                    tags = iter.get_toggled_tags (true);
                    break;
                case 1:
                    tags = iter.get_toggled_tags (false);
                    break;
                case 0:
                    tags = iter.get_toggled_tags (true);
                    tmp_tags = iter.get_toggled_tags (false);
                    tags.concat ((owned) tmp_tags);
                    break;
                default:
                    assert_not_reached ();
                }
                foreach (var tag in tags) {
                    if (tag.name != null && tag.name.has_prefix (id)) {
                        toggled_tag = tag;
                        return true;
                    }
                }
            } while (forward ? iter.forward_to_tag_toggle (null) : iter.backward_to_tag_toggle (null));
            toggled_tag = null;
            return false;
        }

        private void apply_tag_with_id (Gtk.TextTag tag, string id, Gtk.TextIter start, Gtk.TextIter end) {
            var range_start = start;
            var range_end = Gtk.TextIter ();
            while (range_start.compare (end) < 0) {
                range_end.assign (range_start);
                move_to_tag_toggle (ref range_end, true, id, -1);
                if (range_end.compare (end) > 0) {
                    range_end.assign (end);
                }
                if (!range_start.equal (range_end)) {
                    buffer.apply_tag (tag, range_start, range_end);
                }
                if (range_end.equal (end)) {
                    break;
                }
                range_start.assign (range_end);
                range_start.forward_char ();
                move_to_tag_toggle (ref range_start, true, id, 1);
            }
        }

        private void schedule_scroll_to_cursor () {
            Timeout.add (150, () => {
                scroll_to_mark (buffer.get_insert ());
                return false;
            });
        }

        private void scroll_to_mark (Gtk.TextMark mark) {
            Gtk.TextIter iter;
            Gdk.Rectangle rect;
            int dx, dy;
            buffer.get_iter_at_mark (out iter, mark);
            get_location (iter, out rect);
            get_distance_from_viewport (rect, out dx, out dy);
            if (dx != 0 || dy != 0) {
                if (scroll_handler != 0) {
                    Source.remove (scroll_handler);
                }
                var dx_step = SCROLL_TIMEOUT * dx / (double) SCROLL_DURATION;
                var dy_step = SCROLL_TIMEOUT * dy / (double) SCROLL_DURATION;
                int i = 0;
                scroll_handler = Timeout.add (SCROLL_TIMEOUT, () => {
                    hadjustment.@value += dx_step;
                    vadjustment.@value += dy_step;
                    if (i < SCROLL_DURATION / SCROLL_TIMEOUT) {
                        i++;
                        return true;
                    }
                    scroll_handler = 0;
                    return false;
                });
            }
        }

        private void get_location (Gtk.TextIter iter, out Gdk.Rectangle rect, bool win_coords = true) {
            text_view.get_iter_location (iter, out rect);
            if (!win_coords) {
                return;
            }
            int x1 = rect.x;
            int y1 = rect.y;
            int x2 = rect.x + rect.width;
            int y2 = rect.y + rect.height;
            int wx1, wx2, wy1, wy2;
            text_view.buffer_to_window_coords (Gtk.TextWindowType.WIDGET, x1, y1, out wx1, out wy1);
            text_view.buffer_to_window_coords (Gtk.TextWindowType.WIDGET, x2, y2, out wx2, out wy2);
            rect = Gdk.Rectangle () {
                x = wx1,
                y = wy1,
                width = wx2 - wx1,
                height = wy2 - wy1
            };
        }

        private bool iter_at_section_break (Gtk.TextIter iter) {
            foreach (var mark in iter.get_marks ()) {
                if (mark.name != null && mark.name.has_prefix ("section-break")) {
                    return true;
                }
            }
            return false;
        }

        private Gdk.Rectangle get_viewport_rectangle () {
            return Gdk.Rectangle () {
                x = (int) Math.round (hadjustment.@value),
                y = (int) Math.round (vadjustment.@value),
                width = (int) Math.round (hadjustment.page_size),
                height = (int) Math.round (vadjustment.page_size)
            };
        }

        private Gdk.Rectangle to_viewport_coords (Gdk.Rectangle rectangle) {
            int box_width = text_view_box.get_allocated_width ();
            int page_width = text_view.get_allocated_width ();
            var rect = rectangle;
            rect.x += (box_width - page_width) / 2;
            rect.y += text_view.margin;
            return rect;
        }

        private void get_distance_from_viewport (Gdk.Rectangle rectangle, out int dx, out int dy) {
            var viewport_rect = get_viewport_rectangle ();
            var rect = to_viewport_coords (rectangle);
            Gdk.Rectangle un;
            rect.union (viewport_rect, out un);
            dx = viewport_rect.x > un.x ? un.x - viewport_rect.x : un.width - viewport_rect.width;
            dy = viewport_rect.y > un.y ? un.y - viewport_rect.y : un.height - viewport_rect.height;
        }

        private void remove_section_break_at_mark (Gtk.TextMark mark) {
            section_breaks.@foreach ((section_break) => {
                if (section_break.mark == mark) {
                    buffer.delete_mark (mark);
                    section_breaks.remove (section_break);
                }
            });
        }

        private uint create_section_break (Gtk.TextIter iter) {
            Gdk.Rectangle rect;
            get_location (iter, out rect, false);
            int vskip = paper_size.bottom_margin + section_skip_after - rect.height;
            string name = "section-break-%u".printf (section_break_serial++);
            var section_break = SectionBreak () {
                mark = buffer.create_mark (name, iter, true),
                tag = buffer.create_tag (name, "pixels-below-lines", vskip)
            };
            Gtk.TextIter break_iter;
            uint n;
            for (n = 0; n < section_breaks.length (); n++) {
                buffer.get_iter_at_mark (out break_iter, section_breaks.nth_data (n).mark);
                if (iter.compare (break_iter) < 0) {
                    break;
                }
            }
            section_breaks.insert (section_break, (int) n);
            return n;
        }
        
        private void restore_section_breaks (Gtk.TextIter start, Gtk.TextIter end) {
            var iter = start;
            int count = 0;
            while (
                move_to_tag_toggle (ref iter, true, "section-break", -1) &&
                iter.compare (end) < 0)
            {
                var n = create_section_break (iter);
                var next_iter = iter;
                next_iter.forward_char ();
                remove_tags ("section-break", iter, next_iter);
                buffer.apply_tag (section_breaks.nth_data (n).tag, iter, next_iter);
                iter.forward_char ();
                count++;
            }
            debug ("%d section breaks restored", count);
        }

/******************\
|* PUBLIC METHODS *|
\******************/

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
            text_view.grab_focus ();
        }

        public int move_to_section_start (ref Gtk.TextIter iter) {
            Gtk.TextIter start;
            uint n = 0;
            for (; n < section_breaks.length (); n++) {
                buffer.get_iter_at_mark (out start, section_breaks.nth_data (n).mark);
                if (iter.compare (start) < 0) {
                    if (n == 0) {
                        buffer.get_start_iter (out iter);
                        return -1;
                    }
                    break;
                }
            }
            buffer.get_iter_at_mark (out start, section_breaks.nth_data (n - 1).mark);
            iter.assign (start);
            iter.forward_char ();
            return (int) n - 1;
        }

        public void move_to_section_end (ref Gtk.TextIter iter) {
            Gtk.TextIter end;
            for (uint n = 0; n < section_breaks.length (); n++) {
                buffer.get_iter_at_mark (out end, section_breaks.nth_data (n).mark);
                if (iter.compare (end) < 0) {
                    iter.assign (end);
                    iter.backward_char ();
                    return;
                }
            }
            buffer.get_end_iter (out iter);
        }

        public void get_section_bounds (Gtk.TextIter where, out Gtk.TextIter start, out Gtk.TextIter end) {
            start = Gtk.TextIter ();
            start.assign (where);
            int index = move_to_section_start (ref start);
            index++;
            if (index < section_breaks.length ()) {
                buffer.get_iter_at_mark (out end, section_breaks.nth_data ((uint) index).mark);
                end.backward_char ();
            } else {
                buffer.get_end_iter (out end);
            }
        }

        public bool forward_paragraph (ref Gtk.TextIter iter, bool stop_after_section_break = false) {
            if (!iter.forward_line ()) {
                return false;
            }
            if (iter_at_section_break (iter)) {
                iter.forward_char ();
                if (stop_after_section_break) {
                    return false;
                }
            }
            return true;
        }

        public void move_to_paragraph_start (ref Gtk.TextIter iter) {
            iter.set_line_offset (0);
        }

        public void move_to_paragraph_end (ref Gtk.TextIter iter) {
            if (iter.forward_line ()) {
                iter.backward_char ();
            }
        }

        public void iterate_over_paragraphs (ref Gtk.TextIter start, TextRangeFunc paragraph_func) {
            var end = Gtk.TextIter ();
            do {
                end.assign (start);
                move_to_paragraph_end (ref end);
            } while (paragraph_func (start, end) && forward_paragraph (ref start));
            start.assign (end);
        }

        public bool range_intersects_selection (Gtk.TextIter start, Gtk.TextIter end) {
            var sel_start = Gtk.TextIter ();
            var sel_end = Gtk.TextIter ();
            if (!start.equal (end) && buffer.get_selection_bounds (out sel_start, out sel_end)) {
                assert (start.compare (end) < 0);
                return start.compare (sel_end) < 0 && end.compare (sel_start) > 0;
            }
            return false;
        }

        public void draw_section_breaks (Cairo.Context cr) {
            foreach (var section_break in section_breaks) {
                Gdk.Rectangle rect;
                Gtk.TextIter iter;
                buffer.get_iter_at_mark (out iter, section_break.mark);
                get_location (iter, out rect);
                rect.x = 1;
                rect.width = text_view.get_allocated_width () - 2;
                rect.height += section_break.tag.pixels_below_lines;
                Utils.fill_white_rectangle (cr, rect);
                rect.x = 0;
                rect.y += rect.height - section_skip_after;
                rect.width += 2;
                rect.height = paper_size.top_margin / 2;
                Gdk.cairo_set_source_rgba (cr, Utils.page_border_color ());
                cr.move_to (rect.x, rect.y);
                cr.rel_line_to (rect.width, 0);
                cr.move_to (rect.x, rect.y + rect.height);
                cr.rel_line_to (rect.width, 0);
                cr.stroke ();
                Utils.fill_rectangle_as_background (cr, rect);
            }
        }

        public void draw_page_breaks (Cairo.Context cr) {
            Gtk.TextIter start, end, iter;
            Gdk.Rectangle rect, rect_end, section_rect, tmp_rect;
            var viewport_rect = get_viewport_rectangle ();
            var win = Gtk.TextWindowType.WIDGET;
            int text_height = paper_size.text_height;
            int x = paper_size.left_margin;
            cr.set_source_rgba (1.0, 1.0, 1.0, 1.0);
            for (uint n = 0; n <= section_breaks.length (); n++) {
                if (n == 0) {
                    buffer.get_start_iter (out start);
                } else {
                    buffer.get_iter_at_mark (out start, section_breaks.nth_data (n - 1).mark);
                    start.forward_char ();
                }
                if (n < section_breaks.length ()) {
                    buffer.get_iter_at_mark (out end, section_breaks.nth_data (n).mark);
                } else {
                    buffer.get_end_iter (out end);
                }
                get_location (start, out rect);
                get_location (end, out rect_end);
                rect_end.union (rect, out section_rect);
                section_rect.x = x;
                section_rect.y -= paper_size.top_margin;
                section_rect.width = paper_size.text_width;
                if (n < section_breaks.length ()) {
                    end.forward_char ();
                    get_location (end, out tmp_rect);
                    end.backward_char ();
                    section_rect.height = tmp_rect.y - section_skip_after;
                } else {
                    section_rect.height = text_view.get_allocated_height ();
                }
                section_rect.height -= section_rect.y;
                if (to_viewport_coords (section_rect).intersect (viewport_rect, null)) {
                    int y = rect.y;
                    int end_y = rect_end.y + (n < section_breaks.length () ? 0 : rect_end.height);
                    int bx, by;
                    while ((y += text_height) < end_y) {
                        text_view.window_to_buffer_coords (win, x, y, out bx, out by);
                        text_view.get_iter_at_location (out iter, bx, by);
                        get_location (iter, out rect);
                        y = rect.y;
                        cr.save ();
                        Gdk.cairo_set_source_rgba (cr, Utils.page_border_color ());
                        cr.set_dash ({3, 4}, 0);
                        cr.move_to (0, y);
                        cr.line_to (paper_size.width, y);
                        cr.stroke ();
                        cr.restore ();
                        cr.rectangle (0, y - 1, paper_size.width, 3);
                        cr.stroke ();
                    }
                    if (n < section_breaks.length ()) {
                        get_location (end, out rect);
                        int vskip = y - rect.y - rect.height;
                        vskip += paper_size.bottom_margin + section_skip_after;
                        if (section_breaks.nth_data (n).tag.pixels_below_lines != vskip) {
                            section_breaks.nth_data (n).tag.pixels_below_lines = vskip;
                        }
                    } else {
                        int total_height = y + paper_size.bottom_margin;
                        if (text_view.get_allocated_height () != total_height) {
                            text_view.set_size_request (paper_size.width, total_height);
                        }
                    }
                }
            }
        }

    }

}
