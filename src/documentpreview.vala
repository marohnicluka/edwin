/* documentpreview.vala
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

    public class DocumentPreview : Gtk.TextView {
    
        public struct PageBreak {
            public int y;
            public bool overfull;
        }

/**********************\
|* FIELDS AND SIGNALS *|
\**********************/

        unowned Document doc;
        int height = 0;
        uint page_breaking_handler = 0;
        Timer timer = new Timer ();
        List<PageBreak?> page_breaks;
        Gtk.TextIter? hovered_iter = null;
        bool page_breaking_done = false;
        
        public signal void page_breaking_finished ();
        public signal void request_document_focus (Gtk.TextIter where);
        
/****************\
|* CONSTRUCTION *|
\****************/

        public DocumentPreview (Document doc) {
            Object (
                buffer: doc.buffer,
                can_focus: false,
                margin: 40,
                editable: false,
                cursor_visible: false,
                wrap_mode: Gtk.WrapMode.WORD_CHAR,
                left_margin: doc.paper_size.left_margin,
                right_margin: doc.paper_size.right_margin,
                top_margin: doc.paper_size.top_margin,
                bottom_margin: doc.paper_size.bottom_margin,
                width_request: doc.paper_size.width);
            this.doc = doc;
            page_breaks = new List<PageBreak?> ();
            add_events (Gdk.EventMask.POINTER_MOTION_MASK | Gdk.EventMask.LEAVE_NOTIFY_MASK);
            connect_signals ();
        }
        
        ~DocumentPreview () {
            if (page_breaking_handler != 0) {
                Source.remove (page_breaking_handler);
            }
        }
        
        private void connect_signals () {
            draw.connect_after (on_draw_after);
            size_allocate.connect (on_size_allocate);
        }
        
/*************\
|* CALLBACKS *|
\*************/

        private bool on_draw_after (Cairo.Context cr) {
            if (height == 0) {
                Gtk.TextIter iter;
                Gdk.Rectangle rect;
                buffer.get_end_iter (out iter);
                get_iter_location (iter, out rect);
                height = rect.y + rect.height + bottom_margin + top_margin;
                height_request = height;
            }
            return false;
        }
        
        private void on_size_allocate (Gtk.Allocation alloc) {
            if (alloc.height == height && !page_breaking_done && page_breaking_handler == 0) {
                debug ("Breaking pages");
                break_pages ();
            }
        }

/*******************\
|* PRIVATE METHODS *|
\*******************/

        private void break_pages (int y_start = 0) {
            timer.start ();
            int y = y_start;
            int max_height = height - top_margin - bottom_margin;
            int dy = doc.paper_size.text_height;
            Gtk.TextIter iter;
            Gdk.Rectangle rect;
            while ((y += dy) < max_height) {
                var new_y = load_forced_page_breaks_in_range (y - dy, y);
                if (new_y > 0) {
                    y = new_y;
                    continue;
                }
                get_iter_at_location (out iter, 0, y);
                get_iter_location (iter, out rect);
                int fixed_y = rect.y;
                var page_break = PageBreak ();
                if (fixed_y <= y - dy) {
                    page_break.overfull = true;
                    fixed_y += rect.height;
                } else {
                    page_break.overfull = false;
                }
                page_break.y = (y = fixed_y);
                page_breaks.append (page_break);
                if (timer.elapsed () > 0.1) {
                    page_breaking_handler = Timeout.add (5, () => {
                        break_pages (y);
                        return false;
                    });
                    return;
                }
            }
            load_forced_page_breaks_in_range (y - dy, max_height);
            timer.stop ();
            page_breaking_handler = 0;
            page_breaking_finished ();
            page_breaking_done = true;
            queue_draw ();
        }

        private void draw_page_breaks (Cairo.Context cr) {
            Gdk.Rectangle rect;
            for (uint n = 0; n < page_breaks.length (); n++) {
                var page_break = page_breaks.nth_data (n);
                var y = page_break.y + top_margin;
                var width = get_allocated_width ();
                cr.save ();
                var color = Utils.get_color (page_break.overfull ? "alert" : "page-border");
                Gdk.cairo_set_source_rgba (cr, color);
                cr.set_dash ({3, 4}, 0);
                cr.move_to (0, y);
                cr.line_to (width, y);
                cr.stroke ();
                cr.restore ();
                cr.save ();
                rect = {0, y - 1, width, 3};
                Utils.draw_rectangle (cr, rect, "white");
                cr.restore ();
            }
        }
        
        private int load_forced_page_breaks_in_range (int y1, int y2) {
            int y = -1;
            Gdk.Rectangle rect;
            Gtk.TextIter iter;
            for (uint n = 0; n < (buffer as DocumentBuffer).n_forced_page_breaks; n++) {
                var mark = (buffer as DocumentBuffer).get_nth_forced_page_break (n);
                buffer.get_iter_at_mark (out iter, mark);
                assert (iter.starts_line ());
                get_iter_location (iter, out rect);
                if (rect.y > y1 && rect.y <= y2) {
                    PageBreak forced_page_break = {rect.y, false};
                    page_breaks.append (forced_page_break);
                    if (rect.y > y) {
                        y = rect.y;
                    }
                }
            }
            return y;
        }
        
/******************\
|* PUBLIC METHODS *|
\******************/

        public override bool button_press_event (Gdk.EventButton event) {
            return true;
        }

        public override bool button_release_event (Gdk.EventButton event) {
            if (page_breaking_done &&
                (event.state & Gdk.ModifierType.BUTTON1_MASK) != 0 &&
                hovered_iter != null)
            {
                request_document_focus (hovered_iter);
            }
            return true;
        }
        
        public override bool motion_notify_event (Gdk.EventMotion event) {
            if (!page_breaking_done) {
                return false;
            }
            int wx = (int) Math.round (event.x);
            int wy = (int) Math.round (event.y);
            int bx, by;
            window_to_buffer_coords (Gtk.TextWindowType.WIDGET, wx, wy, out bx, out by);
            get_iter_at_position (out hovered_iter, null, bx, by);
            Gdk.Rectangle rect;
            get_iter_location (hovered_iter, out rect);
            if (bx >= rect.x && bx <= rect.x + rect.width && by >= rect.y && by <= rect.y + rect.height) {
                var ptr = new Gdk.Cursor.for_display (event.window.get_display (), Gdk.CursorType.HAND1);
                event.window.set_cursor (ptr);
            } else {
                hovered_iter = null;
                event.window.set_cursor (null);
            }
            return false;
        }
        
        public override bool leave_notify_event (Gdk.EventCrossing event) {
            hovered_iter = null;
            event.window.set_cursor (null);
            return false;
        }

        public override void draw_layer (Gtk.TextViewLayer layer, Cairo.Context cr) {
            switch (layer) {
            case Gtk.TextViewLayer.ABOVE:
                Gdk.Rectangle rect = {0, 0, get_allocated_width (), get_allocated_height ()};
                Utils.draw_rectangle (cr, rect, "page-border");
                break;
            case Gtk.TextViewLayer.BELOW:
                draw_page_breaks (cr);
                break;
            }
        }

    }

}
