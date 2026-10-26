#include "llama.h"
#include <stdint.h>

// ABI v1: model loading and context initialization are supported;
// token generation is not yet exposed.
// Caller must provide a valid NUL-terminated UTF-8 filesystem path.
extern "C" {
__attribute__((visibility("default"))) int32_t allhub_llama_bridge_version(void) {
    return 1;
}
__attribute__((visibility("default"))) int32_t allhub_llama_inference_ready(void) {
    return 0;
}
// Returns 1 if the GGUF model and a small context can be initialized, 0 otherwise.
// Loading a large model may require substantial RAM and time.
__attribute__((visibility("default"))) int32_t allhub_llama_try_load_model(const char * path) {
    if (!path || !path[0]) return 0;
    llama_backend_init();
    llama_model_params params = llama_model_default_params();
    params.n_gpu_layers = 0;
    llama_model * model = llama_model_load_from_file(path, params);
    if (!model) return 0;
    llama_context_params context_params = llama_context_default_params();
    context_params.n_ctx = 512;
    context_params.n_batch = 128;
    llama_context * context = llama_init_from_model(model, context_params);
    if (!context) {
        llama_model_free(model);
        return 0;
    }
    llama_free(context);
    llama_model_free(model);
    return 1;
}
}
