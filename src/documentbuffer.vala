/* documentbuffer.vala
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

    public class DocumentBuffer : Gtk.TextBuffer {
    
        public const Gtk.TextSearchFlags SEARCH_FLAGS =
            Gtk.TextSearchFlags.TEXT_ONLY |
            Gtk.TextSearchFlags.CASE_INSENSITIVE;

/**********************\
|* FIELDS AND SIGNALS *|
\**********************/

        public unowned DocumentView view { get; construct set; }
        public unowned Gtk.TextMark insert_start_mark { get; private set; }
        public unowned Gtk.TextMark pasted_start_mark { get; private set; }
        public unowned Gtk.TextMark selection_start_mark { get; private set; }
        public unowned Gtk.TextMark selection_end_mark { get; private set; }
        public unowned Gtk.TextMark current_search_match_mark { get; private set; }
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
        public unowned Gtk.TextTag tag_search_match { get; private set; }
        public unowned Gtk.TextTag tag_search_match_focused { get; private set; }
        public unowned Gtk.TextTag tag_zoom { get; private set; }
        public HashTable<string, unowned Gtk.TextTag> font_family_tags { get; private set; }
        public HashTable<int, unowned Gtk.TextTag> text_size_tags { get; private set; }
        public HashTable<Gdk.RGBA?, unowned Gtk.TextTag> text_color_tags { get; private set; }
        
        public bool text_properties_changed { get; set; default = false; }
        public bool pasting { get; private set; default = false; }
        public bool can_replace { get; private set; default = false; }
        public unowned Document doc { get { return view.doc; } }
        public Gdk.Atom serialize_format { get; private set; }
        public Gdk.Atom deserialize_format { get; private set; }
        public uint n_forced_page_breaks { get { return forced_page_breaks.length (); } }
        public Gtk.TextIter cursor {
            get {
                Gtk.TextIter iter;
                get_iter_at_mark (out iter, get_insert ());
                return iter;
            }
        }
                
        uint search_handler = 0;
        int n_search_matches = 0;
        int justification_before_insert = 0;
        int cursor_movement_direction = 0;
        bool insertion_in_progress = false;
        bool deletion_in_progress = false;
        bool user_is_deleting = false;
        bool user_is_typing = false;
        List<unowned Gtk.TextMark> forced_page_breaks;
                
        public signal void search_finished (int matches);
        
