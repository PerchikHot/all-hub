#include <stdint.h>

// ABI handshake for the future llama.cpp runtime. This bridge currently
// exposes no model-loading or token-generation functions.
#if defined(__GNUC__)
#define ALLHUB_EXPORT __attribute__((visibility("default")))
#else
#define ALLHUB_EXPORT
#endif

ALLHUB_EXPORT int32_t allhub_llama_bridge_version(void) {
    return 1;
}

ALLHUB_EXPORT int32_t allhub_llama_inference_ready(void) {
    return 0;
}
