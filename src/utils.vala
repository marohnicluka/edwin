/* utils.vala
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

namespace Edwin.Utils {

    public const int INCH = 72;
    
    /**
     *  The sign function.
     */
    public int sgn (int n) {
        if (n > 0) {
            return 1;
        } else if (n < 0) {
            return -1;
        }
        return 0;
    }

    /**
     *  Get page border color.
     */
    public Gdk.RGBA page_border_color () {
        var rgba = Gdk.RGBA ();
        rgba.parse ("#c6c6c6");
        return rgba;
    }

    /**
     *  Get page break color.
     */
    public Gdk.RGBA page_break_color () {
        var rgba = Gdk.RGBA ();
        rgba.parse ("#dadada");
        return rgba;
    }

    /**
     *  Get page border color.
     */
    public Gdk.RGBA alert_color () {
        var rgba = Gdk.RGBA ();
        rgba.parse ("#ef2929");
        return rgba;
    }

    /**
     *  Get dpi for the default screen.
     */
    public double get_dpi () {
        var screen = Gdk.Screen.get_default ();
        return screen.get_resolution ();
    }

    /**
     *  Convert points to pixels with respect to the screen resolution,
     *  scaling the result value by FACTOR.
     */
    public int to_pixels (double points, double factor = 1.0) {
        return (int) Math.round (points * factor * Utils.get_dpi () / INCH);
    }
    
    /**
     *  Create and return CssProvider with given stylesheet loaded.
     */
    public Gtk.CssProvider? get_css_provider (string stylesheet) {
        var provider = new Gtk.CssProvider ();
        try {
            provider.load_from_data (stylesheet, -1);
        } catch (Error e) {
            warning (e.message);
            return null;
        }
        return provider;
    }
    
    /**
     *  Apply stylesheet to widget.
     */
    public void apply_stylesheet (Gtk.Widget widget, string stylesheet) {
        var provider = get_css_provider (stylesheet);
        if (provider != null) {
            var context = widget.get_style_context ();
            var priority = Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION;
            context.add_provider (provider, priority);
        }
    }

    public void fill_rectangle_as_background (Cairo.Context cr, Gdk.Rectangle rect) {
        var window = App.instance.active_window;
        var style_context = window.get_style_context ();
        style_context.render_background (cr, rect.x, rect.y, rect.width, rect.height);
    }
    
    public void fill_white_rectangle (Cairo.Context cr, Gdk.Rectangle rect) {
        cr.set_source_rgba (1.0, 1.0, 1.0, 1.0);
        Gdk.cairo_rectangle (cr, rect);
        cr.fill ();
    }
    
    public void draw_rectangle (Cairo.Context cr, Gdk.Rectangle rect, Gdk.RGBA color) {
        Gdk.cairo_set_source_rgba (cr, color);
        Gdk.cairo_rectangle (cr, rect);
        cr.stroke ();
    }
    
    public void refresh_gui () {
        while (Gtk.events_pending ()) {
            Gtk.main_iteration ();
        }
    }
    
    public Gtk.Image get_icon (string name) {
        var spec = name.split ("::");
        assert (spec.length == 2);
        var base_path = App.instance.resource_path ();
        var path = Path.build_filename (base_path, "resources", "icons", spec[0], spec[1] + ".png");
        return new Gtk.Image.from_resource (path);
    }
        
    public Gtk.ToolButton create_tool_button (string icon_name, string? action_name, string? tip) {
        var image = "::" in icon_name ?
            get_icon (icon_name) : new Gtk.Image.from_icon_name (icon_name, Gtk.IconSize.BUTTON);
        var button = new Gtk.ToolButton (image, null);
        if (action_name != null) {
            button.set_action_name (@"win.$action_name");
        }
        button.set_tooltip_text (tip);
        return button;
    }
        
    public Gtk.ToggleToolButton create_toggle_button (string icon_name, string? action_name, string? tip) {
        var image = "::" in icon_name ?
            get_icon (icon_name) : new Gtk.Image.from_icon_name (icon_name, Gtk.IconSize.BUTTON);
        var button = new Gtk.ToggleToolButton ();
        button.set_icon_widget (image);
        if (action_name != null) {
            button.set_action_name (@"win.$action_name");
        }
        button.set_tooltip_text (tip);
        return button;
    }
    
}
