#include <stddef.h>
#include <stdint.h>
// This compile/link-only test does not execute on a device or inside Atlas.
typedef struct { float stability, difficulty, stability_fast; } AtlasState;
typedef struct { AtlasState memory; float interval_days; } AtlasChoice;
typedef struct { AtlasChoice again, hard, good, easy; } AtlasNext;
extern uint32_t atlas_fsrs7_engine_version(void);
extern uint32_t atlas_fsrs7_abi_version(void);
extern uint32_t atlas_fsrs7_parameter_count(void);
extern size_t atlas_fsrs7_state_size(void);
extern size_t atlas_fsrs7_output_size(void);
extern int32_t atlas_fsrs7_next(const AtlasState*, float, float, AtlasNext*);
int main(void) {
  AtlasNext out = {0};
  return (atlas_fsrs7_engine_version() == 7 && atlas_fsrs7_abi_version() == 1 &&
          atlas_fsrs7_parameter_count() == 34 && atlas_fsrs7_state_size() == 12 && atlas_fsrs7_output_size() == 64 &&
          atlas_fsrs7_next(NULL, 0.0f, 0.9f, &out) == 0) ? 0 : 1;
}
