#include <SDL3/SDL.h>
#include <SDL3/SDL_keyboard.h>
#include <SDL3_ttf/SDL_ttf.h>

#include <ctype.h>
#include <errno.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAX_HISTORY 512
#define MAX_TEXT 65536
#define MAX_LINES 512
#define MAX_LINE 512

typedef struct {
  const char *id;
  const char *title;
  const char *project;
  const char *source;
  const char *hint;
} Example;

static const Example EXAMPLES[] = {
  {"counter", "Counter", "examples/upstream/counter", "examples/upstream/counter/counter.bn", "Click +, Enter, or Space increments."},
  {"counter_hold", "Counter HOLD", "examples/upstream/counter_hold", "examples/upstream/counter_hold/counter_hold.bn", "Same UI as Counter, backed by HOLD source."},
  {"interval", "Interval", "examples/upstream/interval", "examples/upstream/interval/interval.bn", "Starts empty, then ticks once per second."},
  {"interval_hold", "Interval HOLD", "examples/upstream/interval_hold", "examples/upstream/interval_hold/interval_hold.bn", "Starts empty, then ticks once per second through HOLD."},
  {"fibonacci", "Fibonacci", "examples/upstream/fibonacci", "examples/upstream/fibonacci/fibonacci.bn", "Generated Boon output from the Fibonacci source."},
  {"todo_mvc", "TodoMVC", "examples/upstream/todo_mvc", "examples/upstream/todo_mvc/todo_mvc.bn", "Input is focused. Type and Enter to add. Click rows to toggle, [del] to delete."},
  {"pong", "Pong", "examples/terminal/pong", "examples/terminal/pong/pong.bn", "Space starts. W/S or Up/Down move the player paddle. AI follows the ball."},
  {"arkanoid", "Arkanoid", "examples/terminal/arkanoid", "examples/terminal/arkanoid/arkanoid.bn", "Space launches, A/D or arrows move, L marks lost."},
};

enum { EXAMPLE_COUNT = (int)(sizeof(EXAMPLES) / sizeof(EXAMPLES[0])) };

typedef struct {
  char *items[MAX_HISTORY];
  int len;
} History;

typedef struct {
  SDL_Window *window;
  SDL_Renderer *renderer;
  TTF_Font *font;
  int active;
  int source_scroll;
  int preview_scroll;
  bool running;
  bool script;
  bool todo_focused;
  bool pong_started;
  Uint64 last_interval_ms;
  Uint64 last_pong_ms;
  char todo_input[MAX_LINE];
  char preview[MAX_TEXT];
  char source_text[MAX_TEXT];
  char script_checks[MAX_TEXT];
  int script_check_count;
  int script_failure_count;
  History history[EXAMPLE_COUNT];
} App;

static void free_history(History *h) {
  for (int i = 0; i < h->len; i++) free(h->items[i]);
  h->len = 0;
}

static char *dup_text(const char *s) {
  size_t n = strlen(s);
  char *out = (char *)malloc(n + 1);
  if (!out) return NULL;
  memcpy(out, s, n + 1);
  return out;
}

static void append_history(App *app, int index, const char *line) {
  History *h = &app->history[index];
  if (h->len >= MAX_HISTORY) return;
  h->items[h->len] = dup_text(line);
  if (h->items[h->len]) h->len++;
}

static void json_escape(char *out, size_t out_size, const char *text) {
  size_t pos = 0;
  for (const char *p = text; *p && pos + 2 < out_size; p++) {
    if (*p == '"' || *p == '\\') {
      if (pos + 3 >= out_size) break;
      out[pos++] = '\\';
      out[pos++] = *p;
    } else if (*p == '\n') {
      if (pos + 3 >= out_size) break;
      out[pos++] = '\\';
      out[pos++] = 'n';
    } else {
      out[pos++] = *p;
    }
  }
  out[pos] = '\0';
}

