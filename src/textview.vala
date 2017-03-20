/* textview.vala
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

    public const int PAGE_BREAKING_TIMEOUT = 50; // miliseconds
    public const int SCROLL_TIMEOUT = 5; // miliseconds
    public const int SCROLL_DURATION = 100; // miliseconds
    public const double OUTER_MARGIN = 0.5; // inches

    public class TextView : Gtk.TextView {

        public struct TextSection {
            public bool dirty;
            public int height;
            public int[] page_breaks;
        }

/*************************\
|* FIELDS AND PROPERTIES *|
\*************************/

        public Gdk.RGBA default_text_color { get { return get_style_context ().get_color (0); } }
        public unowned Document doc { get; construct set; }
        public bool supports_page_breaking { get; protected set; default = true; }
        public int n_pages { get; private set; }
        public int current_page_number { get; private set; default = -1; }
        public int x_position { get; set; }
        public int y_position { get; set; }
        
        private uint n_section_breaks { get { return (buffer as TextBuffer).n_section_breaks; } }

        uint scroll_handler = 0;
        uint scroll_to_cursor_handler = 0;
        uint page_breaking_handler = 0;
        uint reshape_handler = 0;
        ulong size_allocate_handler = 0;
        List<TextSection?> sections = new List<TextSection?> ();

/****************\
|* CONSTRUCTION *|
\****************/

        public TextView (Document doc) {
            this.doc = doc;
            wrap_mode = Gtk.WrapMode.WORD_CHAR;
            halign = Gtk.Align.CENTER;
            override_background_color (Gtk.StateFlags.NORMAL, Utils.get_color ("transparent"));
            override_background_color (Gtk.StateFlags.SELECTED, Utils.get_color ("selection"));
            sections.append (create_section ());
            set_margins ();
            connect_signals ();
        }
        
        public override Gtk.TextBuffer create_buffer () {
            return new TextBuffer (this);
        }
        
        ~TextView () {
            if (scroll_handler != 0) {
                Source.remove (scroll_handler);
            }
            if (scroll_to_cursor_handler != 0) {
                Source.remove (scroll_to_cursor_handler);
            }
            if (page_breaking_handler != 0) {
                Source.remove (page_breaking_handler);
            }
            if (reshape_handler != 0) {
                Source.remove (reshape_handler);
            }
        }

        private void connect_signals () {
            draw.connect (on_draw);
            draw.connect_after (on_draw_after);
            notify["has-focus"].connect (() => {
                var color = Utils.get_color (has_focus ? "selection" : "selection-unfocused");
                override_background_color (Gtk.StateFlags.SELECTED, color);
            });
            buffer.notify["cursor-position"].connect (on_cursor_position_changed);
            realize.connect (() => {
                (buffer as TextBuffer).set_zoom (doc.zoom);
                break_pages ();
            });
            doc.notify["zoom"].connect (on_zoom_changed);
        }

        protected virtual void set_margins () {
            if (doc.paper_size.left_border_area_width > 0) {
                var size = doc.paper_size.left_border_area_width + doc.paper_size.left_margin;
                set_border_window_size (Gtk.TextWindowType.LEFT, scale (size));
                left_margin = scale (doc.paper_size.border_area_separator);
            } else {
                left_margin = scale (doc.paper_size.left_margin);
            }
            if (doc.paper_size.right_border_area_width > 0) {
                var size = doc.paper_size.right_border_area_width + doc.paper_size.right_margin;
                set_border_window_size (Gtk.TextWindowType.RIGHT, scale (size));
                right_margin = scale (doc.paper_size.border_area_separator);
            } else {
                right_margin = scale (doc.paper_size.right_margin);
            }
            top_margin = scale (doc.paper_size.top_margin);
            bottom_margin = scale (doc.paper_size.bottom_margin);
        }

