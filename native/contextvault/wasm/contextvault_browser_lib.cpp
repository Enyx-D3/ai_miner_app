#include "contextvault_browser_lib.h"

#include "internal.h"

#include <cstring>
#include <filesystem>
#include <cctype>
#include <algorithm>
#include <cmath>
#include <ctime>
#include <iomanip>
#include <map>
#include <sstream>
#include <span>
#include <string>
#include <string_view>
#include <unordered_set>
#include <vector>

namespace {

char* copy_to_c_buffer(const std::string& text) {
    char* buffer = new char[text.size() + 1u];
    std::memcpy(buffer, text.data(), text.size());
    buffer[text.size()] = '\0';
    return buffer;
}

std::string json_escape(std::string_view text) {
    std::string out;
    out.reserve(text.size() + 16u);
    for (const unsigned char ch : text) {
        switch (ch) {
            case '\\': out += "\\\\"; break;
            case '"': out += "\\\""; break;
            case '\b': out += "\\b"; break;
            case '\f': out += "\\f"; break;
            case '\n': out += "\\n"; break;
            case '\r': out += "\\r"; break;
            case '\t': out += "\\t"; break;
            default:
                if (ch < 0x20u) {
                    constexpr char digits[] = "0123456789abcdef";
                    out += "\\u00";
                    out.push_back(digits[(ch >> 4u) & 0x0fu]);
                    out.push_back(digits[ch & 0x0fu]);
                } else {
                    out.push_back(static_cast<char>(ch));
                }
                break;
        }
    }
    return out;
}

std::string trim_copy(std::string_view text) {
    std::size_t start = 0u;
    std::size_t end = text.size();
    while (start < end && std::isspace(static_cast<unsigned char>(text[start]))) {
        ++start;
    }
    while (end > start && std::isspace(static_cast<unsigned char>(text[end - 1u]))) {
        --end;
    }
    return std::string(text.substr(start, end - start));
}

std::string lower_ascii(std::string_view text) {
    std::string out;
    out.reserve(text.size());
    for (const unsigned char ch : text) {
        out.push_back(static_cast<char>(std::tolower(ch)));
    }
    return out;
}

std::string markdown_escape_inline(std::string_view text) {
    std::string out;
    out.reserve(text.size());
    for (const char ch : text) {
        if (ch == '\\' || ch == '`' || ch == '*' || ch == '_' || ch == '[' || ch == ']') {
            out.push_back('\\');
        }
        out.push_back(ch);
    }
    return out;
}

CvBrowserDigestResult make_error_result(const std::string& error) {
    CvBrowserDigestResult result;
    result.error = copy_to_c_buffer(error);
    result.error_size = error.size();
    return result;
}

CvBrowserDigestResult make_json_result(const std::string& json) {
    CvBrowserDigestResult result;
    result.json = copy_to_c_buffer(json);
    result.json_size = json.size();
    return result;
}

std::string markdown_escape_table_cell(std::string_view text) {
    const std::string escaped = markdown_escape_inline(text);
    std::string out;
    out.reserve(escaped.size());
    for (const char ch : escaped) {
        switch (ch) {
            case '|': out += "\\|"; break;
            case '\n':
            case '\r': out += ' '; break;
            default: out.push_back(ch); break;
        }
    }
    return out;
}

std::string demote_markdown_headings(std::string_view text, const std::size_t minimum_level) {
    std::stringstream input{std::string(text)};
    std::ostringstream output;
    std::string line;
    while (std::getline(input, line)) {
        std::size_t hashes = 0u;
        while (hashes < line.size() && line[hashes] == '#') {
            ++hashes;
        }
        if (hashes > 0u && hashes < line.size() && std::isspace(static_cast<unsigned char>(line[hashes]))) {
            const std::size_t level = std::min<std::size_t>(6u, minimum_level + hashes - 1u);
            output << std::string(level, '#') << line.substr(hashes);
        } else {
            output << line;
        }
        output << '\n';
    }
    return output.str();
}

std::string human_readable_timestamp(std::string_view timestamp) {
    const std::string raw = trim_copy(timestamp);
    if (raw.empty()) {
        return "";
    }

    try {
        std::size_t parsed_chars = 0u;
        const double epoch_seconds = std::stod(raw, &parsed_chars);
        if (parsed_chars == 0u || !std::isfinite(epoch_seconds) || epoch_seconds < 0.0) {
            return raw;
        }

        const std::time_t seconds = static_cast<std::time_t>(epoch_seconds);
        std::tm local_time{};
#if defined(_WIN32)
        if (localtime_s(&local_time, &seconds) != 0) {
            return raw;
        }
#else
        if (localtime_r(&seconds, &local_time) == nullptr) {
            return raw;
        }
#endif
        std::ostringstream out;
        out << std::put_time(&local_time, "%Y-%m-%d %H:%M");
        return out.str();
    } catch (const std::exception&) {
        return raw;
    }
}

std::string markdown_heading_text(std::string_view text) {
    std::string out;
    out.reserve(text.size());
    for (const char ch : text) {
        if (ch == '\r') {
            continue;
        }
        out.push_back(ch == '\n' ? ' ' : ch);
    }
    return out.empty() ? "Untitled Conversation" : out;
}

std::string slugify(std::string_view text) {
    std::string slug;
    slug.reserve(text.size());
    bool last_was_separator = true;
    for (const unsigned char ch : text) {
        if (std::isalnum(ch)) {
            slug.push_back(static_cast<char>(std::tolower(ch)));
            last_was_separator = false;
        } else if (!last_was_separator) {
            slug.push_back('_');
            last_was_separator = true;
        }
    }
    while (!slug.empty() && slug.back() == '_') {
        slug.pop_back();
    }
    if (slug.empty()) {
        slug = "conversation";
    }
    if (slug.size() > 64u) {
        slug.resize(64u);
        while (!slug.empty() && slug.back() == '_') {
            slug.pop_back();
        }
    }
    return slug.empty() ? "conversation" : slug;
}

std::string role_label(std::string_view role) {
    if (role == "user") {
        return "Prompt";
    }
    if (role == "assistant") {
        return "Answer";
    }
    if (role == "system") {
        return "System";
    }
    if (role.empty()) {
        return "Message";
    }
    std::string out(role);
    out[0] = static_cast<char>(std::toupper(static_cast<unsigned char>(out[0])));
    return out;
}

std::size_t parse_max_messages_per_file(const char* options_json) {
    constexpr std::size_t default_value = 100u;
    if (options_json == nullptr) {
        return default_value;
    }

    const std::string_view options(options_json);
    const std::string_view key = "max_messages_per_file";
    const std::size_t key_pos = options.find(key);
    if (key_pos == std::string_view::npos) {
        return default_value;
    }
    const std::size_t colon_pos = options.find(':', key_pos + key.size());
    if (colon_pos == std::string_view::npos) {
        return default_value;
    }
    std::size_t pos = colon_pos + 1u;
    while (pos < options.size() && std::isspace(static_cast<unsigned char>(options[pos]))) {
        ++pos;
    }
    std::size_t value = 0u;
    bool has_digit = false;
    while (pos < options.size() && std::isdigit(static_cast<unsigned char>(options[pos]))) {
        has_digit = true;
        value = (value * 10u) + static_cast<std::size_t>(options[pos] - '0');
        ++pos;
    }
    if (!has_digit || value == 0u) {
        return default_value;
    }
    return std::min<std::size_t>(100u, value);
}

bool parse_include_system(const char* options_json) {
    if (options_json == nullptr) {
        return false;
    }

    const std::string_view options(options_json);
    const std::string_view key = "include_system";
    const std::size_t key_pos = options.find(key);
    if (key_pos == std::string_view::npos) {
        return false;
    }
    const std::size_t colon_pos = options.find(':', key_pos + key.size());
    if (colon_pos == std::string_view::npos) {
        return false;
    }
    std::size_t pos = colon_pos + 1u;
    while (pos < options.size() && std::isspace(static_cast<unsigned char>(options[pos]))) {
        ++pos;
    }
    return options.substr(pos, 4u) == "true";
}

bool should_include_paragraph(const tp::TxtParagraphRecord& paragraph, const bool include_system) {
    if (trim_copy(paragraph.text).empty()) {
        return false;
    }
    if (include_system) {
        return true;
    }
    const std::string role = lower_ascii(paragraph.role);
    return role != "system" && role != "tool";
}

struct MarkdownFile {
    std::string path;
    std::string content;
};

void append_json_file(std::ostringstream& out, const MarkdownFile& file) {
    out << "{\"path\":\"" << json_escape(file.path) << "\",";
    out << "\"content\":\"" << json_escape(file.content) << "\"}";
}

struct TopicPart {
    std::string title;
    std::vector<const tp::TxtParagraphRecord*> paragraphs;
    std::size_t atom_count = 0u;
    std::size_t part_number = 1u;
    std::size_t part_count = 1u;
};

std::string numbered_topic_filename(const std::size_t index, std::string_view title, const std::size_t part_number, const std::size_t part_count) {
    std::string number = std::to_string(index);
    while (number.size() < 3u) {
        number.insert(number.begin(), '0');
    }
    std::string path = number + "_" + slugify(title);
    if (part_count > 1u) {
        std::string part = std::to_string(part_number);
        while (part.size() < 3u) {
            part.insert(part.begin(), '0');
        }
        path += "_part_" + part;
    }
    path += ".md";
    return path;
}

void append_compact_reference_table(std::ostream& out, const std::vector<const tp::TxtParagraphRecord*>& paragraphs) {
    out << "## References\n\n";
    out << "| Ref | Type | Thread | Time | Message ID |\n";
    out << "|---|---|---|---|---|\n";
    for (std::size_t i = 0u; i < paragraphs.size(); ++i) {
        const auto& paragraph = *paragraphs[i];
        out << "| R" << (i + 1u);
        out << " | " << markdown_escape_table_cell(role_label(lower_ascii(paragraph.role)));
        out << " | " << markdown_escape_table_cell(paragraph.conversation_title);
        out << " | " << markdown_escape_table_cell(human_readable_timestamp(paragraph.timestamp));
        out << " | `" << markdown_escape_table_cell(paragraph.message_id) << "` |\n";
    }
    out << "\n";
}

void append_compact_message(std::ostream& out, const tp::TxtParagraphRecord& paragraph) {
    out << demote_markdown_headings(trim_copy(paragraph.text), 4u) << "\n";
}

std::string render_compact_topic_part(const TopicPart& part) {
    std::ostringstream out;
    out << "# " << markdown_escape_inline(part.title);
    if (part.part_count > 1u) {
        out << " (Part " << part.part_number << " of " << part.part_count << ")";
    }
    out << "\n\n";

    out << "## Threads Included\n\n";
    out << "- " << markdown_escape_inline(part.title) << "\n\n";

    out << "## Conversation\n\n";
    std::size_t exchange_number = 0u;
    for (std::size_t i = 0u; i < part.paragraphs.size(); ++i) {
        const auto& paragraph = *part.paragraphs[i];
        const std::string role = lower_ascii(paragraph.role.empty() ? "unknown" : paragraph.role);
        if (role == "user") {
            out << "### Exchange " << ++exchange_number << "\n\n";
            out << "**Prompt** [R" << (i + 1u) << "]\n\n";
        } else if (role == "assistant") {
            if (exchange_number == 0u) {
                out << "### Exchange " << ++exchange_number << "\n\n";
            }
            out << "**Answer** [R" << (i + 1u) << "]\n\n";
        } else {
            if (exchange_number == 0u) {
                out << "### Exchange " << ++exchange_number << "\n\n";
            }
            out << "**" << markdown_escape_inline(role_label(role)) << "** [R" << (i + 1u) << "]\n\n";
        }
        append_compact_message(out, paragraph);
    }
    if (part.paragraphs.empty()) {
        out << "_No conversation messages available for this topic._\n\n";
    }

    out << "## Metadata\n\n";
    out << "- Atoms in topic part: " << part.atom_count << "\n";
    out << "- Messages: " << part.paragraphs.size() << "\n";
    out << "- Threads included: 1\n";
    if (part.part_count > 1u) {
        out << "- Part: " << part.part_number << " of " << part.part_count << "\n";
    }
    out << "- Mode: compact\n";
    out << "- LLM: disabled\n\n";

    append_compact_reference_table(out, part.paragraphs);
    return out.str();
}

} // namespace