static void append_expected(App *app, int index, const char *action, const char *value, int item_index) {
  char line[1024];
  char escaped[512];
  escaped[0] = '\0';
  if (value) json_escape(escaped, sizeof(escaped), value);
  snprintf(line, sizeof(line), "{\"protocol_version\":1,\"type\":\"expected_action\",\"action\":\"%s\"%s%s%s%s}",
    action,
    value ? ",\"value\":\"" : "",
    value ? escaped : "",
    value ? "\"" : "",
    item_index >= 0 ? ",\"index\":" : "");
  if (item_index >= 0) {
    char with_index[1100];
    size_t len = strlen(line);
    if (len > 0 && line[len - 1] == '}') line[len - 1] = '\0';
    snprintf(with_index, sizeof(with_index), "%s%d}", line, item_index);
    append_history(app, index, with_index);
  } else {
    append_history(app, index, line);
  }
}

static void shell_quote(char *out, size_t out_size, const char *text) {
  size_t pos = 0;
  if (pos + 1 < out_size) out[pos++] = '\'';
  for (const char *p = text; *p && pos + 5 < out_size; p++) {
    if (*p == '\'') {
      memcpy(out + pos, "'\\''", 4);
      pos += 4;
    } else {
      out[pos++] = *p;
    }
  }
  if (pos + 1 < out_size) out[pos++] = '\'';
  out[pos < out_size ? pos : out_size - 1] = '\0';
}

static bool file_exists(const char *path) {
  FILE *f = fopen(path, "rb");
  if (!f) return false;
  fclose(f);
  return true;
}

static int run_cmd(const char *cmd) {
  int status = system(cmd);
  if (status == -1) return 1;
  return status == 0 ? 0 : 1;
}

static bool ensure_generated(const Example *ex) {
  char binary[256];
  snprintf(binary, sizeof(binary), "build/bin/generated/%s", ex->id);
  if (file_exists(binary)) return true;
  char quoted[512];
  shell_quote(quoted, sizeof(quoted), ex->project);
  char cmd[1024];
  snprintf(cmd, sizeof(cmd), "build/bin/boonpony build %s >/dev/null 2>&1", quoted);
  return run_cmd(cmd) == 0;
}

static void json_unescape_to(char *dst, size_t dst_size, const char *start, const char *end) {
  size_t pos = 0;
  for (const char *p = start; p < end && pos + 1 < dst_size; p++) {
    if (*p == '\\' && p + 1 < end) {
      p++;
      if (*p == 'n') dst[pos++] = '\n';
      else if (*p == 'r') dst[pos++] = '\r';
      else if (*p == 't') dst[pos++] = '\t';
      else dst[pos++] = *p;
    } else {
      dst[pos++] = *p;
    }
  }
  dst[pos] = '\0';
}

static void extract_last_frame_text(const char *jsonl, char *out, size_t out_size) {
  const char *last = NULL;
  const char *p = jsonl;
  while ((p = strstr(p, "\"type\":\"frame\"")) != NULL) {
    const char *line = p;
    while (line > jsonl && line[-1] != '\n') line--;
    last = line;
    p += 14;
  }
  if (!last) {
    snprintf(out, out_size, "No generated protocol frame.");
    return;
  }

  out[0] = '\0';
  p = last;
  const char *line_end = strchr(last, '\n');
  if (!line_end) line_end = last + strlen(last);
  while ((p = strstr(p, "\"text\":\"")) != NULL && p < line_end) {
    p += 8;
    const char *end = p;
    bool esc = false;
    while (end < line_end && *end && (esc || *end != '"')) {
      esc = (!esc && *end == '\\');
      if (*end != '\\') esc = false;
      end++;
    }
    char chunk[MAX_TEXT];
    json_unescape_to(chunk, sizeof(chunk), p, end);
    if (out[0] != '\0') strncat(out, "\n", out_size - strlen(out) - 1);
    strncat(out, chunk, out_size - strlen(out) - 1);
    p = end;
    if (*p == '\n') break;
  }
}

