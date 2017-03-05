/* settings.vala
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

    public enum WindowState {
        NORMAL,
        MAXIMIZED,
        FULLSCREEN
    }

    public class SavedState : Granite.Services.Settings {

        public WindowState window_state { get; set; }
        public int window_width { get; set; }
        public int window_height { get; set; }
        public int window_x { get; set; }
        public int window_y { get; set; }
        public int paned_position { get; set; }

        public SavedState () {
            base ("org.pantheon.edwin.saved-state");
        }
    }

    public class Settings : Granite.Services.Settings {

        public string show_at_start { get; set; }
        public bool autosave { get; set; }

        public Settings ()  {
            base ("org.pantheon.edwin.settings");
        }
    }

}
