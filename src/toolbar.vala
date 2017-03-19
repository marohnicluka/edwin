/* toolbar.vala
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

    public enum TextListType {
        NONE,
        ENUMERATE,
        ITEMIZE
    }

    public class ToolBar : Gtk.Toolbar {
    
        const int CHOOSER_WIDTH = 130;
        const int DEFAULT_FONT_SIZE = 12;
        const int[] FONT_SIZES = { 6, 7, 8, 9, 10, 11, 12, 14, 16, 18, 21, 24, 36, 48, 60, 72 };
        
        public class ParagraphStyleChooser : Gtk.ComboBoxText {
            public ParagraphStyleChooser (string name) {
                this.name = name;
                can_focus = false;
                append ("none",         _("None"));
                append ("default",      _("Default style"));
                append ("body",         _("Text body"));
                append ("heading-1",    _("Heading 1"));
                append ("heading-2",    _("Heading 2"));
                append ("heading-3",    _("Heading 3"));
                append ("title",        _("Title"));
                append ("quote",        _("Quotation"));
                var model_filter = new Gtk.TreeModelFilter (model, null);
                model_filter.set_visible_func ((m, iter) => {
                    string item;
                    m.@get (iter, 1, out item);
                    return item != "none";
                });
                set_model (model_filter);
                active_id = "default";
            }
        }
        
        public class TextSizeChooser : Gtk.ComboBoxText {
            public unowned Gtk.Entry entry {
                get { return get_child () as Gtk.Entry; }
            }
            
            public TextSizeChooser (string nom) {
                Object (name: nom, can_focus: false, has_entry: true);
                foreach (var size in FONT_SIZES) {
                    append_text (size.to_string ());
                }
                entry.input_purpose = Gtk.InputPurpose.DIGITS;
                entry.width_chars = 2;
                entry.buffer.set_max_length (2);
                entry.xalign = 1.0f;
                entry.text = DEFAULT_FONT_SIZE.to_string ();
            }
        }
        
        public class FontButton : Gtk.Button {
        
            public FontFamilyChooser chooser;
            
            public FontButton (string name) {
                this.name = name;
                can_focus = false;
                xalign = 0.0f;
                chooser = new FontFamilyChooser (this);
                this.clicked.connect (() => {
                    chooser.show ();
                });
            }
            
            public void set_font_family (string family) {
                this.label = family;
            }
            
            public string get_font_family () {
                return this.label;
            }

        }
        
        public class ColorChooser : Gtk.ColorButton {
            public ColorChooser (string name) {
                this.name = name;
                can_focus = false;
                rgba = Gdk.RGBA () { red = 0.0, green = 0.0, blue = 0.0, alpha = 1.0 };
                title = _("Choose Text Color");
                realize.connect (() => {
                    var swatch = get_child ();
                    var height = swatch.get_allocated_height ();
                    swatch.set_size_request (height, height);
                });
            }
        }
        
        public class ToolBox : Gtk.Box {
            public ToolBox (string name, bool homogeneous = true) {
                this.name = name;
                this.homogeneous = homogeneous;
                spacing = 0;
                can_focus = false;
                var context = get_style_context ();
                context.add_class (Gtk.STYLE_CLASS_LINKED);
                context.add_class ("raised");
            }
        }
        
        public class ModeButton : Granite.Widgets.ModeButton {
            
            protected int last_selected = -1;
            
            public signal void changed (int index);
            
            public ModeButton (string name) {
                this.name = name;
                mode_changed.connect (() => {
                    changed (selected);
                });
            }
            
            protected void make_inconsistent () {
                notify["selected"].connect (() => {
                    if (last_selected == selected) {
                        ulong handler = 0;
                        handler = button_release_event.connect (() => {
                            set_active (-1);
                            last_selected = -1;
                            disconnect (handler);
                            changed (-1);
                            return false;
                        });
                    }
                    last_selected = selected;
                });
            }
        }
        
        public class AlignmentButton : ModeButton {
            public AlignmentButton (string name) {
                base (name);
                assert (Gtk.Justification.LEFT == append (Utils.get_icon ("text-tools::aligned-left")));
                assert (Gtk.Justification.RIGHT == append (Utils.get_icon ("text-tools::aligned-right")));
                assert (Gtk.Justification.CENTER == append (Utils.get_icon ("text-tools::centered")));
                assert (Gtk.Justification.FILL == append (Utils.get_icon ("text-tools::justified")));
            }
        }
        
        public class ListButton : ModeButton {
            public ListButton (string name) {
                base (name);
                assert (TextListType.ENUMERATE == 1 + append (Utils.get_icon ("text-tools::enumerate")));
                assert (TextListType.ITEMIZE == 1 + append (Utils.get_icon ("text-tools::itemize")));
                make_inconsistent ();
            }
        }
        
        private class Button : Gtk.ToggleButton {
            public Button (string icon_name, string? action_name, string? tooltip) {
                label = null;
                can_focus = false;
                set_image (Utils.get_icon (icon_name));
                if (action_name != null) {
                    set_action_name (@"win.$action_name");
                }
                if (tooltip != null) {
                    set_tooltip_text (tooltip);
                }
            }
        }
        
        /* text toolbar */
        ParagraphStyleChooser paragraph_style_chooser;
        FontButton text_font_chooser;
        ColorChooser text_color_chooser;
        TextSizeChooser text_size_chooser;
        Button button_bold;
        Button button_italic;
        Button button_underline;
        AlignmentButton alignment_button;
        ListButton list_button;
        /* equation editor toolbar
        Gtk.ToolButton eq_layout_superscript;
        Gtk.ToolButton eq_layout_subscript;
        Gtk.ToolButton eq_layout_subsuperscript;
        Gtk.ToolButton eq_layout_array;
        Gtk.ToolButton eq_stacking_fraction;
        Gtk.ToolButton eq_stacking_fraction_no_line;
        Gtk.ToolButton eq_stacking_accent;
        Gtk.ToolButton eq_function_general;
        Gtk.ToolButton eq_function_square_root;
        Gtk.ToolButton eq_function_root;
        Gtk.ToolButton eq_delimiters_bracketing;
        Gtk.ToolButton eq_delimiters_sequence;
        Gtk.ToolButton eq_delimiters_spacer;
        Gtk.ToolButton eq_calculus_integral;
        Gtk.ToolButton eq_calculus_integral_below;
        Gtk.ToolButton eq_calculus_integral_below_above;
        Gtk.ToolButton eq_calculus_limit;
        Gtk.ToolButton eq_big_operator;
        Gtk.ToolButton eq_big_operator_below;
        Gtk.ToolButton eq_big_operator_below_above;
        */
        
        bool programmatic = false;
        uint separator_serial = 0;
        
        public signal void paragraph_style_selected (string id);
        public signal void paragraph_alignment_selected (Gtk.Justification justification);
        public signal void font_family_selected (string family);
        public signal void text_color_selected (Gdk.RGBA color);
        public signal void text_size_selected (int size);
        public signal void text_bold_toggled (bool active);
        public signal void text_italic_toggled (bool active);
        public signal void text_underline_toggled (bool active);
        public signal void list_type_selected (TextListType type);
        public signal void return_focus_to_document ();
        
        public ToolBar () {
            create_layout ();
            connect_signals ();
        }
        
        private void create_layout () {
            /* text toolbar */
            paragraph_style_chooser = new ParagraphStyleChooser ("text-toolbar-style-chooser");
            paragraph_style_chooser.set_size_request (CHOOSER_WIDTH, -1);
            add_widget (paragraph_style_chooser);
            text_color_chooser = new ColorChooser ("text-toolbar-color-button");
            text_font_chooser = new FontButton ("text-toolbar-font-button");
            var font_box = new ToolBox ("text-toolbar-font-box", false);
            font_box.pack_start (text_font_chooser);
            font_box.pack_start (text_color_chooser, false);
            font_box.set_size_request (CHOOSER_WIDTH, -1);
            add_separator ("text-toolbar");
            add_widget (font_box);
            text_size_chooser = new TextSizeChooser ("text-toolbar-size-chooser");
            add_separator ("text-toolbar");
            add_widget (text_size_chooser);
            var button_box = new ToolBox ("text-toolbar-style-box");
            button_bold = new Button ("text-tools::bold", null, null);
            button_italic = new Button ("text-tools::italic", null, null);
            button_underline = new Button ("text-tools::underline", null, null);
            button_box.pack_start (button_bold);
            button_box.pack_start (button_italic);
            button_box.pack_start (button_underline);
            add_separator ("text-toolbar");
            add_widget (button_box);
            alignment_button = new AlignmentButton ("text-toolbar-alignment-button");
            add_separator ("text-toolbar");
            add_widget (alignment_button);
            list_button = new ListButton ("text-toolbar-list-button");
            add_separator ("text-toolbar");
            add_widget (list_button);
            /* equation editor toolbar */
        }
        
        private void connect_signals () {
            paragraph_style_chooser.changed.connect (() => {
                if (programmatic) {
                    return;
                }
                var id = paragraph_style_chooser.active_id;
                debug ("User changed paragraph style to %s", id);
                paragraph_style_selected (id);
            });
            text_font_chooser.chooser.activated.connect (() => {
                var family = text_font_chooser.chooser.get_selected ();
                if (family != null) {
                    debug ("User changed text font to %s", family);
                    text_font_chooser.set_font_family (family);
                    font_family_selected (family);
                    text_font_chooser.chooser.hide ();
                }
            });
            text_color_chooser.color_set.connect (() => {
                var color = text_color_chooser.rgba;
                debug ("User changed text color to %s", color.to_string ());
                text_color_selected (color);
            });
            text_size_chooser.changed.connect (() => {
                if (programmatic) {
                    return;
                }
                if (!text_size_chooser.entry.has_focus) {
                    on_user_changed_font_size ();
                    return_focus_to_document ();
                }
            });
            text_size_chooser.entry.activate.connect (() => {
                on_user_changed_font_size ();
                return_focus_to_document ();
            });
            button_bold.toggled.connect (() => {
                if (programmatic) {
                    return;
                }
                var active = button_bold.active;
                debug ("User toggled bold %s", active ? "on" : "off");
                text_bold_toggled (active);
            });
            button_italic.toggled.connect (() => {
                if (programmatic) {
                    return;
                }
                var active = button_italic.active;
                debug ("User toggled italic %s", active ? "on" : "off");
                text_italic_toggled (active);
            });
            button_underline.toggled.connect (() => {
                if (programmatic) {
                    return;
                }
                var active = button_underline.active;
                debug ("User toggled underline %s", active ? "on" : "off");
                text_underline_toggled (active);
            });
            alignment_button.changed.connect ((index) => {
                if (programmatic) {
                    return;
                }
                var alignment = (Gtk.Justification) index;
                debug ("User changed paragraph alignment to %s", alignment.to_string ());
                paragraph_alignment_selected (alignment);
            });
            list_button.changed.connect ((index) => {
                if (programmatic) {
                    return;
                }
                var list_type = (TextListType) (index + 1);
                debug ("User changed list type to %s", list_type.to_string ());
                list_type_selected (list_type);
            });
        }
        
        private void add_widget (Gtk.Widget widget) {
            var item = new Gtk.ToolItem ();
            item.add (widget);
            add (item);
        }
                  
        private void add_separator (string toolbar_name, bool expand = false) {
            var separator = new Gtk.SeparatorToolItem ();
            separator.name = "%s-%u".printf (toolbar_name, separator_serial++);
            add (separator);
            if (expand) {
                separator.draw = false;
                child_set (separator, expand: true);
            } else {
                separator.width_request = 12;
            }
        }
        
        private void begin_programmatic () {
            programmatic = true;
            Timeout.add (10, () => {
                programmatic = false;
                return false;
            });
        }
        
        private void on_user_changed_font_size () {
            var size = int.parse (text_size_chooser.entry.text);
            if (size <= 0) {
                size = DEFAULT_FONT_SIZE;
                begin_programmatic ();
                text_size_chooser.entry.text = size.to_string ();
            }
            debug ("User changed text size to %d", size);
            text_size_selected (size);
        }
        
