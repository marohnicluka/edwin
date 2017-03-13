/* textbuffer.vala
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

    public class TextBuffer : Gtk.TextBuffer {

/*********************\
|* STRUCTS AND ENUMS *|
\*********************/

        public struct SectionBreak {
            uint serial;
            public unowned Gtk.TextMark mark;
            public unowned Gtk.TextTag? tag;
        }
        
/*************************\
|* FIELDS AND PROPERTIES *|
\*************************/

        public unowned TextView text_view { get; construct set; }
        public unowned Gtk.TextMark insert_start_mark { get; private set; }
        public unowned Gtk.TextMark pasted_start_mark { get; private set; }
        public unowned Gtk.TextMark selection_start_mark { get; private set; }
        public unowned Gtk.TextMark selection_end_mark { get; private set; }
        public unowned Gtk.TextTag tag_bold { get; private set; }
        public unowned Gtk.TextTag tag_italic { get; private set; }
        public unowned Gtk.TextTag tag_underline { get; private set; }
        public unowned Gtk.TextTag tag_aligned_left { get; private set; }
        public unowned Gtk.TextTag tag_aligned_right { get; private set; }
        public unowned Gtk.TextTag tag_centered { get; private set; }
        public unowned Gtk.TextTag tag_justified { get; private set; }
        public unowned Gtk.TextTag tag_enumerate { get; private set; }
        public unowned Gtk.TextTag tag_itemize { get; private set; }
        public unowned Gtk.TextTag tag_skip { get; private set; }
        public unowned Gtk.TextTag tag_no_page_break { get; private set; }
        public HashTable<string, unowned Gtk.TextTag> font_family_tags { get; private set; }
        public HashTable<int, unowned Gtk.TextTag> text_size_tags { get; private set; }
        public HashTable<Gdk.RGBA?, unowned Gtk.TextTag> text_color_tags { get; private set; }
        
        public uint n_section_breaks { get { return section_breaks.length (); } }
        public bool text_properties_changed { get; set; default = false; }
        
        List<SectionBreak?> section_breaks = new List<SectionBreak?> ();
        uint section_break_serial = 0;
        int justification_before_insert = 0;
        int cursor_movement_direction = 0;
        bool insertion_in_progress = false;
        bool deletion_in_progress = false;
        bool user_is_deleting = false;
        bool user_is_typing = false;
        
        private unowned Document doc { get { return text_view.doc; } }
        private Gtk.TextIter cursor {
            get {
                Gtk.TextIter iter;
                get_iter_at_mark (out iter, get_insert ());
                return iter;
            }
        }
        
        public signal void section_breaks_deleted (uint[] indexes);

/****************\
|* CONSTRUCTION *|
\****************/

        public TextBuffer (TextView text_view) {
            this.text_view = text_view;
            create_tags_and_marks ();
            connect_signals ();
        }
        
        private void create_tags_and_marks () {
            /* tags */
            tag_bold = create_tag ("bold",
                "weight", Pango.Weight.BOLD);
            tag_italic = create_tag ("italic",
                "style", Pango.Style.ITALIC);
            tag_underline = create_tag ("underline",
                "underline", Pango.Underline.SINGLE);
            tag_aligned_left = create_tag ("aligned-left",
                "justification", Gtk.Justification.LEFT);
            tag_aligned_right = create_tag ("aligned-right",
                "justification", Gtk.Justification.RIGHT);
            tag_centered = create_tag ("centered",
                "justification", Gtk.Justification.CENTER);
            tag_justified = create_tag ("justified",
                "justification", Gtk.Justification.FILL);
            tag_enumerate = create_tag ("enumerate");
            tag_itemize = create_tag ("itemize");
            /* internal tags */
            tag_skip = create_tag ("internal:skip");
            tag_no_page_break = create_tag ("internal:no-page-break");
            font_family_tags = new HashTable<string, unowned Gtk.TextTag> (str_hash, str_equal);
            text_size_tags = new HashTable<int, unowned Gtk.TextTag> (direct_hash, direct_equal);
            text_color_tags = new HashTable<Gdk.RGBA?, unowned Gtk.TextTag> (
                (key) => { return key.hash (); },
                (a, b) => { return a.equal (b); }
            );
            /* marks */
            Gtk.TextIter where;
            get_start_iter (out where);
            insert_start_mark = create_mark (null, where, true);
            pasted_start_mark = create_mark (null, where, true);
            selection_start_mark = create_mark (null, where, true);
            selection_end_mark = create_mark (null, where, false);
        }
        
        private void connect_signals () {
            text_view.move_cursor.connect (on_move_cursor);
            text_view.key_press_event.connect (on_key_press_event);
            text_view.drag_begin.connect (on_drag_begin);
            text_view.drag_end.connect (on_drag_end);
            text_view.backspace.connect (on_backspace);
            text_view.delete_from_cursor.connect (on_delete_from_cursor);
            text_view.paste_clipboard.connect (on_paste_clipboard);
            notify["cursor-position"].connect (on_cursor_position_changed);
            notify["has-selection"].connect (on_has_selection_changed);
            notify["text"].connect (on_text_changed);
            paste_done.connect (on_paste_done);
            insert_text.connect (on_insert_text);
            insert_text.connect_after (on_insert_text_after);
            delete_range.connect (on_delete_range);
            delete_range.connect_after (on_delete_range_after);
            mark_set.connect (on_mark_set);
            apply_tag.connect (on_apply_tag);
            remove_tag.connect (on_remove_tag);
        }
        
