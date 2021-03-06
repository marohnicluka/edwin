/* fontfamilychooser.vala
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

    public class FontFamilyChooser : ListChooser {
    
        public FontFamilyChooser (Gtk.Widget widget) {
            base (widget);
        }
        
        protected override string get_initial_id () {
            return (relative_to as Gtk.Button).label;
        }
    
        protected override void populate () {
            var font_map = Pango.cairo_font_map_get_default ();
            (unowned Pango.FontFamily)[] families;
            font_map.list_families (out families);
            Gtk.TreeIter iter;
            foreach (var family in families) {
                list_store.append (out iter);
                list_store.@set (iter, 0, family.get_name ().dup ());
            }
        }
        
    }
    
}
