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

    public const int PAGE_BREAKING_TIMEOUT = 150; // miliseconds
    public const int SCROLL_TIMEOUT = 5; // miliseconds
    public const int SCROLL_DURATION = 100; // miliseconds

    public class TextView : Gtk.TextView {

        public const double OUTER_MARGIN = 0.5; // inches

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
        private uint n_section_breaks { get { return (buffer as TextBuffer).n_section_breaks; } }

        Gdk.RGBA selection_color;
        Gdk.RGBA focus_out_color;
        uint scroll_handler = 0;
        uint scroll_to_cursor_handler = 0;
        uint page_breaking_handler = 0;
        List<TextSection?> sections = new List<TextSection?> ();

/****************\
|* CONSTRUCTION *|
\****************/

        public TextView (Document doc) {
            this.doc = doc;
            margin = Utils.to_pixels (Utils.INCH, OUTER_MARGIN);
            wrap_mode = Gtk.WrapMode.WORD_CHAR;
            halign = Gtk.Align.CENTER;
            Gdk.RGBA transparent_color = {0, 0, 0, 0};
            selection_color = Gdk.RGBA ();
            selection_color.parse ("#268bd2");
            focus_out_color = Gdk.RGBA ();
            focus_out_color.parse ("#d3d7cf");
            override_background_color (Gtk.StateFlags.NORMAL, transparent_color);
            override_background_color (Gtk.StateFlags.SELECTED, selection_color);
            sections.append (create_section ());
            set_margins ();
            connect_signals ();
        }

        ~TextView () {
            stop_page_breaking ();
        }

        public override Gtk.TextBuffer create_buffer () {
            return new TextBuffer (this);
        }

        private void connect_signals () {
            draw.connect (on_draw);
            draw.connect_after (on_draw_after);
            notify["has-focus"].connect (() => {
                var color = has_focus ? selection_color : focus_out_color;
                override_background_color (Gtk.StateFlags.SELECTED, color);
            });
            realize.connect (() => {
                Gtk.TextIter iter;
                buffer.get_start_iter (out iter);
            });
        }

        protected virtual void set_margins () {
            left_margin = doc.paper_size.left_margin;
            right_margin = doc.paper_size.right_margin;
            top_margin = doc.paper_size.top_margin;
            bottom_margin = doc.paper_size.bottom_margin;
            width_request = doc.paper_size.width;
            if (doc.paper_size.left_border_area_width > 0) {
                var size = doc.paper_size.left_border_area_width + doc.paper_size.left_margin;
                set_border_window_size (Gtk.TextWindowType.LEFT, size);
                left_margin = doc.paper_size.border_area_separator;
            }
            if (doc.paper_size.right_border_area_width > 0) {
                var size = doc.paper_size.right_border_area_width + doc.paper_size.right_margin;
                set_border_window_size (Gtk.TextWindowType.RIGHT, size);
                right_margin = doc.paper_size.border_area_separator;
            }
        }

/*************\
|* CALLBACKS *|
\*************/

        private bool on_draw (Cairo.Context cr) {
            Utils.fill_white_rectangle (cr, get_bounding_rectangle ());
            if (supports_page_breaking) {
                draw_page_breaks (cr);
            }
            return false;
        }

        private bool on_draw_after (Cairo.Context cr) {
            Utils.draw_rectangle (cr, get_bounding_rectangle (), Utils.page_border_color ());
            if (supports_page_breaking) {
                draw_section_breaks (cr);
            }
            stop_page_breaking ();
            page_breaking_handler = Timeout.add (PAGE_BREAKING_TIMEOUT, () => {
                begin_page_breaking ();
                return false;
            });
            return false;
        }

/*******************\
|* PRIVATE METHODS *|
\*******************/

        private void begin_page_breaking (uint n = 0) {
            if (n < sections.length ()) {
                if (sections.nth_data (n).dirty) {
                    compute_page_breaks (n);
                }
                page_breaking_handler = Timeout.add (10, () => {
                    begin_page_breaking (n + 1);
                    return false;
                });
            } else {
                update_height ();
                page_breaking_handler = 0;
                queue_draw ();
            }
        }

        private void stop_page_breaking () {
            if (page_breaking_handler != 0) {
                Source.remove (page_breaking_handler);
            }
        }

        private TextSection create_section () {
            var section = TextSection ();
            section.page_breaks = { };
            section.dirty = true;
            return section;
        }

        private new void scroll_to_mark (Gtk.TextMark mark) {
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

        private unowned TextBuffer.SectionBreak nth_section_break (uint n) {
            return (buffer as TextBuffer).nth_section_break (n);
        }

        private Gdk.Rectangle get_viewport_rectangle () {
            return Gdk.Rectangle () {
                x = (int) Math.round (doc.hadjustment.@value),
                y = (int) Math.round (doc.vadjustment.@value),
                width = (int) Math.round (doc.hadjustment.page_size),
                height = (int) Math.round (doc.vadjustment.page_size)
            };
        }

        protected virtual Gdk.Rectangle to_viewport_coords (Gdk.Rectangle rectangle) {
            var rect = rectangle;
            rect.x += (doc.get_allocated_width () - get_allocated_width ()) / 2;
            rect.y += this.margin;
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

        private void draw_section_breaks (Cairo.Context cr) {
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
                rect.y += rect.height - (3 * doc.paper_size.top_margin) / 2;
                rect.width += 2;
                rect.height = doc.paper_size.top_margin / 2;
                Gdk.cairo_set_source_rgba (cr, Utils.page_border_color ());
                cr.move_to (rect.x, rect.y);
                cr.rel_line_to (rect.width, 0);
                cr.move_to (rect.x, rect.y + rect.height);
                cr.rel_line_to (rect.width, 0);
                cr.stroke ();
                Utils.fill_rectangle_as_background (cr, rect);
            }
        }

        private void draw_page_breaks (Cairo.Context cr) {
            Gtk.TextIter start, end;
            assert (n_section_breaks + 1 == sections.length ());
            for (uint n = 0; n <= n_section_breaks; n++) {
                get_section_bounds (n, out start, out end);
                foreach (int page_break in sections.nth_data (n).page_breaks) {
                    cr.save ();
                    var pos = page_break >= 0 ? page_break : -page_break;
                    var color = page_break < 0 ? Utils.alert_color () : Utils.page_border_color ();
                    Gdk.cairo_set_source_rgba (cr, color);
                    cr.set_dash ({3, 4}, 0);
                    cr.move_to (0, pos);
                    cr.line_to (doc.paper_size.width, pos);
                    cr.stroke ();
                    cr.restore ();
                    cr.save ();
                    cr.set_source_rgb (1, 1, 1);
                    cr.rectangle (0, pos - 1, doc.paper_size.width, 3);
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
            uint index = indexes[0] + 1;
            for (int i = 0; i < indexes.length; i++) {
                assert (index < sections.length ());
                sections.remove (sections.nth_data (index));
            }
            mark_section_dirty (indexes[0]);
        }

        public void insert_section (uint index)
            requires (index > 0)
        {
            sections.insert (create_section (), (int) index);
            mark_section_dirty (index - 1);
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

        public void schedule_scroll_to_cursor () {
            if (scroll_to_cursor_handler != 0) {
                Source.remove (scroll_to_cursor_handler);
            }
            scroll_to_cursor_handler = Timeout.add (10, () => {
                scroll_to_mark (buffer.get_insert ());
                scroll_to_cursor_handler = 0;
                return false;
            });
        }

        public void compute_page_breaks (uint n) {
            Gtk.TextIter start, end;
            get_section_bounds (n, out start, out end);
            int[] page_breaks = { };
            Gdk.Rectangle rect;
            get_location (start, out rect);
            int y_start = rect.y;
            get_location (end, out rect);
            int y_end = rect.y + rect.height;
            int x = doc.paper_size.text_area_start, y = y_start, bx, by;
            Gtk.TextIter iter;
            while ((y += doc.paper_size.text_height) < y_end) {
                window_to_buffer_coords (Gtk.TextWindowType.WIDGET, x, y, out bx, out by);
                get_iter_at_location (out iter, bx, by);
                get_location (iter, out rect);
                y = rect.y;
                bool over = y <= (page_breaks.length > 0 ? page_breaks[page_breaks.length - 1] : y_start);
                page_breaks += over ? -y : y;
                if (over) {
                    y += rect.height;
                }
            }
            sections.nth_data (n).dirty = false;
            sections.nth_data (n).height = y - y_start;
            sections.nth_data (n).page_breaks = page_breaks;
            if (n < n_section_breaks) {
                end.forward_char ();
                get_location (end, out rect);
                int vskip = y - rect.y - rect.height;
                vskip += doc.paper_size.bottom_margin + (3 * doc.paper_size.top_margin) / 2;
                nth_section_break (n).tag.pixels_below_lines = vskip;
            }
        }

        public void update_height () {
            int height = ((int) n_section_breaks * doc.paper_size.top_margin) / 2;
            int relief = doc.paper_size.top_margin + doc.paper_size.bottom_margin;
            for (uint n = 0; n < sections.length (); n++) {
                if (sections.nth_data (n).dirty) {
                    compute_page_breaks (n);
                }
                height += sections.nth_data (n).height + relief;
            }
            set_size_request (doc.paper_size.width, height);
        }

        public void mark_section_dirty (uint index) {
            for (uint n = index; n < sections.length (); n++) {
                sections.nth_data (n).dirty = true;
            }
        }

        public void mark_section_at_iter_dirty (Gtk.TextIter iter) {
            Gtk.TextIter start, end;
            bool found = false;
            for (uint n = 0; n < sections.length (); n++) {
                if (found) {
                    sections.nth_data (n).dirty = true;
                    continue;
                }
                get_section_bounds (n, out start, out end);
                if (iter.compare (start) >= 0 && iter.compare (end) <= 0) {
                    sections.nth_data (n).dirty = true;
                    found = true;
                }
            }
        }

    }

}