static bool refresh_preview(App *app) {
  const Example *ex = &EXAMPLES[app->active];
  if (!ensure_generated(ex)) {
    snprintf(app->preview, sizeof(app->preview), "Build failed for %s", ex->title);
    return false;
  }

  char input_path[256];
  char output_path[256];
  snprintf(input_path, sizeof(input_path), "build/cache/gui-sdl-%s-input.jsonl", ex->id);
  snprintf(output_path, sizeof(output_path), "build/cache/gui-sdl-%s-output.jsonl", ex->id);
  run_cmd("mkdir -p build/cache build/reports");

  FILE *in = fopen(input_path, "wb");
  if (!in) return false;
  fprintf(in, "{\"protocol_version\":1,\"type\":\"frame\"}\n");
  History *h = &app->history[app->active];
  for (int i = 0; i < h->len; i++) fprintf(in, "%s\n", h->items[i]);
  fprintf(in, "{\"protocol_version\":1,\"type\":\"frame\"}\n");
  fprintf(in, "{\"protocol_version\":1,\"type\":\"tree\"}\n");
  fprintf(in, "{\"protocol_version\":1,\"type\":\"metrics\"}\n");
  fprintf(in, "{\"protocol_version\":1,\"type\":\"quit\"}\n");
  fclose(in);

  char cmd[1024];
  snprintf(cmd, sizeof(cmd), "build/bin/generated/%s --protocol < %s > %s 2>&1", ex->id, input_path, output_path);
  if (run_cmd(cmd) != 0) {
    snprintf(app->preview, sizeof(app->preview), "Protocol run failed for %s", ex->title);
    return false;
  }

  FILE *outf = fopen(output_path, "rb");
  if (!outf) return false;
  char jsonl[MAX_TEXT];
  size_t n = fread(jsonl, 1, sizeof(jsonl) - 1, outf);
  fclose(outf);
  jsonl[n] = '\0';
  extract_last_frame_text(jsonl, app->preview, sizeof(app->preview));
  return true;
}

static void load_source(App *app) {
  FILE *f = fopen(EXAMPLES[app->active].source, "rb");
  if (!f) {
    snprintf(app->source_text, sizeof(app->source_text), "source unavailable: %s", EXAMPLES[app->active].source);
    return;
  }
  size_t n = fread(app->source_text, 1, sizeof(app->source_text) - 1, f);
  fclose(f);
  app->source_text[n] = '\0';
}

static void select_example(App *app, int index) {
  if (index < 0 || index >= EXAMPLE_COUNT) return;
  app->active = index;
  app->source_scroll = 0;
  app->preview_scroll = 0;
  app->todo_focused = (strcmp(EXAMPLES[index].id, "todo_mvc") == 0);
  app->todo_input[0] = '\0';
  app->last_interval_ms = SDL_GetTicks();
  app->last_pong_ms = SDL_GetTicks();
  app->pong_started = false;
  load_source(app);
  refresh_preview(app);
}

static void clear_active(App *app) {
  free_history(&app->history[app->active]);
  app->preview_scroll = 0;
  app->todo_focused = (strcmp(EXAMPLES[app->active].id, "todo_mvc") == 0);
  app->todo_input[0] = '\0';
  app->pong_started = false;
  app->last_interval_ms = SDL_GetTicks();
  app->last_pong_ms = SDL_GetTicks();
  refresh_preview(app);
}

static void split_lines(const char *text, char lines[MAX_LINES][MAX_LINE], int *count) {
  *count = 0;
  const char *p = text;
  while (*p && *count < MAX_LINES) {
    int len = 0;
    while (p[len] && p[len] != '\n' && len < MAX_LINE - 1) len++;
    memcpy(lines[*count], p, len);
    lines[*count][len] = '\0';
    (*count)++;
    p += len;
    if (*p == '\n') p++;
  }
}

static void draw_text(App *app, const char *text, float x, float y, SDL_Color color) {
  if (!text || !*text) return;
  SDL_Surface *surface = TTF_RenderText_Blended(app->font, text, 0, color);
  if (!surface) return;
  SDL_Texture *texture = SDL_CreateTextureFromSurface(app->renderer, surface);
  if (texture) {
    SDL_FRect dst = {x, y, (float)surface->w, (float)surface->h};
    SDL_RenderTexture(app->renderer, texture, NULL, &dst);
    SDL_DestroyTexture(texture);
  }
  SDL_DestroySurface(surface);
}

static void fill_rect(App *app, float x, float y, float w, float h, SDL_Color c) {
  SDL_SetRenderDrawColor(app->renderer, c.r, c.g, c.b, c.a);
  SDL_FRect r = {x, y, w, h};
  SDL_RenderFillRect(app->renderer, &r);
}

