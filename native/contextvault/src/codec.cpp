#include "internal.h"

#include <algorithm>
#include <charconv>
#include <cstdlib>
#include <string>
#include <string_view>

namespace tp {

namespace {
constexpr std::array<std::string_view, 16> kPunctuationTokens = {
    " ",
    "\n",
    "\t",
    ".",
    ",",
    ":",
    ";",
    "\"",
    "(",
    ")",
    "[",
    "]",
    "{",
    "}",
    "/",
    "-"
};

std::optional<std::uint8_t> find_punctuation_token(std::string_view token) {
    for (std::size_t i = 0; i < kPunctuationTokens.size(); ++i) {
        if (kPunctuationTokens[i] == token) {
            return static_cast<std::uint8_t>(i);
        }
    }
    return std::nullopt;
}

int find_rank(const CandidateSpan candidates, const std::uint32_t token_id) {
    for (std::uint8_t i = 0; i < candidates.size; ++i) {
        if (candidates.data[i] == token_id) {
            return static_cast<int>(i);
        }
    }
    return -1;
}

std::size_t digits10(std::uint64_t value) {
    std::size_t digits = 1u;
    while (value >= 10u) {
        value /= 10u;
        ++digits;
    }
    return digits;
}

std::size_t raw_cost(std::string_view token) {
    return token.size() + static_cast<std::size_t>(std::count(token.begin(), token.end(), '~'));
}

std::size_t rank_cost(std::uint64_t rank_value) {
    return 4u + digits10(rank_value);
}

std::size_t punct_cost(std::uint8_t punct_index) {
    return 4u + digits10(punct_index);
}

std::size_t literal_ref_cost(std::uint64_t literal_index) {
    return 4u + digits10(literal_index);
}

std::size_t r1_run_cost(std::uint64_t count) {
    return 4u + digits10(count);
}

bool should_use_marker(const std::size_t marker_cost, const std::size_t raw_cost_value) {
    return marker_cost < raw_cost_value;
}

void append_text(std::vector<std::uint8_t>& out, std::string_view text) {
    out.insert(out.end(), text.begin(), text.end());
}

void append_escaped_raw(std::vector<std::uint8_t>& out, std::string_view token) {
    for (const char ch : token) {
        if (ch == '~') {
            out.push_back(static_cast<std::uint8_t>('~'));
            out.push_back(static_cast<std::uint8_t>('~'));
        } else {
            out.push_back(static_cast<std::uint8_t>(ch));
        }
    }
}

std::size_t escaped_raw_bytes(std::string_view token) {
    return raw_cost(token);
}

void append_rank_marker(std::vector<std::uint8_t>& out, std::uint64_t rank_value) {
    append_text(out, "~q[");
    append_text(out, std::to_string(rank_value));
    append_text(out, "]");
}

void append_punctuation_marker(std::vector<std::uint8_t>& out, std::uint8_t punct_index) {
    append_text(out, "~p[");
    append_text(out, std::to_string(punct_index));
    append_text(out, "]");
}

void append_literal_ref_marker(std::vector<std::uint8_t>& out, std::uint64_t literal_index) {
    append_text(out, "~l[");
    append_text(out, std::to_string(literal_index));
    append_text(out, "]");
}

void append_r1_run_marker(std::vector<std::uint8_t>& out, std::uint64_t count) {
    append_text(out, "~r[");
    append_text(out, std::to_string(count));
    append_text(out, "]");
}

void advance_context(
    std::uint32_t& previous_3,
    std::uint32_t& previous_2,
    std::uint32_t& previous_1,
    std::string_view token,
    const std::uint32_t token_id
) {
    if (is_boundary_token(token)) {
        previous_3 = kBosId;
        previous_2 = kBosId;
        previous_1 = kBosId;
        return;
    }
    previous_3 = previous_2;
    previous_2 = previous_1;
    previous_1 = token_id;
}

bool flush_raw_buffer(
    const std::vector<std::uint8_t>& raw_buffer,
    const Predictor& predictor,
    std::vector<std::string>& literal_table,
    std::unordered_map<std::string, std::uint64_t>& literal_to_index,
    std::vector<std::uint8_t>& output,
    std::uint32_t& previous_3,
    std::uint32_t& previous_2,
    std::uint32_t& previous_1,
    std::string& error
) {
    if (raw_buffer.empty()) {
        return true;
    }

    const auto segments = tokenize_exact(std::span<const std::uint8_t>(raw_buffer.data(), raw_buffer.size()));
    for (const auto& segment : segments) {
        const auto bytes = std::span<const std::uint8_t>(raw_buffer.data() + segment.offset, segment.length);
        const std::string_view token(reinterpret_cast<const char*>(bytes.data()), bytes.size());
        append_text(output, token);
        const std::string key(token);
        if (literal_to_index.find(key) == literal_to_index.end()) {
            literal_to_index.emplace(key, literal_table.size());
            literal_table.emplace_back(std::move(key));
        }
        const auto token_id = predictor.find_token_id(token).value_or(kUnkId);
        advance_context(previous_3, previous_2, previous_1, token, token_id);
    }
    error.clear();
    return true;
}

bool parse_unsigned(std::string_view text, std::uint64_t& value) {
    if (text.empty()) {
        return false;
    }
    const char* begin = text.data();
    const char* end = text.data() + text.size();
    const auto [ptr, ec] = std::from_chars(begin, end, value, 10);
    return ec == std::errc() && ptr == end;
}

bool parse_bracketed_unsigned(
    std::span<const std::uint8_t> input,
    std::size_t value_start,
    std::size_t& end,
    std::uint64_t& value
) {
    if (value_start >= input.size() || input[value_start] != static_cast<std::uint8_t>('[')) {
        return false;
    }
    end = value_start + 1u;
    while (end < input.size() && input[end] != static_cast<std::uint8_t>(']')) {
        ++end;
    }
    if (end >= input.size()) {
        return false;
    }
    const bool parsed = parse_unsigned(
        std::string_view(reinterpret_cast<const char*>(input.data() + value_start + 1u), end - (value_start + 1u)),
        value
    );
    ++end;
    return parsed;
}

bool decode_marker(
    std::span<const std::uint8_t> input,
    std::size_t& pos,
    const Predictor& predictor,
    std::vector<std::uint8_t>& output,
    std::vector<std::uint8_t>& raw_buffer,
    std::vector<std::string>& literal_table,
    std::unordered_map<std::string, std::uint64_t>& literal_to_index,
    std::uint32_t& previous_3,
    std::uint32_t& previous_2,
    std::uint32_t& previous_1,
    std::string& error
) {
    const auto flush_raw = [&]() -> bool {
        if (!flush_raw_buffer(raw_buffer, predictor, literal_table, literal_to_index, output, previous_3, previous_2, previous_1, error)) {
            return false;
        }
        raw_buffer.clear();
        return true;
    };

    const auto marker_snippet = [&](std::size_t pos) -> std::string {
        const std::size_t remaining = input.size() - pos;
        const std::size_t count = std::min<std::size_t>(remaining, 24u);
        return std::string(reinterpret_cast<const char*>(input.data() + pos), count);
    };

    const std::size_t size = input.size();
    if (pos >= size || input[pos] != static_cast<std::uint8_t>('~')) {
        error = "Expected control marker";
        return false;
    }
    if (pos + 1 >= size) {
        error = "Truncated control marker";
        return false;
    }

    const char next = static_cast<char>(input[pos + 1]);
    if (next == '~') {
        raw_buffer.push_back(static_cast<std::uint8_t>('~'));
        pos += 2;
        return true;
    }

    if (next == 'l') {
        std::size_t end = pos + 2;
        std::uint64_t literal_index = 0;
        bool parsed = false;
        if (end < size && input[end] == static_cast<std::uint8_t>('[')) {
            parsed = parse_bracketed_unsigned(input, end, end, literal_index);
        } else {
            while (end < size && input[end] >= static_cast<std::uint8_t>('0') && input[end] <= static_cast<std::uint8_t>('9')) {
                ++end;
            }
            parsed = parse_unsigned(std::string_view(reinterpret_cast<const char*>(input.data() + pos + 2), end - (pos + 2)), literal_index);
        }
        if (!parsed || literal_index >= literal_table.size()) {
            error = "Invalid literal reference";
            return false;
        }

        const std::string_view token = literal_table[static_cast<std::size_t>(literal_index)];
        append_text(output, token);
        const auto token_id = predictor.find_token_id(token).value_or(kUnkId);
        advance_context(previous_3, previous_2, previous_1, token, token_id);
        pos = end;
        return true;
    }

        if (next == 'r') {
            if (pos + 2 >= size || input[pos + 2] != static_cast<std::uint8_t>('[')) {
                error = "Invalid rank1 run at pos " + std::to_string(pos) + " near '" + marker_snippet(pos) + "'";
                return false;
            }
            std::size_t end = pos + 3;
            while (end < size && input[end] != static_cast<std::uint8_t>(']')) {
                ++end;
            }
            if (end >= size) {
                error = "Unterminated rank1 run at pos " + std::to_string(pos) + " near '" + marker_snippet(pos) + "'";
                return false;
            }
            std::uint64_t count = 0;
            if (!parse_unsigned(std::string_view(reinterpret_cast<const char*>(input.data() + pos + 3), end - (pos + 3)), count) || count == 0) {
                error = "Invalid rank1 run at pos " + std::to_string(pos) + " near '" + marker_snippet(pos) + "'";
                return false;
            }
            for (std::uint64_t i = 0; i < count; ++i) {
                const CandidateSpan candidates = predictor.predict(previous_3, previous_2, previous_1);
                if (candidates.size == 0) {
                    error = "Empty candidate list";
                    return false;
                }
                const std::uint32_t token_id = candidates.data[0];
                const std::string_view token = predictor.token_bytes(token_id);
                append_text(output, token);
                advance_context(previous_3, previous_2, previous_1, token, token_id);
            }
            pos = end + 1;
            return true;
        }

        if (next == 'q' || (next >= '1' && next <= '9')) {
            std::size_t end = pos + 2;
            std::uint64_t rank_value = 0;
            bool parsed = false;
            if (next == 'q') {
                parsed = parse_bracketed_unsigned(input, end, end, rank_value);
            } else {
                while (end < size && input[end] >= static_cast<std::uint8_t>('0') && input[end] <= static_cast<std::uint8_t>('9')) {
                    ++end;
                }
                parsed = parse_unsigned(std::string_view(reinterpret_cast<const char*>(input.data() + pos + 1), end - (pos + 1)), rank_value);
            }
            if (!parsed || rank_value < 1u || rank_value > 16u) {
                error = "Invalid rank marker";
                return false;
            }
            const CandidateSpan candidates = predictor.predict(previous_3, previous_2, previous_1);
            const std::uint64_t candidate_index = rank_value - 1u;
            if (candidate_index >= candidates.size) {
                error = "Rank exceeds current candidate list";
                return false;
            }
            const std::uint32_t token_id = candidates.data[static_cast<std::size_t>(candidate_index)];
            const std::string_view token = predictor.token_bytes(token_id);
            append_text(output, token);
            advance_context(previous_3, previous_2, previous_1, token, token_id);
            pos = end;
            return true;
        }

    if (next == 'p') {
        std::size_t end = pos + 2;
        std::uint64_t punct_index = 0;
        bool parsed = false;
        if (end < size && input[end] == static_cast<std::uint8_t>('[')) {
            parsed = parse_bracketed_unsigned(input, end, end, punct_index);
        } else {
            while (end < size && input[end] >= static_cast<std::uint8_t>('0') && input[end] <= static_cast<std::uint8_t>('9')) {
                ++end;
            }
            parsed = parse_unsigned(std::string_view(reinterpret_cast<const char*>(input.data() + pos + 2), end - (pos + 2)), punct_index);
        }
        if (!parsed || punct_index >= kPunctuationTokens.size()) {
            error = "Invalid punctuation marker";
            return false;
        }
        const std::string_view token = kPunctuationTokens[static_cast<std::size_t>(punct_index)];
        append_text(output, token);
        const auto token_id = predictor.find_token_id(token).value_or(kUnkId);
        advance_context(previous_3, previous_2, previous_1, token, token_id);
        pos = end;
        return true;
    }

    error = "Unknown control marker";
    return false;
}

} // namespace

std::vector<std::uint8_t> encode_bytes(
    const std::span<const std::uint8_t> input,
    const Predictor& predictor,
    std::string& error,
    EncodeStats* stats
) {
    error.clear();
    std::vector<std::uint8_t> encoded;
    encoded.reserve(input.size() + 64u);

    const auto segments = tokenize_exact(input);
    std::uint32_t previous_3 = kBosId;
    std::uint32_t previous_2 = kBosId;
    std::uint32_t previous_1 = kBosId;
    std::uint64_t r1_run = 0;
    std::vector<std::string> literal_table;
    std::unordered_map<std::string, std::uint64_t> literal_to_index;

    const auto flush_r1_run = [&]() {
        if (r1_run == 0) {
            return;
        }
        if (r1_run == 1u) {
            append_r1_run_marker(encoded, 1u);
            if (stats != nullptr) {
                stats->r1_bytes += r1_run_cost(1u);
            }
        } else {
            const std::size_t run_marker_cost = r1_run_cost(r1_run);
            const std::size_t single_cost = r1_run_cost(1u) * static_cast<std::size_t>(r1_run);
            if (run_marker_cost < single_cost) {
                append_r1_run_marker(encoded, r1_run);
                if (stats != nullptr) {
                    stats->r1_bytes += run_marker_cost;
                }
            } else {
                for (std::uint64_t i = 0; i < r1_run; ++i) {
                    append_r1_run_marker(encoded, 1u);
                }
                if (stats != nullptr) {
                    stats->r1_bytes += single_cost;
                }
            }
        }
        r1_run = 0;
    };

    for (const auto& segment : segments) {
        const auto bytes = std::span<const std::uint8_t>(input.data() + segment.offset, segment.length);
        const std::string_view token(reinterpret_cast<const char*>(bytes.data()), bytes.size());
        const auto actual_id = predictor.find_token_id(token);
        const CandidateSpan candidates = predictor.predict(previous_3, previous_2, previous_1);
        const std::uint64_t token_raw_cost = raw_cost(token);

        if (stats != nullptr) {
            ++stats->token_count;
        }

        bool emitted = false;
        if (segment.kind != Segment::Kind::Raw && actual_id.has_value()) {
            const int rank = find_rank(candidates, *actual_id);
            if (rank == 0) {
                const std::size_t marker_cost = rank_cost(1u);
                if (should_use_marker(marker_cost, token_raw_cost)) {
                    ++r1_run;
                    emitted = true;
                    if (stats != nullptr) {
                        ++stats->r1_count;
                    }
                }
            } else if (rank > 0 && rank < static_cast<int>(kMaxTopK)) {
                const std::size_t marker_cost = rank_cost(static_cast<std::uint64_t>(rank + 1));
                if (should_use_marker(marker_cost, token_raw_cost)) {
                    flush_r1_run();
                    append_rank_marker(encoded, static_cast<std::uint64_t>(rank + 1));
                    emitted = true;
                    if (stats != nullptr) {
                        ++stats->rank2_16_count;
                        stats->rank2_16_bytes += marker_cost;
                    }
                }
            }
        }

        if (!emitted) {
            if (const auto it = literal_to_index.find(std::string(token)); it != literal_to_index.end()) {
                const std::size_t ref_cost = literal_ref_cost(it->second);
                if (should_use_marker(ref_cost, token_raw_cost)) {
                    flush_r1_run();
                    append_literal_ref_marker(encoded, it->second);
                    emitted = true;
                    if (stats != nullptr) {
                        ++stats->literal_ref_count;
                        stats->literal_ref_bytes += ref_cost;
                    }
                }
            }
        }

        if (!emitted) {
            if (const auto punct = find_punctuation_token(token); punct.has_value()) {
                if (should_use_marker(punct_cost(*punct), token_raw_cost)) {
                    flush_r1_run();
                    append_punctuation_marker(encoded, *punct);
                    emitted = true;
                    if (stats != nullptr) {
                        ++stats->punct_count;
                        stats->punct_bytes += punct_cost(*punct);
                    }
                }
            }
        }

        if (!emitted) {
            flush_r1_run();
            append_escaped_raw(encoded, token);
            if (literal_to_index.find(std::string(token)) == literal_to_index.end()) {
                literal_to_index.emplace(std::string(token), literal_table.size());
                literal_table.emplace_back(token);
            }
            if (stats != nullptr) {
                ++stats->literal_count;
                stats->literal_bytes += token.size();
                stats->literal_output_bytes += escaped_raw_bytes(token);
                stats->escape_bytes += escaped_raw_bytes(token) - token.size();
            }
        }

        const auto token_id = actual_id.value_or(kUnkId);
        advance_context(previous_3, previous_2, previous_1, token, token_id);
    }

    flush_r1_run();
    return encoded;
}

std::vector<std::uint8_t> decode_bytes(
    const std::span<const std::uint8_t> input,
    const Predictor& predictor,
    std::string& error
) {
    error.clear();
    std::vector<std::uint8_t> output;
    std::vector<std::uint8_t> raw_buffer;
    output.reserve(input.size());
    raw_buffer.reserve(256u);
    std::vector<std::string> literal_table;
    std::unordered_map<std::string, std::uint64_t> literal_to_index;

    std::uint32_t previous_3 = kBosId;
    std::uint32_t previous_2 = kBosId;
    std::uint32_t previous_1 = kBosId;

    const auto flush_raw = [&]() -> bool {
        if (!flush_raw_buffer(raw_buffer, predictor, literal_table, literal_to_index, output, previous_3, previous_2, previous_1, error)) {
            return false;
        }
        raw_buffer.clear();
        return true;
    };

    std::size_t pos = 0;
    while (pos < input.size()) {
        const std::uint8_t byte = input[pos];
        if (byte != static_cast<std::uint8_t>('~')) {
            raw_buffer.push_back(byte);
            ++pos;
            continue;
        }

        if (!flush_raw()) {
            return {};
        }

        if (pos + 1 >= input.size()) {
            error = "Truncated control marker";
            return {};
        }

        const char next = static_cast<char>(input[pos + 1]);
        if (next == '~') {
            raw_buffer.push_back(static_cast<std::uint8_t>('~'));
            pos += 2;
            continue;
        }

        if (next == 'l') {
            std::size_t end = pos + 2;
            std::uint64_t literal_index = 0;
            bool parsed = false;
            if (end < input.size() && input[end] == static_cast<std::uint8_t>('[')) {
                parsed = parse_bracketed_unsigned(input, end, end, literal_index);
            } else {
                while (end < input.size() && input[end] >= static_cast<std::uint8_t>('0') && input[end] <= static_cast<std::uint8_t>('9')) {
                    ++end;
                }
                parsed = parse_unsigned(std::string_view(reinterpret_cast<const char*>(input.data() + pos + 2), end - (pos + 2)), literal_index);
            }
            if (!parsed || literal_index >= literal_table.size()) {
                error = "Invalid literal reference";
                return {};
            }

            const std::string_view token = literal_table[static_cast<std::size_t>(literal_index)];
            append_text(output, token);
            const auto token_id = predictor.find_token_id(token).value_or(kUnkId);
            advance_context(previous_3, previous_2, previous_1, token, token_id);
            pos = end;
            continue;
        }

        if (next == 'r') {
            if (pos + 2 >= input.size() || input[pos + 2] != static_cast<std::uint8_t>('[')) {
                error = "Invalid rank1 run";
                return {};
            }
            std::size_t end = pos + 3;
            while (end < input.size() && input[end] != static_cast<std::uint8_t>(']')) {
                ++end;
            }
            if (end >= input.size()) {
                error = "Unterminated rank1 run";
                return {};
            }

            std::uint64_t count = 0;
            if (!parse_unsigned(std::string_view(reinterpret_cast<const char*>(input.data() + pos + 3), end - (pos + 3)), count) || count == 0) {
                error = "Invalid rank1 run";
                return {};
            }

            for (std::uint64_t i = 0; i < count; ++i) {
                const CandidateSpan candidates = predictor.predict(previous_3, previous_2, previous_1);
                if (candidates.size == 0) {
                    error = "Empty candidate list";
                    return {};
                }
                const std::uint32_t token_id = candidates.data[0];
                const std::string_view token = predictor.token_bytes(token_id);
                append_text(output, token);
                advance_context(previous_3, previous_2, previous_1, token, token_id);
            }

            pos = end + 1;
            continue;
        }

        if (next == 'q' || (next >= '1' && next <= '9')) {
            std::size_t end = pos + 2;
            std::uint64_t rank_value = 0;
            bool parsed = false;
            if (next == 'q') {
                parsed = parse_bracketed_unsigned(input, end, end, rank_value);
            } else {
                while (end < input.size() && input[end] >= static_cast<std::uint8_t>('0') && input[end] <= static_cast<std::uint8_t>('9')) {
                    ++end;
                }
                parsed = parse_unsigned(std::string_view(reinterpret_cast<const char*>(input.data() + pos + 1), end - (pos + 1)), rank_value);
            }
            if (!parsed || rank_value < 1u || rank_value > 16u) {
                error = "Invalid rank marker";
                return {};
            }

            const CandidateSpan candidates = predictor.predict(previous_3, previous_2, previous_1);
            const std::uint64_t candidate_index = rank_value - 1u;
            if (candidate_index >= candidates.size) {
                error = "Rank exceeds current candidate list";
                return {};
            }

            const std::uint32_t token_id = candidates.data[static_cast<std::size_t>(candidate_index)];
            const std::string_view token = predictor.token_bytes(token_id);
            append_text(output, token);
            advance_context(previous_3, previous_2, previous_1, token, token_id);
            pos = end;
            continue;
        }

        if (next == 'p') {
            std::size_t end = pos + 2;
            std::uint64_t punct_index = 0;
            bool parsed = false;
            if (end < input.size() && input[end] == static_cast<std::uint8_t>('[')) {
                parsed = parse_bracketed_unsigned(input, end, end, punct_index);
            } else {
                while (end < input.size() && input[end] >= static_cast<std::uint8_t>('0') && input[end] <= static_cast<std::uint8_t>('9')) {
                    ++end;
                }
                parsed = parse_unsigned(std::string_view(reinterpret_cast<const char*>(input.data() + pos + 2), end - (pos + 2)), punct_index);
            }
            if (!parsed || punct_index >= kPunctuationTokens.size()) {
                error = "Invalid punctuation marker";
                return {};
            }

            const std::string_view token = kPunctuationTokens[static_cast<std::size_t>(punct_index)];
            append_text(output, token);
            const auto token_id = predictor.find_token_id(token).value_or(kUnkId);
            advance_context(previous_3, previous_2, previous_1, token, token_id);
            pos = end;
            continue;
        }

        error = "Unknown control marker";
        return {};
    }

    if (!flush_raw()) {
        return {};
    }

    return output;
}

int encode_file_impl(
    const std::filesystem::path& input_path,
    const std::filesystem::path& output_path,
    const std::filesystem::path& predictor_path,
    std::string& error
) {
    Predictor predictor;
    if (!predictor.load(predictor_path, error)) return 2;

    const auto input = read_file(input_path, error);
    if (!error.empty()) return 2;

    std::vector<std::uint8_t> encoded = encode_bytes(input, predictor, error, nullptr);
    if (!error.empty()) return 2;

    if (!write_file(output_path, encoded, error)) return 2;
    return 0;
}

int decode_file_impl(
    const std::filesystem::path& input_path,
    const std::filesystem::path& output_path,
    const std::filesystem::path& predictor_path,
    std::string& error
) {
    Predictor predictor;
    if (!predictor.load(predictor_path, error)) return 2;

    const auto input = read_file(input_path, error);
    if (!error.empty()) return 2;

    std::vector<std::uint8_t> output = decode_bytes(input, predictor, error);
    if (!error.empty()) return 3;

    if (!write_file(output_path, output, error)) return 2;
    return 0;
}

} // namespace tp
