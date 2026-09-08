#pragma once

#include <cstddef>
#include <cstdint>

#if defined(_WIN32) && defined(TINYPREDICT_BUILD_SHARED)
  #define TP_API __declspec(dllexport)
#else
  #define TP_API
#endif

#ifdef __cplusplus
extern "C" {
#endif

// Return codes. Zero means success.
enum tp_result {
    TP_OK = 0,
    TP_INVALID_ARGUMENT = 1,
    TP_IO_ERROR = 2,
    TP_FORMAT_ERROR = 3,
    TP_PREDICTOR_MISMATCH = 4,
    TP_CHECKSUM_ERROR = 5,
    TP_INTERNAL_ERROR = 6
};

// Build a static word-level unigram/bigram/trigram predictor from a UTF-8 or byte corpus.
// The tokenizer treats ASCII letters, digits, underscore, and apostrophe as WORD bytes.
TP_API int tp_build_predictor(
    const char* corpus_path,
    const char* predictor_path,
    std::uint32_t vocabulary_size,
    std::uint32_t top_k
);

// Encode a file using an installed static predictor.
TP_API int tp_encode_file(
    const char* input_path,
    const char* output_path,
    const char* predictor_path
);

// Decode a .tpc file using the exact predictor version used for encoding.
TP_API int tp_decode_file(
    const char* input_path,
    const char* output_path,
    const char* predictor_path
);

// Thread-local description of the most recent error from this library.
TP_API const char* tp_last_error(void);

#ifdef __cplusplus
}
#endif