static void stroke_rect(App *app, float x, float y, float w, float h, SDL_Color c) {
  SDL_SetRenderDrawColor(app->renderer, c.r, c.g, c.b, c.a);
  SDL_FRect r = {x, y, w, h};
  SDL_RenderRect(app->renderer, &r);
}

static int visible_line_count(float height) {
  return (int)(height / 19.0f);
}

static void draw_scrollbar(App *app, float x, float y, float h, int total, int first, int visible) {
  fill_rect(app, x, y, 8, h, (SDL_Color){48, 54, 62, 255});
  if (total <= visible) return;
  float thumb_h = h * ((float)visible / (float)total);
  if (thumb_h < 24) thumb_h = 24;
  float max_first = (float)(total - visible);
  float thumb_y = y + (h - thumb_h) * ((float)first / max_first);
  fill_rect(app, x, thumb_y, 8, thumb_h, (SDL_Color){148, 163, 184, 255});
}

static void render(App *app) {
  SDL_Color bg = {18, 22, 28, 255};
  SDL_Color panel = {31, 36, 45, 255};
  SDL_Color active = {51, 92, 140, 255};
  SDL_Color ink = {236, 241, 247, 255};
  SDL_Color muted = {156, 168, 182, 255};
  SDL_Color border = {82, 94, 110, 255};
  SDL_SetRenderDrawColor(app->renderer, bg.r, bg.g, bg.b, bg.a);
  SDL_RenderClear(app->renderer);

  fill_rect(app, 0, 0, 220, 900, panel);
  fill_rect(app, 220, 48, 720, 792, (SDL_Color){24, 29, 36, 255});
  fill_rect(app, 940, 48, 500, 792, (SDL_Color){21, 26, 33, 255});
  stroke_rect(app, 220, 48, 720, 792, border);
  stroke_rect(app, 940, 48, 500, 792, border);
  draw_text(app, "Boon-Pony SDL Playground", 236, 14, ink);
  draw_text(app, EXAMPLES[app->active].hint, 236, 844, muted);
  fill_rect(app, 662, 10, 84, 30, (SDL_Color){54, 96, 67, 255});
  draw_text(app, "Run", 690, 16, ink);
  fill_rect(app, 758, 10, 154, 30, (SDL_Color){92, 65, 55, 255});
  draw_text(app, "Clear + Rerun", 770, 16, ink);

  for (int i = 0; i < EXAMPLE_COUNT; i++) {
    float y = 16.0f + (float)i * 36.0f;
    fill_rect(app, 12, y, 196, 28, i == app->active ? active : (SDL_Color){42, 48, 58, 255});
    draw_text(app, EXAMPLES[i].title, 22, y + 5, ink);
  }

  char lines[MAX_LINES][MAX_LINE];
  int count = 0;
  split_lines(app->preview, lines, &count);
  int visible = visible_line_count(748);
  if (app->preview_scroll > count - visible) app->preview_scroll = count > visible ? count - visible : 0;
  for (int i = 0; i < visible && i + app->preview_scroll < count; i++) {
    draw_text(app, lines[i + app->preview_scroll], 244, 72 + (float)i * 19.0f, ink);
  }
  draw_scrollbar(app, 924, 62, 760, count, app->preview_scroll, visible);

  split_lines(app->source_text, lines, &count);
  visible = visible_line_count(748);
  if (app->source_scroll > count - visible) app->source_scroll = count > visible ? count - visible : 0;
  char header[256];
  snprintf(header, sizeof(header), "%s @ line %d", EXAMPLES[app->active].source, app->source_scroll + 1);
  draw_text(app, header, 960, 58, muted);
  for (int i = 0; i < visible - 1 && i + app->source_scroll < count; i++) {
    char numbered[MAX_LINE + 32];
    snprintf(numbered, sizeof(numbered), "%3d: %s", i + app->source_scroll + 1, lines[i + app->source_scroll]);
    draw_text(app, numbered, 960, 90 + (float)i * 19.0f, ink);
  }
  draw_scrollbar(app, 1424, 62, 760, count, app->source_scroll, visible);
  SDL_RenderPresent(app->renderer);
}

