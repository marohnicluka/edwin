/* documentview.vala
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

    public class DocumentView : Gtk.ScrolledWindow {
    
        unowned Document doc;
        Gtk.Viewport viewport;
        
        public TextView text_view { get; private set; }
        
        public DocumentView (Document doc) {
            Object (hadjustment: null, vadjustment: null);
            this.doc = doc;
            var box = new Gtk.EventBox ();
            text_view = new TextView (doc.paper_size);
            text_view.wrap_mode = Gtk.WrapMode.WORD_CHAR;
            text_view.margin = page_border_width;
            text_view.set_size_request (doc.paper_size.width, doc.paper_size.height);
            text_view.left_margin = doc.paper_size.left_margin;
            text_view.right_margin = doc.paper_size.right_margin;
            text_view.top_margin = doc.paper_size.top_margin;
            text_view.bottom_margin = doc.paper_size.bottom_margin;
            text_view.halign = Gtk.Align.CENTER;
            box.add (text_view);
            viewport = new Gtk.Viewport (null, null);
            viewport.add (box);
            add (viewport);
            connect_signals ();
        }
        
        private void connect_signals () {
			viewport.realize.connect (() => {
				var win = viewport.get_view_window ();
				var events = win.get_events ();
				win.set_events (events & ~Gdk.EventMask.FOCUS_CHANGE_MASK);
			});
        }
        
    }
    
}
