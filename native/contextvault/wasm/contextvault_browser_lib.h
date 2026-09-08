#pragma once

#include <cstddef>
#include <cstdint>

extern "C" {

struct CvBrowserDigestResult {
    char* json = nullptr;
    std::size_t json_size = 0;
    char* error = nullptr;
    std::size_t error_size = 0;
};

CvBrowserDigestResult cv_digest_chatgpt_json_summary(
    const std::uint8_t* json_bytes,
    std::size_t json_size,
    const char* source_name
);

int cv_digest_chatgpt_json_summary_out(
    const std::uint8_t* json_bytes,
    std::size_t json_size,
    const char* source_name,
    CvBrowserDigestResult* out_result
);

CvBrowserDigestResult cv_digest_chatgpt_json_to_markdown(
    const std::uint8_t* json_bytes,
    std::size_t json_size,
    const char* options_json
);

int cv_digest_chatgpt_json_to_markdown_out(
    const std::uint8_t* json_bytes,
    std::size_t json_size,
    const char* options_json,
    CvBrowserDigestResult* out_result
);

void cv_free_browser_digest_result(CvBrowserDigestResult result);

void cv_free_browser_digest_result_ptr(CvBrowserDigestResult* result);

}