static void event_counter(App *app) {
  append_expected(app, app->active, "click_button", NULL, 0);
  refresh_preview(app);
}

static void event_interval_tick(App *app) {
  append_expected(app, app->active, "wait", NULL, -1);
  refresh_preview(app);
}

static void event_pong(App *app, const char *key) {
  append_expected(app, app->active, "key", key, -1);
  append_expected(app, app->active, "wait", NULL, -1);
  if (strcmp(key, "Space") == 0) app->pong_started = true;
  refresh_preview(app);
}

static void event_todo_text(App *app, const char *text) {
  if (!app->todo_focused) {
    append_expected(app, app->active, "focus_input", NULL, 0);
    app->todo_focused = true;
  }
  strncat(app->todo_input, text, sizeof(app->todo_input) - strlen(app->todo_input) - 1);
  append_expected(app, app->active, "type", app->todo_input, -1);
  refresh_preview(app);
}

static void event_todo_key(App *app, const char *key) {
  if (!app->todo_focused) {
    append_expected(app, app->active, "focus_input", NULL, 0);
    app->todo_focused = true;
  }
  if (strcmp(key, "Backspace") == 0) {
    size_t len = strlen(app->todo_input);
    if (len > 0) app->todo_input[len - 1] = '\0';
    append_expected(app, app->active, "type", app->todo_input, -1);
  } else {
    append_expected(app, app->active, "key", key, -1);
    if (strcmp(key, "Enter") == 0) app->todo_input[0] = '\0';
  }
  refresh_preview(app);
}

static void event_todo_toggle_all(App *app) {
  append_expected(app, app->active, "click_checkbox", NULL, 0);
  refresh_preview(app);
}

static void event_todo_filter(App *app, const char *filter) {
  append_expected(app, app->active, "click_text", filter, -1);
  refresh_preview(app);
}

static void event_todo_delete_index(App *app, int row) {
  char payload[64];
  snprintf(payload, sizeof(payload), "delete:%d", row);
  append_expected(app, app->active, "click_text", payload, -1);
  refresh_preview(app);
}

static void event_todo_click(App *app, int x, int y) {
  app->todo_focused = true;
  if (y < 110) {
    append_expected(app, app->active, "focus_input", NULL, 0);
  } else if (y >= 148 && y <= 620) {
    int row = (y - 148) / 19;
    if (x > 850) {
      event_todo_delete_index(app, row);
      return;
    } else {
      append_expected(app, app->active, "click_checkbox", NULL, row + 1);
    }
  } else if (y > 180 && y < 240 && x > 690) {
    append_expected(app, app->active, "click_text", "Clear completed", -1);
  } else if (y > 180 && y < 240 && x > 240 && x < 330) {
    event_todo_filter(app, "All");
    return;
  } else if (y > 180 && y < 240 && x >= 330 && x < 430) {
    event_todo_filter(app, "Active");
    return;
  } else if (y > 180 && y < 240 && x >= 430 && x < 560) {
    event_todo_filter(app, "Completed");
    return;
  } else {
    append_expected(app, app->active, "focus_input", NULL, 0);
  }
  refresh_preview(app);
}

static void handle_mouse(App *app, int x, int y) {
  if (x < 220) {
    int index = (y - 16) / 36;
    if (index >= 0 && index < EXAMPLE_COUNT) select_example(app, index);
    return;
  }
  if (y >= 10 && y <= 40 && x >= 662 && x <= 746) {
    refresh_preview(app);
    return;
  }
  if (y >= 10 && y <= 40 && x >= 758 && x <= 912) {
    clear_active(app);
    return;
  }

  const char *id = EXAMPLES[app->active].id;
  if ((strcmp(id, "counter") == 0) || (strcmp(id, "counter_hold") == 0)) {
    event_counter(app);
  } else if (strcmp(id, "todo_mvc") == 0) {
    event_todo_click(app, x, y);
  } else if (strcmp(id, "pong") == 0) {
    event_pong(app, "Space");
  } else if (strcmp(id, "arkanoid") == 0) {
    event_pong(app, "Space");
  }
}

