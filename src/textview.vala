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

    public class TextView : Gtk.TextView {

        unowned Document doc;

        public TextView (Document doc) {
            this.doc = doc;        }

        public override void draw_layer (Gtk.TextViewLayer layer, Cairo.Context cr) {
            cr.save ();
            switch (layer) {
            case Gtk.TextViewLayer.BELOW:
                doc.draw_page_breaks (cr);
                break;
            case Gtk.TextViewLayer.ABOVE:
                Gdk.Rectangle rect =  {0, 0, get_allocated_width (), get_allocated_height ()};
                Utils.draw_rectangle (cr, rect, Utils.page_border_color ());
                doc.draw_section_breaks (cr);
                break;
            }
            cr.restore ();
        }

    }

}