/****************\
|* CONSTRUCTION *|
\****************/

        public DocumentBuffer (DocumentView view) {
            this.view = view;
            serialize_format = register_serialize_tagset (null);
            deserialize_format = register_deserialize_tagset (null);
            forced_page_breaks = new List<unowned Gtk.TextMark> ();
            create_tags_and_marks ();
            connect_signals ();
        }
        
        private void create_tags_and_marks () {
            /* tags */
            tag_bold = create_tag ("edwin-bold",
                "weight", Pango.Weight.BOLD);
            tag_italic = create_tag ("edwin-italic",
                "style", Pango.Style.ITALIC);
            tag_underline = create_tag ("edwin-underline",
                "underline", Pango.Underline.SINGLE);
            tag_aligned_left = create_tag ("edwin-aligned-left",
                "justification", Gtk.Justification.LEFT);
            tag_aligned_right = create_tag ("edwin-aligned-right",
                "justification", Gtk.Justification.RIGHT);
            tag_centered = create_tag ("edwin-centered",
                "justification", Gtk.Justification.CENTER);
            tag_justified = create_tag ("edwin-justified",
                "justification", Gtk.Justification.FILL);
            tag_enumerate = create_tag ("edwin-enumerate");
            tag_itemize = create_tag ("edwin-itemize");
            /* internal tags */
            tag_skip = create_tag ("edwin-internal:skip");
            tag_no_page_break = create_tag ("edwin-internal:no-page-break");
            tag_search_match = create_tag ("edwin-internal:search-match",
                "background-rgba", Utils.get_color ("highlight"));
            tag_search_match_focused = create_tag ("edwin-internal:search-match-focused",
                "background-rgba", Utils.get_color ("selection-unfocused"));
            tag_zoom = create_tag ("edwin-internal:zoom");
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
            current_search_match_mark = create_mark (null, where, true);
        }
        
        private void connect_signals () {
            view.move_cursor.connect (on_move_cursor);
            view.key_press_event.connect (on_key_press_event);
            view.drag_begin.connect (on_drag_begin);
            view.drag_end.connect (on_drag_end);
            view.backspace.connect (on_backspace);
            view.delete_from_cursor.connect (on_delete_from_cursor);
            view.paste_clipboard.connect (on_paste_clipboard);
            notify["cursor-position"].connect (on_cursor_position_changed);
            notify["has-selection"].connect (on_has_selection_changed);
            notify["text"].connect (on_text_changed);
            paste_done.connect (on_paste_done);
            mark_set.connect (on_mark_set);
            apply_tag.connect (on_apply_tag);
            remove_tag.connect (on_remove_tag);
            insert_text.connect (on_insert_text);
            insert_text.connect_after (on_insert_text_after);
            delete_range.connect (on_delete_range);
            delete_range.connect_after (on_delete_range_after);
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
            if (!tag_is_internal (tag)) {
                doc.push_undo_operation_tag (start, end, tag, true);
            }
            doc.on_text_changed ();
        }

        private void on_remove_tag (Gtk.TextTag tag, Gtk.TextIter start, Gtk.TextIter end) {
            if (!tag_is_internal (tag)) {
                doc.push_undo_operation_tag (start, end, tag, false);
            }
            doc.on_text_changed ();
        }

        private void on_paste_clipboard () {
            move_mark (pasted_start_mark, cursor);
            doc.begin_user_action ();
            before_insertion_routine (cursor);
            pasting = true;
        }

        private void on_paste_done (Gtk.Clipboard clipboard) {
            Gtk.TextIter start;
            get_iter_at_mark (out start, pasted_start_mark);
            after_insertion_routine (start, cursor);
            doc.end_user_action ();
            pasting = false;
            view.scroll_to_cursor ();
        }
        
        private void on_mark_set (Gtk.TextIter location, Gtk.TextMark mark) {
            if (has_selection && (mark == get_insert () || mark == get_selection_bound ()))
            {
                on_selection_range_changed ();
            } else if (mark == current_search_match_mark) {
                view.scroll_mark_onscreen (current_search_match_mark);
            }
        }

        private void on_has_selection_changed () {
            if (!has_selection) {
                can_replace = false;
                if (!view.has_focus) {
                    restore_selection ();
                }
            } else if (view.has_focus) {
                save_selection ();
            }
        }

        private void on_selection_range_changed () {
            can_replace = false;
            save_selection ();
            doc.schedule_update_toolbar ();
        }

        private bool on_key_press_event (Gdk.EventKey event) {
            bool ctrl = (event.state & Gdk.ModifierType.CONTROL_MASK) != 0;
            switch (event.keyval) {
            case Gdk.Key.Return:
                if (ctrl) {
                    insert_at_cursor ("\n", -1);
                    insert_forced_page_break (cursor);
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
            if (iter.has_tag (tag_skip) && !iter.toggles_tag (tag_skip)) {
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
            if (view.has_focus) {
                view.scroll_to_cursor ();
            }
            if (!has_selection) {
                doc.schedule_update_toolbar ();
            }
        }

        private void on_delete_range (Gtk.TextIter start, Gtk.TextIter end) {
            Gtk.TextIter iter;
            for (uint n = 0; n < forced_page_breaks.length (); n++) {
                get_iter_at_mark (out iter, get_nth_forced_page_break (n));
                if (iter.compare (start) > 0 && iter.compare (end) <= 0) {
                    remove_nth_forced_page_break (n);
                }
            }
            deletion_in_progress = true;
            doc.push_undo_operation_delete (start, end);
        }

        private void on_delete_range_after (Gtk.TextIter start, Gtk.TextIter end) {
            deletion_in_progress = false;
        }

        private void on_insert_text (ref Gtk.TextIter iter, string text, int len) {
            move_mark (insert_start_mark, iter);
            insertion_in_progress = true;
            if (!pasting) {
                before_insertion_routine (iter);
            }
        }

        private void on_insert_text_after (ref Gtk.TextIter end, string text, int len) {
            Gtk.TextIter start;
            get_iter_at_mark (out start, insert_start_mark);
            apply_tag (tag_zoom, start, end);
            if (!pasting) {
                after_insertion_routine (start, end);
            }
            insertion_in_progress = false;
            text_properties_changed = false;
        }
        
        private void on_text_changed () {
            doc.on_text_changed ();
        }
        
/*******************\
|* PRIVATE METHODS *|
\*******************/

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
        
        private bool tag_has_id (Gtk.TextTag tag, string ids) {
            if (tag.name != null) {
                foreach (var id in ids.split (",")) {
                    if (tag.name.has_prefix (id.strip ())) {
                        return true;
                    }
                }
            }
            return false;
        }
        
        private void before_insertion_routine (Gtk.TextIter iter) {
            justification_before_insert = text_properties_changed ?
                doc.toolbar.get_paragraph_alignment () :
                get_paragraph_justification (iter);
        }

        private void after_insertion_routine (Gtk.TextIter start, Gtk.TextIter end) {
            doc.push_undo_operation_insert (start, end);
            if (doc.doing_undo_redo) {
                return;
            }
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
                apply_tag_with_id (family_tag, "edwin-font-family", start, end);
                apply_tag_with_id (size_tag, "edwin-text-size", start, end);
                apply_tag_with_id (color_tag, "edwin-text-color", start, end);
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
        
        private void search_for_string_in_paragraph (string str, Gtk.TextIter start, Gtk.TextIter end) {
            Gtk.TextIter match_start, match_end;
            var iter = start;
            var limit = iter;
            move_to_paragraph_end (ref limit);
            if (limit.compare (end) > 0) {
                limit.assign (end);
            }
            while (iter.forward_search (str, SEARCH_FLAGS, out match_start, out match_end, limit)) {
                apply_tag (tag_search_match, match_start, match_end);
                iter.assign (match_end);
                n_search_matches++;
            }
            if (forward_paragraph (ref iter)) {
                search_handler = Timeout.add (5, () => {
                    search_for_string_in_paragraph (str, iter, end);
                    return false;
                });
            } else {
                search_finished (n_search_matches);
                search_handler = 0;
            }
        }
        
        private void remove_tag_undoable (Gtk.TextTag tag, Gtk.TextIter start, Gtk.TextIter end) {
            var iter = start;
            var end_iter = Gtk.TextIter ();
            while (iter.compare (end) < 0) {
                if (iter.has_tag (tag)) {
                    end_iter.assign (iter);
                    end_iter.forward_to_tag_toggle (tag);
                    if (end_iter.compare (end) > 0) {
                        end_iter.assign (end);
                    }
                    remove_tag (tag, iter, end_iter);
                } else if (!iter.forward_to_tag_toggle (tag)) {
                    break;
                }
            }
        }
        
        private void replace_search_match (ref Gtk.TextIter match_start, string replacement) {
            var iter = match_start;
            iter.forward_to_tag_toggle (tag_search_match);
            insert_text (ref iter, replacement, -1);
            if (!iter.ends_tag (tag_search_match)) {
                iter.backward_to_tag_toggle (tag_search_match);
            }
            match_start.assign (iter);
            match_start.backward_to_tag_toggle (tag_search_match);
            @delete (ref match_start, ref iter);
        }
        
        private void insert_forced_page_break (Gtk.TextIter where)
            requires (where.starts_line ())
        {
            forced_page_breaks.append (create_mark (null, where, true));
        }
        
        private void remove_nth_forced_page_break (uint n)
            requires (n < forced_page_breaks.length ())
        {
            forced_page_breaks.remove (forced_page_breaks.nth_data (n));
        }
        
/******************\
|* PUBLIC METHODS *|
\******************/

        public void set_zoom (double @value) {
            tag_zoom.scale = @value;
        }

        public bool tag_is_internal (Gtk.TextTag tag) {
            return tag_has_id (tag, "gtkspell,edwin-internal");
        }

        public unowned Gtk.TextTag get_font_family_tag (string family) {
            unowned Gtk.TextTag? tag = font_family_tags.lookup (family);
            if (tag == null) {
                tag = create_tag (@"edwin-font-family:$family",
                    "family", family);
                font_family_tags.insert (family, tag);
            }
            return tag;
        }

        public unowned Gtk.TextTag get_text_size_tag (int size) {
            unowned Gtk.TextTag? tag = text_size_tags.lookup (size);
            if (tag == null) {
                tag = create_tag (@"edwin-text-size:%d".printf (size / Pango.SCALE),
                    "size", size);
                text_size_tags.insert (size, tag);
            }
            return tag;
        }

        public unowned Gtk.TextTag get_text_color_tag (Gdk.RGBA color) {
            unowned Gtk.TextTag? tag = text_color_tags.lookup (color);
            if (tag == null) {
                tag = create_tag (@"edwin-text-color:%s".printf (color.to_string ()),
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

        public void remove_tags (string? id, Gtk.TextIter start, Gtk.TextIter end) {
            tag_table.@foreach ((tag) => {
                if (id == null || tag_has_id (tag, id)) {
                    remove_tag_undoable (tag, start, end);
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

        public void move_to_paragraph_start (ref Gtk.TextIter iter) {
            iter.set_line_offset (0);
        }

        public void move_to_paragraph_end (ref Gtk.TextIter iter) {
            if (iter.forward_line ()) {
                iter.backward_char ();
            }
        }
        
        public bool forward_paragraph (ref Gtk.TextIter iter) {
            Gtk.TextIter end;
            get_end_iter (out end);
            return iter.forward_line () && iter.compare (end) < 0;
        }

        public void get_styled_paragraph_bounds (Gtk.TextIter where, out Gtk.TextIter start, out Gtk.TextIter end) {
            start = where;
            end = where;
            var tag = get_tag_at_iter (where, "edwin-paragraph-style");
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
            (unowned Gtk.TextTag)[] alignment_tags =
                {tag_aligned_left, tag_aligned_right, tag_centered, tag_justified};
            foreach (var tag in alignment_tags) {
                remove_tag_undoable (tag, start, end);
            }
            if (justification >= 0 && justification != view.get_default_attributes ().justification) {
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
            var attributes = view.get_default_attributes ();
            var iter = where;
            if (iter.backward_char ()) {
                modified = iter.get_attributes (attributes);
            }
            return attributes;
        }

        public Gtk.Justification get_paragraph_justification (Gtk.TextIter where) {
            var iter = where;
            move_to_paragraph_start (ref iter);
            while (iter.ends_line () && iter.backward_char ());
            var attributes = view.get_default_attributes ();
            iter.get_attributes (attributes);
            return attributes.justification;
        }

        public Gdk.RGBA get_text_color (Gtk.TextIter where) {
            var iter = where;
            Gdk.RGBA color = view.default_text_color;
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
        
        public void clear_search () {
            if (search_handler != 0) {
                Source.remove (search_handler);
                search_handler = 0;
            }
            if (n_search_matches > 0) {
                Gtk.TextIter start, end;
                get_bounds (out start, out end);
                remove_tag (tag_search_match, start, end);
                remove_tag (tag_search_match_focused, start, end);
            }
            n_search_matches = 0;
        }

        public void begin_search_in_range (string str, Gtk.TextIter start, Gtk.TextIter end) {
            clear_search ();
            if (str.length == 0) {
                search_finished (0);
            } else {
                search_for_string_in_paragraph (str, start, end);
            }
        }
        
        public bool select_first_search_match ()
            requires (n_search_matches > 0)
        {
            Gtk.TextIter iter;
            var end = Gtk.TextIter ();
            get_start_iter (out iter);
            if (!iter.has_tag (tag_search_match)) {
                assert (iter.forward_to_tag_toggle (tag_search_match));
            }
            end.assign (iter);
            end.forward_to_tag_toggle (tag_search_match);
            apply_tag (tag_search_match_focused, iter, end);
            move_mark (current_search_match_mark, iter);
            iter.assign (end);
            return iter.forward_to_tag_toggle (tag_search_match);
        }
        
        public void unfocus_current_search_match ()
            requires (search_match_selected ())
        {
            Gtk.TextIter start;
            get_iter_at_mark (out start, current_search_match_mark);
            var end = start;
            end.forward_to_tag_toggle (tag_search_match_focused);
            remove_tag (tag_search_match_focused, start, end);
        }
        
        public bool select_next_search_match (out bool has_next) {
            Gtk.TextIter iter;
            get_iter_at_mark (out iter, current_search_match_mark);
            var start = Gtk.TextIter ();
            bool start_found = false;
            bool end_found = false;
            has_next = false;
            while (iter.forward_to_tag_toggle (tag_search_match)) {
                if (end_found) {
                    has_next = true;
                    return true;
                }
                if (start_found && iter.ends_tag (tag_search_match)) {
                    apply_tag (tag_search_match_focused, start, iter);
                    move_mark (current_search_match_mark, start);
                    end_found = true;
                    can_replace = true;
                }
                if (iter.begins_tag (tag_search_match)) {
                    start.assign (iter);
                    start_found = true;
                }
            }
            return start_found && end_found;
        }

        public bool select_prev_search_match (out bool has_prev) {
            Gtk.TextIter iter;
            get_iter_at_mark (out iter, current_search_match_mark);
            var end = Gtk.TextIter ();
            bool start_found = false;
            bool end_found = false;
            has_prev = false;
            while (iter.backward_to_tag_toggle (tag_search_match)) {
                if (start_found) {
                    has_prev = true;
                    return true;
                }
                if (end_found && iter.begins_tag (tag_search_match)) {
                    apply_tag (tag_search_match_focused, iter, end);
                    move_mark (current_search_match_mark, iter);
                    start_found = true;
                    can_replace = true;
                }
                if (iter.ends_tag (tag_search_match)) {
                    end.assign (iter);
                    end_found = true;
                }
            }
            return start_found && end_found;
        }
        
        public bool search_match_selected () {
            Gtk.TextIter iter;
            get_iter_at_mark (out iter, current_search_match_mark);
            return n_search_matches > 0 && iter.has_tag (tag_search_match_focused);
        }
        
        public bool replace_current_search_match (string replacement, ref bool has_next, ref bool has_prev)
            requires (search_match_selected ())
        {
            Gtk.TextIter iter;
            get_iter_at_mark (out iter, current_search_match_mark);
            replace_search_match (ref iter, replacement);
            if (has_next) {
                select_next_search_match (out has_next);
            } else if (has_prev) {
                select_prev_search_match (out has_prev);
            } else {
                return false;
            }
            return true;
        }

        public void replace_all_search_matches (string replacement) {
            Gtk.TextIter iter;
            get_start_iter (out iter);
            while (true) {
                if (!iter.has_tag (tag_search_match) && !iter.forward_to_tag_toggle (tag_search_match)) {
                    return;
                }
                replace_search_match (ref iter, replacement);
            }
        }
        
        public unowned Gtk.TextMark get_nth_forced_page_break (uint n)
            requires (n < forced_page_breaks.length ())
        {
            return forced_page_breaks.nth_data (n);
        }
        
    }
    
}