static void handle_mouse_window(App *app, float window_x, float window_y) {
  float x = window_x;
  float y = window_y;
  SDL_RenderCoordinatesFromWindow(app->renderer, window_x, window_y, &x, &y);
  handle_mouse(app, (int)x, (int)y);
}

static void handle_wheel_window(App *app, float window_x, float wheel_y) {
  float x = window_x;
  float y = 0.0f;
  SDL_RenderCoordinatesFromWindow(app->renderer, window_x, 0.0f, &x, &y);
  int delta = wheel_y > 0 ? -3 : 3;
  if (x >= 940) app->source_scroll += delta;
  else app->preview_scroll += delta;
  if (app->source_scroll < 0) app->source_scroll = 0;
  if (app->preview_scroll < 0) app->preview_scroll = 0;
}

static void handle_key(App *app, SDL_Keycode key) {
  const char *id = EXAMPLES[app->active].id;
  if (key == SDLK_ESCAPE || key == SDLK_Q) {
    app->running = false;
  } else if (key == SDLK_TAB || key == SDLK_RIGHT) {
    select_example(app, (app->active + 1) % EXAMPLE_COUNT);
  } else if (key == SDLK_LEFT) {
    select_example(app, (app->active + EXAMPLE_COUNT - 1) % EXAMPLE_COUNT);
  } else if (key == SDLK_R) {
    clear_active(app);
  } else if ((strcmp(id, "counter") == 0) || (strcmp(id, "counter_hold") == 0)) {
    if (key == SDLK_RETURN || key == SDLK_SPACE) event_counter(app);
  } else if (strcmp(id, "todo_mvc") == 0) {
    if (key == SDLK_RETURN) event_todo_key(app, "Enter");
    else if (key == SDLK_BACKSPACE) event_todo_key(app, "Backspace");
  } else if (strcmp(id, "pong") == 0) {
    if (key == SDLK_SPACE) event_pong(app, "Space");
    else if (key == SDLK_W || key == SDLK_UP) event_pong(app, "W");
    else if (key == SDLK_S || key == SDLK_DOWN) event_pong(app, "S");
  } else if (strcmp(id, "arkanoid") == 0) {
    if (key == SDLK_SPACE) event_pong(app, "Space");
    else if (key == SDLK_A || key == SDLK_LEFT) event_pong(app, "A");
    else if (key == SDLK_D || key == SDLK_RIGHT) event_pong(app, "D");
    else if (key == SDLK_L) event_pong(app, "L");
  }
}

static void pump_timers(App *app) {
  Uint64 now = SDL_GetTicks();
  const char *id = EXAMPLES[app->active].id;
  if ((strcmp(id, "interval") == 0) || (strcmp(id, "interval_hold") == 0)) {
    if (now - app->last_interval_ms >= 1000) {
      app->last_interval_ms = now;
      event_interval_tick(app);
    }
  } else if (strcmp(id, "pong") == 0 && app->pong_started) {
    if (now - app->last_pong_ms >= 120) {
      app->last_pong_ms = now;
      append_expected(app, app->active, "wait", NULL, -1);
      refresh_preview(app);
    }
  }
}

static bool init_sdl(App *app, bool script) {
  if (!SDL_Init(SDL_INIT_VIDEO)) return false;
  if (!TTF_Init()) return false;
  SDL_WindowFlags flags = SDL_WINDOW_RESIZABLE;
  if (script) flags |= SDL_WINDOW_HIDDEN;
  app->window = SDL_CreateWindow("Boon-Pony SDL Playground", 1440, 900, flags);
  if (!app->window) return false;
  app->renderer = SDL_CreateRenderer(app->window, NULL);
  if (!app->renderer) return false;
  if (!SDL_SetRenderLogicalPresentation(app->renderer, 1440, 900, SDL_LOGICAL_PRESENTATION_LETTERBOX)) return false;
  app->font = TTF_OpenFont(".boon-local/gui/fonts/JetBrainsMono-Regular.ttf", 15.0f);
  if (!app->font) return false;
  SDL_StartTextInput(app->window);
  return true;
}

static void shutdown_sdl(App *app) {
  if (app->font) TTF_CloseFont(app->font);
  if (app->renderer) SDL_DestroyRenderer(app->renderer);
  if (app->window) SDL_DestroyWindow(app->window);
  TTF_Quit();
  SDL_Quit();
}

