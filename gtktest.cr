// ./fcc $(pkg-config --libs --cflags gtk+-2.0) gtktest.cr std/string.cr
module gtktest;

import gtk;

import sys, std.string, std.file;

bool delete_event(void* widget, void* event, gpointer data) {
    /* If you return FALSE in the "delete-event" signal handler,
     * GTK will emit the "destroy" signal. Returning TRUE means
     * you don't want the window to be destroyed.
     * This is useful for popping up 'are you sure you want to quit?'
     * type dialogs. */

    g_print ("delete event occurred\n");

    /* Change TRUE to FALSE and the main window will be destroyed with
     * a "delete-event". */

    return true;
}

alias G_TYPE_STRING = GType:(16 << 2);

extern(C) FILE* stdout;
int main (int argc, char **argv) {
    gtk_init (&argc, &argv);
    
    auto window = gtk_window_new GTK_WINDOW_TOPLEVEL;
    
    gtk_window_set_title (gtkCastWindow(window), "Hello Buttons!");
    
    auto model = gtk_tree_store_new (2, G_TYPE_STRING, G_TYPE_STRING);
    
    string line;
    GtkTreeIter[auto~] iters;
    GtkTreeIter* current() { return &iters[iters.length-1]; }
    GtkTreeIter* prev() { return &iters[iters.length-2]; }
    bool reading;
    writeln "Building model. ";
    while line <- splitAt("\n",
        castIter!string readfile open "xmldump.txt") {
      // writeln "> $line";
      if (auto rest = line.startsWith "----module ") {
        auto restp = toStringz rest;
        GtkTreeIter iter;
        iters ~= iter;
        model.gtk_tree_store_append (current(), null);
        model.gtk_tree_store_set (current(), 0, restp, 1, null, -1);
        int st = current().stamp;
        reading = true;
      }
      if (line.startsWith "----done") {
        iters = type-of iters: iters[0 .. $-1];
        reading = false;
      }
      if (reading) {
        if (line.startsWith "<node") {
          auto classnamep = toStringz line.between(" classname=\"", "\"");
          auto namep = toStringz line.between (" name=\"", "\" ");
          auto infop = toStringz line.between (" info=\"", "\" ");
          if (line.find " info=" == -1) infop = namep;
          GtkTreeIter iter;
          iters ~= iter;
          model.gtk_tree_store_append (current(), prev());
          model.gtk_tree_store_set (current(), 0, classnamep, 1, infop, -1);
        }
        if (line == "</node>") {
          iters = type-of iters: iters[0 .. $-1];
        }
      }
    }
    
    auto sw = gtk_scrolled_window_new (null, null);
    sw.gtkCastScrolledWindow()
      .gtk_scrolled_window_set_policy (GTK_POLICY_AUTOMATIC x 2);
    
    auto tree = gtk_tree_view_new ();
    tree.gtkCastTreeView().gtk_tree_view_set_headers_visible true;
    
    sw.gtkCastContainer().gtk_container_add tree;
    window.gtkCastContainer().gtk_container_add sw;
    
    {
      auto renderer = gtk_cell_renderer_text_new ();
      auto column = gtk_tree_view_column_new_with_attributes ("Class",
                      renderer, "text".ptr, 0, null);
      tree.gtkCastTreeView().gtk_tree_view_append_column column;
      column = gtk_tree_view_column_new_with_attributes ("Info",
                      renderer, "text".ptr, 1, null);
      tree.gtkCastTreeView().gtk_tree_view_append_column column;
      tree.gtkCastTreeView().gtk_tree_view_set_model model.gtkCastTreeModel();
      g_object_unref (model);
    }
    
    window.g_signal_connect_data (
      "delete-event",
      void*:function bool(void* widget, event, data) { return false; },
      null, null, 0
    );
    
    g_signal_connect (window, "destroy", delegate void(GtkWidget*) { gtk_main_quit(); });
    
    window.gtkCastContainer().gtk_container_set_border_width 10;
    
    window.gtk_widget_show_all ();
    
    /* All GTK applications must have a gtk_main(). Control ends here
     * and waits for an event to occur (like a key press or
     * mouse event). */
    gtk_main ();
    
    return 0;
}
