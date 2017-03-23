/* styletemplates.vala
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

    public class StyleTemplate : Object {
        
        public PaperSize paper_size { get; set; }
        
        HashTable<string, ParagraphStyle> paragraph_styles;
        
        public void add_paragraph_style (string id, ParagraphStyle paragraph_style) {
            paragraph_styles.insert (id, paragraph_style);
        }
        
        public StyleTemplate () {
            paragraph_styles = new HashTable<string, ParagraphStyle> (str_hash, str_equal);
        }
        
        public string[] get_paragraph_style_ids () {
            string[] ids = { };
            paragraph_styles.@foreach ((id, paragraph_style) => {
                ids += id;
            });
            return ids;
        }
        
        public unowned ParagraphStyle? get_paragraph_style (string id) {
            return paragraph_styles.lookup (id);
        }
        
        public static StyleTemplate @default (DocumentBuffer buffer) {
            var template = new StyleTemplate ();
            /* text body */
            var style = new ParagraphStyle (buffer, "text-body", _("Text Body"));
            var font_desc = Pango.FontDescription.from_string ("FreeSerif 13");
            style.set_spacing (0, 10);
            style.set_font_description (font_desc);
            style.set_justification (Gtk.Justification.FILL);
            template.add_paragraph_style ("text-body", style);
            /* heading 1 */
            
            return template;
        }
        
    }
    
}