/*************\
|* CALLBACKS *|
\*************/

        private void on_backspace () {
            if (!user_is_deleting) {
                doc.begin_user_action ();
                user_is_deleting = true;
                user_is_typing = false;
            }
        }
        
        private void on_delete_from_cursor (Gtk.DeleteType type, int count) {
            on_backspace ();
        }
        
        private void on_drag_begin (Gdk.DragContext context) {
            debug ("Drag started");
            doc.begin_user_action ();
        }
        
        private void on_drag_end (Gdk.DragContext context) {
            debug ("Drag ended");
            doc.end_user_action ();
        }

        private void on_apply_tag (Gtk.TextTag tag, Gtk.TextIter start, Gtk.TextIter end) {
            if (tag.name == null || !tag.name.has_prefix ("gtkspell")) {
                doc.push_undo_operation_tag (start, end, tag, true);
            }
            doc.on_text_changed ();
        }

        private void on_remove_tag (Gtk.TextTag tag, Gtk.TextIter start, Gtk.TextIter end) {
            if (tag.name == null || !tag.name.has_prefix ("gtkspell")) {
                doc.push_undo_operation_tag (start, end, tag, false);
            }
            doc.on_text_changed ();
        }

        private void on_paste_clipboard () {
            move_mark (pasted_start_mark, cursor);
            doc.begin_user_action ();
        }

        private void on_paste_done (Gtk.Clipboard clipboard) {
            Gtk.TextIter pasted_start;
            get_iter_at_mark (out pasted_start, pasted_start_mark);
            restore_section_breaks (pasted_start, cursor);
            doc.end_user_action ();
        }
        
        private void on_mark_set (Gtk.TextIter location, Gtk.TextMark mark) {
            if (has_selection && (mark == get_insert () || mark == get_selection_bound ()))
            {
                on_selection_range_changed ();
            }
        }

        private void on_has_selection_changed () {
            if (!text_view.has_focus && !has_selection) {
                restore_selection ();
            } else if (text_view.has_focus && has_selection) {
                save_selection ();
            }
        }

        private void on_selection_range_changed () {
            save_selection ();
            doc.schedule_update_toolbar ();
        }

        private bool on_key_press_event (Gdk.EventKey event) {
            bool ctrl = (event.state & Gdk.ModifierType.CONTROL_MASK) != 0;
            switch (event.keyval) {
            case Gdk.Key.Return:
                if (ctrl) {
                    Gtk.TextIter start, end;
                    doc.begin_user_action ();
                    if (get_selection_bounds (out start, out end)) {
                        @delete (ref start, ref end);
                    }
                    insert_at_cursor ("\n", -1);
                    var n = create_section_break (cursor);
                    insert_at_cursor ("\n", -1);
                    get_iter_at_mark (out start, nth_section_break (n).mark);
                    apply_tag (nth_section_break (n).tag, start, cursor);
                    doc.end_user_action ();
                    return true;
                }
                break;
            }
            if (event.str.get_char ().isgraph () && !user_is_typing) {
                doc.begin_user_action ();
                user_is_typing = true;
                user_is_deleting = false;
            }
            if (event.str.get_char ().isspace ()) {
                doc.begin_user_action ();
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
                if (has_selection) {
                    move_mark (get_insert (), iter);
                } else {
                    place_cursor (iter);
                }
            } else if (iter.has_tag (tag_skip) && !iter.toggles_tag (tag_skip)) {
                int test = cursor_movement_direction;
                if (has_selection) {
                    get_iter_at_mark (out selection_bound, get_selection_bound ());
                    test = selection_bound.compare (iter);
                }
                if (test < 0) {
                    iter.backward_to_tag_toggle (tag_skip);
                } else {
                    iter.forward_to_tag_toggle (tag_skip);
                }
                if (has_selection) {
                    move_mark (get_insert (), iter);
                } else {
                    place_cursor (iter);
                }
            }
            if (!insertion_in_progress) {
                text_properties_changed = false;
                user_is_typing = false;
            }
            if (!deletion_in_progress) {
                user_is_deleting = false;
            }
            if (doc.user_action_in_progress && !insertion_in_progress && !deletion_in_progress) {
                doc.end_user_action ();
            }
            cursor_movement_direction = 0;
            text_view.schedule_scroll_to_cursor ();
            if (!has_selection) {
                doc.schedule_update_toolbar ();
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
            doc.push_undo_operation_delete (start, end);
        }

        private void on_delete_range_after (Gtk.TextIter start, Gtk.TextIter end) {
            uint[] deleted_section_breaks = { };
            start.get_marks ().@foreach ((mark) => {
                if (mark.name != null && mark.name.has_prefix ("section-break")) {
                    var serial = (uint) int.parse (mark.name.substring (14));
                    var n = get_section_break_index_from_serial (serial);
                    section_breaks.remove (section_breaks.nth_data (n));
                    deleted_section_breaks += n;
                    delete_mark (mark);
                }
            });
            if (deleted_section_breaks.length > 0) {
                debug ("Deleted %d section breaks", deleted_section_breaks.length);
            }
            section_breaks_deleted (deleted_section_breaks);
            deletion_in_progress = false;
            text_view.schedule_scroll_to_cursor ();
        }

        private void on_insert_text (ref Gtk.TextIter iter, string text, int len) {
            move_mark (insert_start_mark, iter);
            insertion_in_progress = true;
            justification_before_insert = text_properties_changed ?
                doc.toolbar.get_paragraph_alignment () :
                get_paragraph_justification (iter);
        }

        private void on_insert_text_after (ref Gtk.TextIter end, string text, int len) {
            Gtk.TextIter start;
            get_iter_at_mark (out start, insert_start_mark);
            doc.push_undo_operation_insert (start, end);
            if (!doc.doing_undo_redo) {
                style_inserted_text (start, end);
            }
            insertion_in_progress = false;
            text_properties_changed = false;
            text_view.schedule_scroll_to_cursor ();
        }
        
        private void on_text_changed () {
            doc.on_text_changed ();
        }

/*******************\
|* PRIVATE METHODS *|
\*******************/

        private uint get_section_break_index_from_serial (uint serial) {
            uint n = 0;
            for (; n < section_breaks.length (); n++) {
                if (section_breaks.nth_data (n).serial == serial) {
                    return n;
                }
            }
            assert_not_reached ();
        }

        private void save_selection () {
            Gtk.TextIter start, end;
            if (get_selection_bounds (out start, out end)) {
                move_mark (selection_start_mark, start);
                move_mark (selection_end_mark, end);
            }
        }
        
        private void restore_selection () {
            Gtk.TextIter start, end;
            get_iter_at_mark (out start, selection_start_mark);
            get_iter_at_mark (out end, selection_end_mark);
            select_range (start, end);
        }
        
        private bool tag_has_id (Gtk.TextTag tag, string id) {
            return tag.name != null && tag.name.has_prefix (id);
        }

        private void style_inserted_text (Gtk.TextIter start, Gtk.TextIter end) {
            bool modified;
            var attributes = get_attributes_before (start, out modified);
            if (modified || text_properties_changed) {
                var font_desc = text_properties_changed ?
                    doc.toolbar.get_text_font_desc () :
                    attributes.font;
                var family_tag = get_font_family_tag (font_desc.get_family ());
                var size_tag = get_text_size_tag (font_desc.get_size ());
                var color_tag = get_text_color_tag (text_properties_changed ?
                    doc.toolbar.get_text_color () :
                    get_text_color (start));
                bool has_bold_tag = font_desc.get_weight () == Pango.Weight.BOLD;
                bool has_italic_tag = font_desc.get_style () == Pango.Style.ITALIC;
                bool has_underline_tag = text_properties_changed ?
                    doc.toolbar.get_underline_state () :
                    attributes.appearance.underline == Pango.Underline.SINGLE;
                apply_tag_with_id (family_tag, "font-family", start, end);
                apply_tag_with_id (size_tag, "text-size", start, end);
                apply_tag_with_id (color_tag, "text-color", start, end);
                if (has_bold_tag) {
                    apply_tag (tag_bold, start, end);
                }
                if (has_italic_tag) {
                    apply_tag (tag_italic, start, end);
                }
                if (has_underline_tag) {
                    apply_tag (tag_underline, start, end);
                }
            }
            var iter = end;
            move_to_paragraph_end (ref iter);
            apply_alignment_to_range (justification_before_insert, start, iter);
        }

/******************\
|* PUBLIC METHODS *|
\******************/

        public unowned Gtk.TextTag get_font_family_tag (string family) {
            unowned Gtk.TextTag? tag = font_family_tags.lookup (family);
            if (tag == null) {
                tag = create_tag (@"font-family:$family",
                    "family", family);
                font_family_tags.insert (family, tag);
            }
            return tag;
        }

        public unowned Gtk.TextTag get_text_size_tag (int size) {
            unowned Gtk.TextTag? tag = text_size_tags.lookup (size);
            if (tag == null) {
                tag = create_tag (@"text-size:%d".printf (size / Pango.SCALE),
                    "size", size);
                text_size_tags.insert (size, tag);
            }
            return tag;
        }

        public unowned Gtk.TextTag get_text_color_tag (Gdk.RGBA color) {
            unowned Gtk.TextTag? tag = text_color_tags.lookup (color);
            if (tag == null) {
                tag = create_tag (@"text-color:%s".printf (color.to_string ()),
                    "foreground-rgba", color);
                text_color_tags.insert (color, tag);
            }
            return tag;
        }
        
        public unowned Gtk.TextTag? get_tag_at_iter (Gtk.TextIter iter, string id) {
            var tags = iter.get_tags ();
            var tags_ended = iter.get_toggled_tags (false);
            tags.concat ((owned) tags_ended);
            assert (tags_ended == null);
            foreach (var tag in tags) {
                if (tag_has_id (tag, id)) {
                    return tag;
                }
            }
            return null;
        }

        public void remove_tags (string id, Gtk.TextIter start, Gtk.TextIter end) {
            tag_table.@foreach ((tag) => {
                if (tag_has_id (tag, id)) {
                    remove_tag (tag, start, end);
                }
            });
        }

        public bool move_to_tag_toggle (ref Gtk.TextIter iter, bool forward, string id, int dir = 0, out unowned Gtk.TextTag toggled_tag = null) {
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
                    assert (tmp_tags == null);
                    break;
                default:
                    assert_not_reached ();
                }
                foreach (var tag in tags) {
                    if (tag_has_id (tag, id)) {
                        toggled_tag = tag;
                        return true;
                    }
                }
            } while (forward ? iter.forward_to_tag_toggle (null) : iter.backward_to_tag_toggle (null));
            toggled_tag = null;
            return false;
        }

        public void apply_tag_with_id (Gtk.TextTag tag, string id, Gtk.TextIter start, Gtk.TextIter end) {
            var range_start = start;
            var range_end = Gtk.TextIter ();
            while (range_start.compare (end) < 0) {
                range_end.assign (range_start);
                move_to_tag_toggle (ref range_end, true, id, -1);
                if (range_end.compare (end) > 0) {
                    range_end.assign (end);
                }
                if (!range_start.equal (range_end)) {
                    apply_tag (tag, range_start, range_end);
                }
                if (range_end.equal (end)) {
                    break;
                }
                range_start.assign (range_end);
                range_start.forward_char ();
                move_to_tag_toggle (ref range_start, true, id, 1);
            }
        }

        public uint create_section_break (Gtk.TextIter iter) {
            string name = "section-break:%u".printf (section_break_serial);
            var section_break = SectionBreak () {
                serial = section_break_serial,
                mark = create_mark (name, iter, true),
                tag = create_tag (name)
            };
            Gtk.TextIter break_iter;
            uint n;
            for (n = 0; n < section_breaks.length (); n++) {
                get_iter_at_mark (out break_iter, section_breaks.nth_data (n).mark);
                if (iter.compare (break_iter) < 0) {
                    break;
                }
            }
            section_breaks.insert (section_break, (int) n);
            section_break_serial++;
            return n;
        }
        
        public unowned SectionBreak? nth_section_break (uint n) {
            assert (n < section_breaks.length ());
            return section_breaks.nth_data (n);
        }
        
        public bool iter_at_section_break (Gtk.TextIter iter) {
            foreach (var mark in iter.get_marks ()) {
                if (mark.name != null && mark.name.has_prefix ("section-break")) {
                    return true;
                }
            }
            return false;
        }

        public void restore_section_breaks (Gtk.TextIter start, Gtk.TextIter end) {
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
                apply_tag (section_breaks.nth_data (n).tag, iter, next_iter);
                iter.forward_char ();
                count++;
            }
            debug ("%d section breaks restored", count);
        }

        public void move_to_paragraph_start (ref Gtk.TextIter iter) {
            iter.set_line_offset (0);
        }

        public void move_to_paragraph_end (ref Gtk.TextIter iter) {
            if (iter.forward_line ()) {
                iter.backward_char ();
            }
        }

        public int move_to_section_start (ref Gtk.TextIter iter) {
            Gtk.TextIter start;
            uint n = 0;
            for (; n < section_breaks.length (); n++) {
                get_iter_at_mark (out start, section_breaks.nth_data (n).mark);
                if (iter.compare (start) < 0) {
                    if (n == 0) {
                        get_start_iter (out iter);
                        return -1;
                    }
                    break;
                }
            }
            get_iter_at_mark (out start, section_breaks.nth_data (n - 1).mark);
            iter.assign (start);
            iter.forward_char ();
            return (int) n - 1;
        }

        public void move_to_section_end (ref Gtk.TextIter iter) {
            Gtk.TextIter end;
            for (uint n = 0; n < section_breaks.length (); n++) {
                get_iter_at_mark (out end, section_breaks.nth_data (n).mark);
                if (iter.compare (end) < 0) {
                    iter.assign (end);
                    iter.backward_char ();
                    return;
                }
            }
            get_end_iter (out iter);
        }

        public int get_section_bounds (Gtk.TextIter where, out Gtk.TextIter start, out Gtk.TextIter end) {
            start = Gtk.TextIter ();
            start.assign (where);
            int index = move_to_section_start (ref start);
            index++;
            if (index < section_breaks.length ()) {
                get_iter_at_mark (out end, section_breaks.nth_data ((uint) index).mark);
                end.backward_char ();
            } else {
                get_end_iter (out end);
            }
            return index;
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

        public bool range_intersects_selection (Gtk.TextIter start, Gtk.TextIter end) {
            var sel_start = Gtk.TextIter ();
            var sel_end = Gtk.TextIter ();
            if (!start.equal (end) && get_selection_bounds (out sel_start, out sel_end)) {
                assert (start.compare (end) < 0);
                return start.compare (sel_end) < 0 && end.compare (sel_start) > 0;
            }
            return false;
        }
        
        public void get_styled_paragraph_bounds (Gtk.TextIter where, out Gtk.TextIter start, out Gtk.TextIter end) {
            start = where;
            end = where;
            var tag = get_tag_at_iter (where, "paragraph-style");
            if (tag == null) {
                move_to_paragraph_start (ref start);
                move_to_paragraph_end (ref end);
            } else {
                if (!start.begins_tag (tag)) {
                    start.backward_to_tag_toggle (tag);
                }
                if (!end.ends_tag (tag)) {
                    end.forward_to_tag_toggle (tag);
                }
            }
        }
        
        public void apply_alignment_to_range (int justification, Gtk.TextIter start, Gtk.TextIter end) {
            if (start.equal (end)) {
                return;
            }
            remove_tag (tag_aligned_left, start, end);
            remove_tag (tag_aligned_right, start, end);
            remove_tag (tag_centered, start, end);
            remove_tag (tag_justified, start, end);
            if (justification >= 0 && justification != text_view.get_default_attributes ().justification) {
                switch (justification) {
                case Gtk.Justification.LEFT:
                    apply_tag (tag_aligned_left, start, end);
                    break;
                case Gtk.Justification.RIGHT:
                    apply_tag (tag_aligned_right, start, end);
                    break;
                case Gtk.Justification.CENTER:
                    apply_tag (tag_centered, start, end);
                    break;
                case Gtk.Justification.FILL:
                    apply_tag (tag_justified, start, end);
                    break;
                }
            }
        }

        public Gtk.TextAttributes get_attributes_before (Gtk.TextIter where, out bool modified = null) {
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

        public Gtk.Justification get_paragraph_justification (Gtk.TextIter where) {
            var iter = where;
            move_to_paragraph_start (ref iter);
            while (iter.ends_line () && iter.backward_char ());
            var attributes = text_view.get_default_attributes ();
            iter.get_attributes (attributes);
            return attributes.justification;
        }

        public Gdk.RGBA get_text_color (Gtk.TextIter where) {
            var iter = where;
            Gdk.RGBA color = text_view.default_text_color;
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

    }
    
}