extern "C" CvBrowserDigestResult cv_digest_chatgpt_json_summary(
    const std::uint8_t* json_bytes,
    const std::size_t json_size,
    const char* source_name
) {
    if (json_bytes == nullptr && json_size != 0u) {
        return make_error_result("json_bytes is null");
    }

    std::string error;
    const std::filesystem::path source_path = source_name == nullptr || source_name[0] == '\0'
        ? std::filesystem::path("browser_chatgpt_export.json")
        : std::filesystem::path(source_name);

    const tp::TxtImportRecord record = tp::import_chatgpt_bytes(
        std::span<const std::uint8_t>(json_bytes, json_size),
        source_path,
        error,
        false
    );
    if (!error.empty()) {
        return make_error_result(error);
    }

    const tp::TxtAtomIndex atom_index = tp::build_txt_atom_index(record, error);
    if (!error.empty()) {
        return make_error_result(error);
    }

    std::unordered_set<std::string> thread_titles;
    for (const auto& paragraph : record.paragraphs) {
        if (!paragraph.conversation_title.empty()) {
            thread_titles.insert(paragraph.conversation_title);
        }
    }

    std::ostringstream out;
    out << "{";
    out << "\"source\":\"" << json_escape(source_path.string()) << "\",";
    out << "\"title\":\"" << json_escape(record.title) << "\",";
    out << "\"paragraphs\":" << record.paragraphs.size() << ",";
    out << "\"atoms\":" << atom_index.atoms.size() << ",";
    out << "\"threads\":" << thread_titles.size() << ",";
    out << "\"source_kind\":\"chatgpt\"";
    out << "}";

    return make_json_result(out.str());
}

