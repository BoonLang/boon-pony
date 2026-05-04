#include <stdint.h>

extern void* BrowserAbi_boon_browser_state_new_o(void);
extern int32_t BrowserAbi_boon_browser_state_init_oIIIi(void* state,
  uint32_t width, uint32_t height, uint32_t scale_milli);
extern int32_t BrowserAbi_boon_browser_state_select_example_oIIi(void* state,
  uint32_t ptr, uint32_t len);
extern int32_t BrowserAbi_boon_browser_state_input_oIIi(void* state,
  uint32_t ptr, uint32_t len);
extern int32_t BrowserAbi_boon_browser_state_tick_oIi(void* state,
  uint32_t delta_ms);
extern uint8_t* BrowserAbi_boon_browser_state_scene_ptr_oo(void* state);
extern uint32_t BrowserAbi_boon_browser_state_scene_len_oI(void* state);

static void* browser_state = 0;

static void* state(void)
{
  if(browser_state == 0)
    browser_state = BrowserAbi_boon_browser_state_new_o();

  return browser_state;
}

int32_t boon_browser_init(uint32_t width, uint32_t height, uint32_t scale_milli)
{
  return BrowserAbi_boon_browser_state_init_oIIIi(state(), width, height,
    scale_milli);
}

int32_t boon_browser_select_example(uint32_t ptr, uint32_t len)
{
  return BrowserAbi_boon_browser_state_select_example_oIIi(state(), ptr, len);
}

int32_t boon_browser_input(uint32_t ptr, uint32_t len)
{
  return BrowserAbi_boon_browser_state_input_oIIi(state(), ptr, len);
}

int32_t boon_browser_tick(uint32_t delta_ms)
{
  return BrowserAbi_boon_browser_state_tick_oIi(state(), delta_ms);
}

uint32_t boon_browser_scene_ptr(void)
{
  return (uint32_t)(uintptr_t)BrowserAbi_boon_browser_state_scene_ptr_oo(state());
}

uint32_t boon_browser_scene_len(void)
{
  return BrowserAbi_boon_browser_state_scene_len_oI(state());
}
