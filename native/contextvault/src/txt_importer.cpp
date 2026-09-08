#include "internal.h"

#include <algorithm>
#include <cctype>
#include <charconv>
#include <limits>
#include <memory>
#include <sstream>

namespace tp {

namespace {

constexpr std::size_t kTxtAtom002WindowChars = 4096u;

struct JsonValue {
    enum class Kind : std::uint8_t { Null, Bool, Number, String, Array, Object };

    Kind kind = Kind::Null;
    bool bool_value = false;
    std::string string_value;
    std::string number_text;
    std::shared_ptr<std::vector<JsonValue>> array_value;
    std::shared_ptr<std::unordered_map<std::string, JsonValue>> object_value;
};

class JsonParser {
public:
    JsonParser(std::string_view text, std::string& error) : text_(text), error_(error) {}

    bool parse(JsonValue& out) {
        skip_ws();
        if (!parse_value(out)) {
            return false;
        }
        skip_ws();
        if (!eof()) {
            set_error("Unexpected trailing JSON content");
            return false;
        }
        return true;
    }

private:
    std::string_view text_;
    std::size_t pos_ = 0;
    std::string& error_;

    bool eof() const noexcept { return pos_ >= text_.size(); }

    char peek() const noexcept {
        return eof() ? '\0' : text_[pos_];
    }

    char get() noexcept {
        return eof() ? '\0' : text_[pos_++];
    }

    void skip_ws() noexcept {
        while (!eof()) {
            const unsigned char ch = static_cast<unsigned char>(peek());
            if (ch == ' ' || ch == '\t' || ch == '\r' || ch == '\n') {
                ++pos_;
            } else {
                break;
            }
        }
    }

    void set_error(const std::string& message) {
        if (error_.empty()) {
            error_ = message;
        }
    }

    static void append_utf8(std::string& out, char32_t codepoint) {
        if (codepoint <= 0x7Fu) {
            out.push_back(static_cast<char>(codepoint));
        } else if (codepoint <= 0x7FFu) {
            out.push_back(static_cast<char>(0xC0u | (codepoint >> 6)));
            out.push_back(static_cast<char>(0x80u | (codepoint & 0x3Fu)));
        } else if (codepoint <= 0xFFFFu) {
            out.push_back(static_cast<char>(0xE0u | (codepoint >> 12)));
            out.push_back(static_cast<char>(0x80u | ((codepoint >> 6) & 0x3Fu)));
            out.push_back(static_cast<char>(0x80u | (codepoint & 0x3Fu)));
        } else {
            out.push_back(static_cast<char>(0xF0u | (codepoint >> 18)));
            out.push_back(static_cast<char>(0x80u | ((codepoint >> 12) & 0x3Fu)));
            out.push_back(static_cast<char>(0x80u | ((codepoint >> 6) & 0x3Fu)));
            out.push_back(static_cast<char>(0x80u | (codepoint & 0x3Fu)));
        }
    }

    static std::uint32_t hex_digit(char ch) {
        if (ch >= '0' && ch <= '9') return static_cast<std::uint32_t>(ch - '0');
        if (ch >= 'a' && ch <= 'f') return static_cast<std::uint32_t>(10 + ch - 'a');
        if (ch >= 'A' && ch <= 'F') return static_cast<std::uint32_t>(10 + ch - 'A');
        return 0xFFFFFFFFu;
    }

    bool parse_string(std::string& out) {
        if (get() != '"') {
            set_error("Expected JSON string");
            return false;
        }

        while (!eof()) {
            const char ch = get();
            if (ch == '"') {
                return true;
            }
            if (ch != '\\') {
                out.push_back(ch);
                continue;
            }
            if (eof()) {
                set_error("Unterminated JSON escape");
                return false;
            }
            const char esc = get();
            switch (esc) {
                case '"': out.push_back('"'); break;
                case '\\': out.push_back('\\'); break;
                case '/': out.push_back('/'); break;
                case 'b': out.push_back('\b'); break;
                case 'f': out.push_back('\f'); break;
                case 'n': out.push_back('\n'); break;
                case 'r': out.push_back('\r'); break;
                case 't': out.push_back('\t'); break;
                case 'u': {
                    if (pos_ + 4 > text_.size()) {
                        set_error("Invalid JSON unicode escape");
                        return false;
                    }
                    std::uint32_t codepoint = 0;
                    for (int i = 0; i < 4; ++i) {
                        const std::uint32_t digit = hex_digit(text_[pos_ + static_cast<std::size_t>(i)]);
                        if (digit == 0xFFFFFFFFu) {
                            set_error("Invalid JSON unicode escape");
                            return false;
                        }
                        codepoint = static_cast<std::uint32_t>((codepoint << 4) | digit);
                    }
                    pos_ += 4;

                    if (codepoint >= 0xD800u && codepoint <= 0xDBFFu) {
                        if (pos_ + 6 > text_.size() || text_[pos_] != '\\' || text_[pos_ + 1] != 'u') {
                            set_error("Invalid JSON surrogate pair");
                            return false;
                        }
                        pos_ += 2;
                        std::uint32_t low = 0;
                        for (int i = 0; i < 4; ++i) {
                            const std::uint32_t digit = hex_digit(text_[pos_ + static_cast<std::size_t>(i)]);
                            if (digit == 0xFFFFFFFFu) {
                                set_error("Invalid JSON unicode escape");
                                return false;
                            }
                            low = static_cast<std::uint32_t>((low << 4) | digit);
                        }
                        pos_ += 4;
                        if (low < 0xDC00u || low > 0xDFFFu) {
                            set_error("Invalid JSON surrogate pair");
                            return false;
                        }
                        const char32_t full = static_cast<char32_t>(
                            0x10000u + ((codepoint - 0xD800u) << 10) + (low - 0xDC00u)
                        );
                        append_utf8(out, full);
                    } else {
                        append_utf8(out, static_cast<char32_t>(codepoint));
                    }
                    break;
                }
                default:
                    set_error("Unsupported JSON escape");
                    return false;
            }
        }

        set_error("Unterminated JSON string");
        return false;
    }

