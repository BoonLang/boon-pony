#include <SDL3/SDL.h>
#include <SDL3_ttf/SDL_ttf.h>

#include <stdio.h>

int main(int argc, char **argv) {
  (void)argc;
  (void)argv;

  if (!SDL_Init(SDL_INIT_VIDEO)) {
    fprintf(stderr, "SDL_Init failed: %s\n", SDL_GetError());
    return 1;
  }

  if (!TTF_Init()) {
    fprintf(stderr, "TTF_Init failed: %s\n", SDL_GetError());
    SDL_Quit();
    return 2;
  }

  printf("{\"status\":\"pass\",\"sdl_version\":\"%d.%d.%d\",\"ttf_initialized\":true,\"native_window_verified\":false}\n",
    SDL_MAJOR_VERSION, SDL_MINOR_VERSION, SDL_MICRO_VERSION);

  TTF_Quit();
  SDL_Quit();
  return 0;
}