extern "C" int cv_digest_chatgpt_json_summary_out(
    const std::uint8_t* json_bytes,
    const std::size_t json_size,
    const char* source_name,
    CvBrowserDigestResult* out_result
) {
    if (out_result == nullptr) {
        return 0;
    }

    *out_result = cv_digest_chatgpt_json_summary(json_bytes, json_size, source_name);
    return out_result->error == nullptr ? 1 : 0;
}

extern "C" CvBrowserDigestResult cv_digest_chatgpt_json_to_markdown(
    const std::uint8_t* json_bytes,
    const std::size_t json_size,
    const char* options_json
) {
    if (json_bytes == nullptr && json_size != 0u) {
        return make_error_result("json_bytes is null");
    }

    std::string error;
    const tp::TxtImportRecord record = tp::import_chatgpt_bytes(
        std::span<const std::uint8_t>(json_bytes, json_size),
        std::filesystem::path("browser_chatgpt_export.json"),
        error,
        false
    );
    if (!error.empty()) {
        return make_error_result(error);
    }

    const tp::TxtAtomIndex atom_index = tp::build_txt_atom_index(record, error);
    if (!error.empty()) {
        return make_error_result(error);
    }

    const std::size_t max_messages_per_file = parse_max_messages_per_file(options_json);
    const bool include_system = parse_include_system(options_json);
    std::vector<std::size_t> atom_counts_by_paragraph(record.paragraphs.size(), 0u);
    for (const auto& atom : atom_index.atoms) {
        if (atom.paragraph_index < atom_counts_by_paragraph.size()) {
            ++atom_counts_by_paragraph[atom.paragraph_index];
        }
    }

    std::map<std::string, std::vector<const tp::TxtParagraphRecord*>> threads;
    for (const auto& paragraph : record.paragraphs) {
        if (!should_include_paragraph(paragraph, include_system)) {
            continue;
        }
        std::string title = paragraph.conversation_title.empty()
            ? std::string("Untitled Conversation")
            : paragraph.conversation_title;
        threads[title].push_back(&paragraph);
    }

    std::map<std::string, std::size_t> atom_counts_by_thread;
    for (const auto& [title, paragraphs] : threads) {
        std::size_t atom_count = 0u;
        for (const auto* paragraph : paragraphs) {
            if (paragraph->paragraph_index < atom_counts_by_paragraph.size()) {
                atom_count += atom_counts_by_paragraph[paragraph->paragraph_index];
            }
        }
        atom_counts_by_thread[title] = atom_count;
    }

    std::vector<TopicPart> parts;
    for (const auto& [title, paragraphs] : threads) {
        const std::size_t part_count = std::max<std::size_t>(
            1u,
            (paragraphs.size() + max_messages_per_file - 1u) / max_messages_per_file
        );
        const std::size_t thread_atom_count = atom_counts_by_thread[title];
        for (std::size_t part_index = 0u; part_index < part_count; ++part_index) {
            const std::size_t start = part_index * max_messages_per_file;
            const std::size_t end = std::min<std::size_t>(paragraphs.size(), start + max_messages_per_file);
            TopicPart part;
            part.title = title;
            part.part_number = part_index + 1u;
            part.part_count = part_count;
            part.atom_count = part_count == 1u
                ? thread_atom_count
                : (thread_atom_count * (end - start) + paragraphs.size() - 1u) / std::max<std::size_t>(1u, paragraphs.size());
            part.paragraphs.insert(
                part.paragraphs.end(),
                paragraphs.begin() + static_cast<std::ptrdiff_t>(start),
                paragraphs.begin() + static_cast<std::ptrdiff_t>(end)
            );
            parts.emplace_back(std::move(part));
        }
    }

    std::vector<MarkdownFile> files;
    files.reserve(parts.size() + 2u);

    std::ostringstream index;
    index << "# ChatGPT Export Digest\n\n";
    index << "## Overview\n\n";
    index << "- Source: `browser_chatgpt_export.json`\n";
    index << "- Title: " << markdown_escape_inline(record.title) << "\n";
    index << "- Paragraphs: " << record.paragraphs.size() << "\n";
    index << "- Atoms: " << atom_index.atoms.size() << "\n";
    index << "- Topic chapters: " << threads.size() << "\n";
    index << "- Topic files written: " << parts.size() << "\n";
    index << "- Max messages per file: " << max_messages_per_file << "\n";
    index << "- Mode: compact\n";
    index << "- LLM: disabled\n\n";
    index << "## Topics\n\n";

    std::size_t topic_index = 0u;
    for (const auto& part : parts) {
        ++topic_index;
        const std::string path = "topics/" + numbered_topic_filename(topic_index, part.title, part.part_number, part.part_count);
        index << topic_index << ". [" << markdown_escape_inline(part.title);
        if (part.part_count > 1u) {
            index << " (Part " << part.part_number << " of " << part.part_count << ")";
        }
        index << "](" << path << ") - " << part.atom_count << " atoms, " << part.paragraphs.size() << " messages\n";

        files.push_back(MarkdownFile{path, render_compact_topic_part(part)});
    }

    files.insert(files.begin(), MarkdownFile{"index.md", index.str()});

    std::ostringstream stats;
    stats << "# Browser Processing Stats\n\n";
    stats << "- Paragraphs: " << record.paragraphs.size() << "\n";
    stats << "- Atoms: " << atom_index.atoms.size() << "\n";
    stats << "- Threads: " << threads.size() << "\n";
    stats << "- Topic files: " << parts.size() << "\n";
    stats << "- Max messages per file: " << max_messages_per_file << "\n";
    stats << "- Include system: " << (include_system ? "true" : "false") << "\n";
    stats << "- Mode: compact\n";
    stats << "- LLM: disabled\n";
    files.push_back(MarkdownFile{"stats/browser_processing_stats.md", stats.str()});

    std::ostringstream out;
    out << "{\"files\":[";
    for (std::size_t i = 0u; i < files.size(); ++i) {
        if (i != 0u) {
            out << ",";
        }
        append_json_file(out, files[i]);
    }
    out << "],\"stats\":{";
    out << "\"paragraphs\":" << record.paragraphs.size() << ",";
    out << "\"atoms\":" << atom_index.atoms.size() << ",";
    out << "\"threads\":" << threads.size() << ",";
    out << "\"topic_files\":" << parts.size();
    out << "}}";

    return make_json_result(out.str());
}

extern "C" int cv_digest_chatgpt_json_to_markdown_out(
    const std::uint8_t* json_bytes,
    const std::size_t json_size,
    const char* options_json,
    CvBrowserDigestResult* out_result
) {
    if (out_result == nullptr) {
        return 0;
    }

    *out_result = cv_digest_chatgpt_json_to_markdown(json_bytes, json_size, options_json);
    return out_result->error == nullptr ? 1 : 0;
}

extern "C" void cv_free_browser_digest_result(CvBrowserDigestResult result) {
    delete[] result.json;
    delete[] result.error;
}

extern "C" void cv_free_browser_digest_result_ptr(CvBrowserDigestResult* result) {
    if (result == nullptr) {
        return;
    }

    cv_free_browser_digest_result(*result);
    *result = CvBrowserDigestResult{};
}
