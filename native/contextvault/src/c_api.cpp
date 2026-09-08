#include "internal.h"
#include "tinypredict/tinypredict.h"

#include <exception>

namespace {
thread_local std::string g_last_error;

template <typename Fn>
int call_guarded(Fn&& fn) {
    try {
        g_last_error.clear();
        return fn(g_last_error);
    } catch (const std::exception& ex) {
        g_last_error = ex.what();
        return TP_INTERNAL_ERROR;
    } catch (...) {
        g_last_error = "Unknown internal error";
        return TP_INTERNAL_ERROR;
    }
}
}

extern "C" {

int tp_build_predictor(
    const char* corpus_path,
    const char* predictor_path,
    const std::uint32_t vocabulary_size,
    const std::uint32_t top_k
) {
    if (!corpus_path || !predictor_path) {
        g_last_error = "corpus_path and predictor_path are required";
        return TP_INVALID_ARGUMENT;
    }
    return call_guarded([&](std::string& error) {
        const int result = tp::build_predictor_impl(
            corpus_path,
            predictor_path,
            vocabulary_size,
            top_k,
            error
        );
        if (result == 0) return TP_OK;
        return result == 1 ? TP_INVALID_ARGUMENT : TP_IO_ERROR;
    });
}

int tp_encode_file(
    const char* input_path,
    const char* output_path,
    const char* predictor_path
) {
    if (!input_path || !output_path || !predictor_path) {
        g_last_error = "input_path, output_path, and predictor_path are required";
        return TP_INVALID_ARGUMENT;
    }
    return call_guarded([&](std::string& error) {
        const int result = tp::encode_file_impl(input_path, output_path, predictor_path, error);
        return result == 0 ? TP_OK : TP_IO_ERROR;
    });
}

int tp_decode_file(
    const char* input_path,
    const char* output_path,
    const char* predictor_path
) {
    if (!input_path || !output_path || !predictor_path) {
        g_last_error = "input_path, output_path, and predictor_path are required";
        return TP_INVALID_ARGUMENT;
    }
    return call_guarded([&](std::string& error) {
        const int result = tp::decode_file_impl(input_path, output_path, predictor_path, error);
        switch (result) {
            case 0: return TP_OK;
            case 2: return TP_IO_ERROR;
            case 3: return TP_FORMAT_ERROR;
            case 4: return TP_PREDICTOR_MISMATCH;
            case 5: return TP_CHECKSUM_ERROR;
            default: return TP_INTERNAL_ERROR;
        }
    });
}

const char* tp_last_error(void) {
    return g_last_error.c_str();
}

} // extern "C"