/******************\
|* PUBLIC METHODS *|
\******************/
        
        public void set_paragraph_style (string id) {
            begin_programmatic ();
            paragraph_style_chooser.set_active_id (id);
        }
        
        public string get_paragraph_style () {
            return paragraph_style_chooser.active_id;
        }
        
        public void set_paragraph_alignment (int alignment) {
            begin_programmatic ();
            alignment_button.set_active (alignment);
        }
        
        public Gtk.Justification get_paragraph_alignment () {
            return (Gtk.Justification) alignment_button.selected;
        }
        
        public void set_list_type (int type) {
            begin_programmatic ();
            list_button.set_active (type - 1);
        }
        
        public TextListType get_list_type () {
            return (TextListType) (list_button.selected + 1);
        }
        
        public void set_text_font_desc (Pango.FontDescription font_desc) {
            assert (font_desc.get_size_is_absolute () == false);
            var family = font_desc.get_family ();
            text_font_chooser.set_font_family (family);
            begin_programmatic ();
            var size = font_desc.get_size ();
            if (size > 100) {
                size /= Pango.SCALE;
            }
            text_size_chooser.entry.text = size > 0 ? size.to_string () : "";
            button_bold.active = font_desc.get_weight () == Pango.Weight.BOLD;
            button_italic.active = font_desc.get_style () == Pango.Style.ITALIC;
        }
        
        public Pango.FontDescription get_text_font_desc () {
            var font_desc = Pango.FontDescription.from_string (text_font_chooser.get_font_family ());
            string size_text = text_size_chooser.entry.text;
            int size = size_text.length == 0 ? DEFAULT_FONT_SIZE : int.parse (size_text);
            font_desc.set_size (size * Pango.SCALE);
            font_desc.set_weight (button_bold.active ? Pango.Weight.BOLD : Pango.Weight.NORMAL);
            font_desc.set_style (button_italic.active ? Pango.Style.ITALIC : Pango.Style.NORMAL);
            return font_desc;
        }
        
        public void set_text_color (Gdk.RGBA color) {
            text_color_chooser.set_rgba (color);
        }

        public Gdk.RGBA get_text_color () {
            return text_color_chooser.rgba;
        }
        
        public void set_text_size (int size) {
            begin_programmatic ();
            text_size_chooser.entry.text = size > 0 ? size.to_string () : "";
        }
        
        public void set_font_family (string family) {
            text_font_chooser.set_font_family (family);
        }
        
        public string get_font_family () {
            return text_font_chooser.get_font_family ();
        }
        
        public void set_underline_state (bool state) {
            begin_programmatic ();
            button_underline.active = state;
        }
        
        public bool get_underline_state () {
            return button_underline.active;
        }

    }
    
}
