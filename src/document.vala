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

    public const double OUTER_MARGIN = 0.5; // inches
    public const int PAGE_BREAKING_TIMEOUT = 250; // miliseconds
    public const int SCROLL_TIMEOUT = 5; // miliseconds
    public const int SCROLL_DURATION = 100; // miliseconds

    public class Document : Gtk.Viewport {

        public struct SectionBreak {
            public unowned Gtk.TextMark mark;
            public unowned Gtk.TextTag tag;
        }
        
/*************************\
|* FIELDS AND PROPERTIES *|
\*************************/

        /* mutable properties */
        public PaperSize paper_size { get; set; }

        /* widgets */
        TextView text_view;
        Gtk.EventBox text_view_box;

        /* private fields */
        unowned Gtk.TextTag tag_skip;
        unowned Gtk.TextTag tag_no_page_break;
        unowned Gtk.TextMark insert_start_mark;
        int cursor_movement_direction = 0;
        uint scroll_handler = 0;
        uint section_break_serial = 0;
        List<SectionBreak?> section_breaks = null;

        /* often used */
        public unowned Gtk.TextBuffer buffer {
            get { return text_view.buffer; }
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
        
        /* signals */
        public signal void page_breaking_done ();

/****************\
|* CONSTRUCTION *|
\****************/

        public Document () {
            Object (hadjustment: null, vadjustment: null);
            paper_size = new PaperSize.@default ();
            create_widgets ();
            create_tags ();
            this.realize.connect (on_realize);
        }

        public static Document? open (File file) {
            if (!file.query_exists ()) {
                return null;
            }
            var doc = new Document ();
            return doc;
        }

        private void create_widgets () {
            text_view = new TextView (this);
            text_view_box = new Gtk.EventBox ();
            text_view.margin = Utils.to_pixels (Utils.INCH, OUTER_MARGIN);
            text_view.wrap_mode = Gtk.WrapMode.WORD_CHAR;
            text_view.left_margin = paper_size.left_margin;
            text_view.right_margin = paper_size.right_margin;
            text_view.top_margin = paper_size.top_margin;
            text_view.bottom_margin = paper_size.bottom_margin;
            text_view.width_request = paper_size.width;
            text_view.halign = Gtk.Align.CENTER;
            text_view_box.add (text_view);
            this.add (text_view_box);
        }

        private void create_tags () {
            buffer.create_tag ("bold",
                "weight", Pango.Weight.BOLD);
            buffer.create_tag ("italic",
                "style", Pango.Style.ITALIC);
            buffer.create_tag ("underline",
                "underline", Pango.Underline.SINGLE);
            /* internal tags */
            tag_skip = buffer.create_tag ("internal:skip");
            tag_no_page_break = buffer.create_tag ("internal:no-page-break");
        }

/*************\
|* CALLBACKS *|
\*************/

        private void on_realize () {
			var win = this.get_view_window ();
			var events = win.get_events ();
			win.set_events (events & ~Gdk.EventMask.FOCUS_CHANGE_MASK);
            Gtk.TextIter where;
            buffer.get_start_iter (out where);
            insert_start_mark = buffer.create_mark (null, where, true);
            text_view.move_cursor.connect (on_move_cursor);
            text_view.key_press_event.connect (on_key_press_event);
            buffer.notify["cursor-position"].connect (on_cursor_position_changed);
            buffer.delete_range.connect (on_delete_range);
            buffer.delete_range.connect_after (on_delete_range_after);
            buffer.insert_text.connect (on_insert_text);
            buffer.insert_text.connect_after (on_insert_text_after);
        }

        private bool on_key_press_event (Gdk.EventKey event) {
            bool ctrl = (event.state & Gdk.ModifierType.CONTROL_MASK) != 0;
            switch (event.keyval) {
            case Gdk.Key.Return:
                if (ctrl) {
                    Gtk.TextIter start, end;
                    if (buffer.get_selection_bounds (out start, out end)) {
                        buffer.@delete (ref start, ref end);
                        insert_section_break (start);
                    } else {
                        insert_section_break (cursor);
                    }
                    return true;
                }
                break;
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
                buffer.place_cursor (iter);
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
            cursor_movement_direction = 0;
            Timeout.add (10, () => {
                scroll_to_mark (buffer.get_insert ());
                return false;
            });
        }

        private void on_delete_range (Gtk.TextIter start, Gtk.TextIter end) {
            if (iter_at_section_break (start)) {
                start.backward_char ();
            }
            if (iter_at_section_break (end)) {
                end.forward_char ();
            }
        }

        private void on_delete_range_after (Gtk.TextIter start, Gtk.TextIter end) {
            start.get_marks ().@foreach ((mark) => {
                if (mark.name != null && mark.name.has_prefix ("section-break")) {
                    remove_section_break_at_mark (mark);
                }
            });
        }

        private void on_insert_text (ref Gtk.TextIter iter, string text, int len) {
            buffer.move_mark (insert_start_mark, iter);
        }

        private void on_insert_text_after (ref Gtk.TextIter iter, string text, int len) {
            Gtk.TextIter start;
            buffer.get_iter_at_mark (out start, insert_start_mark);
        }

/*******************\
|* PRIVATE METHODS *|
\*******************/

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

        private void remove_section_break_at_mark (Gtk.TextMark mark) {
            section_breaks.@foreach ((section_break) => {
                if (section_break.mark == mark) {
                    buffer.delete_mark (mark);
                    buffer.tag_table.remove (section_break.tag);
                    section_breaks.remove (section_break);
                }
            });
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
        
        private uint create_section_break (Gtk.TextIter iter, int vskip) {
            uint n;
            Gtk.TextIter break_iter;
            string name = "section-break-%u".printf (section_break_serial++);
            var section_break = SectionBreak () {
                mark = buffer.create_mark (name, iter, true),
                tag = buffer.create_tag (name, "pixels-below-lines", vskip)
            };
            for (n = 0; n < section_breaks.length (); n++) {
                buffer.get_iter_at_mark (out break_iter, section_breaks.nth_data (n).mark);
                if (iter.compare (break_iter) < 0) {
                    break;
                }
            }
            section_breaks.insert (section_break, (int) n);
            return n;
        }

/******************\
|* PUBLIC METHODS *|
\******************/

        public new void focus () {
            text_view.grab_focus ();
        }

        public void insert_section_break (Gtk.TextIter where) {
            Gtk.TextIter iter = where;
            buffer.insert (ref iter, "\n", -1);
            int vskip = paper_size.bottom_margin + section_skip_after;
            Gdk.Rectangle rect;
            get_location (iter, out rect, false);
            vskip -= rect.height;
            uint n = create_section_break (iter, vskip);
            buffer.insert_with_tags (ref iter, "\n", -1, section_breaks.nth_data (n).tag);
            buffer.place_cursor (iter);
            iter.backward_char ();
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

        public void move_to_paragraph_end (ref Gtk.TextIter iter) {
            if (iter.forward_line ()) {
                iter.backward_char ();
            }
        }

        public void iterate_over_lines (ref Gtk.TextIter start, TextRangeFunc line_func) {
            var end = start;
            while (end.forward_char ()) {
                if (text_view.starts_display_line (end)) {
                    end.backward_char ();
                    if (!line_func (start, end)) {
                        break;
                    }
                    end.forward_char ();
                    start.assign (end);
                }
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

        public int get_y_at_iter (Gtk.TextIter iter, bool win_coords = true) {
            Gdk.Rectangle rect;
            get_location (iter, out rect, win_coords);
            return rect.y;
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
