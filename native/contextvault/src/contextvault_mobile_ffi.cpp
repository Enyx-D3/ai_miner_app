#include "../wasm/contextvault_browser_lib.h"

#include <cstdint>
#include <fstream>
#include <string>
#include <vector>

namespace {
thread_local std::string g_last_error;

bool read_all_bytes(const char* path, std::vector<std::uint8_t>& out) {
    if (path == nullptr || path[0] == '\0') {
        g_last_error = "JSON path is empty";
        return false;
    }

    std::ifstream input(path, std::ios::binary | std::ios::ate);
    if (!input) {
        g_last_error = "Unable to open combined ChatGPT JSON file";
        return false;
    }

    const std::streamoff size = input.tellg();
    if (size < 0) {
        g_last_error = "Unable to determine combined ChatGPT JSON size";
        return false;
    }

    input.seekg(0, std::ios::beg);
    out.resize(static_cast<std::size_t>(size));
    if (size > 0 && !input.read(reinterpret_cast<char*>(out.data()), size)) {
        g_last_error = "Unable to read combined ChatGPT JSON file";
        return false;
    }
    return true;
}
}  // namespace

extern "C" char* cv_mobile_digest_markdown_file(
    const char* json_path,
    const char* options_json
) {
    g_last_error.clear();
    std::vector<std::uint8_t> bytes;
    if (!read_all_bytes(json_path, bytes)) {
        return nullptr;
    }

    CvBrowserDigestResult result = cv_digest_chatgpt_json_to_markdown(
        bytes.empty() ? nullptr : bytes.data(),
        bytes.size(),
        options_json
    );

    if (result.error != nullptr) {
        g_last_error.assign(result.error, result.error_size);
        cv_free_browser_digest_result(result);
        return nullptr;
    }

    char* output = result.json;
    result.json = nullptr;
    result.json_size = 0;
    cv_free_browser_digest_result(result);
    return output;
}

extern "C" const char* cv_mobile_last_error() {
    return g_last_error.c_str();
}

extern "C" void cv_mobile_free_string(char* value) {
    delete[] value;
}
