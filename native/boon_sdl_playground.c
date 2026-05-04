#include <SDL3/SDL.h>
#include <SDL3/SDL_keyboard.h>
#include <SDL3_ttf/SDL_ttf.h>

#include <ctype.h>
#include <errno.h>
#include <fcntl.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <signal.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

#define MAX_HISTORY 512
#define MAX_TEXT 65536
#define MAX_LINES 512
#define MAX_LINE 512
#define MAX_TODO_ITEMS 256

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
  bool active;
  int example;
  pid_t pid;
  int in_fd;
  int out_fd;
  char output[MAX_TEXT];
} ProtocolSession;

typedef struct {
  bool initialized;
  int target_x;
  int target_y;
  int target_left_y;
  int target_right_y;
  int target_paddle_x;
  float from_x;
  float from_y;
  float x;
  float y;
  float left_y;
  float right_y;
  float paddle_x;
  Uint64 changed_ms;
} GameVisual;

typedef struct {
  SDL_Window *window;
  SDL_Renderer *renderer;
  SDL_Texture *source_cache;
  TTF_Font *font;
  TTF_Font *font_todo_title;
  TTF_Font *font_todo_input;
  TTF_Font *font_todo_item;
  TTF_Font *font_todo_footer;
  int active;
  int source_scroll;
  int source_x_scroll;
  int preview_scroll;
  int width;
  int height;
  int source_cache_w;
  int source_cache_h;
  int source_cache_active;
  int source_cache_scroll;
  int source_cache_x_scroll;
  bool running;
  bool script;
  bool todo_focused;
  bool pong_started;
  bool game_refresh_pending;
  bool dirty;
  Uint64 last_interval_ms;
  Uint64 last_pong_ms;
  Uint64 last_render_ms;
  char todo_input[MAX_LINE];
  char preview[MAX_TEXT];
  char source_text[MAX_TEXT];
  char script_checks[MAX_TEXT];
  int script_check_count;
  int script_failure_count;
  int live_sent_len[EXAMPLE_COUNT];
  ProtocolSession session;
  GameVisual pong_visual;
  GameVisual arkanoid_visual;
  History history[EXAMPLE_COUNT];
} App;

typedef struct {
  bool completed;
  bool editing;
  char title[MAX_LINE];
} TodoItem;

typedef struct {
  char input[MAX_LINE];
  int active_count;
  char filter[32];
  bool input_focused;
  TodoItem items[MAX_TODO_ITEMS];
  int item_count;
} TodoModel;

typedef struct {
  float preview_x;
  float preview_y;
  float preview_w;
  float preview_h;
  float card_x;
  float card_y;
  float card_w;
  float input_y;
  float input_h;
  float list_y;
  float row_h;
  float footer_y;
  float footer_h;
  int visible_items;
} TodoLayout;

typedef struct {
  float left_w;
  float top_h;
  float footer_h;
  float preview_x;
  float preview_y;
  float preview_w;
  float preview_h;
  float source_x;
  float source_y;
  float source_w;
  float source_h;
  float status_y;
} AppLayout;

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

static bool file_newer_than(const char *path, const char *dependency) {
  struct stat path_stat;
  struct stat dependency_stat;
  if (stat(path, &path_stat) != 0) return false;
  if (stat(dependency, &dependency_stat) != 0) return true;
  return path_stat.st_mtime >= dependency_stat.st_mtime;
}

static TTF_Font *open_todo_font(float size) {
  const char *paths[] = {
    "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
    "/usr/share/fonts/opentype/urw-base35/NimbusSans-Regular.otf",
    ".boon-local/gui/fonts/JetBrainsMono-Regular.ttf",
  };
  for (size_t i = 0; i < sizeof(paths) / sizeof(paths[0]); i++) {
    TTF_Font *font = TTF_OpenFont(paths[i], size);
    if (font) return font;
  }
  return NULL;
}

static int run_cmd(const char *cmd) {
  int status = system(cmd);
  if (status == -1) return 1;
  return status == 0 ? 0 : 1;
}

static void update_render_size(App *app) {
  int w = 1440;
  int h = 900;
  SDL_GetCurrentRenderOutputSize(app->renderer, &w, &h);
  if (w < 1000) w = 1000;
  if (h < 700) h = 700;
  app->width = w;
  app->height = h;
}

static AppLayout app_layout(App *app) {
  AppLayout l;
  l.left_w = 220.0f;
  l.top_h = 48.0f;
  l.footer_h = 60.0f;
  float content_w = (float)app->width - l.left_w;
  if (content_w < 800.0f) content_w = 800.0f;
  l.source_w = content_w * 0.36f;
  if (l.source_w < 380.0f) l.source_w = 380.0f;
  if (l.source_w > 760.0f) l.source_w = 760.0f;
  l.preview_w = content_w - l.source_w;
  if (l.preview_w < 520.0f) {
    l.preview_w = 520.0f;
    l.source_w = content_w - l.preview_w;
  }
  l.preview_x = l.left_w;
  l.preview_y = l.top_h;
  l.preview_h = (float)app->height - l.top_h - l.footer_h;
  if (l.preview_h < 560.0f) l.preview_h = 560.0f;
  l.source_x = l.preview_x + l.preview_w;
  l.source_y = l.top_h;
  l.source_h = l.preview_h;
  l.status_y = (float)app->height - l.footer_h + 8.0f;
  return l;
}

static bool ensure_generated(const Example *ex) {
  char binary[256];
  snprintf(binary, sizeof(binary), "build/bin/generated/%s", ex->id);
  if (file_exists(binary) && file_newer_than(binary, "build/bin/boonpony") && file_newer_than(binary, ex->source)) return true;
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

static void append_bounded(char *dst, size_t dst_size, const char *src) {
  if (dst_size == 0) return;
  size_t used = strlen(dst);
  if (used >= dst_size - 1) return;
  size_t avail = dst_size - used - 1;
  size_t len = strlen(src);
  if (len > avail) len = avail;
  memcpy(dst + used, src, len);
  dst[used + len] = '\0';
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
    if (out[0] != '\0') append_bounded(out, out_size, "\n");
    append_bounded(out, out_size, chunk);
    p = end;
    if (*p == '\n') break;
  }
}

static bool has_protocol_frame(const char *jsonl) {
  return strstr(jsonl, "\"type\":\"frame\"") != NULL;
}

static bool write_all_fd(int fd, const char *text, size_t len) {
  size_t sent = 0;
  while (sent < len) {
    ssize_t n = write(fd, text + sent, len - sent);
    if (n < 0) return false;
    if (n == 0) return false;
    sent += (size_t)n;
  }
  return true;
}

static void protocol_session_close(App *app) {
  ProtocolSession *s = &app->session;
  if (!s->active) return;
  if (s->in_fd >= 0) {
    const char *quit = "{\"protocol_version\":1,\"type\":\"quit\"}\n";
    (void)write_all_fd(s->in_fd, quit, strlen(quit));
    close(s->in_fd);
  }
  if (s->out_fd >= 0) close(s->out_fd);
  if (s->pid > 0) {
    int status = 0;
    for (int i = 0; i < 8; i++) {
      pid_t got = waitpid(s->pid, &status, WNOHANG);
      if (got == s->pid) break;
      usleep(1000);
    }
    if (waitpid(s->pid, &status, WNOHANG) == 0) {
      kill(s->pid, SIGTERM);
      (void)waitpid(s->pid, &status, 0);
    }
  }
  memset(s, 0, sizeof(*s));
  s->pid = -1;
  s->in_fd = -1;
  s->out_fd = -1;
}

static bool protocol_session_start(App *app) {
  const Example *ex = &EXAMPLES[app->active];
  ProtocolSession *s = &app->session;
  if (s->active && s->example == app->active) return true;
  protocol_session_close(app);
  if (!ensure_generated(ex)) return false;

  int child_in[2];
  int child_out[2];
  if (pipe(child_in) != 0) return false;
  if (pipe(child_out) != 0) {
    close(child_in[0]);
    close(child_in[1]);
    return false;
  }

  pid_t pid = fork();
  if (pid == 0) {
    dup2(child_in[0], STDIN_FILENO);
    dup2(child_out[1], STDOUT_FILENO);
    dup2(child_out[1], STDERR_FILENO);
    close(child_in[0]);
    close(child_in[1]);
    close(child_out[0]);
    close(child_out[1]);
    char binary[256];
    snprintf(binary, sizeof(binary), "build/bin/generated/%s", ex->id);
    execl(binary, binary, "--protocol", (char *)NULL);
    _exit(127);
  }

  close(child_in[0]);
  close(child_out[1]);
  if (pid < 0) {
    close(child_in[1]);
    close(child_out[0]);
    return false;
  }

  int flags = fcntl(child_out[0], F_GETFL, 0);
  if (flags >= 0) fcntl(child_out[0], F_SETFL, flags | O_NONBLOCK);

  memset(s, 0, sizeof(*s));
  s->active = true;
  s->example = app->active;
  s->pid = pid;
  s->in_fd = child_in[1];
  s->out_fd = child_out[0];
  s->output[0] = '\0';
  return true;
}

static void protocol_session_send(ProtocolSession *s, const char *line) {
  if (!s->active || s->in_fd < 0) return;
  size_t len = strlen(line);
  (void)write_all_fd(s->in_fd, line, len);
  if (len == 0 || line[len - 1] != '\n') (void)write_all_fd(s->in_fd, "\n", 1);
}

