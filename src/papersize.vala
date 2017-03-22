/* papersize.vala
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

    public class PaperSize : Object {
    
        public int width { get; private set; }
        public int height { get; private set; }
        public int left_margin { get; set; }
        public int right_margin { get; set; }
        public int top_margin { get; set; }
        public int bottom_margin { get; set; }
        public int inner_margin { get; set; default = 0; }
        
        public int text_height { get { return height - top_margin - bottom_margin; } }
        
        string _name;
        public string name {
            get { return _name; }
            set {
                _name = value;
                use_paper (_name);
            }
        }
        
        public PaperSize (string name) {
            use_paper (name);
        }
        
        public PaperSize.@default () {
            use_paper (Gtk.PAPER_NAME_A4);
            var margin = Utils.to_pixels (Utils.INCH);
            left_margin = margin;
            right_margin = margin;
            top_margin = margin;
            bottom_margin = margin;
        }
        
        private void use_paper (string name) {
            var paper_size = new Gtk.PaperSize (name);
            var unit = Gtk.Unit.POINTS;
            width = Utils.to_pixels (paper_size.get_width (unit));
            height = Utils.to_pixels (paper_size.get_height (unit));
            left_margin = Utils.to_pixels (paper_size.get_default_left_margin (unit));
            right_margin = Utils.to_pixels (paper_size.get_default_right_margin (unit));
            top_margin = Utils.to_pixels (paper_size.get_default_top_margin (unit));
            bottom_margin = Utils.to_pixels (paper_size.get_default_bottom_margin (unit));
        }
    
    }
    
}
