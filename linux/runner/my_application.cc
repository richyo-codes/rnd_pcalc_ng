#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#include <gdk/gdk.h>
#include <glib.h>

#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char **dart_entrypoint_arguments;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

static FlMethodChannel *window_drag_channel = nullptr;
static FlMethodChannel *window_style_channel = nullptr;

static void apply_window_decorations(GtkWindow *window,
                                     gboolean use_system_decorations) {
  gtk_window_set_titlebar(window, nullptr);
  gtk_window_set_decorated(window, use_system_decorations);
}

#ifdef FLUTTER_LINUX_GTK4
using NativeResizeEdge = GdkSurfaceEdge;
#else
using NativeResizeEdge = GdkWindowEdge;
#endif

static NativeResizeEdge default_resize_edge() {
#ifdef FLUTTER_LINUX_GTK4
  return GDK_SURFACE_EDGE_SOUTH_EAST;
#else
  return GDK_WINDOW_EDGE_SOUTH_EAST;
#endif
}

static NativeResizeEdge native_resize_edge(const gchar *edge) {
  if (g_strcmp0(edge, "top") == 0) {
#ifdef FLUTTER_LINUX_GTK4
    return GDK_SURFACE_EDGE_NORTH;
#else
    return GDK_WINDOW_EDGE_NORTH;
#endif
  }
  if (g_strcmp0(edge, "topRight") == 0) {
#ifdef FLUTTER_LINUX_GTK4
    return GDK_SURFACE_EDGE_NORTH_EAST;
#else
    return GDK_WINDOW_EDGE_NORTH_EAST;
#endif
  }
  if (g_strcmp0(edge, "right") == 0) {
#ifdef FLUTTER_LINUX_GTK4
    return GDK_SURFACE_EDGE_EAST;
#else
    return GDK_WINDOW_EDGE_EAST;
#endif
  }
  if (g_strcmp0(edge, "bottomRight") == 0) {
#ifdef FLUTTER_LINUX_GTK4
    return GDK_SURFACE_EDGE_SOUTH_EAST;
#else
    return GDK_WINDOW_EDGE_SOUTH_EAST;
#endif
  }
  if (g_strcmp0(edge, "bottom") == 0) {
#ifdef FLUTTER_LINUX_GTK4
    return GDK_SURFACE_EDGE_SOUTH;
#else
    return GDK_WINDOW_EDGE_SOUTH;
#endif
  }
  if (g_strcmp0(edge, "bottomLeft") == 0) {
#ifdef FLUTTER_LINUX_GTK4
    return GDK_SURFACE_EDGE_SOUTH_WEST;
#else
    return GDK_WINDOW_EDGE_SOUTH_WEST;
#endif
  }
  if (g_strcmp0(edge, "left") == 0) {
#ifdef FLUTTER_LINUX_GTK4
    return GDK_SURFACE_EDGE_WEST;
#else
    return GDK_WINDOW_EDGE_WEST;
#endif
  }
  if (g_strcmp0(edge, "topLeft") == 0) {
#ifdef FLUTTER_LINUX_GTK4
    return GDK_SURFACE_EDGE_NORTH_WEST;
#else
    return GDK_WINDOW_EDGE_NORTH_WEST;
#endif
  }
  return default_resize_edge();
}

static NativeResizeEdge parse_resize_edge(FlValue *args) {
  if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
    return default_resize_edge();
  }

  FlValue *edge_value = fl_value_lookup_string(args, "edge");
  if (edge_value == nullptr ||
      fl_value_get_type(edge_value) != FL_VALUE_TYPE_STRING) {
    return default_resize_edge();
  }

  return native_resize_edge(fl_value_get_string(edge_value));
}

static void window_style_method_call_cb(FlMethodChannel *channel,
                                        FlMethodCall *method_call,
                                        gpointer user_data) {
  (void)channel;
  const gchar *method = fl_method_call_get_name(method_call);
  GtkWindow *window = GTK_WINDOW(user_data);
  g_autoptr(FlMethodResponse) response = nullptr;

  if (g_strcmp0(method, "setUseSystemDecorations") == 0) {
    gboolean enabled = FALSE;
    FlValue *args = fl_method_call_get_args(method_call);
    if (args != nullptr && fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
      FlValue *value = fl_value_lookup_string(args, "enabled");
      if (value != nullptr && fl_value_get_type(value) == FL_VALUE_TYPE_BOOL) {
        enabled = fl_value_get_bool(value);
      }
    }
    apply_window_decorations(window, enabled);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }

  g_autoptr(GError) error = nullptr;
  if (!fl_method_call_respond(method_call, response, &error)) {
    g_warning("Failed to respond on app/window_style channel: %s",
              error->message);
  }
}

