/* languagechooser.vala
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

    public class LanguageChooser : ListChooser {
    
        public LanguageChooser (Gtk.Widget widget) {
            base (widget);
            id_column_index = 1;
        }
        
        protected override string get_initial_id () {
            return App.instance.get_focused_window ().document.language;
        }
    
        protected override void populate () {            
            GtkSpell.Checker.get_language_list ().@foreach ((lang) => {
                Gtk.TreeIter iter;
                list_store.append (out iter);
                string name = GtkSpell.Checker.decode_language_code (lang);
                list_store.@set (iter, 0, name, 1, lang);
            });
        }
        
    }
    
}