    bool parse_number(std::string& out) {
        const std::size_t start = pos_;
        if (peek() == '-') {
            ++pos_;
        }
        if (!std::isdigit(static_cast<unsigned char>(peek()))) {
            set_error("Invalid JSON number");
            return false;
        }
        if (peek() == '0') {
            ++pos_;
        } else {
            while (std::isdigit(static_cast<unsigned char>(peek()))) {
                ++pos_;
            }
        }
        if (peek() == '.') {
            ++pos_;
            if (!std::isdigit(static_cast<unsigned char>(peek()))) {
                set_error("Invalid JSON number");
                return false;
            }
            while (std::isdigit(static_cast<unsigned char>(peek()))) {
                ++pos_;
            }
        }
        if (peek() == 'e' || peek() == 'E') {
            ++pos_;
            if (peek() == '+' || peek() == '-') {
                ++pos_;
            }
            if (!std::isdigit(static_cast<unsigned char>(peek()))) {
                set_error("Invalid JSON number");
                return false;
            }
            while (std::isdigit(static_cast<unsigned char>(peek()))) {
                ++pos_;
            }
        }
        out.assign(text_.substr(start, pos_ - start));
        return true;
    }

    bool parse_literal(std::string_view literal) {
        if (text_.substr(pos_, literal.size()) != literal) {
            return false;
        }
        pos_ += literal.size();
        return true;
    }

    bool parse_array(JsonValue& out) {
        if (get() != '[') {
            set_error("Expected JSON array");
            return false;
        }
        out.kind = JsonValue::Kind::Array;
        out.array_value = std::make_shared<std::vector<JsonValue>>();
        skip_ws();
        if (consume(']')) {
            return true;
        }
        while (true) {
            JsonValue element;
            if (!parse_value(element)) {
                return false;
            }
            out.array_value->push_back(std::move(element));
            skip_ws();
            if (consume(']')) {
                return true;
            }
            if (!consume(',')) {
                set_error("Expected ',' or ']' in JSON array");
                return false;
            }
            skip_ws();
        }
    }

    bool parse_object(JsonValue& out) {
        if (get() != '{') {
            set_error("Expected JSON object");
            return false;
        }
        out.kind = JsonValue::Kind::Object;
        out.object_value = std::make_shared<std::unordered_map<std::string, JsonValue>>();
        skip_ws();
        if (consume('}')) {
            return true;
        }
        while (true) {
            std::string key;
            if (!parse_string(key)) {
                return false;
            }
            skip_ws();
            if (!consume(':')) {
                set_error("Expected ':' in JSON object");
                return false;
            }
            skip_ws();
            JsonValue value;
            if (!parse_value(value)) {
                return false;
            }
            (*out.object_value)[std::move(key)] = std::move(value);
            skip_ws();
            if (consume('}')) {
                return true;
            }
            if (!consume(',')) {
                set_error("Expected ',' or '}' in JSON object");
                return false;
            }
            skip_ws();
        }
    }

    bool consume(char expected) {
        if (peek() != expected) {
            return false;
        }
        ++pos_;
        return true;
    }