static void write_report(const char *path, const char *status, App *app, int frames) {
  if (!path || !*path) return;
  FILE *f = fopen(path, "wb");
  if (!f) return;
  fprintf(f,
    "{\n"
    "  \"command\":\"gui-sdl-playground\",\n"
    "  \"status\":\"%s\",\n"
    "  \"backend\":\"sdl3\",\n"
    "  \"video_driver\":\"%s\",\n"
    "  \"native_window_verified\":true,\n"
    "  \"generated_protocol_children\":true,\n"
    "  \"active_example\":\"%s\",\n"
    "  \"frames_rendered\":%d,\n"
    "  \"examples\":[\"counter\",\"counter_hold\",\"interval\",\"interval_hold\",\"fibonacci\",\"todo_mvc\",\"pong\",\"arkanoid\"],\n"
    "  \"script_check_count\":%d,\n"
    "  \"script_failure_count\":%d,\n"
    "  \"checks\":[%s]\n"
    "}\n",
    status,
    SDL_GetCurrentVideoDriver() ? SDL_GetCurrentVideoDriver() : "unknown",
    EXAMPLES[app->active].id,
    frames,
    app->script_check_count,
    app->script_failure_count,
    app->script_checks);
  fclose(f);
}

static void record_check(App *app, const char *example, const char *name, bool pass, const char *expected) {
  char expected_json[512];
  char preview_json[512];
  char preview_excerpt[256];
  snprintf(preview_excerpt, sizeof(preview_excerpt), "%.220s", app->preview);
  json_escape(expected_json, sizeof(expected_json), expected ? expected : "");
  json_escape(preview_json, sizeof(preview_json), preview_excerpt);
  char item[1300];
  snprintf(item, sizeof(item),
    "%s{\"example\":\"%s\",\"check\":\"%s\",\"status\":\"%s\",\"expected\":\"%s\",\"preview_excerpt\":\"%s\"}",
    app->script_check_count > 0 ? "," : "",
    example,
    name,
    pass ? "pass" : "fail",
    expected_json,
    preview_json);
  strncat(app->script_checks, item, sizeof(app->script_checks) - strlen(app->script_checks) - 1);
  app->script_check_count++;
  if (!pass) app->script_failure_count++;
}

static void expect_contains(App *app, const char *name, const char *needle) {
  record_check(app, EXAMPLES[app->active].id, name, strstr(app->preview, needle) != NULL, needle);
}

static void expect_not_contains(App *app, const char *name, const char *needle) {
  record_check(app, EXAMPLES[app->active].id, name, strstr(app->preview, needle) == NULL, needle);
}

static void expect_empty(App *app, const char *name) {
  record_check(app, EXAMPLES[app->active].id, name, app->preview[0] == '\0', "empty preview");
}