static void window_drag_method_call_cb(FlMethodChannel *channel,
                                       FlMethodCall *method_call,
                                       gpointer user_data) {
  (void)channel;
  const gchar *method = fl_method_call_get_name(method_call);
  GtkWindow *window = GTK_WINDOW(user_data);
  g_autoptr(FlMethodResponse) response = nullptr;

  if (g_strcmp0(method, "startDrag") == 0) {
#ifdef FLUTTER_LINUX_GTK4
    GtkNative *native = gtk_widget_get_native(GTK_WIDGET(window));
    GdkSurface *surface =
        native != nullptr ? gtk_native_get_surface(native) : nullptr;
    GdkDisplay *display = gtk_widget_get_display(GTK_WIDGET(window));
    GdkSeat *seat =
        display != nullptr ? gdk_display_get_default_seat(display) : nullptr;
    GdkDevice *pointer = seat != nullptr ? gdk_seat_get_pointer(seat) : nullptr;

    if (surface != nullptr && GDK_IS_TOPLEVEL(surface) && pointer != nullptr) {
      double x = 0.0;
      double y = 0.0;
      gdk_device_get_surface_at_position(pointer, &x, &y);
      gdk_toplevel_begin_move(GDK_TOPLEVEL(surface), pointer, 1, x, y,
                              GDK_CURRENT_TIME);
    }
#else
    GdkDisplay *display = gtk_widget_get_display(GTK_WIDGET(window));
    GdkSeat *seat =
        display != nullptr ? gdk_display_get_default_seat(display) : nullptr;
    GdkDevice *pointer = seat != nullptr ? gdk_seat_get_pointer(seat) : nullptr;

    if (pointer != nullptr) {
      gint x = 0;
      gint y = 0;
      gdk_device_get_position(pointer, nullptr, &x, &y);
      gtk_window_begin_move_drag(window, 1, x, y, GDK_CURRENT_TIME);
    }
#endif
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (g_strcmp0(method, "startResize") == 0) {
#ifdef FLUTTER_LINUX_GTK4
    GtkNative *native = gtk_widget_get_native(GTK_WIDGET(window));
    GdkSurface *surface =
        native != nullptr ? gtk_native_get_surface(native) : nullptr;
    GdkDisplay *display = gtk_widget_get_display(GTK_WIDGET(window));
    GdkSeat *seat =
        display != nullptr ? gdk_display_get_default_seat(display) : nullptr;
    GdkDevice *pointer = seat != nullptr ? gdk_seat_get_pointer(seat) : nullptr;

    if (surface != nullptr && GDK_IS_TOPLEVEL(surface) && pointer != nullptr) {
      double x = 0.0;
      double y = 0.0;
      gdk_device_get_surface_at_position(pointer, &x, &y);
      gdk_toplevel_begin_resize(
          GDK_TOPLEVEL(surface),
          parse_resize_edge(fl_method_call_get_args(method_call)), pointer, 1,
          x, y, GDK_CURRENT_TIME);
    }
#else
    GdkDisplay *display = gtk_widget_get_display(GTK_WIDGET(window));
    GdkSeat *seat =
        display != nullptr ? gdk_display_get_default_seat(display) : nullptr;
    GdkDevice *pointer = seat != nullptr ? gdk_seat_get_pointer(seat) : nullptr;

    if (pointer != nullptr) {
      gint x = 0;
      gint y = 0;
      gdk_device_get_position(pointer, nullptr, &x, &y);
      gtk_window_begin_resize_drag(
          window, parse_resize_edge(fl_method_call_get_args(method_call)), 1, x,
          y, GDK_CURRENT_TIME);
    }
#endif
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (g_strcmp0(method, "minimize") == 0) {
#ifdef FLUTTER_LINUX_GTK4
    gtk_window_minimize(window);
#else
    gtk_window_iconify(window);
#endif
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (g_strcmp0(method, "maximize") == 0) {
    gtk_window_maximize(window);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (g_strcmp0(method, "isMaximized") == 0) {
#ifdef FLUTTER_LINUX_GTK4
    gboolean is_maximized = FALSE;
    GtkNative *native = gtk_widget_get_native(GTK_WIDGET(window));
    GdkSurface *surface =
        native != nullptr ? gtk_native_get_surface(native) : nullptr;
    if (surface != nullptr && GDK_IS_TOPLEVEL(surface)) {
      const GdkToplevelState state =
          gdk_toplevel_get_state(GDK_TOPLEVEL(surface));
      is_maximized = (state & GDK_TOPLEVEL_STATE_MAXIMIZED) != 0;
    }
#else
    gboolean is_maximized = gtk_window_is_maximized(window);
#endif
    response = FL_METHOD_RESPONSE(
        fl_method_success_response_new(fl_value_new_bool(is_maximized)));
  } else if (g_strcmp0(method, "toggleMaximize") == 0) {
#ifdef FLUTTER_LINUX_GTK4
    gboolean is_maximized = FALSE;
    GtkNative *native = gtk_widget_get_native(GTK_WIDGET(window));
    GdkSurface *surface =
        native != nullptr ? gtk_native_get_surface(native) : nullptr;
    if (surface != nullptr && GDK_IS_TOPLEVEL(surface)) {
      const GdkToplevelState state =
          gdk_toplevel_get_state(GDK_TOPLEVEL(surface));
      is_maximized = (state & GDK_TOPLEVEL_STATE_MAXIMIZED) != 0;
    }
#else
    gboolean is_maximized = gtk_window_is_maximized(window);
#endif
    if (is_maximized) {
      gtk_window_unmaximize(window);
    } else {
      gtk_window_maximize(window);
    }
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (g_strcmp0(method, "close") == 0) {
    gtk_window_close(window);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }

  g_autoptr(GError) error = nullptr;
  if (!fl_method_call_respond(method_call, response, &error)) {
    g_warning("Failed to respond on app/window_drag channel: %s",
              error->message);
  }
}

// Implements GApplication::activate.
static void my_application_activate(GApplication *application) {
  MyApplication *self = MY_APPLICATION(application);
  GtkWindow *window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  gtk_window_set_title(window, "pcalc express");
  gtk_window_set_icon_name(window, APPLICATION_ID);
  apply_window_decorations(window, FALSE);
  gtk_window_set_default_size(window, 620, 800);
#ifndef FLUTTER_LINUX_GTK4
  gtk_window_set_position(window, GTK_WIN_POS_CENTER);
#endif

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView *view = fl_view_new(project);
  FlBinaryMessenger *messenger =
      fl_engine_get_binary_messenger(fl_view_get_engine(view));
  if (window_drag_channel == nullptr) {
    g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
    window_drag_channel = fl_method_channel_new(messenger, "app/window_drag",
                                                FL_METHOD_CODEC(codec));
  }
  fl_method_channel_set_method_call_handler(
      window_drag_channel, window_drag_method_call_cb, window, nullptr);
  if (window_style_channel == nullptr) {
    g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
    window_style_channel = fl_method_channel_new(messenger, "app/window_style",
                                                 FL_METHOD_CODEC(codec));
  }
  fl_method_channel_set_method_call_handler(
      window_style_channel, window_style_method_call_cb, window, nullptr);

#ifdef FLUTTER_LINUX_GTK4
  gtk_widget_set_focusable(GTK_WIDGET(view), TRUE);
  gtk_window_set_child(window, GTK_WIDGET(view));
#else
  gtk_widget_set_can_focus(GTK_WIDGET(view), TRUE);
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));
  gtk_widget_show(GTK_WIDGET(view));
#endif

  gtk_window_present(window);
  gtk_widget_realize(GTK_WIDGET(view));
  fl_register_plugins(FL_PLUGIN_REGISTRY(view));
  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication *application,
                                                  gchar ***arguments,
                                                  int *exit_status) {
  MyApplication *self = MY_APPLICATION(application);
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;
  return TRUE;
}

static void my_application_startup(GApplication *application) {
  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

static void my_application_shutdown(GApplication *application) {
  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

static void my_application_dispose(GObject *object) {
  MyApplication *self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass *klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication *self) {}

MyApplication *my_application_new() {
  g_set_prgname(APPLICATION_ID);
  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_NON_UNIQUE, nullptr));
}
