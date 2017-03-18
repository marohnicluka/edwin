/* edwin.vala
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

    /* settings */
    public SavedState saved_state;
    public Settings settings;

    public class App : Granite.Application {
        
        private static string _app_cmd_name;
        private static string _data_home_folder_unsaved;
        private static string _cwd;
        private static bool print_version = false;
        private static bool create_new_document = false;
        private static bool create_new_window = false;
        
        public string app_cmd_name { get { return _app_cmd_name; } }
        public string data_home_folder_unsaved { get { return _data_home_folder_unsaved; } }
        
        construct {
            flags |= ApplicationFlags.HANDLES_OPEN;
            flags |= ApplicationFlags.HANDLES_COMMAND_LINE;
            build_data_dir = Constants.DATADIR;
            build_pkg_data_dir = Constants.PKGDATADIR;
            build_release_name = Constants.RELEASE_NAME;
            build_version = Constants.VERSION;
            build_version_info = Constants.VERSION_INFO;
            
            program_name = app_cmd_name;
            exec_name = app_cmd_name.down ();
            app_years = "2017";
            app_icon = "accessories-text-editor";
            app_launcher = exec_name + ".desktop";
            application_id = "org.pantheon." + exec_name;
            main_url = "https://github.com/marohnicluka/edwin";
            about_authors = { "Luka Marohnić <marohnicluka@gmail.com>" };
            about_license_type = Gtk.License.GPL_3_0;
        }
        
        public App () {
            /* internationalization */
            Intl.setlocale (LocaleCategory.ALL, "");
            string langpack_dir = Path.build_filename (Constants.INSTALL_PREFIX, "share", "locale");
            Intl.bindtextdomain (Constants.GETTEXT_PACKAGE, langpack_dir);
            Intl.bind_textdomain_codeset (Constants.GETTEXT_PACKAGE, "UTF-8");
            Intl.textdomain (Constants.GETTEXT_PACKAGE);
            /* initialize logger */
            Granite.Services.Logger.initialize (app_cmd_name);
            Granite.Services.Logger.DisplayLevel = Granite.Services.LogLevel.DEBUG;
            /* initialize settings */
            saved_state = new SavedState ();
            settings = new Settings ();
            /* get folder for storing unsaved files and create it if necessary */
            var user_data_dir = Environment.get_user_data_dir ();
            _data_home_folder_unsaved = Path.build_filename (user_data_dir, exec_name, "unsaved");
            create_unsaved_documents_directory ();
        }
        
        private static App _instance = null;
        
        public static App instance {
            get {
                if (_instance == null) {
                    _instance = new App ();
                }
                return _instance;
            }
        }
        
        public MainWindow? get_last_window () {
            unowned List<weak Gtk.Window> windows = get_windows ();
            return windows.length () > 0 ? windows.last ().data as MainWindow : null;
        }

		public unowned MainWindow? get_focused_window () {
			unowned List<weak Gtk.Window> windows = get_windows ();
			return windows.length () > 0 ? windows.first ().data as MainWindow : null;
		}
        
        public MainWindow new_window () {
            return new MainWindow (this);
        }
        
        protected override void activate () {
            set_accelerators ();
            var window = get_last_window ();
            if (window == null) {
                window = this.new_window ();
                window.show_all ();
            } else {
                window.present ();
            }
        }
        
        private void set_accelerators () {
            set_accels_for_action ("win.Quit",              {"<Primary>q"});
            set_accels_for_action ("win.NewDocument",       {"<Primary>n"});
            set_accels_for_action ("win.Undo",              {"<Primary>z"});
            set_accels_for_action ("win.Redo",              {"<Primary><Shift>z"});
            set_accels_for_action ("win.Find",              {"<Primary>f"});
            set_accels_for_action ("win.NextMatch",         {"<Primary>g"});
            set_accels_for_action ("win.PreviousMatch",     {"<Primary><Shift>g"});
            set_accels_for_action ("win.Replace",           {"<Primary>r"});
            set_accels_for_action ("win.ReplaceAll",        {"<Primary><Shift>r"});
        }
                
        private void create_unsaved_documents_directory () {
            File directory = File.new_for_path (data_home_folder_unsaved);
            if (!directory.query_exists ()) {
                debug ("Creating 'unsaved' directory: %s", directory.get_path ());
                try {
                    directory.make_directory_with_parents ();
                } catch (Error e) {
                    warning ("Failed to create 'unsaved' directory: %s", e.message);
                }
            }
		}
		
		protected override int command_line (ApplicationCommandLine cmd) {
		    var context = new OptionContext ();
		    context.add_main_entries (entries, Constants.GETTEXT_PACKAGE);
		    context.add_group (Gtk.get_option_group (true));
		    string[] args = cmd.get_arguments ();
	        /* try to parse the command line */
		    try {
		        unowned string[] tmp = args;
		        context.parse (ref tmp);
	        } catch (Error e) {
	            warning ("Failed to parse command line arguments: %s", e.message);
	            return Posix.EXIT_FAILURE;
	        }
	        if (print_version) {
	            /* display version information and exit */
	            stdout.printf ("Edwin %s (%s)\n", build_version, build_version_info);
	            stdout.printf ("Copyright %s by Luka Marohnić.\n", app_years);
	            return Posix.EXIT_SUCCESS;
	        }
	        activate ();
            /* create new window if requested */
	        if (create_new_window && get_last_window () != null) {
	            create_new_window = false;
	            this.new_window ();
	        }
	        /* create new document if requested */
	        if (create_new_document) {
                create_new_document = false;
                var window = get_last_window ();
                window.win_actions.activate_action ("NewDocument", null);
            }
            /* set current working directory */
            Environment.set_current_dir (_cwd);
            return Posix.EXIT_SUCCESS;
		}
		
		protected override void open (File[] files, string hint) {

        }
		
		const OptionEntry[] entries = {
            { "new-document", 'd', 0, OptionArg.NONE, out create_new_document, N_("New Document"), null },
            { "new-window", 'n', 0, OptionArg.NONE, out create_new_window, N_("New Window"), null },
            { "version", 'v', 0, OptionArg.NONE, out print_version, N_("Print version info and exit"), null },
            { "cwd", 'c', 0, OptionArg.STRING, ref _cwd, N_("Current working directory"), "" },
            { null }
        };
		
		public string resource_path () {
			string sep = "%c".printf (Path.DIR_SEPARATOR);
			return sep + application_id.replace (".", sep);
		}
		
        public MenuModel get_menu_model (string name) {
            string menus_file_path = Path.build_filename (resource_path (), "ui", "menus.ui");
            var builder = new Gtk.Builder.from_resource (menus_file_path);
            return builder.get_object (name) as MenuModel;
        }
        
		public static int main (string[] args) {
            _app_cmd_name = "Edwin";
            var app = App.instance;
            return app.run (args);
        }
	}
    
}
