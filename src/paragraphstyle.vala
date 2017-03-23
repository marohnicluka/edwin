/* paragraphstyle.vala
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

    public class ParagraphStyle : Object {

        public string name { get; construct set; }
        public unowned DocumentBuffer buffer { get; construct set; }
        
        unowned Gtk.TextTag tag;
        unowned Gtk.TextTag tag_vspace_above;
        unowned Gtk.TextTag tag_vspace_below;
        
        public ParagraphStyle (DocumentBuffer buffer, string id, string name) {
            tag = buffer.create_tag (@"paragraph-style:$id");
            tag_vspace_above = buffer.create_tag (@"internal:$id-vspace-above");
            tag_vspace_below = buffer.create_tag (@"internal:$id-vspace-below");
            this.name = name;
            this.buffer = buffer;
        }
        
        public void set_spacing (int pixels_above, int pixels_below) {
            tag_vspace_above.pixels_above_lines = pixels_above;
            tag_vspace_below.pixels_below_lines = pixels_below;
        }
        
        public void set_font_description (Pango.FontDescription font_desc) {
            tag.font_desc = font_desc;
        }
        
        public void set_color (Gdk.RGBA fg_rgba, Gdk.RGBA? bg_rgba = null, bool bg_paragraph = false) {
            tag.foreground_rgba = fg_rgba;
            if (bg_rgba != null) {
                if (bg_paragraph) {
                    tag.paragraph_background_rgba = bg_rgba;
                } else {
                    tag.background_rgba = bg_rgba;
                }
            }
        }
        
        public void set_underline (Pango.Underline underline, Gdk.RGBA? rgba = null) {
            tag.underline = underline;
            if (rgba != null) {
                tag.underline_rgba = rgba;
            }
        }
        
        public void set_margin (int left_margin, int right_margin = 0) {
            tag.left_margin = left_margin;
            if (right_margin > 0) {
                tag.right_margin = right_margin;
            }
        }
        
        public void set_justification (Gtk.Justification justification) {
            tag.justification = justification;
        }
        
        public bool has_iter (Gtk.TextIter iter) {
            return iter.has_tag (tag) && iter.ends_tag (tag);
        }
        
        public void apply_to_paragraph (Gtk.TextIter where) {
            Gtk.TextIter start, end;
            buffer.get_styled_paragraph_bounds (where, out start, out end);
            buffer.remove_tags ("paragraph-style", start, end);
            buffer.apply_tag (tag, start, end);
            update_paragraph_spacing (start, end);
        }
        
        public void update_paragraph_spacing (Gtk.TextIter start, Gtk.TextIter end) {
            var iter = start;
            buffer.move_to_paragraph_end (ref iter);
            buffer.apply_tag (tag_vspace_above, start, iter);
            iter.assign (end);
            buffer.move_to_paragraph_start (ref iter);
            buffer.apply_tag (tag_vspace_below, iter, end);
        }
    
    }

}