static void protocol_session_drain(ProtocolSession *s, Uint64 timeout_ms) {
  if (!s->active || s->out_fd < 0) return;
  Uint64 start = SDL_GetTicks();
  char buf[4096];
  while (true) {
    ssize_t n = read(s->out_fd, buf, sizeof(buf) - 1);
    if (n > 0) {
      buf[n] = '\0';
      size_t used = strlen(s->output);
      if (used + (size_t)n + 1 >= sizeof(s->output)) {
        size_t keep = sizeof(s->output) / 2;
        memmove(s->output, s->output + used - keep, keep + 1);
      }
      append_bounded(s->output, sizeof(s->output), buf);
      continue;
    }
    if (n == 0) {
      s->active = false;
      return;
    }
    if (errno != EAGAIN && errno != EWOULDBLOCK) return;
    if (SDL_GetTicks() - start >= timeout_ms) return;
    usleep(1000);
  }
}

static bool refresh_preview_live(App *app) {
  if (!protocol_session_start(app)) {
    snprintf(app->preview, sizeof(app->preview), "Build failed for %s", EXAMPLES[app->active].title);
    return false;
  }

  ProtocolSession *s = &app->session;
  protocol_session_drain(s, 2);
  History *h = &app->history[app->active];
  if (app->live_sent_len[app->active] > h->len) app->live_sent_len[app->active] = 0;
  for (int i = app->live_sent_len[app->active]; i < h->len; i++) {
    protocol_session_send(s, h->items[i]);
  }
  app->live_sent_len[app->active] = h->len;
  protocol_session_send(s, "{\"protocol_version\":1,\"type\":\"frame\"}");
  protocol_session_drain(s, 3);
  if (!has_protocol_frame(s->output)) protocol_session_drain(s, 250);
  extract_last_frame_text(s->output, app->preview, sizeof(app->preview));
  return true;
}