/*************\
|* CALLBACKS *|
\*************/

        private void on_zoom_changed () {
            schedule_reshape ();
        }

        private bool on_draw (Cairo.Context cr) {
            Utils.fill_white_rectangle (cr, get_bounding_rectangle ());
            if (supports_page_breaking) {
                draw_page_breaks (cr);
            }
            return false;
        }

        private bool on_draw_after (Cairo.Context cr) {
            Utils.draw_rectangle (cr, get_bounding_rectangle (), Utils.get_color ("page-border"));
            if (supports_page_breaking) {
                draw_section_breaks (cr);
            }
            return false;
        }
        
        private void on_cursor_position_changed () {
            if (supports_page_breaking) {
                var n = get_page_num_at_iter ((buffer as TextBuffer).cursor);
                if (n != current_page_number) {
                    current_page_number = n;
                }
            }
        }
        
/*******************\
|* PRIVATE METHODS *|
\*******************/

        private void schedule_reshape () {
            if (size_allocate_handler != 0) {
                return;
            }
            if (reshape_handler != 0) {
                Source.remove (reshape_handler);
            }
            reshape_handler = Timeout.add (150, () => {
                (buffer as TextBuffer).set_zoom (doc.zoom);
                set_margins ();
                for (uint n = 0; n < n_section_breaks; n++) {
                    nth_section_break (n).tag.pixels_below_lines = scale (nth_section_break (n).vskip);
                }
                Gtk.TextIter start, end;
                buffer.get_bounds (out start, out end);
                doc.begin_user_action ();
                buffer.@delete (ref start, ref end);
                doc.end_user_action ();
                size_allocate_handler = size_allocate.connect (() => {
                    disconnect (size_allocate_handler);
                    doc.undo ();
                    schedule_page_breaking ();
                    size_allocate_handler = 0;
                });
                update_size ();
                reshape_handler = 0;
                return false;
            });
        }

        private int scale (double @value) {
            return (int) Math.round (@value * doc.zoom);
        }

        private int unscale (double @value) {
            return (int) Math.round (@value / doc.zoom);
        }

        private TextSection create_section () {
            var section = TextSection ();
            section.page_breaks = { };
            section.dirty = true;
            return section;
        }

        private unowned TextBuffer.SectionBreak nth_section_break (uint n) {
            return (buffer as TextBuffer).nth_section_break (n);
        }

        private void compute_page_breaks (uint n) {
            Gtk.TextIter start, end;
            get_section_bounds (n, out start, out end);
            int[] page_breaks = { };
            Gdk.Rectangle rect;
            get_location (start, out rect);
            int y_start = rect.y;
            get_location (end, out rect);
            int y_end = rect.y + rect.height;
            int x = scale (doc.paper_size.text_area_start), y = y_start, bx, by;
            int step = scale (doc.paper_size.text_height);
            Gtk.TextIter iter;
            while ((y += step) < y_end) {
                window_to_buffer_coords (Gtk.TextWindowType.WIDGET, x, y, out bx, out by);
                get_iter_at_location (out iter, bx, by);
                get_location (iter, out rect);
                y = rect.y;
                bool over = y <= (page_breaks.length > 0 ?
                    y_start + scale (page_breaks[page_breaks.length - 1]) : y_start);
                var page_break = unscale (y - y_start);
                page_breaks += over ? -page_break : page_break;
                if (over) {
                    y += rect.height;
                }
            }
            sections.nth_data (n).dirty = false;
            sections.nth_data (n).height = unscale (y - y_start);
            sections.nth_data (n).page_breaks = page_breaks;
            if (n < n_section_breaks) {
                int vskip = y - y_end;
                end.forward_char ();
                get_location (end, out rect, false);
                vskip -= rect.height;
                vskip = unscale (vskip);
                vskip += doc.paper_size.bottom_margin + (3 * doc.paper_size.top_margin) / 2;
                nth_section_break (n).vskip = vskip;
                nth_section_break (n).tag.pixels_below_lines = scale (vskip);
            }
        }

        private void update_size () {
            int height = ((int) n_section_breaks * doc.paper_size.top_margin) / 2;
            int relief = doc.paper_size.top_margin + doc.paper_size.bottom_margin;
            for (uint n = 0; n < sections.length (); n++) {
                height += sections.nth_data (n).height + relief;
            }
            set_size_request (scale (doc.paper_size.width), scale (height));
        }

        private Gdk.Rectangle to_viewport_coords (Gdk.Rectangle rectangle) {
            var rect = rectangle;
            rect.x += x_position;
            rect.y += y_position;
            return rect;
        }

        private void get_distance_from_viewport (Gdk.Rectangle rectangle, out int dx, out int dy) {
            var viewport_rect = doc.get_viewport_rectangle ();
            var rect = to_viewport_coords (rectangle);
            Gdk.Rectangle un;
            rect.union (viewport_rect, out un);
            dx = viewport_rect.x > un.x ? un.x - viewport_rect.x : un.width - viewport_rect.width;
            dy = viewport_rect.y > un.y ? un.y - viewport_rect.y : un.height - viewport_rect.height;
        }
        
        private void draw_section_breaks (Cairo.Context cr) {
            int margin_skip = scale (3.0 * doc.paper_size.top_margin / 2.0);
            int between_pages_skip = scale (doc.paper_size.top_margin / 2.0);
            for (uint n = 0; n < n_section_breaks; n++) {
                Gdk.Rectangle rect;
                Gtk.TextIter iter;
                buffer.get_iter_at_mark (out iter, nth_section_break (n).mark);
                get_location (iter, out rect);
                rect.x = 1;
                rect.width = get_allocated_width () - 2;
                rect.height += nth_section_break (n).tag.pixels_below_lines;
                Utils.fill_white_rectangle (cr, rect);
                rect.x = 0;
                rect.y += rect.height - margin_skip;
                rect.width += 2;
                rect.height = between_pages_skip;
                Gdk.cairo_set_source_rgba (cr, Utils.get_color ("page-border"));
                cr.move_to (rect.x, rect.y);
                cr.rel_line_to (rect.width, 0);
                cr.move_to (rect.x, rect.y + rect.height);
                cr.rel_line_to (rect.width, 0);
                cr.stroke ();
                Utils.fill_rectangle_as_background (cr, rect);
            }
        }

        private void draw_page_breaks (Cairo.Context cr) {
            assert (n_section_breaks + 1 == sections.length ());
            Gtk.TextIter start;
            Gdk.Rectangle rect;
            for (uint n = 0; n <= n_section_breaks; n++) {
                get_section_bounds (n, out start, null);
                get_location (start, out rect);
                var y_start = rect.y;
                foreach (int page_break in sections.nth_data (n).page_breaks) {
                    var pos = y_start + scale (page_break >= 0 ? page_break : -page_break);
                    rect = {0, pos - 1, doc.paper_size.width, 3};
                    cr.save ();
                    var color = page_break < 0 ?
                        Utils.get_color ("alert") : Utils.get_color ("page-border");
                    Gdk.cairo_set_source_rgba (cr, color);
                    cr.set_dash ({3, 4}, 0);
                    cr.move_to (0, pos);
                    cr.line_to (doc.paper_size.width, pos);
                    cr.stroke ();
                    cr.restore ();
                    cr.save ();
                    Gdk.cairo_set_source_rgba (cr, Utils.get_color ("white"));
                    Gdk.cairo_rectangle (cr, rect);
                    cr.stroke ();
                    cr.restore ();
                }
            }
        }

