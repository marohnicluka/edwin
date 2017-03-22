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

    public const int DEFAULT_MARGIN = 12; // pixels

    public class TextView : Gtk.TextView {

/*************************\
|* FIELDS AND PROPERTIES *|
\*************************/

        public Gdk.RGBA default_text_color { get { return get_style_context ().get_color (0); } }
        public unowned Document doc { get; construct set; }
        public uint n_page_breaks { get { return page_breaks.length (); } }
        
        List<unowned Gtk.TextMark> page_breaks;
        
/****************\
|* CONSTRUCTION *|
\****************/

        public TextView (Document doc) {
            this.doc = doc;
            page_breaks = new List<unowned Gtk.TextMark> ();
            wrap_mode = Gtk.WrapMode.WORD_CHAR;
            left_margin = DEFAULT_MARGIN;
            right_margin = DEFAULT_MARGIN;
            top_margin = DEFAULT_MARGIN;
            bottom_margin = DEFAULT_MARGIN;
            connect_signals ();
        }
        
        public override Gtk.TextBuffer create_buffer () {
            return new TextBuffer (this);
        }
        
        ~TextView () {

        }

        private void connect_signals () {
            doc.notify["zoom"].connect (on_zoom_changed);
        }

/*************\
|* CALLBACKS *|
\*************/

        private void on_zoom_changed () {

        }

/*******************\
|* PRIVATE METHODS *|
\*******************/

        private void draw_page_breaks (Cairo.Context cr) {
            Gtk.TextIter iter;
            Gdk.Rectangle rect;
            for (uint n = 0; n < n_page_breaks; n++) {
                buffer.get_iter_at_mark (out iter, get_nth_page_break (n));
                get_location (iter, out rect, Gtk.TextWindowType.TEXT);
                var y = rect.y;
                var width = get_allocated_width ();
                cr.save ();
                Gdk.cairo_set_source_rgba (cr, Utils.get_color ("page-border"));
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

/******************\
|* PUBLIC METHODS *|
\******************/

        public override void draw_layer (Gtk.TextViewLayer layer, Cairo.Context cr) {
            switch (layer) {
            case Gtk.TextViewLayer.ABOVE:
            
                break;
            case Gtk.TextViewLayer.BELOW:
                draw_page_breaks (cr);
                break;
            }
        }

        public void get_location (Gtk.TextIter iter, out Gdk.Rectangle rect, Gtk.TextWindowType type) {
            get_iter_location (iter, out rect);
            int x1 = rect.x;
            int y1 = rect.y;
            int x2 = rect.x + rect.width;
            int y2 = rect.y + rect.height;
            int wx1, wx2, wy1, wy2;
            buffer_to_window_coords (type, x1, y1, out wx1, out wy1);
            buffer_to_window_coords (type, x2, y2, out wx2, out wy2);
            rect = Gdk.Rectangle () {
                x = wx1,
                y = wy1,
                width = wx2 - wx1,
                height = wy2 - wy1
            };
        }
        
        public void scroll_to_cursor () {
            scroll_mark_onscreen (buffer.get_insert ());
        }
    
        public void insert_page_break (Gtk.TextIter where)
            requires (where.starts_line ())
        {
            var mark = buffer.create_mark (null, where, true);
            page_breaks.append (mark);
        }
        
        public void remove_nth_page_break (uint n)
            requires (n < n_page_breaks)
        {
            page_breaks.remove (page_breaks.nth_data (n));
        }
        
        public unowned Gtk.TextMark get_nth_page_break (uint n)
            requires (n < n_page_breaks)
        {
            return page_breaks.nth_data (n);
        }
        
    }

}