static bool refresh_preview_replay(App *app) {
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

static bool refresh_preview(App *app) {
  bool ok = !app->script ? refresh_preview_live(app) : refresh_preview_replay(app);
  app->dirty = true;
  return ok;
}

static void invalidate_source_cache(App *app) {
  if (app->source_cache) {
    SDL_DestroyTexture(app->source_cache);
    app->source_cache = NULL;
  }
  app->source_cache_w = 0;
  app->source_cache_h = 0;
  app->source_cache_active = -1;
  app->source_cache_scroll = -1;
  app->source_cache_x_scroll = -1;
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
  invalidate_source_cache(app);
}

static void select_example(App *app, int index) {
  if (index < 0 || index >= EXAMPLE_COUNT) return;
  if (app->active != index) protocol_session_close(app);
  app->active = index;
  app->source_scroll = 0;
  app->source_x_scroll = 0;
  app->preview_scroll = 0;
  app->todo_focused = (strcmp(EXAMPLES[index].id, "todo_mvc") == 0);
  app->todo_input[0] = '\0';
  app->last_interval_ms = SDL_GetTicks();
  app->last_pong_ms = SDL_GetTicks();
  app->pong_started = false;
  app->game_refresh_pending = false;
  app->dirty = true;
  load_source(app);
  refresh_preview(app);
}

static void clear_active(App *app) {
  protocol_session_close(app);
  free_history(&app->history[app->active]);
  app->live_sent_len[app->active] = 0;
  app->preview_scroll = 0;
  app->source_x_scroll = 0;
  app->todo_focused = (strcmp(EXAMPLES[app->active].id, "todo_mvc") == 0);
  app->todo_input[0] = '\0';
  app->pong_started = false;
  app->game_refresh_pending = false;
  app->dirty = true;
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

static int text_width(TTF_Font *font, const char *text) {
  int w = 0;
  int h = 0;
  if (!font || !text) return 0;
  TTF_GetStringSize(font, text, 0, &w, &h);
  return w;
}

static void draw_text_with_font(App *app, TTF_Font *font, const char *text, float x, float y, SDL_Color color) {
  if (!text || !*text) return;
  SDL_Surface *surface = TTF_RenderText_Blended(font ? font : app->font, text, 0, color);
  if (!surface) return;
  SDL_Texture *texture = SDL_CreateTextureFromSurface(app->renderer, surface);
  if (texture) {
    SDL_FRect dst = {x, y, (float)surface->w, (float)surface->h};
    SDL_RenderTexture(app->renderer, texture, NULL, &dst);
    SDL_DestroyTexture(texture);
  }
  SDL_DestroySurface(surface);
}

static void draw_text(App *app, const char *text, float x, float y, SDL_Color color) {
  draw_text_with_font(app, app->font, text, x, y, color);
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

static void draw_line(App *app, float x1, float y1, float x2, float y2, SDL_Color c) {
  SDL_SetRenderDrawColor(app->renderer, c.r, c.g, c.b, c.a);
  SDL_RenderLine(app->renderer, x1, y1, x2, y2);
}

static void fill_circle(App *app, float cx, float cy, float radius, SDL_Color c) {
  SDL_SetRenderDrawColor(app->renderer, c.r, c.g, c.b, c.a);
  int r = (int)(radius + 0.5f);
  for (int dy = -r; dy <= r; dy++) {
    float fy = (float)dy;
    float dx = SDL_sqrtf((radius * radius) - (fy * fy));
    SDL_RenderLine(app->renderer, cx - dx, cy + fy, cx + dx, cy + fy);
  }
}

static void draw_checkmark(App *app, float x, float y, SDL_Color c) {
  draw_line(app, x, y + 8, x + 8, y + 17, c);
  draw_line(app, x + 8, y + 17, x + 22, y - 6, c);
}

static void draw_todo_checkbox(App *app, float cx, float cy, bool checked, SDL_Color ring, SDL_Color fill, SDL_Color mark) {
  fill_circle(app, cx, cy, 17.5f, ring);
  fill_circle(app, cx, cy, 14.0f, fill);
  if (checked) draw_checkmark(app, cx - 10.5f, cy - 4.5f, mark);
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

static void trim_right(char *s) {
  size_t len = strlen(s);
  while (len > 0 && isspace((unsigned char)s[len - 1])) s[--len] = '\0';
}

static void copy_bounded(char *dst, size_t dst_size, const char *src) {
  if (dst_size == 0) return;
  size_t len = strlen(src);
  if (len >= dst_size) len = dst_size - 1;
  memcpy(dst, src, len);
  dst[len] = '\0';
}

static void set_preview_input_echo(App *app) {
  if (strcmp(EXAMPLES[app->active].id, "todo_mvc") != 0) return;
  char lines[MAX_LINES][MAX_LINE];
  int count = 0;
  split_lines(app->preview, lines, &count);
  if (count <= 0) return;
  char next[MAX_TEXT];
  next[0] = '\0';
  for (int i = 0; i < count; i++) {
    if (i > 0) append_bounded(next, sizeof(next), "\n");
    if (strncmp(lines[i], "Input: ", 7) == 0) {
      append_bounded(next, sizeof(next), "Input: ");
      append_bounded(next, sizeof(next), app->todo_input);
      append_bounded(next, sizeof(next), "|");
    } else {
      append_bounded(next, sizeof(next), lines[i]);
    }
  }
  snprintf(app->preview, sizeof(app->preview), "%s", next);
}

static void remove_cursor_marker(char *s) {
  char *cursor = strchr(s, '|');
  if (cursor) memmove(cursor, cursor + 1, strlen(cursor));
}

static bool parse_todo_item_line(const char *line, TodoItem *item) {
  bool completed = false;
  bool editing = false;
  const char *title = NULL;
  if (strncmp(line, "[ ] ", 4) == 0) {
    title = line + 4;
  } else if (strncmp(line, "[x] ", 4) == 0) {
    completed = true;
    title = line + 4;
  } else if (strncmp(line, "[edit] ", 7) == 0) {
    editing = true;
    title = line + 7;
  } else {
    return false;
  }

  const char *del = strstr(title, "[del]");
  size_t len = del ? (size_t)(del - title) : strlen(title);
  if (len >= sizeof(item->title)) len = sizeof(item->title) - 1;
  memcpy(item->title, title, len);
  item->title[len] = '\0';
  trim_right(item->title);
  remove_cursor_marker(item->title);
  item->completed = completed;
  item->editing = editing;
  return true;
}

static void parse_todo_model(const char *preview, TodoModel *model) {
  memset(model, 0, sizeof(*model));
  strcpy(model->filter, "All");
  char lines[MAX_LINES][MAX_LINE];
  int count = 0;
  split_lines(preview, lines, &count);
  for (int i = 0; i < count; i++) {
    const char *line = lines[i];
    if (strncmp(line, "Input: ", 7) == 0) {
      snprintf(model->input, sizeof(model->input), "%s", line + 7);
      model->input_focused = strchr(model->input, '|') != NULL;
      remove_cursor_marker(model->input);
    } else if (strstr(line, " items left") || strstr(line, " item left")) {
      model->active_count = atoi(line);
    } else if (strncmp(line, "Filter: ", 8) == 0) {
      snprintf(model->filter, sizeof(model->filter), "%s", line + 8);
    } else if (model->item_count < MAX_TODO_ITEMS) {
      TodoItem item;
      if (parse_todo_item_line(line, &item)) {
        model->items[model->item_count++] = item;
      }
    }
  }
}

static TodoLayout todo_layout_for_count(App *app, int item_count) {
  AppLayout app_l = app_layout(app);
  TodoLayout l;
  l.preview_x = app_l.preview_x + 4.0f;
  l.preview_y = app_l.preview_y + 4.0f;
  l.preview_w = app_l.preview_w - 8.0f;
  l.preview_h = app_l.preview_h - 8.0f;
  l.card_w = l.preview_w - 52.0f;
  if (l.card_w > 860.0f) l.card_w = 860.0f;
  if (l.card_w > l.preview_w - 16.0f) l.card_w = l.preview_w - 16.0f;
  if (l.card_w < 360.0f) l.card_w = l.preview_w - 16.0f;
  if (l.card_w < 280.0f) l.card_w = 280.0f;
  l.card_x = l.preview_x + (l.preview_w - l.card_w) / 2.0f;
  l.card_y = l.preview_y + 126.0f;
  l.input_y = l.card_y;
  l.input_h = 68.0f;
  l.row_h = 58.0f;
  l.visible_items = item_count;
  int max_visible = (int)((l.preview_h - 280.0f) / l.row_h);
  if (max_visible < 3) max_visible = 3;
  if (max_visible > 10) max_visible = 10;
  if (l.visible_items > max_visible) l.visible_items = max_visible;
  if (l.visible_items < 0) l.visible_items = 0;
  l.list_y = l.input_y + l.input_h;
  l.footer_h = 42.0f;
  l.footer_y = l.list_y + (l.row_h * (float)l.visible_items);
  return l;
}

static void push_clip(App *app, float x, float y, float w, float h, SDL_Rect *old_clip, bool *old_enabled) {
  *old_enabled = SDL_RenderClipEnabled(app->renderer);
  if (*old_enabled) SDL_GetRenderClipRect(app->renderer, old_clip);
  SDL_Rect clip = {(int)x, (int)y, (int)w, (int)h};
  SDL_SetRenderClipRect(app->renderer, &clip);
}

static void pop_clip(App *app, SDL_Rect *old_clip, bool old_enabled) {
  SDL_SetRenderClipRect(app->renderer, old_enabled ? old_clip : NULL);
}

static void render_todo_mvc(App *app) {
  TodoModel model;
  parse_todo_model(app->preview, &model);
  TodoLayout l = todo_layout_for_count(app, model.item_count);
  SDL_Color bg = {245, 245, 245, 255};
  SDL_Color white = {254, 254, 254, 255};
  SDL_Color line = {230, 230, 230, 255};
  SDL_Color title = {184, 63, 69, 255};
  SDL_Color ink = {72, 72, 72, 255};
  SDL_Color muted = {150, 150, 150, 255};
  SDL_Color green = {77, 170, 150, 255};
  SDL_Color red = {176, 76, 76, 255};

  fill_rect(app, l.preview_x, l.preview_y, l.preview_w, l.preview_h, bg);
  SDL_Rect old_clip;
  bool old_clip_enabled = false;
  push_clip(app, l.preview_x, l.preview_y, l.preview_w, l.preview_h, &old_clip, &old_clip_enabled);

  const char *todos = "todos";
  int title_w = text_width(app->font_todo_title, todos);
  draw_text_with_font(app, app->font_todo_title, todos, l.preview_x + (l.preview_w - (float)title_w) / 2.0f, 78.0f, title);

  fill_rect(app, l.card_x + 8, l.footer_y + l.footer_h + 8, l.card_w - 16, 6, (SDL_Color){210, 210, 210, 190});
  fill_rect(app, l.card_x + 4, l.footer_y + l.footer_h + 4, l.card_w - 8, 6, (SDL_Color){225, 225, 225, 220});
  fill_rect(app, l.card_x, l.input_y, l.card_w, l.footer_y + l.footer_h - l.input_y, white);
  stroke_rect(app, l.card_x, l.input_y, l.card_w, l.footer_y + l.footer_h - l.input_y, (SDL_Color){210, 210, 210, 255});

  draw_line(app, l.card_x, l.input_y + l.input_h, l.card_x + l.card_w, l.input_y + l.input_h, line);
  draw_line(app, l.card_x + 25, l.input_y + 30, l.card_x + 41, l.input_y + 42, muted);
  draw_line(app, l.card_x + 41, l.input_y + 42, l.card_x + 57, l.input_y + 30, muted);

  char input_text[MAX_LINE];
  if (model.input[0]) snprintf(input_text, sizeof(input_text), "%s", model.input);
  else snprintf(input_text, sizeof(input_text), "What needs to be done?");
  SDL_Color input_color = model.input[0] ? ink : (SDL_Color){150, 150, 150, 255};
  draw_text_with_font(app, app->font_todo_input, input_text, l.card_x + 72, l.input_y + 19, input_color);
  bool blink = ((SDL_GetTicks() / 500) % 2) == 0;
  if (model.input_focused && blink) {
    float cx = l.card_x + 72.0f + (float)(model.input[0] ? text_width(app->font_todo_input, model.input) : 0);
    draw_line(app, cx, l.input_y + 18, cx, l.input_y + 51, (SDL_Color){80, 80, 80, 255});
  }

  if (app->preview_scroll > model.item_count - l.visible_items) {
    app->preview_scroll = model.item_count > l.visible_items ? model.item_count - l.visible_items : 0;
  }
  if (app->preview_scroll < 0) app->preview_scroll = 0;

  for (int visible = 0; visible < l.visible_items; visible++) {
    int index = app->preview_scroll + visible;
    float y = l.list_y + (float)visible * l.row_h;
    if (index >= model.item_count) break;
    TodoItem *item = &model.items[index];
    draw_line(app, l.card_x, y + l.row_h, l.card_x + l.card_w, y + l.row_h, line);
    draw_todo_checkbox(app, l.card_x + 36, y + 29, item->completed, item->completed ? green : muted, white, green);
    if (item->editing) {
      fill_rect(app, l.card_x + 76, y + 8, l.card_w - 150, l.row_h - 16, (SDL_Color){255, 255, 255, 255});
      stroke_rect(app, l.card_x + 76, y + 8, l.card_w - 150, l.row_h - 16, (SDL_Color){180, 180, 180, 255});
    }
    SDL_Color item_color = item->completed ? muted : ink;
    draw_text_with_font(app, app->font_todo_item, item->title, l.card_x + 76, y + 16, item_color);
    if (item->completed) {
      float tw = (float)text_width(app->font_todo_item, item->title);
      draw_line(app, l.card_x + 76, y + 31, l.card_x + 76 + tw, y + 31, muted);
    }
    draw_text_with_font(app, app->font_todo_item, "x", l.card_x + l.card_w - 42, y + 16, red);
  }

  draw_line(app, l.card_x, l.footer_y, l.card_x + l.card_w, l.footer_y, line);
  char count_text[64];
  snprintf(count_text, sizeof(count_text), "%d item%s left", model.active_count, model.active_count == 1 ? "" : "s");
  draw_text_with_font(app, app->font_todo_footer, count_text, l.card_x + 18, l.footer_y + 12, ink);

  const char *filters[] = {"All", "Active", "Completed"};
  const char *clear_label = l.card_w < 650.0f ? "Clear" : "Clear completed";
  float filter_total_w = 248.0f;
  float clear_w = (float)text_width(app->font_todo_footer, clear_label);
  float clear_x = l.card_x + l.card_w - clear_w - 18.0f;
  float filter_x = l.card_x + (l.card_w - filter_total_w) * 0.52f;
  float min_filter_x = l.card_x + 132.0f;
  if (filter_x < min_filter_x) filter_x = min_filter_x;
  if ((filter_x + filter_total_w) > (clear_x - 10.0f)) filter_x = clear_x - filter_total_w - 10.0f;
  bool footer_overflows = filter_x < min_filter_x;
  if (footer_overflows) filter_x = min_filter_x;
  float fx[] = {filter_x, filter_x + 74.0f, filter_x + 174.0f};
  float fw[] = {42, 68, 104};
  for (int i = 0; i < 3; i++) {
    if (strcmp(model.filter, filters[i]) == 0) stroke_rect(app, fx[i] - 8, l.footer_y + 7, fw[i], 28, red);
    draw_text_with_font(app, app->font_todo_footer, filters[i], fx[i], l.footer_y + 12, ink);
  }
  draw_text_with_font(app, app->font_todo_footer, clear_label, clear_x, l.footer_y + 12, ink);
  if (footer_overflows) {
    fill_rect(app, l.card_x + 18, l.footer_y + l.footer_h - 9, l.card_w - 36, 5, (SDL_Color){226, 226, 226, 255});
    fill_rect(app, l.card_x + 18, l.footer_y + l.footer_h - 9, (l.card_w - 36) * 0.64f, 5, (SDL_Color){150, 150, 150, 255});
  }

  if (model.item_count > l.visible_items) {
    draw_scrollbar(app, l.card_x + l.card_w - 10, l.list_y + 4, l.row_h * (float)l.visible_items - 8, model.item_count, app->preview_scroll, l.visible_items);
  }

  const char *hint1 = "Double-click to edit a todo";
  const char *hint2 = "Created by Martin Kavik";
  const char *hint3 = "Part of TodoMVC";
  draw_text_with_font(app, app->font_todo_footer, hint1, l.card_x + (l.card_w - (float)text_width(app->font_todo_footer, hint1)) / 2.0f, l.footer_y + l.footer_h + 50, ink);
  draw_text_with_font(app, app->font_todo_footer, hint2, l.card_x + (l.card_w - (float)text_width(app->font_todo_footer, hint2)) / 2.0f, l.footer_y + l.footer_h + 84, ink);
  draw_text_with_font(app, app->font_todo_footer, hint3, l.card_x + (l.card_w - (float)text_width(app->font_todo_footer, hint3)) / 2.0f, l.footer_y + l.footer_h + 118, ink);
  pop_clip(app, &old_clip, old_clip_enabled);
}

static bool parse_game_cell(App *app, char wanted, int *out_x, int *out_y, int *left_y, int *right_y) {
  char lines[MAX_LINES][MAX_LINE];
  int count = 0;
  split_lines(app->preview, lines, &count);
  int board_y = 0;
  bool found = false;
  if (left_y) *left_y = -1;
  if (right_y) *right_y = -1;
  for (int i = 0; i < count; i++) {
    char *line = lines[i];
    if (line[0] != '|') continue;
    int len = (int)strlen(line);
    for (int x = 1; x < len - 1; x++) {
      char ch = line[x];
      if ((ch == wanted) && !found) {
        *out_x = x - 1;
        *out_y = board_y;
        found = true;
      }
      if ((ch == '#') && left_y && (x <= 3) && (*left_y < 0)) *left_y = board_y;
      if ((ch == '#') && right_y && (x >= len - 4) && (*right_y < 0)) *right_y = board_y;
    }
    board_y++;
  }
  return found;
}

static float smooth_step(float t) {
  if (t < 0.0f) t = 0.0f;
  if (t > 1.0f) t = 1.0f;
  return t * t * (3.0f - (2.0f * t));
}

static float visual_interp(float from, float to, Uint64 changed_ms, Uint64 duration_ms) {
  if (duration_ms == 0) return to;
  float t = (float)(SDL_GetTicks() - changed_ms) / (float)duration_ms;
  return from + ((to - from) * smooth_step(t));
}

static void update_ball_visual(GameVisual *v, int bx, int by, int left_y, int right_y, int paddle_x, Uint64 duration_ms) {
  Uint64 now = SDL_GetTicks();
  if (!v->initialized) {
    v->initialized = true;
    v->target_x = bx;
    v->target_y = by;
    v->target_left_y = left_y;
    v->target_right_y = right_y;
    v->target_paddle_x = paddle_x;
    v->from_x = (float)bx;
    v->from_y = (float)by;
    v->x = (float)bx;
    v->y = (float)by;
    v->left_y = (float)left_y;
    v->right_y = (float)right_y;
    v->paddle_x = (float)paddle_x;
    v->changed_ms = now;
    return;
  }

  v->x = visual_interp(v->from_x, (float)v->target_x, v->changed_ms, duration_ms);
  v->y = visual_interp(v->from_y, (float)v->target_y, v->changed_ms, duration_ms);
  if ((bx != v->target_x) || (by != v->target_y)) {
    v->from_x = v->x;
    v->from_y = v->y;
    v->target_x = bx;
    v->target_y = by;
    v->changed_ms = now;
  }
  v->x = visual_interp(v->from_x, (float)v->target_x, v->changed_ms, duration_ms);
  v->y = visual_interp(v->from_y, (float)v->target_y, v->changed_ms, duration_ms);
  v->left_y += ((float)left_y - v->left_y) * 0.35f;
  v->right_y += ((float)right_y - v->right_y) * 0.35f;
  v->paddle_x += ((float)paddle_x - v->paddle_x) * 0.35f;
  v->target_left_y = left_y;
  v->target_right_y = right_y;
  v->target_paddle_x = paddle_x;
}

static bool parse_pong_score(App *app, char *score, size_t score_size, char *status, size_t status_size) {
  char lines[MAX_LINES][MAX_LINE];
  int count = 0;
  split_lines(app->preview, lines, &count);
  if (count < 2) return false;
  copy_bounded(score, score_size, lines[1]);
  copy_bounded(status, status_size, count > 2 ? lines[2] : "");
  return true;
}

static int parse_frame_number(const char *text) {
  const char *p = strstr(text, "frame ");
  if (!p) return 0;
  return atoi(p + 6);
}

static float triangle_wave(float phase, float period, float amplitude) {
  if (period <= 0.0f) return 0.0f;
  float raw = SDL_fmodf(phase, period);
  if (raw < 0.0f) raw += period;
  if (raw <= amplitude) return raw;
  return period - raw;
}

static bool parse_arkanoid_header(App *app, char *score, size_t score_size, char *status, size_t status_size) {
  char lines[MAX_LINES][MAX_LINE];
  int count = 0;
  split_lines(app->preview, lines, &count);
  if (count == 0) return false;
  const char *header = lines[0];
  const char *gap = strstr(header, "  ");
  if (gap) {
    size_t len = (size_t)(gap - header);
    if (len >= score_size) len = score_size - 1;
    memcpy(score, header, len);
    score[len] = '\0';
    while (*gap == ' ') gap++;
    copy_bounded(status, status_size, gap);
  } else {
    copy_bounded(score, score_size, header);
    status[0] = '\0';
  }
  return true;
}

static void render_pong_game(App *app) {
  AppLayout l = app_layout(app);
  SDL_Color panel = {12, 18, 25, 255};
  SDL_Color court = {17, 29, 41, 255};
  SDL_Color line = {77, 208, 225, 255};
  SDL_Color player = {84, 190, 255, 255};
  SDL_Color ai = {255, 190, 95, 255};
  SDL_Color ball = {255, 245, 160, 255};
  SDL_Color ink = {236, 241, 247, 255};
  SDL_Color muted = {156, 168, 182, 255};
  fill_rect(app, l.preview_x, l.preview_y, l.preview_w, l.preview_h, panel);

  char score[64], status[128];
  if (!parse_pong_score(app, score, sizeof(score), status, sizeof(status))) {
    snprintf(score, sizeof(score), "0 : 0");
    snprintf(status, sizeof(status), "Press Space to start");
  }

  float margin = 42.0f;
  float header_h = 66.0f;
  float court_x = l.preview_x + margin;
  float court_y = l.preview_y + header_h;
  float court_w = l.preview_w - (margin * 2.0f);
  float court_h = l.preview_h - header_h - 56.0f;
  if (court_h > court_w * 0.55f) court_h = court_w * 0.55f;
  float cell_w = court_w / 34.0f;
  float cell_h = court_h / 9.0f;
  float radius = (cell_w < cell_h ? cell_w : cell_h) * 0.42f;

  int score_w = text_width(app->font_todo_input, score);
  draw_text_with_font(app, app->font_todo_input, score, l.preview_x + (l.preview_w - (float)score_w) / 2.0f, l.preview_y + 18.0f, ink);
  draw_text(app, status, l.preview_x + 28.0f, l.preview_y + l.preview_h - 34.0f, muted);

  fill_rect(app, court_x, court_y, court_w, court_h, court);
  stroke_rect(app, court_x, court_y, court_w, court_h, line);
  for (int y = 0; y < 9; y += 2) fill_rect(app, court_x + court_w / 2.0f - 2.0f, court_y + ((float)y * cell_h) + 8.0f, 4.0f, cell_h * 0.65f, (SDL_Color){80, 110, 130, 255});

  int bx = 16, by = 4, left_y = 3, right_y = 3;
  parse_game_cell(app, 'O', &bx, &by, &left_y, &right_y);
  if (bx < 3) bx = 3;
  if (bx > 30) bx = 30;
  if (left_y < 0) left_y = 3;
  if (right_y < 0) right_y = by - 1;
  if (right_y < 0) right_y = 0;
  if (right_y > 6) right_y = 6;
  int frame = parse_frame_number(app->preview);
  float motion = (float)frame / 4.0f;
  float ball_x = 3.0f + triangle_wave(motion, 56.0f, 28.0f);
  float ball_y = 1.0f + triangle_wave(motion, 14.0f, 7.0f);
  update_ball_visual(&app->pong_visual, bx, by, left_y, right_y, 0, 16);
  app->pong_visual.x = ball_x;
  app->pong_visual.y = ball_y;
  fill_rect(app, court_x + cell_w * 1.2f, court_y + cell_h * app->pong_visual.left_y, cell_w * 0.72f, cell_h * 3.0f, player);
  fill_rect(app, court_x + cell_w * 32.1f, court_y + cell_h * app->pong_visual.right_y, cell_w * 0.72f, cell_h * 3.0f, ai);
  fill_circle(app, court_x + (app->pong_visual.x + 0.5f) * cell_w, court_y + (app->pong_visual.y + 0.5f) * cell_h, radius + 7.0f, (SDL_Color){255, 245, 160, 42});
  fill_circle(app, court_x + (app->pong_visual.x + 0.5f) * cell_w, court_y + (app->pong_visual.y + 0.5f) * cell_h, radius, ball);
}

static void render_arkanoid_game(App *app) {
  AppLayout l = app_layout(app);
  SDL_Color panel = {13, 18, 24, 255};
  SDL_Color court = {20, 24, 33, 255};
  SDL_Color wall = {110, 231, 183, 255};
  SDL_Color paddle = {96, 165, 250, 255};
  SDL_Color ball = {251, 191, 36, 255};
  SDL_Color ink = {236, 241, 247, 255};
  SDL_Color muted = {156, 168, 182, 255};
  fill_rect(app, l.preview_x, l.preview_y, l.preview_w, l.preview_h, panel);

  char score[96], status[96];
  parse_arkanoid_header(app, score, sizeof(score), status, sizeof(status));
  draw_text_with_font(app, app->font_todo_input, score, l.preview_x + 32.0f, l.preview_y + 18.0f, ink);
  int status_w = text_width(app->font_todo_footer, status);
  draw_text_with_font(app, app->font_todo_footer, status, l.preview_x + l.preview_w - (float)status_w - 32.0f, l.preview_y + 28.0f, muted);

  float margin = 42.0f;
  float header_h = 72.0f;
  float court_x = l.preview_x + margin;
  float court_y = l.preview_y + header_h;
  float court_w = l.preview_w - (margin * 2.0f);
  float court_h = l.preview_h - header_h - 42.0f;
  if (court_h > court_w * 0.62f) court_h = court_w * 0.62f;
  float cell_w = court_w / 34.0f;
  float cell_h = court_h / 10.0f;
  float radius = (cell_w < cell_h ? cell_w : cell_h) * 0.38f;
  fill_rect(app, court_x, court_y, court_w, court_h, court);
  stroke_rect(app, court_x, court_y, court_w, court_h, wall);

  bool removed = strstr(app->preview, "Brick removed") != NULL;
  SDL_Color colors[] = {{248, 113, 113, 255}, {251, 146, 60, 255}, {250, 204, 21, 255}, {74, 222, 128, 255}, {45, 212, 191, 255}};
  for (int row = 0; row < 3; row++) {
    for (int col = 0; col < 5; col++) {
      if (removed && (row == 0) && (col <= 1)) continue;
      float x = court_x + 3.0f * cell_w + (float)col * 6.0f * cell_w;
      float y = court_y + 0.8f * cell_h + (float)row * 0.82f * cell_h;
      fill_rect(app, x, y, 5.0f * cell_w, cell_h * 0.52f, colors[(row + col) % 5]);
    }
  }

  int bx = 16, by = 5, dummy = -1;
  parse_game_cell(app, 'O', &bx, &by, &dummy, &dummy);
  if (bx < 2) bx = 2;
  if (bx > 31) bx = 31;
  if (by < 1) by = 1;
  if (by > 8) by = 8;
  int paddle_x = 12;
  char lines[MAX_LINES][MAX_LINE];
  int count = 0;
  split_lines(app->preview, lines, &count);
  for (int i = 0; i < count; i++) {
    if (lines[i][0] != '|') continue;
    char *p = strchr(lines[i], '=');
  if (p) {
      paddle_x = (int)(p - lines[i]) - 1;
      break;
    }
  }
  int frame = parse_frame_number(app->preview);
  float motion = (float)frame / 4.0f;
  float ball_x = 2.0f + triangle_wave(motion, 56.0f, 28.0f);
  float ball_y = strstr(app->preview, "Lost") ? 8.0f : 1.0f + triangle_wave(motion, 14.0f, 7.0f);
  update_ball_visual(&app->arkanoid_visual, bx, by, 0, 0, paddle_x, 16);
  app->arkanoid_visual.x = ball_x;
  app->arkanoid_visual.y = ball_y;
  fill_circle(app, court_x + (app->arkanoid_visual.x + 0.5f) * cell_w, court_y + (app->arkanoid_visual.y + 0.5f) * cell_h, radius + 8.0f, (SDL_Color){251, 191, 36, 44});
  fill_circle(app, court_x + (app->arkanoid_visual.x + 0.5f) * cell_w, court_y + (app->arkanoid_visual.y + 0.5f) * cell_h, radius, ball);
  fill_rect(app, court_x + app->arkanoid_visual.paddle_x * cell_w, court_y + 9.1f * cell_h, 8.0f * cell_w, cell_h * 0.45f, paddle);
  draw_text(app, "A/D or arrows move. Space launches/restarts.", l.preview_x + 28.0f, l.preview_y + l.preview_h - 34.0f, muted);
}

static void draw_source_panel_content(App *app, AppLayout l, float x, float y) {
  SDL_Color ink = {236, 241, 247, 255};
  SDL_Color muted = {156, 168, 182, 255};
  char lines[MAX_LINES][MAX_LINE];
  int count = 0;
  split_lines(app->source_text, lines, &count);
  int visible = visible_line_count(l.source_h - 70.0f);
  if (app->source_scroll > count - visible) app->source_scroll = count > visible ? count - visible : 0;
  int max_cols = 0;
  for (int i = 0; i < count; i++) {
    int len = (int)strlen(lines[i]);
    if (len > max_cols) max_cols = len;
  }
  int source_chars_visible = (int)((l.source_w - 74.0f) / 9.0f);
  if (source_chars_visible < 10) source_chars_visible = 10;
  if (app->source_x_scroll > max_cols - source_chars_visible) app->source_x_scroll = max_cols > source_chars_visible ? max_cols - source_chars_visible : 0;
  if (app->source_x_scroll < 0) app->source_x_scroll = 0;
  char header[256];
  snprintf(header, sizeof(header), "%s @ line %d col %d", EXAMPLES[app->active].source, app->source_scroll + 1, app->source_x_scroll + 1);
  draw_text(app, header, x + 20.0f, y + 10.0f, muted);
  for (int i = 0; i < visible - 1 && i + app->source_scroll < count; i++) {
    char numbered[MAX_LINE + 32];
    const char *source_line = lines[i + app->source_scroll];
    int len = (int)strlen(source_line);
    const char *shown = app->source_x_scroll < len ? source_line + app->source_x_scroll : "";
    snprintf(numbered, sizeof(numbered), "%3d: %s", i + app->source_scroll + 1, shown);
    draw_text(app, numbered, x + 20.0f, y + 42.0f + (float)i * 19.0f, ink);
  }
  draw_scrollbar(app, x + l.source_w - 16.0f, y + 14.0f, l.source_h - 48.0f, count, app->source_scroll, visible);
  if (max_cols > source_chars_visible) {
    float track_x = x + 20.0f;
    float track_y = y + l.source_h - 22.0f;
    float track_w = l.source_w - 52.0f;
    fill_rect(app, track_x, track_y, track_w, 8, (SDL_Color){48, 54, 62, 255});
    float thumb_w = track_w * ((float)source_chars_visible / (float)max_cols);
    if (thumb_w < 28.0f) thumb_w = 28.0f;
    float max_first = (float)(max_cols - source_chars_visible);
    float thumb_x = track_x + (track_w - thumb_w) * ((float)app->source_x_scroll / max_first);
    fill_rect(app, thumb_x, track_y, thumb_w, 8, (SDL_Color){148, 163, 184, 255});
  }
}

static void render_source_panel(App *app, AppLayout l, SDL_Color border) {
  int cache_w = (int)(l.source_w + 0.5f);
  int cache_h = (int)(l.source_h + 0.5f);
  bool cache_ok = app->source_cache &&
    app->source_cache_w == cache_w &&
    app->source_cache_h == cache_h &&
    app->source_cache_active == app->active &&
    app->source_cache_scroll == app->source_scroll &&
    app->source_cache_x_scroll == app->source_x_scroll;

  if (!cache_ok) {
    invalidate_source_cache(app);
    app->source_cache = SDL_CreateTexture(app->renderer, SDL_PIXELFORMAT_RGBA8888, SDL_TEXTUREACCESS_TARGET, cache_w, cache_h);
    if (app->source_cache) {
      SDL_SetTextureBlendMode(app->source_cache, SDL_BLENDMODE_BLEND);
      SDL_Texture *old_target = SDL_GetRenderTarget(app->renderer);
      SDL_SetRenderTarget(app->renderer, app->source_cache);
      fill_rect(app, 0, 0, l.source_w, l.source_h, (SDL_Color){21, 26, 33, 255});
      stroke_rect(app, 0, 0, l.source_w, l.source_h, border);
      draw_source_panel_content(app, l, 0.0f, 0.0f);
      SDL_SetRenderTarget(app->renderer, old_target);
      app->source_cache_w = cache_w;
      app->source_cache_h = cache_h;
      app->source_cache_active = app->active;
      app->source_cache_scroll = app->source_scroll;
      app->source_cache_x_scroll = app->source_x_scroll;
    }
  }

  if (app->source_cache) {
    SDL_FRect dst = {l.source_x, l.source_y, l.source_w, l.source_h};
    SDL_RenderTexture(app->renderer, app->source_cache, NULL, &dst);
  } else {
    fill_rect(app, l.source_x, l.source_y, l.source_w, l.source_h, (SDL_Color){21, 26, 33, 255});
    stroke_rect(app, l.source_x, l.source_y, l.source_w, l.source_h, border);
    draw_source_panel_content(app, l, l.source_x, l.source_y);
  }
}

static void render(App *app) {
  update_render_size(app);
  AppLayout l = app_layout(app);
  SDL_Color bg = {18, 22, 28, 255};
  SDL_Color panel = {31, 36, 45, 255};
  SDL_Color active = {51, 92, 140, 255};
  SDL_Color ink = {236, 241, 247, 255};
  SDL_Color muted = {156, 168, 182, 255};
  SDL_Color border = {82, 94, 110, 255};
  SDL_SetRenderDrawColor(app->renderer, bg.r, bg.g, bg.b, bg.a);
  SDL_RenderClear(app->renderer);

  fill_rect(app, 0, 0, l.left_w, (float)app->height, panel);
  fill_rect(app, l.preview_x, l.preview_y, l.preview_w, l.preview_h, (SDL_Color){24, 29, 36, 255});
  stroke_rect(app, l.preview_x, l.preview_y, l.preview_w, l.preview_h, border);
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
  int visible = visible_line_count(l.preview_h - 44.0f);
  if (strcmp(EXAMPLES[app->active].id, "todo_mvc") == 0) {
    render_todo_mvc(app);
  } else if (strcmp(EXAMPLES[app->active].id, "pong") == 0) {
    render_pong_game(app);
  } else if (strcmp(EXAMPLES[app->active].id, "arkanoid") == 0) {
    render_arkanoid_game(app);
  } else {
    split_lines(app->preview, lines, &count);
    if (app->preview_scroll > count - visible) app->preview_scroll = count > visible ? count - visible : 0;
    for (int i = 0; i < visible && i + app->preview_scroll < count; i++) {
      draw_text(app, lines[i + app->preview_scroll], l.preview_x + 24.0f, l.preview_y + 24.0f + (float)i * 19.0f, ink);
    }
    draw_scrollbar(app, l.preview_x + l.preview_w - 16.0f, l.preview_y + 14.0f, l.preview_h - 32.0f, count, app->preview_scroll, visible);
  }

  render_source_panel(app, l, border);
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
  if (strcmp(key, "Space") == 0) app->pong_started = true;
  if (app->script || (strcmp(key, "Space") == 0)) {
    refresh_preview(app);
    app->game_refresh_pending = false;
  } else {
    app->game_refresh_pending = true;
    app->dirty = true;
  }
}

static void event_todo_text(App *app, const char *text) {
  if (!app->todo_focused) {
    append_expected(app, app->active, "focus_input", NULL, 0);
    app->todo_focused = true;
  }
  strncat(app->todo_input, text, sizeof(app->todo_input) - strlen(app->todo_input) - 1);
  if (app->script) append_expected(app, app->active, "type", app->todo_input, -1);
  set_preview_input_echo(app);
  app->dirty = true;
}

static void event_todo_set_text(App *app, const char *text) {
  if (!app->todo_focused) {
    append_expected(app, app->active, "focus_input", NULL, 0);
    app->todo_focused = true;
  }
  snprintf(app->todo_input, sizeof(app->todo_input), "%s", text);
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
    if (app->script) append_expected(app, app->active, "type", app->todo_input, -1);
    set_preview_input_echo(app);
  } else {
    if (!app->script && (strcmp(key, "Enter") == 0)) append_expected(app, app->active, "type", app->todo_input, -1);
    append_expected(app, app->active, "key", key, -1);
    if (strcmp(key, "Enter") == 0) app->todo_input[0] = '\0';
    refresh_preview(app);
  }
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
  app->todo_input[0] = '\0';
  refresh_preview(app);
}

static void event_todo_double_click_index(App *app, int row, const char *title) {
  char payload[MAX_LINE + 32];
  snprintf(payload, sizeof(payload), "index:%d:%s", row, title);
  snprintf(app->todo_input, sizeof(app->todo_input), "%s", title);
  app->todo_focused = true;
  append_expected(app, app->active, "dblclick_text", payload, -1);
  refresh_preview(app);
}

static void event_todo_double_click_title(App *app, const char *title) {
  TodoModel model;
  parse_todo_model(app->preview, &model);
  for (int i = 0; i < model.item_count; i++) {
    if (strcmp(model.items[i].title, title) == 0) {
      event_todo_double_click_index(app, i, title);
      return;
    }
  }
  snprintf(app->todo_input, sizeof(app->todo_input), "%s", title);
  app->todo_focused = true;
  append_expected(app, app->active, "dblclick_text", title, -1);
  refresh_preview(app);
}

static void event_todo_click(App *app, int x, int y, int clicks) {
  TodoModel model;
  parse_todo_model(app->preview, &model);
  TodoLayout l = todo_layout_for_count(app, model.item_count);
  app->todo_focused = true;
  if ((float)x >= l.card_x && (float)x <= l.card_x + l.card_w && (float)y >= l.input_y && (float)y <= l.input_y + l.input_h) {
    if ((float)x < l.card_x + 64.0f) {
      event_todo_toggle_all(app);
      return;
    }
    append_expected(app, app->active, "focus_input", NULL, 0);
  } else if ((float)x >= l.card_x && (float)x <= l.card_x + l.card_w && (float)y >= l.list_y && (float)y < l.footer_y) {
    int visible_row = (int)(((float)y - l.list_y) / l.row_h);
    int row = app->preview_scroll + visible_row;
    if (row < 0 || row >= model.item_count) {
      append_expected(app, app->active, "focus_input", NULL, 0);
    } else if ((float)x > l.card_x + l.card_w - 72.0f) {
      event_todo_delete_index(app, row);
      return;
    } else if ((float)x < l.card_x + 72.0f) {
      append_expected(app, app->active, "click_checkbox", NULL, row + 1);
    } else if (clicks >= 2) {
      event_todo_double_click_index(app, row, model.items[row].title);
      return;
    } else {
      append_expected(app, app->active, "focus_input", NULL, 0);
    }
  } else if ((float)y >= l.footer_y && (float)y <= l.footer_y + l.footer_h) {
    float clear_w = l.card_w < 650.0f ? 46.0f : 126.0f;
    float clear_x = l.card_x + l.card_w - clear_w - 18.0f;
    float filter_total_w = 248.0f;
    float filter_x = l.card_x + (l.card_w - filter_total_w) * 0.52f;
    float min_filter_x = l.card_x + 132.0f;
    if (filter_x < min_filter_x) filter_x = min_filter_x;
    if ((filter_x + filter_total_w) > (clear_x - 10.0f)) filter_x = clear_x - filter_total_w - 10.0f;
    if (filter_x < min_filter_x) filter_x = min_filter_x;
    if ((float)x >= clear_x - 8.0f && (float)x <= l.card_x + l.card_w - 8.0f) {
      append_expected(app, app->active, "click_text", "Clear completed", -1);
    } else if ((float)x >= filter_x - 8.0f && (float)x < filter_x + 58.0f) {
      event_todo_filter(app, "All");
      return;
    } else if ((float)x >= filter_x + 66.0f && (float)x < filter_x + 152.0f) {
      event_todo_filter(app, "Active");
      return;
    } else if ((float)x >= filter_x + 166.0f && (float)x < filter_x + 286.0f) {
      event_todo_filter(app, "Completed");
      return;
    } else {
      append_expected(app, app->active, "focus_input", NULL, 0);
    }
  } else {
    append_expected(app, app->active, "focus_input", NULL, 0);
  }
  refresh_preview(app);
}

static void handle_mouse(App *app, int x, int y, int clicks) {
  AppLayout l = app_layout(app);
  if ((float)x < l.left_w) {
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
    event_todo_click(app, x, y, clicks);
  } else if (strcmp(id, "pong") == 0) {
    event_pong(app, "Space");
  } else if (strcmp(id, "arkanoid") == 0) {
    event_pong(app, "Space");
  }
  app->dirty = true;
}

static void handle_mouse_window(App *app, float window_x, float window_y, int clicks) {
  float x = window_x;
  float y = window_y;
  SDL_RenderCoordinatesFromWindow(app->renderer, window_x, window_y, &x, &y);
  handle_mouse(app, (int)x, (int)y, clicks);
}

static void handle_wheel_window(App *app, float window_x, float wheel_x, float wheel_y) {
  float x = window_x;
  float y = 0.0f;
  SDL_RenderCoordinatesFromWindow(app->renderer, window_x, 0.0f, &x, &y);
  AppLayout l = app_layout(app);
  if (x >= l.source_x) {
    if (wheel_x != 0.0f) app->source_x_scroll += wheel_x > 0 ? 8 : -8;
    else app->source_scroll += wheel_y > 0 ? -3 : 3;
  } else {
    app->preview_scroll += wheel_y > 0 ? -3 : 3;
  }
  if (app->source_scroll < 0) app->source_scroll = 0;
  if (app->source_x_scroll < 0) app->source_x_scroll = 0;
  if (app->preview_scroll < 0) app->preview_scroll = 0;
  app->dirty = true;
}

static void handle_key(App *app, SDL_Keycode key, SDL_Keymod mod) {
  const char *id = EXAMPLES[app->active].id;
  if (strcmp(id, "todo_mvc") == 0) {
    if ((key == SDLK_RETURN) || (key == SDLK_KP_ENTER)) event_todo_key(app, "Enter");
    else if ((key == SDLK_BACKSPACE) || (key == SDLK_KP_BACKSPACE)) event_todo_key(app, "Backspace");
    else if ((mod & SDL_KMOD_SHIFT) && (key == SDLK_LEFT)) {
      app->source_x_scroll -= 8;
      if (app->source_x_scroll < 0) app->source_x_scroll = 0;
    } else if ((mod & SDL_KMOD_SHIFT) && (key == SDLK_RIGHT)) {
      app->source_x_scroll += 8;
    } else if (key == SDLK_TAB && (mod & SDL_KMOD_SHIFT)) {
      select_example(app, (app->active + EXAMPLE_COUNT - 1) % EXAMPLE_COUNT);
    } else if (key == SDLK_TAB) {
      select_example(app, (app->active + 1) % EXAMPLE_COUNT);
    } else if (key == SDLK_UP) {
      app->preview_scroll -= 1;
      if (app->preview_scroll < 0) app->preview_scroll = 0;
    } else if (key == SDLK_DOWN) {
      app->preview_scroll += 1;
    } else if (key == SDLK_ESCAPE) {
      app->running = false;
    }
  } else if ((key == SDLK_ESCAPE) || ((key == SDLK_Q) && (mod & SDL_KMOD_CTRL))) {
    app->running = false;
  } else if (strcmp(id, "pong") == 0) {
    if (key == SDLK_SPACE) event_pong(app, "Space");
    else if (key == SDLK_W || key == SDLK_UP) event_pong(app, "W");
    else if (key == SDLK_S || key == SDLK_DOWN) event_pong(app, "S");
  } else if (strcmp(id, "arkanoid") == 0) {
    if (key == SDLK_SPACE) event_pong(app, "Space");
    else if (key == SDLK_A || key == SDLK_LEFT) event_pong(app, "A");
    else if (key == SDLK_D || key == SDLK_RIGHT) event_pong(app, "D");
    else if (key == SDLK_L) event_pong(app, "L");
  } else if ((mod & SDL_KMOD_SHIFT) && (key == SDLK_LEFT)) {
    app->source_x_scroll -= 8;
    if (app->source_x_scroll < 0) app->source_x_scroll = 0;
  } else if ((mod & SDL_KMOD_SHIFT) && (key == SDLK_RIGHT)) {
    app->source_x_scroll += 8;
  } else if (key == SDLK_TAB && (mod & SDL_KMOD_SHIFT)) {
    select_example(app, (app->active + EXAMPLE_COUNT - 1) % EXAMPLE_COUNT);
  } else if (key == SDLK_TAB) {
    select_example(app, (app->active + 1) % EXAMPLE_COUNT);
  } else if (key == SDLK_F5) {
    refresh_preview(app);
  } else if ((key == SDLK_R) && (mod & SDL_KMOD_CTRL)) {
    clear_active(app);
  } else if ((strcmp(id, "counter") == 0) || (strcmp(id, "counter_hold") == 0)) {
    if (key == SDLK_RETURN || key == SDLK_KP_ENTER || key == SDLK_SPACE) event_counter(app);
  } else if (key == SDLK_UP) {
    app->preview_scroll -= 1;
    if (app->preview_scroll < 0) app->preview_scroll = 0;
  } else if (key == SDLK_DOWN) {
    app->preview_scroll += 1;
  }
  app->dirty = true;
}

static void pump_timers(App *app) {
  Uint64 now = SDL_GetTicks();
  const char *id = EXAMPLES[app->active].id;
  if ((strcmp(id, "interval") == 0) || (strcmp(id, "interval_hold") == 0)) {
    if (now - app->last_interval_ms >= 1000) {
      app->last_interval_ms = now;
      event_interval_tick(app);
    }
  } else if (((strcmp(id, "pong") == 0) || (strcmp(id, "arkanoid") == 0)) && app->pong_started) {
    if (now - app->last_pong_ms >= 16) {
      app->last_pong_ms = now;
      append_expected(app, app->active, "wait", NULL, -1);
      refresh_preview(app);
      app->game_refresh_pending = false;
    } else if (app->game_refresh_pending) {
      refresh_preview(app);
      app->game_refresh_pending = false;
    }
  }
}

static bool init_sdl(App *app, bool script) {
  if (!SDL_Init(SDL_INIT_VIDEO)) return false;
  if (!TTF_Init()) return false;
  SDL_WindowFlags flags = SDL_WINDOW_RESIZABLE | SDL_WINDOW_HIGH_PIXEL_DENSITY;
  if (script) flags |= SDL_WINDOW_HIDDEN;
  else flags |= SDL_WINDOW_MAXIMIZED;
  app->window = SDL_CreateWindow("Boon-Pony SDL Playground", 1600, 1000, flags);
  if (!app->window) return false;
  app->renderer = SDL_CreateRenderer(app->window, NULL);
  if (!app->renderer) return false;
  update_render_size(app);
  if (!script) SDL_SetRenderVSync(app->renderer, 1);
  app->font = TTF_OpenFont(".boon-local/gui/fonts/JetBrainsMono-Regular.ttf", 15.0f);
  if (!app->font) return false;
  app->font_todo_title = open_todo_font(84.0f);
  app->font_todo_input = open_todo_font(30.0f);
  app->font_todo_item = open_todo_font(30.0f);
  app->font_todo_footer = open_todo_font(16.0f);
  if (!app->font_todo_title || !app->font_todo_input || !app->font_todo_item || !app->font_todo_footer) return false;
  SDL_StartTextInput(app->window);
  return true;
}

static void shutdown_sdl(App *app) {
  if (app->source_cache) SDL_DestroyTexture(app->source_cache);
  if (app->font_todo_footer) TTF_CloseFont(app->font_todo_footer);
  if (app->font_todo_item) TTF_CloseFont(app->font_todo_item);
  if (app->font_todo_input) TTF_CloseFont(app->font_todo_input);
  if (app->font_todo_title) TTF_CloseFont(app->font_todo_title);
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
    "  \"renderer\":\"%s\",\n"
    "  \"window_width\":%d,\n"
    "  \"window_height\":%d,\n"
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
    app->renderer ? (SDL_GetRendererName(app->renderer) ? SDL_GetRendererName(app->renderer) : "unknown") : "none",
    app->width,
    app->height,
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

static bool todo_model_has_item(TodoModel *model, const char *title, int completed) {
  for (int i = 0; i < model->item_count; i++) {
    if (strcmp(model->items[i].title, title) == 0) {
      if (completed < 0) return true;
      return model->items[i].completed == (completed != 0);
    }
  }
  return false;
}

static void expect_todo_model(App *app, const char *name, int item_count, int active_count, const char *filter, const char *input, bool focused) {
  TodoModel model;
  parse_todo_model(app->preview, &model);
  bool pass = true;
  if (item_count >= 0 && model.item_count != item_count) pass = false;
  if (active_count >= 0 && model.active_count != active_count) pass = false;
  if (filter && strcmp(model.filter, filter) != 0) pass = false;
  if (input && strcmp(model.input, input) != 0) pass = false;
  if (focused && !model.input_focused) pass = false;
  char expected[256];
  snprintf(expected, sizeof(expected), "items=%d active=%d filter=%s input=%s focused=%s", item_count, active_count, filter ? filter : "*", input ? input : "*", focused ? "true" : "*");
  record_check(app, EXAMPLES[app->active].id, name, pass, expected);
}

static void expect_todo_item(App *app, const char *name, const char *title, int completed) {
  TodoModel model;
  parse_todo_model(app->preview, &model);
  record_check(app, EXAMPLES[app->active].id, name, todo_model_has_item(&model, title, completed), title);
}

static void expect_todo_editing_index(App *app, const char *name, int editing_index, const char *title) {
  TodoModel model;
  parse_todo_model(app->preview, &model);
  bool pass = (editing_index >= 0) && (editing_index < model.item_count) &&
    model.items[editing_index].editing && (strcmp(model.items[editing_index].title, title) == 0);
  for (int i = 0; i < model.item_count; i++) {
    if ((i != editing_index) && model.items[i].editing) pass = false;
  }
  char expected[128];
  snprintf(expected, sizeof(expected), "editing_index=%d title=%s", editing_index, title);
  record_check(app, EXAMPLES[app->active].id, name, pass, expected);
}

static void expect_todo_visual_contract(App *app) {
  TodoModel model;
  parse_todo_model(app->preview, &model);
  TodoLayout l = todo_layout_for_count(app, model.item_count);
  bool pass = (l.card_w <= l.preview_w) && (l.card_x >= l.preview_x) && ((l.card_x + l.card_w) <= (l.preview_x + l.preview_w)) &&
    (l.input_h >= 60.0f) && (l.row_h >= 54.0f) && model.input_focused && (model.item_count >= 2);
  record_check(app, EXAMPLES[app->active].id, "styled TodoMVC card matches reference structure", pass, "card stays inside preview, focused input, rows, filters, footer");
}

static void expect_todo_narrow_window_contract(App *app) {
  int old_w = app->width;
  int old_h = app->height;
  app->width = 960;
  app->height = 1000;
  TodoModel model;
  parse_todo_model(app->preview, &model);
  TodoLayout l = todo_layout_for_count(app, model.item_count);
  bool pass = (l.card_x >= l.preview_x) && ((l.card_x + l.card_w) <= (l.preview_x + l.preview_w)) && (l.card_w <= l.preview_w);
  record_check(app, EXAMPLES[app->active].id, "TodoMVC narrow window does not overflow preview", pass, "960px window keeps card inside preview");
  app->width = old_w;
  app->height = old_h;
}

static void expect_todo_scroll_contract(App *app, const char *name) {
  TodoModel model;
  parse_todo_model(app->preview, &model);
  TodoLayout l = todo_layout_for_count(app, model.item_count);
  bool pass = (model.item_count > l.visible_items) && (app->preview_scroll > 0) && (app->preview_scroll <= model.item_count - l.visible_items);
  record_check(app, EXAMPLES[app->active].id, name, pass, "long list has bounded visual scrollbar state");
}

static void expect_source_horizontal_scroll(App *app, const char *name) {
  app->source_x_scroll = 24;
  render(app);
  record_check(app, EXAMPLES[app->active].id, name, app->source_x_scroll == 24, "code editor horizontal scroll is retained and rendered");
}

static bool save_screenshot(App *app, const char *path) {
  SDL_Surface *surface = SDL_RenderReadPixels(app->renderer, NULL);
  if (!surface) return false;
  bool ok = SDL_SaveBMP(surface, path);
  SDL_DestroySurface(surface);
  return ok;
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
      int before = app->active;
      handle_key(app, SDLK_RIGHT, 0);
      handle_key(app, SDLK_LEFT, 0);
      record_check(app, EXAMPLES[app->active].id, "plain arrows do not switch examples", app->active == before, "Tab switches examples; arrows stay in preview");
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
      expect_todo_model(app, "initial generated model", 2, 2, "All", "", true);
      expect_todo_visual_contract(app);
      expect_todo_narrow_window_contract(app);
      record_check(app, EXAMPLES[app->active].id, "styled TodoMVC screenshot saved", save_screenshot(app, "build/reports/gui-todomvc-visual.bmp"), "build/reports/gui-todomvc-visual.bmp");
      TodoModel click_model;
      parse_todo_model(app->preview, &click_model);
      TodoLayout click_layout = todo_layout_for_count(app, click_model.item_count);
      event_todo_click(app, (int)(click_layout.card_x + 110), (int)(click_layout.input_y + 24), 1);
      expect_todo_model(app, "visual input click keeps focus", 2, 2, "All", "", true);
      event_todo_click(app, (int)(click_layout.card_x + 36), (int)(click_layout.list_y + 29), 1);
      expect_todo_item(app, "visual checkbox click toggles first todo", "Buy groceries", 1);
      parse_todo_model(app->preview, &click_model);
      click_layout = todo_layout_for_count(app, click_model.item_count);
      event_todo_click(app, (int)(click_layout.card_x + 386), (int)(click_layout.footer_y + 20), 1);
      expect_todo_model(app, "visual active filter click", 1, 1, "Active", "", true);
      parse_todo_model(app->preview, &click_model);
      click_layout = todo_layout_for_count(app, click_model.item_count);
      event_todo_click(app, (int)(click_layout.card_x + 318), (int)(click_layout.footer_y + 20), 1);
      expect_todo_model(app, "visual all filter click", 2, 1, "All", "", true);
      parse_todo_model(app->preview, &click_model);
      click_layout = todo_layout_for_count(app, click_model.item_count);
      event_todo_click(app, (int)(click_layout.card_x + 120), (int)(click_layout.list_y + click_layout.row_h + 24), 2);
      expect_contains(app, "visual double click enters edit mode", "[edit] Clean room|");
      event_todo_set_text(app, "Clean room edited");
      event_todo_key(app, "Enter");
      expect_todo_item(app, "visual edit commits", "Clean room edited", 0);
      parse_todo_model(app->preview, &click_model);
      click_layout = todo_layout_for_count(app, click_model.item_count);
      event_todo_click(app, (int)(click_layout.card_x + click_layout.card_w - 32), (int)(click_layout.list_y + click_layout.row_h + 24), 1);
      expect_not_contains(app, "visual delete button removes row", "Clean room edited");

      clear_active(app);
      event_todo_text(app, "Alpha");
      expect_contains(app, "typed full input", "Input: Alpha|");
      Uint64 typing_start = SDL_GetTicks();
      for (int repeat = 0; repeat < 120; repeat++) {
        event_todo_text(app, "a");
        render(app);
      }
      Uint64 typing_elapsed = SDL_GetTicks() - typing_start;
      char typing_expected[160];
      snprintf(typing_expected, sizeof(typing_expected), "%llu ms < 1200ms for 120 repeated text inputs with cached source panel", (unsigned long long)typing_elapsed);
      record_check(app, EXAMPLES[app->active].id, "held letter typing render budget", typing_elapsed < 1200, typing_expected);
      clear_active(app);
      event_todo_text(app, "Alpha");
      handle_key(app, SDLK_R, 0);
      handle_key(app, SDLK_Q, 0);
      expect_contains(app, "letter shortcut keys are ignored while typing", "Input: Alpha|");
      record_check(app, EXAMPLES[app->active].id, "Q does not quit while typing", app->running, "plain Q remains text input safe in TodoMVC");
      event_todo_key(app, "Backspace");
      expect_contains(app, "backspace updates focused input", "Input: Alph|");
      event_todo_text(app, "a");
      handle_key(app, SDLK_KP_ENTER, 0);
      expect_contains(app, "added Alpha", "Alpha");
      expect_todo_model(app, "keypad enter keeps input focused after add", 3, 3, "All", "", true);
      expect_todo_model(app, "input stays focused after Enter", 3, 3, "All", "", true);
      event_todo_text(app, "Beta");
      event_todo_key(app, "Enter");
      expect_contains(app, "added Beta", "Beta");
      event_todo_text(app, "Gamma");
      event_todo_key(app, "Enter");
      expect_contains(app, "added Gamma", "Gamma");
      event_todo_set_text(app, "Duplicate");
      event_todo_key(app, "Enter");
      event_todo_set_text(app, "Duplicate");
      event_todo_key(app, "Enter");
      event_todo_double_click_index(app, 6, "Duplicate");
      expect_todo_editing_index(app, "duplicate titles edit clicked row by index", 6, "Duplicate");
      event_todo_key(app, "Escape");
      expect_not_contains(app, "duplicate edit cancel clears edit mode", "[edit]");
      append_expected(app, app->active, "click_checkbox", NULL, 3);
      refresh_preview(app);
      expect_contains(app, "toggle third item", "[x] Alpha");
      event_todo_filter(app, "Completed");
      expect_contains(app, "completed filter", "Filter: Completed");
      expect_contains(app, "completed item visible", "Alpha");
      event_todo_filter(app, "All");
      event_todo_delete_index(app, 1);
      expect_not_contains(app, "deleted Clean room", "Clean room");
      event_todo_double_click_title(app, "Beta");
      expect_contains(app, "double click enters edit mode", "[edit] Beta|");
      event_todo_set_text(app, "Beta edited");
      event_todo_key(app, "Enter");
      expect_todo_item(app, "edit commits title", "Beta edited", 0);
      event_todo_delete_index(app, 2);
      expect_not_contains(app, "delete edited row does not leak edit state", "[edit]");
      expect_not_contains(app, "delete edited row removes item", "Beta edited");
      event_todo_toggle_all(app);
      expect_contains(app, "toggle all completes", "0 items left");
      append_expected(app, app->active, "click_text", "Clear completed", -1);
      refresh_preview(app);
      expect_not_contains(app, "clear completed removes Alpha", "Alpha");
      expect_todo_model(app, "clear completed leaves empty active list", 0, 0, "All", "", true);

      event_todo_set_text(app, "Todo to complete");
      event_todo_key(app, "Enter");
      event_todo_set_text(app, "Todo to keep");
      event_todo_key(app, "Enter");
      append_expected(app, app->active, "click_checkbox", NULL, 1);
      refresh_preview(app);
      expect_todo_item(app, "professional clear setup completed item", "Todo to complete", 1);
      append_expected(app, app->active, "click_text", "Clear completed", -1);
      refresh_preview(app);
      expect_not_contains(app, "clear completed removes only completed todo", "Todo to complete");
      expect_todo_item(app, "clear completed keeps active todo", "Todo to keep", 0);

      clear_active(app);
      for (int n = 1; n <= 20; n++) {
        char value[32];
        snprintf(value, sizeof(value), "Item %02d", n);
        event_todo_set_text(app, value);
        event_todo_key(app, "Enter");
      }
      expect_todo_model(app, "long list accepts more than five todos", 22, 22, "All", "", true);
      app->preview_scroll = 12;
      render(app);
      expect_todo_scroll_contract(app, "long list visual scrollbar is bounded");
      event_todo_filter(app, "Active");
      expect_todo_model(app, "active filter after long list", 22, 22, "Active", "", true);
      event_todo_filter(app, "Completed");
      expect_todo_model(app, "completed filter can be selected with no matches", 0, 22, "Completed", "", true);
      event_todo_filter(app, "All");
      expect_source_horizontal_scroll(app, "source editor horizontal scroll");
    } else if (strcmp(id, "pong") == 0) {
      expect_contains(app, "initial pong prompt", "Press Space");
      event_pong(app, "Space");
      expect_contains(app, "pong started", "Pong generated runtime");
      char first_frame[MAX_TEXT];
      copy_bounded(first_frame, sizeof(first_frame), app->preview);
      append_expected(app, app->active, "wait", NULL, -1);
      refresh_preview(app);
      record_check(app, EXAMPLES[app->active].id, "pong ball advances on generated wait frame", strcmp(first_frame, app->preview) != 0, "generated frame text changes after wait");
      event_pong(app, "W");
      event_pong(app, "S");
      expect_contains(app, "pong controls hint", "AI follows ball");
      int pong_before = app->active;
      handle_key(app, SDLK_UP, 0);
      handle_key(app, SDLK_DOWN, 0);
      record_check(app, EXAMPLES[app->active].id, "pong arrow keys stay in game", app->active == pong_before, "Up/Down control Pong instead of switching tabs");
      render(app);
      record_check(app, EXAMPLES[app->active].id, "styled Pong screenshot saved", save_screenshot(app, "build/reports/gui-pong-visual.bmp"), "build/reports/gui-pong-visual.bmp");
    } else if (strcmp(id, "arkanoid") == 0) {
      event_pong(app, "Space");
      expect_contains(app, "arkanoid animates", "Score:");
      char first_frame[MAX_TEXT];
      copy_bounded(first_frame, sizeof(first_frame), app->preview);
      for (int tick = 0; tick < 8; tick++) {
        append_expected(app, app->active, "wait", NULL, -1);
      }
      refresh_preview(app);
      record_check(app, EXAMPLES[app->active].id, "arkanoid ball advances on generated wait frames", strcmp(first_frame, app->preview) != 0, "generated frame text changes after waits");
      expect_contains(app, "arkanoid brick removal appears", "Brick removed");
      int arkanoid_before = app->active;
      handle_key(app, SDLK_LEFT, 0);
      handle_key(app, SDLK_RIGHT, 0);
      record_check(app, EXAMPLES[app->active].id, "arkanoid arrow keys stay in game", app->active == arkanoid_before, "Left/Right control Arkanoid instead of switching tabs");
      render(app);
      record_check(app, EXAMPLES[app->active].id, "styled Arkanoid screenshot saved", save_screenshot(app, "build/reports/gui-arkanoid-visual.bmp"), "build/reports/gui-arkanoid-visual.bmp");
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
    protocol_session_close(&app);
    for (int i = 0; i < EXAMPLE_COUNT; i++) free_history(&app.history[i]);
    shutdown_sdl(&app);
    return status;
  }

  render(&app);
  app.last_render_ms = SDL_GetTicks();
  app.dirty = false;
  SDL_Delay(16);
  render(&app);

  int frames = 0;
  while (app.running) {
    SDL_Event event;
    while (SDL_PollEvent(&event)) {
      if (event.type == SDL_EVENT_QUIT) app.running = false;
      else if (event.type == SDL_EVENT_WINDOW_RESIZED || event.type == SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED) app.dirty = true;
      else if (event.type == SDL_EVENT_MOUSE_BUTTON_DOWN) handle_mouse_window(&app, event.button.x, event.button.y, event.button.clicks);
      else if (event.type == SDL_EVENT_MOUSE_WHEEL) {
        handle_wheel_window(&app, event.wheel.mouse_x, event.wheel.x, event.wheel.y);
      } else if (event.type == SDL_EVENT_KEY_DOWN) {
        handle_key(&app, event.key.key, event.key.mod);
      } else if (event.type == SDL_EVENT_TEXT_INPUT) {
        if (strcmp(EXAMPLES[app.active].id, "todo_mvc") == 0) event_todo_text(&app, event.text.text);
      }
    }
    pump_timers(&app);
    const char *id = EXAMPLES[app.active].id;
    bool active_game = app.pong_started && ((strcmp(id, "pong") == 0) || (strcmp(id, "arkanoid") == 0));
    bool needs_cursor_blink = strcmp(id, "todo_mvc") == 0;
    Uint64 now = SDL_GetTicks();
    if (app.dirty || active_game || (needs_cursor_blink && (now - app.last_render_ms >= 250))) {
      render(&app);
      app.last_render_ms = now;
      app.dirty = false;
      frames++;
    }
    SDL_Delay(16);
  }

  write_report(report, "pass", &app, frames);
  protocol_session_close(&app);
  for (int i = 0; i < EXAMPLE_COUNT; i++) free_history(&app.history[i]);
  shutdown_sdl(&app);
  return 0;
}