/******************\
|* PUBLIC METHODS *|
\******************/

        public void get_section_bounds (uint n, out Gtk.TextIter start, out Gtk.TextIter end)
            requires (n <= n_section_breaks)
        {
            if (n == 0) {
                buffer.get_start_iter (out start);
            } else {
                buffer.get_iter_at_mark (out start, nth_section_break (n - 1).mark);
                start.forward_char ();
            }
            if (n < n_section_breaks) {
                buffer.get_iter_at_mark (out end, nth_section_break (n).mark);
            } else {
                buffer.get_end_iter (out end);
            }
        }

        public void remove_sections (uint[] indexes) {
            for (int i = 0; i < indexes.length; i++) {
                sections.remove (sections.nth_data (indexes[i] + 1));
            }
            mark_section_dirty (indexes[indexes.length - 1]);
        }

        public void insert_section (uint index)
            requires (index > 0)
        {
            sections.insert (create_section (), (int) index);
            mark_section_dirty (index - 1);
            mark_section_dirty (index);
        }

        public Gdk.Rectangle get_bounding_rectangle () {
            Gdk.Rectangle rect = {0, 0, get_allocated_width (), get_allocated_height ()};
            return rect;
        }

        public void get_location (Gtk.TextIter iter, out Gdk.Rectangle rect, bool win_coords = true) {
            get_iter_location (iter, out rect);
            if (!win_coords) {
                return;
            }
            int x1 = rect.x;
            int y1 = rect.y;
            int x2 = rect.x + rect.width;
            int y2 = rect.y + rect.height;
            int wx1, wx2, wy1, wy2;
            buffer_to_window_coords (Gtk.TextWindowType.WIDGET, x1, y1, out wx1, out wy1);
            buffer_to_window_coords (Gtk.TextWindowType.WIDGET, x2, y2, out wx2, out wy2);
            rect = Gdk.Rectangle () {
                x = wx1,
                y = wy1,
                width = wx2 - wx1,
                height = wy2 - wy1
            };
        }

        public new void scroll_to_iter (Gtk.TextIter iter) {
            Gdk.Rectangle rect;
            int dx, dy;
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
                    doc.hadjustment.@value += dx_step;
                    doc.vadjustment.@value += dy_step;
                    if (i < SCROLL_DURATION / SCROLL_TIMEOUT) {
                        i++;
                        return true;
                    }
                    scroll_handler = 0;
                    return false;
                });
            }
        }

        public void scroll_to_cursor () {
            scroll_to_iter ((buffer as TextBuffer).cursor);
        }
        
        public void schedule_scroll_to_cursor () {
            if (scroll_to_cursor_handler != 0) {
                Source.remove (scroll_to_cursor_handler);
            }
            scroll_to_cursor_handler = Timeout.add (150, () => {
                scroll_to_cursor ();
                scroll_to_cursor_handler = 0;
                return false;
            });
        }

        public void mark_section_dirty (uint n) {
            if (!supports_page_breaking) {
                return;
            }
            sections.nth_data (n).dirty = true;
            schedule_page_breaking ();
        }

        public void mark_section_at_iter_dirty (Gtk.TextIter iter) {
            Gtk.TextIter start, end;
            for (uint n = 0; n < sections.length (); n++) {
                get_section_bounds (n, out start, out end);
                if (iter.compare (start) >= 0 && iter.compare (end) <= 0) {
                    mark_section_dirty (n);
                    break;
                }
            }
        }
        
        public void break_pages () {
            bool page_breaks_changed = false;
            int np = 0;
            for (uint n = 0; n < sections.length (); n++) {
                if (sections.nth_data (n).dirty) {
                    compute_page_breaks (n);
                    page_breaks_changed = true;
                }
                np += sections.nth_data (n).page_breaks.length + 1;
            }
            n_pages = np;
            if (page_breaks_changed) {
                update_size ();
                if (has_focus) {
                    schedule_scroll_to_cursor ();
                }
            }
        }
        
        public void schedule_page_breaking () {
            if (page_breaking_handler != 0) {
                Source.remove (page_breaking_handler);
            }
            page_breaking_handler = Timeout.add (PAGE_BREAKING_TIMEOUT, () => {
                break_pages ();
                page_breaking_handler = 0;
                return false;
            });
        }
        
        public int get_page_num_at_iter (Gtk.TextIter iter) {
            Gdk.Rectangle rect;
            get_location (iter, out rect);
            int y = rect.y;
            int np = 0;
            Gtk.TextIter start, end;
            for (uint n = 0; n < sections.length (); n++) {
                get_section_bounds (n, out start, out end);
                var page_breaks = sections.nth_data (n).page_breaks;
                if (iter.compare (start) >= 0 && iter.compare (end) <= 0) {
                    get_location (start, out rect);
                    int y_rel = unscale (y - rect.y);
                    foreach (int page_break in page_breaks) {
                        if (page_break > y_rel) {
                            break;
                        }
                        np++;
                    }
                    break;
                }
                np += page_breaks.length + 1;
            }
            return np;
        }

    }

}