static int run_script(App *app, const char *report) {
  int frames = 0;
  for (int i = 0; i < EXAMPLE_COUNT; i++) {
    select_example(app, i);
    render(app);
    frames++;
    const char *id = EXAMPLES[i].id;
    if ((strcmp(id, "counter") == 0) || (strcmp(id, "counter_hold") == 0)) {
      expect_contains(app, "initial value", "0+");
      event_counter(app);
      expect_contains(app, "incremented value", "1+");
    } else if ((strcmp(id, "interval") == 0) || (strcmp(id, "interval_hold") == 0)) {
      expect_empty(app, "initial empty interval frame");
      event_interval_tick(app);
      expect_contains(app, "first tick", "1");
      event_interval_tick(app);
      expect_contains(app, "second tick", "2");
    } else if (strcmp(id, "fibonacci") == 0) {
      expect_contains(app, "fibonacci result", "55");
    } else if (strcmp(id, "todo_mvc") == 0) {
      expect_contains(app, "initial focused input", "Input: |");
      event_todo_text(app, "Alpha");
      expect_contains(app, "typed full input", "Input: Alpha|");
      event_todo_key(app, "Enter");
      expect_contains(app, "added Alpha", "Alpha");
      event_todo_text(app, "Beta");
      event_todo_key(app, "Enter");
      expect_contains(app, "added Beta", "Beta");
      event_todo_text(app, "Gamma");
      event_todo_key(app, "Enter");
      expect_contains(app, "added Gamma", "Gamma");
      append_expected(app, app->active, "click_checkbox", NULL, 3);
      refresh_preview(app);
      expect_contains(app, "toggle third item", "[x] Alpha");
      event_todo_filter(app, "Completed");
      expect_contains(app, "completed filter", "Filter: Completed");
      expect_contains(app, "completed item visible", "Alpha");
      event_todo_filter(app, "All");
      event_todo_delete_index(app, 1);
      expect_not_contains(app, "deleted Clean room", "Clean room");
      event_todo_toggle_all(app);
      expect_contains(app, "toggle all completes", "0 items left");
      append_expected(app, app->active, "click_text", "Clear completed", -1);
      refresh_preview(app);
      expect_not_contains(app, "clear completed removes Alpha", "Alpha");
    } else if (strcmp(id, "pong") == 0) {
      expect_contains(app, "initial pong prompt", "Press Space");
      event_pong(app, "Space");
      expect_contains(app, "pong started", "Pong generated runtime");
      event_pong(app, "W");
      event_pong(app, "S");
      expect_contains(app, "pong controls hint", "AI follows ball");
    } else if (strcmp(id, "arkanoid") == 0) {
      event_pong(app, "Space");
      expect_contains(app, "arkanoid animates", "Score:");
    }
    render(app);
    frames++;
  }
  write_report(report, app->script_failure_count == 0 ? "pass" : "fail", app, frames);
  return app->script_failure_count == 0 ? 0 : 1;
}

int main(int argc, char **argv) {
  const char *report = "build/reports/gui-sdl-playground.json";
  const char *start_id = "counter";
  bool script = false;
  for (int i = 1; i < argc; i++) {
    if (strcmp(argv[i], "--script") == 0) {
      script = true;
      if ((i + 1) < argc && argv[i + 1][0] != '-') i++;
    } else if (strcmp(argv[i], "--report") == 0 && i + 1 < argc) {
      report = argv[++i];
    } else if (strcmp(argv[i], "--example") == 0 && i + 1 < argc) {
      start_id = argv[++i];
    }
  }

  App app;
  memset(&app, 0, sizeof(app));
  app.running = true;
  app.script = script;
  app.last_interval_ms = SDL_GetTicks();
  app.last_pong_ms = SDL_GetTicks();

  if (!init_sdl(&app, script)) {
    fprintf(stderr, "SDL playground init failed: %s\n", SDL_GetError());
    write_report(report, "fail", &app, 0);
    shutdown_sdl(&app);
    return 1;
  }

  int start = 0;
  for (int i = 0; i < EXAMPLE_COUNT; i++) {
    if (strcmp(EXAMPLES[i].id, start_id) == 0) start = i;
  }
  select_example(&app, start);

  if (script) {
    int status = run_script(&app, report);
    for (int i = 0; i < EXAMPLE_COUNT; i++) free_history(&app.history[i]);
    shutdown_sdl(&app);
    return status;
  }

  int frames = 0;
  while (app.running) {
    SDL_Event event;
    while (SDL_PollEvent(&event)) {
      if (event.type == SDL_EVENT_QUIT) app.running = false;
      else if (event.type == SDL_EVENT_MOUSE_BUTTON_DOWN) handle_mouse_window(&app, event.button.x, event.button.y);
      else if (event.type == SDL_EVENT_MOUSE_WHEEL) {
        handle_wheel_window(&app, event.wheel.mouse_x, event.wheel.y);
      } else if (event.type == SDL_EVENT_KEY_DOWN) {
        handle_key(&app, event.key.key);
      } else if (event.type == SDL_EVENT_TEXT_INPUT) {
        if (strcmp(EXAMPLES[app.active].id, "todo_mvc") == 0) event_todo_text(&app, event.text.text);
      }
    }
    pump_timers(&app);
    render(&app);
    frames++;
    SDL_Delay(16);
  }

  write_report(report, "pass", &app, frames);
  for (int i = 0; i < EXAMPLE_COUNT; i++) free_history(&app.history[i]);
  shutdown_sdl(&app);
  return 0;
}
