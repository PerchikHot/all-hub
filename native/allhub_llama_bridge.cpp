#include "llama.h"
#include <stdint.h>
#include <vector>
#include <string>
#include <cstring>

// ABI v1: model verification and experimental one-shot token generation.
// Caller must provide a valid NUL-terminated UTF-8 filesystem path.
extern "C" {
__attribute__((visibility("default"))) int32_t allhub_llama_bridge_version(void) {
    return 1;
}
__attribute__((visibility("default"))) int32_t allhub_llama_inference_ready(void) {
    return 1;
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
// One-shot CPU generation; caller owns output buffer. Returns bytes written or negative error.
// Designed for short prompts and small quantized models on mobile.
__attribute__((visibility("default"))) int32_t allhub_llama_generate(
    const char * path, const char * prompt, char * output, int32_t capacity, int32_t max_tokens) {
    if (!path || !prompt || !output || capacity < 2 || max_tokens < 1) return -1;
    output[0] = 0;
    llama_backend_init();
    llama_model_params mp = llama_model_default_params();
    mp.n_gpu_layers = 0;
    llama_model * model = llama_model_load_from_file(path, mp);
    if (!model) return -2;
    llama_context_params cp = llama_context_default_params();
    cp.n_ctx = 2048;
    cp.n_batch = 512;
    llama_context * ctx = llama_init_from_model(model, cp);
    if (!ctx) { llama_model_free(model); return -3; }
    int32_t result = -4;
    llama_sampler * sampler = nullptr;
    do {
        const llama_vocab * vocab = llama_model_get_vocab(model);
        int count = -llama_tokenize(vocab, prompt, (int32_t)strlen(prompt), nullptr, 0, true, true);
        if (count <= 0 || count > 1536) break;
        std::vector<llama_token> tokens(count);
        count = llama_tokenize(vocab, prompt, (int32_t)strlen(prompt), tokens.data(), count, true, true);
        if (count <= 0) break;
        sampler = llama_sampler_init_greedy();
        if (!sampler) break;
        int32_t written = 0;
        bool ok = true;
        int32_t position = 0;
        for (int i = 0; i < max_tokens && i < 256; ++i) {
            llama_batch batch = llama_batch_get_one(tokens.data(), (int32_t)tokens.size());
            batch.pos = nullptr; // llama.cpp derives positions from the existing context
            if (llama_decode(ctx, batch) != 0) { ok = false; break; }
            const llama_token next = llama_sampler_sample(sampler, ctx, -1);
            if (llama_vocab_is_eog(vocab, next)) break;
            char piece[1024];
            int n = llama_token_to_piece(vocab, next, piece, sizeof(piece), 0, true);
            if (n < 0 || written + n >= capacity) break;
            memcpy(output + written, piece, n);
            written += n;
            output[written] = 0;
            tokens.assign(1, next);
        }
        result = ok ? written : -5;
    } while (false);
    if (sampler) llama_sampler_free(sampler);
    llama_free(ctx);
    llama_model_free(model);
    return result;
}
}