    bool parse_value(JsonValue& out) {
        skip_ws();
        if (eof()) {
            set_error("Unexpected end of JSON input");
            return false;
        }
        const char ch = peek();
        if (ch == '{') {
            return parse_object(out);
        }
        if (ch == '[') {
            return parse_array(out);
        }
        if (ch == '"') {
            out.kind = JsonValue::Kind::String;
            out.string_value.clear();
            return parse_string(out.string_value);
        }
        if (ch == '-' || std::isdigit(static_cast<unsigned char>(ch))) {
            out.kind = JsonValue::Kind::Number;
            out.number_text.clear();
            return parse_number(out.number_text);
        }
        if (parse_literal("true")) {
            out.kind = JsonValue::Kind::Bool;
            out.bool_value = true;
            return true;
        }
        if (parse_literal("false")) {
            out.kind = JsonValue::Kind::Bool;
            out.bool_value = false;
            return true;
        }
        if (parse_literal("null")) {
            out.kind = JsonValue::Kind::Null;
            return true;
        }
        set_error("Invalid JSON value");
        return false;
    }
};

const JsonValue* object_find(const JsonValue& value, std::string_view key) {
    if (value.kind != JsonValue::Kind::Object || !value.object_value) {
        return nullptr;
    }
    const auto it = value.object_value->find(std::string(key));
    if (it == value.object_value->end()) {
        return nullptr;
    }
    return &it->second;
}

bool value_to_string(const JsonValue& value, std::string& out) {
    if (value.kind == JsonValue::Kind::String) {
        out = value.string_value;
        return true;
    }
    if (value.kind == JsonValue::Kind::Number) {
        out = value.number_text;
        return true;
    }
    return false;
}

std::string join_text_parts(const JsonValue& value) {
    std::string text;
    if (value.kind == JsonValue::Kind::String) {
        return value.string_value;
    }
    if (value.kind == JsonValue::Kind::Array && value.array_value) {
        bool first = true;
        for (const auto& part : *value.array_value) {
            if (part.kind == JsonValue::Kind::String) {
                if (!first) {
                    text.push_back('\n');
                }
                text += part.string_value;
                first = false;
            }
        }
    }
    return text;
}

struct ChatMessageRecord {
    std::string conversation_id;
    std::string conversation_title;
    std::string message_id;
    std::string role;
    std::string timestamp;
    std::uint64_t order_hint = 0;
    std::string text;
};

bool extract_chat_message(const JsonValue& node, const std::string& conversation_id, const std::string& conversation_title, ChatMessageRecord& out) {
    if (node.kind != JsonValue::Kind::Object) {
        return false;
    }

    const JsonValue* message = object_find(node, "message");
    if (!message) {
        return false;
    }
    if (message->kind != JsonValue::Kind::Object) {
        return false;
    }

    out.conversation_id = conversation_id;
    out.conversation_title = conversation_title;

    if (const JsonValue* id_value = object_find(*message, "id")) {
        value_to_string(*id_value, out.message_id);
    }
    if (out.message_id.empty()) {
        out.message_id = "message";
    }

    if (!conversation_id.empty()) {
        out.message_id = conversation_id + ":" + out.message_id;
    }

    if (const JsonValue* author = object_find(*message, "author")) {
        if (author->kind == JsonValue::Kind::Object) {
            if (const JsonValue* role = object_find(*author, "role")) {
                value_to_string(*role, out.role);
            }
        }
    }
    if (out.role.empty()) {
        out.role = "unknown";
    }

    if (const JsonValue* create_time = object_find(*message, "create_time")) {
        value_to_string(*create_time, out.timestamp);
    }

    if (const JsonValue* content = object_find(*message, "content")) {
        if (content->kind == JsonValue::Kind::Object) {
            if (const JsonValue* parts = object_find(*content, "parts")) {
                out.text = join_text_parts(*parts);
            }
            if (out.text.empty()) {
                if (const JsonValue* text = object_find(*content, "text")) {
                    out.text = join_text_parts(*text);
                }
            }
        } else {
            out.text = join_text_parts(*content);
        }
    }

    if (out.text.empty()) {
        return false;
    }

    if (const JsonValue* create_time = object_find(*message, "create_time")) {
        if (create_time->kind == JsonValue::Kind::Number) {
            const auto from_chars_result = std::from_chars(
                create_time->number_text.data(),
                create_time->number_text.data() + create_time->number_text.size(),
                out.order_hint
            );
            if (from_chars_result.ec != std::errc{}) {
                out.order_hint = 0;
            }
        }
    }

    return true;
}

bool parse_chatgpt_conversation(
    const JsonValue& conversation,
    TxtImportRecord& record,
    std::uint64_t& paragraph_index,
    const bool compute_paragraph_checksums
) {
    if (conversation.kind != JsonValue::Kind::Object) {
        return false;
    }

    std::string conversation_id;
    if (const JsonValue* id = object_find(conversation, "id")) {
        value_to_string(*id, conversation_id);
    }
    std::string conversation_title;
    if (const JsonValue* title = object_find(conversation, "title")) {
        value_to_string(*title, conversation_title);
    }

    std::vector<ChatMessageRecord> messages;
    if (const JsonValue* mapping = object_find(conversation, "mapping")) {
        if (mapping->kind == JsonValue::Kind::Object && mapping->object_value) {
            messages.reserve(mapping->object_value->size());
            for (const auto& [unused_key, node] : *mapping->object_value) {
                ChatMessageRecord message;
                if (extract_chat_message(node, conversation_id, conversation_title, message)) {
                    messages.emplace_back(std::move(message));
                }
            }
        }
    } else if (const JsonValue* messages_value = object_find(conversation, "messages")) {
        if (messages_value->kind == JsonValue::Kind::Array && messages_value->array_value) {
            for (const auto& node : *messages_value->array_value) {
                ChatMessageRecord message;
                if (extract_chat_message(node, conversation_id, conversation_title, message)) {
                    messages.emplace_back(std::move(message));
                }
            }
        }
    }

    if (messages.empty()) {
        return false;
    }

    std::stable_sort(messages.begin(), messages.end(), [](const ChatMessageRecord& lhs, const ChatMessageRecord& rhs) {
        if (lhs.order_hint != rhs.order_hint) {
            return lhs.order_hint < rhs.order_hint;
        }
        if (lhs.timestamp != rhs.timestamp) {
            return lhs.timestamp < rhs.timestamp;
        }
        return lhs.message_id < rhs.message_id;
    });

    for (auto& message : messages) {
        TxtParagraphRecord paragraph;
        paragraph.message_id = message.message_id;
        paragraph.conversation_title = message.conversation_title;
        paragraph.role = message.role;
        paragraph.timestamp = message.timestamp;
        paragraph.paragraph_index = static_cast<std::size_t>(paragraph_index++);
        paragraph.start_offset = 0;
        paragraph.end_offset = 0;
        paragraph.start_line = 0;
        paragraph.end_line = 0;
        paragraph.text = std::move(message.text);
        if (compute_paragraph_checksums) {
            paragraph.checksum = fnv1a64(std::span<const std::uint8_t>(
                reinterpret_cast<const std::uint8_t*>(paragraph.text.data()),
                paragraph.text.size()
            ));
        }
        record.paragraphs.emplace_back(std::move(paragraph));
    }

    if (record.title.empty() && !conversation_title.empty()) {
        record.title = conversation_title;
    }
    return true;
}

} // namespace

TxtImportRecord import_chatgpt_bytes(
    std::span<const std::uint8_t> bytes,
    const std::filesystem::path& source_path,
    std::string& error,
    const bool compute_paragraph_checksums
) {
    error.clear();

    std::string text(bytes.begin(), bytes.end());
    if (text.size() >= 3 &&
        static_cast<unsigned char>(text[0]) == 0xEF &&
        static_cast<unsigned char>(text[1]) == 0xBB &&
        static_cast<unsigned char>(text[2]) == 0xBF) {
        text.erase(0, 3);
    }

    JsonValue root;
    JsonParser parser(std::string_view(text), error);
    if (!parser.parse(root)) {
        return {};
    }

    TxtImportRecord record;
    record.source_path = source_path;
    record.title = source_path.stem().string();
    record.source_kind = ImportSourceKind::ChatGPT;
    record.source_checksum = fnv1a64(bytes);

    std::uint64_t paragraph_index = 0;
    bool any_messages = false;

    if (root.kind == JsonValue::Kind::Array && root.array_value) {
                for (const auto& item : *root.array_value) {
                    if (parse_chatgpt_conversation(item, record, paragraph_index, compute_paragraph_checksums)) {
                        any_messages = true;
                    }
                }
    } else if (root.kind == JsonValue::Kind::Object) {
        if (const JsonValue* conversations = object_find(root, "conversations")) {
            if (conversations->kind == JsonValue::Kind::Array && conversations->array_value) {
                for (const auto& item : *conversations->array_value) {
                    if (parse_chatgpt_conversation(item, record, paragraph_index, compute_paragraph_checksums)) {
                        any_messages = true;
                    }
                }
            }
        } else if (parse_chatgpt_conversation(root, record, paragraph_index, compute_paragraph_checksums)) {
            any_messages = true;
        }
    }

    if (!any_messages) {
        error = "No ChatGPT conversation messages found";
        return {};
    }

    return record;
}

TxtImportRecord import_chatgpt_file(
    const std::filesystem::path& path,
    std::string& error,
    const bool compute_paragraph_checksums
) {
    error.clear();

    const auto bytes = read_file(path, error);
    if (!error.empty()) {
        return {};
    }

    return import_chatgpt_bytes(
        std::span<const std::uint8_t>(bytes.data(), bytes.size()),
        path,
        error,
        compute_paragraph_checksums
    );
}

namespace {

bool is_line_blank(std::span<const std::uint8_t> line) {
    for (const std::uint8_t byte : line) {
        if (byte != static_cast<std::uint8_t>(' ') &&
            byte != static_cast<std::uint8_t>('\t') &&
            byte != static_cast<std::uint8_t>('\r')) {
            return false;
        }
    }
    return true;
}

std::size_t line_ending_length(std::span<const std::uint8_t> data, std::size_t line_end) {
    if (line_end >= data.size()) {
        return 0;
    }
    if (data[line_end] == static_cast<std::uint8_t>('\r')) {
        if (line_end + 1 < data.size() && data[line_end + 1] == static_cast<std::uint8_t>('\n')) {
            return 2;
        }
        return 1;
    }
    if (data[line_end] == static_cast<std::uint8_t>('\n')) {
        return 1;
    }
    return 0;
}

std::string trim_copy(std::string_view text) {
    std::size_t start = 0;
    std::size_t end = text.size();
    while (start < end) {
        const char ch = text[start];
        if (ch == ' ' || ch == '\t' || ch == '\r' || ch == '\n' || ch == '\v' || ch == '\f') {
            ++start;
        } else {
            break;
        }
    }
    while (end > start) {
        const char ch = text[end - 1];
        if (ch == ' ' || ch == '\t' || ch == '\r' || ch == '\n' || ch == '\v' || ch == '\f') {
            --end;
        } else {
            break;
        }
    }
    return std::string(text.substr(start, end - start));
}

std::string lower_ascii(std::string_view text) {
    std::string out;
    out.reserve(text.size());
    for (const unsigned char raw_ch : text) {
        out.push_back(static_cast<char>(std::tolower(raw_ch)));
    }
    return out;
}

int month_number_from_name(std::string_view word) {
    const std::string lower = lower_ascii(word);
    if (lower == "jan" || lower == "january") return 1;
    if (lower == "feb" || lower == "february") return 2;
    if (lower == "mar" || lower == "march") return 3;
    if (lower == "apr" || lower == "april") return 4;
    if (lower == "may") return 5;
    if (lower == "jun" || lower == "june") return 6;
    if (lower == "jul" || lower == "july") return 7;
    if (lower == "aug" || lower == "august") return 8;
    if (lower == "sep" || lower == "sept" || lower == "september") return 9;
    if (lower == "oct" || lower == "october") return 10;
    if (lower == "nov" || lower == "november") return 11;
    if (lower == "dec" || lower == "december") return 12;
    return 0;
}

bool is_date_separator(const char ch) {
    return ch == '-' || ch == '/' || ch == '.';
}

std::size_t skip_text_spaces(std::string_view text, std::size_t pos) {
    while (pos < text.size()) {
        const unsigned char ch = static_cast<unsigned char>(text[pos]);
        if (std::isspace(ch) == 0) {
            break;
        }
        ++pos;
    }
    return pos;
}

bool is_digit_text(std::string_view text) {
    return !text.empty() && std::all_of(text.begin(), text.end(), [](const char ch) {
        return std::isdigit(static_cast<unsigned char>(ch)) != 0;
    });
}

bool parse_uint(std::string_view text, int& out) {
    if (!is_digit_text(text)) {
        return false;
    }
    try {
        out = std::stoi(std::string(text));
        return true;
    } catch (...) {
        return false;
    }
}

std::string zero_pad_int(int value, int width) {
    std::string out = std::to_string(value);
    while (static_cast<int>(out.size()) < width) {
        out.insert(out.begin(), '0');
    }
    return out;
}

bool is_numeric_separator(const char ch) {
    return ch == ',' || ch == '.';
}

std::string normalize_numeric_token(std::string_view token) {
    std::string out;
    out.reserve(token.size());
    for (const char ch : token) {
        if (std::isdigit(static_cast<unsigned char>(ch))) {
            out.push_back(ch);
        } else if (ch == '.' || ch == '-') {
            out.push_back(ch);
        }
    }
    return out;
}

bool is_currency_prefix(std::string_view text, std::size_t pos, std::size_t& prefix_len) {
    prefix_len = 0;
    if (pos >= text.size()) {
        return false;
    }
    if (text[pos] == '$') {
        prefix_len = 1;
        return true;
    }
    if (pos + 3 <= text.size()) {
        const std::string lower = lower_ascii(text.substr(pos, 3));
        if (lower == "usd" || lower == "eur" || lower == "gbp" || lower == "jpy" || lower == "cny") {
            prefix_len = 3;
            return true;
        }
    }
    return false;
}

bool is_currency_suffix(std::string_view text, std::size_t pos, std::size_t& suffix_len) {
    suffix_len = 0;
    if (pos >= text.size()) {
        return false;
    }
    const std::string lower = lower_ascii(text.substr(pos));
    if (lower.rfind("usd", 0) == 0 || lower.rfind("eur", 0) == 0 || lower.rfind("gbp", 0) == 0 ||
        lower.rfind("jpy", 0) == 0 || lower.rfind("cny", 0) == 0) {
        suffix_len = 3;
        return true;
    }
    if (lower.rfind("million", 0) == 0) {
        suffix_len = 7;
        return true;
    }
    if (lower.rfind("billion", 0) == 0) {
        suffix_len = 7;
        return true;
    }
    if (lower.rfind("thousand", 0) == 0) {
        suffix_len = 8;
        return true;
    }
    if (lower.rfind("m", 0) == 0 || lower.rfind("bn", 0) == 0 || lower.rfind("k", 0) == 0) {
        suffix_len = lower.rfind("bn", 0) == 0 ? 2 : 1;
        return true;
    }
    return false;
}

bool append_iso_date(
    std::string_view text,
    const std::size_t pos,
    const std::size_t paragraph_index,
    const std::size_t paragraph_offset,
    TxtImportRecord& record,
    std::size_t& consumed
) {
    consumed = 0;
    if (pos + 10 > text.size()) {
        return false;
    }
    const std::string_view candidate = text.substr(pos, 10);
    if (!std::isdigit(static_cast<unsigned char>(candidate[0])) ||
        !std::isdigit(static_cast<unsigned char>(candidate[1])) ||
        !std::isdigit(static_cast<unsigned char>(candidate[2])) ||
        !std::isdigit(static_cast<unsigned char>(candidate[3])) ||
        !is_date_separator(candidate[4]) ||
        !std::isdigit(static_cast<unsigned char>(candidate[5])) ||
        !std::isdigit(static_cast<unsigned char>(candidate[6])) ||
        !is_date_separator(candidate[7]) ||
        !std::isdigit(static_cast<unsigned char>(candidate[8])) ||
        !std::isdigit(static_cast<unsigned char>(candidate[9]))) {
        return false;
    }

    int year = 0;
    int month = 0;
    int day = 0;
    if (!parse_uint(candidate.substr(0, 4), year) ||
        !parse_uint(candidate.substr(5, 2), month) ||
        !parse_uint(candidate.substr(8, 2), day)) {
        return false;
    }
    if (month < 1 || month > 12 || day < 1 || day > 31) {
        return false;
    }

    TxtDateRecord date;
    date.paragraph_index = paragraph_index;
    date.start_offset = paragraph_offset + pos;
    date.end_offset = paragraph_offset + pos + 10;
    date.raw_text = std::string(candidate);
    date.normalized_date = zero_pad_int(year, 4) + "-" + zero_pad_int(month, 2) + "-" + zero_pad_int(day, 2);
    record.dates.emplace_back(std::move(date));
    consumed = 10;
    return true;
}

bool append_month_date(
    std::string_view text,
    const std::size_t pos,
    const std::size_t paragraph_index,
    const std::size_t paragraph_offset,
    TxtImportRecord& record,
    std::size_t& consumed
) {
    consumed = 0;
    std::size_t cursor = pos;
    std::string month_word;
    while (cursor < text.size() && std::isalpha(static_cast<unsigned char>(text[cursor]))) {
        month_word.push_back(text[cursor]);
        ++cursor;
    }
    const int month = month_number_from_name(month_word);
    if (month == 0) {
        return false;
    }
    cursor = skip_text_spaces(text, cursor);
    std::size_t day_start = cursor;
    while (cursor < text.size() && std::isdigit(static_cast<unsigned char>(text[cursor]))) {
        ++cursor;
    }
    if (cursor == day_start) {
        return false;
    }
    const std::string_view day_text = text.substr(day_start, cursor - day_start);
    int day = 0;
    if (!parse_uint(day_text, day) || day < 1 || day > 31) {
        return false;
    }
    cursor = skip_text_spaces(text, cursor);
    if (cursor < text.size() && text[cursor] == ',') {
        ++cursor;
    }
    cursor = skip_text_spaces(text, cursor);
    std::size_t year_start = cursor;
    while (cursor < text.size() && std::isdigit(static_cast<unsigned char>(text[cursor]))) {
        ++cursor;
    }
    if (cursor - year_start < 4) {
        return false;
    }
    const std::string_view year_text = text.substr(year_start, cursor - year_start);
    int year = 0;
    if (!parse_uint(year_text, year)) {
        return false;
    }
    if (year < 1000 || year > 9999) {
        return false;
    }

    TxtDateRecord date;
    date.paragraph_index = paragraph_index;
    date.start_offset = paragraph_offset + pos;
    date.end_offset = paragraph_offset + cursor;
    date.raw_text = std::string(text.substr(pos, cursor - pos));
    date.normalized_date = zero_pad_int(year, 4) + "-" + zero_pad_int(month, 2) + "-" + zero_pad_int(day, 2);
    record.dates.emplace_back(std::move(date));
    consumed = cursor - pos;
    return true;
}

struct ParagraphDateSpan {
    std::size_t start_offset = 0;
    std::size_t end_offset = 0;
};

void extract_dates_from_text(
    std::string_view text,
    const std::size_t paragraph_index,
    const std::size_t paragraph_offset,
    TxtImportRecord& record,
    std::vector<ParagraphDateSpan>& paragraph_date_spans
) {
    for (std::size_t pos = 0; pos < text.size(); ++pos) {
        std::size_t consumed = 0;
        if (append_iso_date(text, pos, paragraph_index, paragraph_offset, record, consumed)) {
            paragraph_date_spans.push_back(ParagraphDateSpan{
                paragraph_offset + pos,
                paragraph_offset + pos + consumed
            });
            pos += consumed > 0 ? consumed - 1 : 0;
            continue;
        }
        if (std::isalpha(static_cast<unsigned char>(text[pos])) &&
            append_month_date(text, pos, paragraph_index, paragraph_offset, record, consumed)) {
            paragraph_date_spans.push_back(ParagraphDateSpan{
                paragraph_offset + pos,
                paragraph_offset + pos + consumed
            });
            pos += consumed > 0 ? consumed - 1 : 0;
            continue;
        }
    }
}

void extract_numbers_from_text(
    std::string_view text,
    const std::size_t paragraph_index,
    const std::size_t paragraph_offset,
    TxtImportRecord& record,
    std::span<const ParagraphDateSpan> date_spans
) {
    std::size_t date_span_index = 0;
    auto advance_date_span = [&](const std::size_t absolute_offset) {
        while (date_span_index < date_spans.size() && date_spans[date_span_index].end_offset <= absolute_offset) {
            ++date_span_index;
        }
    };

    for (std::size_t pos = 0; pos < text.size(); ++pos) {
        const std::size_t absolute_pos = paragraph_offset + pos;
        advance_date_span(absolute_pos);
        if (date_span_index < date_spans.size() &&
            absolute_pos >= date_spans[date_span_index].start_offset &&
            absolute_pos < date_spans[date_span_index].end_offset) {
            pos = date_spans[date_span_index].end_offset > paragraph_offset
                ? date_spans[date_span_index].end_offset - paragraph_offset - 1u
                : pos;
            continue;
        }

        std::size_t cursor = pos;
        std::size_t prefix_len = 0;
        bool has_currency_prefix = false;
        if (is_currency_prefix(text, cursor, prefix_len)) {
            has_currency_prefix = true;
            cursor += prefix_len;
        }

        const std::size_t number_start = cursor;
        bool saw_digit = false;
        bool saw_decimal = false;
        while (cursor < text.size()) {
            const std::size_t absolute_cursor = paragraph_offset + cursor;
            advance_date_span(absolute_cursor);
            if (date_span_index < date_spans.size() &&
                absolute_cursor >= date_spans[date_span_index].start_offset &&
                absolute_cursor < date_spans[date_span_index].end_offset) {
                break;
            }
            const char ch = text[cursor];
            if (std::isdigit(static_cast<unsigned char>(ch))) {
                saw_digit = true;
                ++cursor;
                continue;
            }
            if (is_numeric_separator(ch)) {
                if (ch == '.' && !saw_decimal) {
                    saw_decimal = true;
                    ++cursor;
                    continue;
                }
                if (ch == ',' && saw_digit) {
                    ++cursor;
                    continue;
                }
            }
            break;
        }

        if (!saw_digit || cursor == number_start) {
            continue;
        }

        std::size_t suffix_pos = cursor;
        suffix_pos = skip_text_spaces(text, suffix_pos);

        bool is_percent = false;
        bool is_amount = has_currency_prefix;
        std::size_t suffix_len = 0;

        if (suffix_pos < text.size() && text[suffix_pos] == '%') {
            is_percent = true;
            ++suffix_pos;
        } else if (is_currency_suffix(text, suffix_pos, suffix_len)) {
            is_amount = true;
            suffix_pos += suffix_len;
        }

        const std::size_t raw_start = has_currency_prefix ? pos : number_start;
        const std::size_t raw_end = suffix_pos;
        const std::string raw_text = std::string(text.substr(raw_start, raw_end - raw_start));

        TxtNumericRecord numeric;
        numeric.paragraph_index = paragraph_index;
        numeric.start_offset = paragraph_offset + raw_start;
        numeric.end_offset = paragraph_offset + raw_end;
        numeric.raw_text = raw_text;
        numeric.normalized_value = normalize_numeric_token(raw_text);
        if (is_percent) {
            numeric.kind = TxtNumericKind::Percentage;
            numeric.normalized_value += "%";
        } else if (is_amount) {
            numeric.kind = TxtNumericKind::Amount;
        } else {
            numeric.kind = TxtNumericKind::Number;
        }
        record.numerics.emplace_back(std::move(numeric));

        pos = raw_end > 0 ? raw_end - 1 : pos;
    }
}

std::size_t count_words(std::string_view text) {
    std::size_t count = 0;
    bool in_word = false;
    for (const unsigned char raw_ch : text) {
        if (std::isalnum(raw_ch)) {
            if (!in_word) {
                ++count;
                in_word = true;
            }
        } else {
            in_word = false;
        }
    }
    return count;
}

bool looks_like_title_cased_text(std::string_view text) {
    bool saw_word = false;
    bool saw_title_cased_word = false;
    bool saw_lowercase_word = false;
    std::string word;

    auto flush_word = [&]() {
        if (word.empty()) {
            return;
        }
        saw_word = true;
        const unsigned char first = static_cast<unsigned char>(word.front());
        bool title_cased = std::isupper(first) != 0;
        bool has_lowercase = false;
        bool has_uppercase = false;
        for (const unsigned char ch : word) {
            if (std::islower(ch)) {
                has_lowercase = true;
            } else if (std::isupper(ch)) {
                has_uppercase = true;
            }
        }
        title_cased = title_cased || (has_uppercase && !has_lowercase);
        saw_title_cased_word = saw_title_cased_word || title_cased;
        saw_lowercase_word = saw_lowercase_word || (has_lowercase && !title_cased);
        word.clear();
    };

    for (const unsigned char raw_ch : text) {
        if (std::isalnum(raw_ch)) {
            word.push_back(static_cast<char>(raw_ch));
        } else {
            flush_word();
        }
    }
    flush_word();

    return saw_word && saw_title_cased_word && !saw_lowercase_word;
}

bool looks_like_heading_text(std::string_view text) {
    const std::string trimmed = trim_copy(text);
    if (trimmed.empty()) {
        return false;
    }

    const std::size_t word_count = count_words(trimmed);
    if (word_count == 0 || word_count > 14u || trimmed.size() > 140u) {
        return false;
    }

    const std::size_t newline_count = static_cast<std::size_t>(std::count(trimmed.begin(), trimmed.end(), '\n'));
    if (newline_count > 2u) {
        return false;
    }

    const char last = trimmed.back();
    if (last == '.' || last == '!' || last == '?' || last == ':' || last == ';') {
        return false;
    }

    bool has_alpha = false;
    bool all_caps = true;
    for (const unsigned char raw_ch : trimmed) {
        if (std::isalpha(raw_ch)) {
            has_alpha = true;
            if (std::islower(raw_ch)) {
                all_caps = false;
            }
        }
    }
    if (!has_alpha) {
        return false;
    }

    const bool title_cased = looks_like_title_cased_text(trimmed);
    if ((word_count <= 8u && (title_cased || all_caps)) || (word_count <= 4u && trimmed.size() <= 50u)) {
        return true;
    }

    const std::string lower = lower_ascii(trimmed);
    if (word_count <= 6u &&
        (lower.rfind("chapter ", 0) == 0 ||
         lower.rfind("section ", 0) == 0 ||
         lower.rfind("part ", 0) == 0 ||
         lower.rfind("page ", 0) == 0 ||
         lower.rfind("introduction", 0) == 0 ||
         lower.rfind("preface", 0) == 0 ||
         lower.rfind("conclusion", 0) == 0)) {
        return true;
    }

    return false;
}

void finalize_sections(TxtImportRecord& record) {
    record.sections.clear();
    if (record.paragraphs.empty()) {
        return;
    }

    TxtSectionRecord current;
    std::size_t next_section_index = 0;
    bool have_current = false;

    auto push_current = [&]() {
        if (!have_current) {
            return;
        }
        if (current.end_paragraph_index < current.start_paragraph_index) {
            current.end_paragraph_index = current.start_paragraph_index;
        }
        record.sections.emplace_back(current);
    };

    auto start_section = [&](const std::size_t paragraph_index, const std::string& heading_text) {
        push_current();
        current = {};
        current.section_index = next_section_index++;
        current.heading_paragraph_index = paragraph_index;
        current.start_paragraph_index = paragraph_index;
        current.end_paragraph_index = paragraph_index;
        current.heading_text = heading_text;
        have_current = true;
    };

    const std::string first_paragraph_text = trim_copy(record.paragraphs.front().text);
    start_section(
        0,
        record.paragraphs.front().is_heading && !first_paragraph_text.empty()
            ? first_paragraph_text
            : record.title
    );

    for (std::size_t i = 0; i < record.paragraphs.size(); ++i) {
        auto& paragraph = record.paragraphs[i];
        const bool heading_like = paragraph.is_heading;

        paragraph.section_index = current.section_index;

        if (i == 0) {
            if (heading_like) {
                current.heading_text = trim_copy(paragraph.text);
            }
            current.end_paragraph_index = 0;
            continue;
        }

        if (heading_like) {
            current.end_paragraph_index = i - 1;
            start_section(i, trim_copy(paragraph.text));
            paragraph.section_index = current.section_index;
            continue;
        }

        current.end_paragraph_index = i;
    }

    push_current();

    if (record.sections.empty()) {
        TxtSectionRecord fallback;
        fallback.section_index = 0;
        fallback.heading_paragraph_index = 0;
        fallback.start_paragraph_index = 0;
        fallback.end_paragraph_index = record.paragraphs.size() - 1;
        fallback.heading_text = record.title;
        record.sections.emplace_back(std::move(fallback));
        for (auto& paragraph : record.paragraphs) {
            paragraph.section_index = 0;
        }
    }
}

void build_fixed_char_shards(TxtImportRecord& record, const std::size_t source_size) {
    record.char_window_chars = kTxtAtom002WindowChars;
    record.char_shards.clear();
    if (source_size == 0) {
        return;
    }

    const std::size_t shard_count = (source_size + kTxtAtom002WindowChars - 1u) / kTxtAtom002WindowChars;
    record.char_shards.reserve(shard_count);
    for (std::size_t shard_index = 0, start = 0; start < source_size; ++shard_index, start += kTxtAtom002WindowChars) {
        const std::size_t end = std::min<std::size_t>(start + kTxtAtom002WindowChars, source_size);
        record.char_shards.push_back(TxtImportRecord::TxtCharShardRecord{shard_index, start, end});
    }
}

void finalize_paragraph(
    const std::span<const std::uint8_t> data,
    const std::size_t start_offset,
    const std::size_t end_offset,
    const std::size_t start_line,
    const std::size_t end_line,
    const std::size_t paragraph_index,
    TxtImportRecord& record,
    const bool compute_paragraph_checksums
) {
    if (end_offset <= start_offset) {
        return;
    }

    TxtParagraphRecord paragraph;
    paragraph.paragraph_index = paragraph_index;
    paragraph.start_offset = start_offset;
    paragraph.end_offset = end_offset;
    paragraph.start_line = start_line;
    paragraph.end_line = end_line;
    const std::size_t paragraph_size = end_offset - start_offset;
    paragraph.text.assign(
        reinterpret_cast<const char*>(data.data() + start_offset),
        paragraph_size
    );
    paragraph.is_heading = looks_like_heading_text(paragraph.text);
    std::uint64_t checksum = 14695981039346656037ull;
    const std::uint8_t* paragraph_bytes = data.data() + start_offset;
    for (std::size_t i = 0; i < paragraph_size; ++i) {
        checksum ^= paragraph_bytes[i];
        checksum *= 1099511628211ull;
    }
    if (compute_paragraph_checksums) {
        paragraph.checksum = checksum;
    }
    record.paragraphs.emplace_back(std::move(paragraph));
    const auto& stored = record.paragraphs.back();
    std::vector<ParagraphDateSpan> paragraph_date_spans;
    extract_dates_from_text(stored.text, stored.paragraph_index, stored.start_offset, record, paragraph_date_spans);
    extract_numbers_from_text(stored.text, stored.paragraph_index, stored.start_offset, record, paragraph_date_spans);
}

} // namespace

TxtImportRecord import_txt_bytes(
    std::span<const std::uint8_t> bytes,
    const std::filesystem::path& source_path,
    std::string& error,
    const bool compute_paragraph_checksums
) {
    error.clear();

    TxtImportRecord record;
    record.source_path = source_path;
    record.title = source_path.stem().string();
    record.source_kind = ImportSourceKind::Txt;
    record.source_checksum = fnv1a64(bytes);

    const std::span<const std::uint8_t> data(bytes.data(), bytes.size());
    std::size_t cursor = 0;
    std::size_t line_number = 1;
    std::size_t paragraph_start = 0;
    std::size_t paragraph_start_line = 0;
    std::size_t paragraph_end = 0;
    std::size_t paragraph_index = 0;
    bool in_paragraph = false;

    while (cursor < data.size()) {
        const std::size_t line_start = cursor;
        while (cursor < data.size() &&
               data[cursor] != static_cast<std::uint8_t>('\n') &&
               data[cursor] != static_cast<std::uint8_t>('\r')) {
            ++cursor;
        }
        const std::size_t line_end = cursor;
        const std::span<const std::uint8_t> line(data.data() + line_start, line_end - line_start);
        const bool blank = is_line_blank(line);
        const std::size_t eol_len = line_ending_length(data, cursor);
        const std::size_t next_cursor = cursor + eol_len;

        if (blank) {
            if (in_paragraph) {
                finalize_paragraph(
                    data,
                    paragraph_start,
                    paragraph_end,
                    paragraph_start_line,
                    line_number - 1,
                    paragraph_index++,
                    record,
                    compute_paragraph_checksums
                );
                in_paragraph = false;
            }
            cursor = next_cursor;
            line_number += 1;
            continue;
        }

        if (!in_paragraph) {
            paragraph_start = line_start;
            paragraph_start_line = line_number;
            in_paragraph = true;
        }

        paragraph_end = line_end + eol_len;
        if (paragraph_end > data.size()) {
            paragraph_end = data.size();
        }

        cursor = next_cursor;
        line_number += 1;
    }

    if (in_paragraph) {
        finalize_paragraph(
            data,
            paragraph_start,
            paragraph_end,
            paragraph_start_line,
            line_number - 1,
            paragraph_index,
            record,
            compute_paragraph_checksums
        );
    }

    finalize_sections(record);
    build_fixed_char_shards(record, data.size());

    return record;
}

TxtImportRecord import_txt_file(const std::filesystem::path& path, std::string& error, const bool compute_paragraph_checksums) {
    error.clear();

    const auto bytes = read_file(path, error);
    if (!error.empty()) {
        return {};
    }

    return import_txt_bytes(std::span<const std::uint8_t>(bytes.data(), bytes.size()), path, error, compute_paragraph_checksums);
}

TxtImportRecord import_source_record(
    const ImportSourceKind kind,
    const std::filesystem::path& path,
    std::string& error,
    const bool compute_paragraph_checksums
) {
    error.clear();
    switch (kind) {
        case ImportSourceKind::Txt:
            return import_txt_file(path, error, compute_paragraph_checksums);
        case ImportSourceKind::ChatGPT:
            return import_chatgpt_file(path, error, compute_paragraph_checksums);
    }

    error = "Unknown import source kind";
    return {};
}

namespace {

void append_escaped(std::string& out, std::string_view text) {
    for (const char ch : text) {
        if (ch == '\\') {
            out += "\\\\";
        } else if (ch == '\n') {
            out += "\\n";
        } else if (ch == '\r') {
            out += "\\r";
        } else if (ch == '\t') {
            out += "\\t";
        } else {
            out.push_back(ch);
        }
    }
}

} // namespace

bool write_txt_manifest(
    const TxtImportRecord& record,
    const std::filesystem::path& path,
    std::string& error,
    const std::optional<double> compression_time_ms
) {
    std::string out;
    out.reserve(1024 + record.paragraphs.size() * 256);

    out += "format=ContextVaultImportManifest\n";
    out += "source_kind=";
    out += (record.source_kind == ImportSourceKind::ChatGPT) ? "chatgpt" : "txt";
    out += "\n";
    out += "source_path=";
    append_escaped(out, record.source_path.string());
    out += "\n";
    out += "title=";
    append_escaped(out, record.title);
    out += "\n";
    out += "source_checksum=" + std::to_string(record.source_checksum) + "\n";
    out += "char_window_chars=" + std::to_string(record.char_window_chars) + "\n";
    out += "char_shard_count=" + std::to_string(record.char_shards.size()) + "\n";
    out += "section_count=" + std::to_string(record.sections.size()) + "\n";
    out += "date_count=" + std::to_string(record.dates.size()) + "\n";
    out += "paragraph_count=" + std::to_string(record.paragraphs.size()) + "\n";
    if (compression_time_ms.has_value()) {
        out += "compression_time_ms=" + std::to_string(*compression_time_ms) + "\n";
    }

    for (const auto& section : record.sections) {
        out += "\n[section ";
        out += std::to_string(section.section_index);
        out += "]\n";
        out += "heading_paragraph_index=" + std::to_string(section.heading_paragraph_index) + "\n";
        out += "start_paragraph_index=" + std::to_string(section.start_paragraph_index) + "\n";
        out += "end_paragraph_index=" + std::to_string(section.end_paragraph_index) + "\n";
        out += "heading_text=";
        append_escaped(out, section.heading_text);
        out += "\n";
    }

    for (const auto& shard : record.char_shards) {
        out += "\n[char_shard ";
        out += std::to_string(shard.shard_index);
        out += "]\n";
        out += "start_offset=" + std::to_string(shard.start_offset) + "\n";
        out += "end_offset=" + std::to_string(shard.end_offset) + "\n";
    }

    for (const auto& paragraph : record.paragraphs) {
        out += "\n[paragraph ";
        out += std::to_string(paragraph.paragraph_index);
        out += "]\n";
        if (!paragraph.message_id.empty()) {
            out += "message_id=";
            append_escaped(out, paragraph.message_id);
            out += "\n";
        }
        if (!paragraph.conversation_title.empty()) {
            out += "conversation_title=";
            append_escaped(out, paragraph.conversation_title);
            out += "\n";
        }
        if (!paragraph.role.empty()) {
            out += "role=";
            append_escaped(out, paragraph.role);
            out += "\n";
        }
        if (!paragraph.timestamp.empty()) {
            out += "timestamp=";
            append_escaped(out, paragraph.timestamp);
            out += "\n";
        }
        out += "section_index=" + std::to_string(paragraph.section_index) + "\n";
        out += "is_heading=";
        out += paragraph.is_heading ? "yes" : "no";
        out += "\n";
        out += "start_offset=" + std::to_string(paragraph.start_offset) + "\n";
        out += "end_offset=" + std::to_string(paragraph.end_offset) + "\n";
        out += "checksum=" + std::to_string(paragraph.checksum) + "\n";
    }

    const std::vector<std::uint8_t> bytes(out.begin(), out.end());
    return write_file(path, bytes, error);
}

} // namespace tp


