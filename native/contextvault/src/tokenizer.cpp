#include "internal.h"

#include <array>
#include <cstring>

namespace tp {

namespace {

constexpr auto kPhraseTokens = std::to_array<std::string_view>({
    "Project update:",
    "project update:",
    "Project update",
    "project update",
    "Project status:",
    "Release note:",
    "release note:",
    "The next step is",
    "the next step is",
    "the next step is to",
    "next step is",
    "next step is to",
    "We need to",
    "we need to",
    "Please note:",
    "Please note",
    "please note",
    "Please note that",
    "please note that",
    "Please check",
    "please check",
    "Let me know",
    "let me know",
    "Let me know if",
    "let me know if",
    "Thank you",
    "thank you",
    "As soon as",
    "as soon as",
    "As soon as possible",
    "as soon as possible",
    "The project was",
    "the project was",
    "The demo is",
    "the demo is",
    "The codec is",
    "the codec is",
    "The encoder must stay",
    "the encoder must stay",
    "The decoder must stay",
    "the decoder must stay",
    "The predictor should",
    "the predictor should",
    "The fallback must stay",
    "the fallback must stay",
    "keep the predictor stable",
    "keep the decoder exact",
    "keep the output exact",
    "keep the fallback safe",
    "keep the build stable",
    "please review",
    "Please review",
    "please verify",
    "Please verify",
    "how are you doing",
    "How are you doing",
    "how are you",
    "How are you",
    "in the",
    "of the",
    "to the",
    "in other words",
    "In other words",
    "for example",
    "For example",
    "for instance",
    "For instance",
    "as a result",
    "As a result",
    "in addition",
    "In addition",
    "on the other hand",
    "On the other hand",
    "at the same time",
    "At the same time",
    "the result is",
    "the output is",
    "the final result",
    "the output should",
});

enum class ByteClass : std::uint8_t {
    Word,
    Space,
    Newline,
    Punct,
    Utf8,
    Raw,
};

ByteClass classify_byte(const std::uint8_t byte) {
    if (is_word_byte(byte)) {
        return ByteClass::Word;
    }
    if (byte == '\n' || byte == '\r') {
        return ByteClass::Newline;
    }
    if (byte == ' ' || byte == '\t' || byte == '\v' || byte == '\f') {
        return ByteClass::Space;
    }
    if (byte >= 0x80u) {
        return ByteClass::Utf8;
    }
    if (byte >= 0x20u && byte <= 0x7eu) {
        return ByteClass::Punct;
    }
    return ByteClass::Raw;
}

std::optional<std::string_view> match_phrase(const std::span<const std::uint8_t> bytes, const std::size_t pos) {
    std::string_view best;
    for (const auto phrase : kPhraseTokens) {
        const std::size_t len = phrase.size();
        if (len <= best.size()) {
            continue;
        }
        if (pos + len > bytes.size()) {
            continue;
        }
        if (std::memcmp(bytes.data() + pos, phrase.data(), len) == 0) {
            best = phrase;
        }
    }
    if (best.empty()) {
        return std::nullopt;
    }
    return best;
}

Segment::Kind to_segment_kind(const ByteClass cls) {
    return cls == ByteClass::Raw ? Segment::Kind::Raw : Segment::Kind::Token;
}

} // namespace

bool is_word_byte(const std::uint8_t byte) {
    return (byte >= 'A' && byte <= 'Z') ||
           (byte >= 'a' && byte <= 'z') ||
           (byte >= '0' && byte <= '9') ||
           byte == '_' || byte == '\'';
}

bool is_boundary_token(std::string_view token) {
    if (token.empty()) {
        return false;
    }
    for (const char ch : token) {
        if (ch == '\n' || ch == '\r') {
            return true;
        }
    }
    return token == "." || token == "!" || token == "?";
}

std::vector<Segment> tokenize_exact(const std::span<const std::uint8_t> bytes) {
    std::vector<Segment> segments;
    if (bytes.empty()) {
        return segments;
    }

    std::size_t pos = 0;
    while (pos < bytes.size()) {
        if (const auto phrase = match_phrase(bytes, pos); phrase.has_value()) {
            segments.push_back({Segment::Kind::Token, pos, phrase->size()});
            pos += phrase->size();
            continue;
        }

        const ByteClass current = classify_byte(bytes[pos]);
        const std::size_t start = pos;

        if (current == ByteClass::Punct || current == ByteClass::Raw) {
            segments.push_back({to_segment_kind(current), start, 1});
            ++pos;
            continue;
        }

        ++pos;
        while (pos < bytes.size()) {
            if (match_phrase(bytes, pos).has_value()) {
                break;
            }
            const ByteClass next = classify_byte(bytes[pos]);
            if (next != current) {
                break;
            }
            ++pos;
        }

        segments.push_back({to_segment_kind(current), start, pos - start});
    }

    return segments;
}

} // namespace tp
