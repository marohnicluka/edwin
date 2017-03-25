/* hyphenation.vala
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

namespace Edwin.Hyphenation {

    public class LanguagePatterns {
    
        public struct Break {
            int offset;
            int priority;
        }
        
        string[] patterns;
        bool loaded;
        List<Break?> possible_breaks;
        
        public LanguagePatterns () {
            patterns = { };
            loaded = false;
        }
        
        public async bool load (File pattern_file, Cancellable? cancellable) {
            var name = pattern_file.get_basename ();
            try {
                var @is = yield pattern_file.read_async (Priority.DEFAULT, cancellable);
                var dis = new DataInputStream (@is);
                string line;
                int dropped = 0;
                int accepted = 0;
                while ((line = yield dis.read_line_async (Priority.DEFAULT, cancellable)) != null) {
                    if ("1" in line || "3" in line || "5" in line) {
                        line = line.replace ("2", "").replace ("4", "").replace ("6", "");
                        patterns += line;
                        accepted++;
                    } else dropped++;
                }
                debug ("Hyphenation patterns for language \'%s\' loaded: %d entries accepted, %d entries dropped", name.substring (0, name.length - 4), accepted, dropped);
                loaded = true;
                return true;
            } catch (Error e) {
                warning (e.message);
                return false;
            }
        }
        
        private void find_possible_breaks (string word, string pat, int index) {
            int offset = word.substring (0, index).char_count ();
            int start = 0, end = 0;
            unichar ch;
            for (int cnt = 0; pat.get_next_char (ref end, out ch); cnt++) {
                if (ch.isdigit ()) {
                    var priority = (int.parse (word.substring (start, end)) + 1) / 2;
                    Break possible_break = {offset + cnt, priority};
                    possible_breaks.append (possible_break);
                    cnt--;
                }
                start = end;
            }
        }
        
        public int[] get_possible_word_breaks (string word)
            requires (loaded)
        {
            possible_breaks = new List<Break?> ();
            int index;
            foreach (unowned string pat in patterns) {
                var chunk = pat.replace ("1", "").replace ("3", "").replace ("5", "");
                int start = 0;
                if (chunk.has_prefix (".") && chunk.has_suffix (".")) {
                    if (word != chunk) {
                        continue;
                    }
                    find_possible_breaks (word, pat, 0);
                } else if (chunk.has_prefix (".")) {
                    if (!word.has_prefix (chunk)) {
                        continue;
                    }
                    find_possible_breaks (word, pat, 0);
                } else if (chunk.has_suffix (".")) {
                    if (!word.has_suffix (chunk)) {
                        continue;
                    }
                    find_possible_breaks (word, pat, word.length - chunk.length);
                } else while ((index = word.index_of (chunk, start)) != -1) {
                    find_possible_breaks (word, pat, index);
                    start = index + chunk.length;
                }
            }
            possible_breaks.sort ((a, b) => {
                double score_a = a.offset * (1 + (a.priority - 1) / 4.0);
                double score_b = b.offset * (1 + (b.priority - 1) / 4.0);
                if (score_a == score_b) {
                    return 0;
                } else if (score_a > score_b) {
                    return -1;
                }
                return 1;
            });
            int[] breaks = { };
            for (uint n = 0; n < possible_breaks.length (); n++) {
                var offset = possible_breaks.nth_data (n).offset;
                breaks += offset;
            }
            return breaks;
        }
        
    }

    public class Manager : Object {
        
        HashTable<string, LanguagePatterns> language_patterns_table;
        unowned Cancellable? cancellable;
        int total = 0;
        int loaded = 0;
        
        public signal void patterns_loaded (int n);
        
        public Manager (Cancellable? cancellable = null) {
            language_patterns_table = new HashTable<string, LanguagePatterns> (str_hash, str_equal);
            this.cancellable = cancellable;
            foreach (var lang in GtkSpell.Checker.get_language_list ()) {
                var path = Path.build_filename (Constants.PKGDATADIR, "patterns", @"$lang.pat");
                var file = File.new_for_path (path);
                if (file.query_exists ()) {
                    total++;
                    var language_patterns = new LanguagePatterns ();
                    language_patterns.load.begin (file, cancellable, (obj, res) => {
                        if (language_patterns.load.end (res)) {
                            language_patterns_table.insert (lang, language_patterns);
                            loaded++;
                            if (loaded == total) {
                                patterns_loaded (total);
                            }
                        } else total--;
                    });
                }
            }
        }
        
        public unowned LanguagePatterns? get_patterns_for_language (string lang) {
            return language_patterns_table.lookup (lang);
        }
        
    }

}
