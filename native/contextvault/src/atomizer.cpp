#include "internal.h"

#include <algorithm>
#include <array>
#include <bit>
#include <cmath>
#include <cctype>
#include <limits>
#include <sstream>
#include <unordered_set>

namespace tp {

namespace {

std::string atom_kind_name(const TxtAtomKind kind) {
    switch (kind) {
        case TxtAtomKind::Paragraph: return "paragraph";
        case TxtAtomKind::Sentence: return "sentence";
    }
    return "unknown";
}

bool is_residual_change_kind(std::string_view change_kind) {
    return change_kind == "change-insert" || change_kind == "change-delete" || change_kind == "change-replace";
}

bool is_sentence_terminator(const char ch) {
    return ch == '.' || ch == '!' || ch == '?';
}

bool is_closing_punctuation(const char ch) {
    return ch == '"' || ch == '\'' || ch == ')' || ch == ']' || ch == '}';
}

bool is_decimal_point(std::string_view text, std::size_t pos) {
    if (pos == 0 || pos + 1 >= text.size()) {
        return false;
    }
    const unsigned char left = static_cast<unsigned char>(text[pos - 1]);
    const unsigned char right = static_cast<unsigned char>(text[pos + 1]);
    return std::isdigit(left) != 0 && std::isdigit(right) != 0;
}

std::string lower_ascii(std::string_view text);

bool is_abbreviation_token(std::string_view token) {
    if (token.empty()) {
        return false;
    }

    const std::string lower = lower_ascii(token);
    static const std::array<std::string_view, 14> kCommonAbbreviations = {
        "e.g.", "i.e.", "etc.", "mr.", "mrs.", "ms.", "dr.", "prof.",
        "sr.", "jr.", "vs.", "no.", "u.s.", "u.k."
    };
    if (std::find(kCommonAbbreviations.begin(), kCommonAbbreviations.end(), lower) != kCommonAbbreviations.end()) {
        return true;
    }

    std::size_t letters = 0;
    std::size_t periods = 0;
    bool letters_are_alpha = true;
    for (const unsigned char raw_ch : token) {
        if (std::isalpha(raw_ch) != 0) {
            ++letters;
            continue;
        }
        if (raw_ch == '.') {
            ++periods;
            continue;
        }
        letters_are_alpha = false;
        break;
    }

    if (!letters_are_alpha || letters < 2u || periods == 0u || token.size() > 10u) {
        return false;
    }

    if (token.back() != '.') {
        return false;
    }

    return periods >= 2u || (periods == 1u && letters <= 4u && std::all_of(token.begin(), token.end(), [](unsigned char ch) {
        return std::isalpha(ch) != 0 || ch == '.';
    }));
}

bool is_abbreviation_period(std::string_view text, std::size_t pos) {
    if (pos >= text.size() || text[pos] != '.') {
        return false;
    }

    std::size_t start = pos;
    while (start > 0) {
        const char ch = text[start - 1];
        if (ch == ' ' || ch == '\t' || ch == '\r' || ch == '\n' || ch == '\v' || ch == '\f') {
            break;
        }
        --start;
    }

    std::size_t end = pos + 1;
    while (end < text.size()) {
        const char ch = text[end];
        if (ch == ' ' || ch == '\t' || ch == '\r' || ch == '\n' || ch == '\v' || ch == '\f') {
            break;
        }
        ++end;
    }

    const std::string_view token = text.substr(start, end - start);
    return is_abbreviation_token(token);
}

struct AtomSplitResult {
    std::vector<std::pair<std::size_t, std::size_t>> ranges;
    bool used_sentence_split = false;
};

std::size_t count_term_like_chunks(std::string_view text) {
    std::size_t count = 0;
    bool in_term = false;
    for (const unsigned char ch : text) {
        if (std::isalnum(ch) != 0) {
            if (!in_term) {
                ++count;
                in_term = true;
            }
        } else {
            in_term = false;
        }
    }
    return count;
}

bool should_keep_whole_paragraph(const TxtParagraphRecord& paragraph) {
    const std::string_view text = paragraph.text;
    if (paragraph.is_heading || text.empty()) {
        return true;
    }

    const std::size_t term_count = count_term_like_chunks(text);
    const std::size_t newline_count = static_cast<std::size_t>(std::count(text.begin(), text.end(), '\n'));
    const std::size_t length = text.size();

    if (length <= 220u || term_count <= 18u) {
        return true;
    }
    if (newline_count >= 2u && length <= 320u) {
        return true;
    }

    std::size_t sentence_marks = 0;
    for (std::size_t pos = 0; pos < text.size(); ++pos) {
        if (is_sentence_terminator(text[pos]) && !is_decimal_point(text, pos) && !is_abbreviation_period(text, pos)) {
            ++sentence_marks;
        }
    }
    return sentence_marks <= 1u;
}

std::vector<std::pair<std::size_t, std::size_t>> merge_short_sentence_ranges(
    std::string_view text,
    const std::vector<std::pair<std::size_t, std::size_t>>& ranges
) {
    if (ranges.size() <= 1u) {
        return ranges;
    }

    std::vector<std::pair<std::size_t, std::size_t>> merged;
    merged.reserve(ranges.size());

    auto term_count_for = [&](std::size_t start, std::size_t end) {
        return count_term_like_chunks(text.substr(start, end - start));
    };

    std::pair<std::size_t, std::size_t> current = ranges.front();
    std::size_t current_term_count = term_count_for(current.first, current.second);

    constexpr std::size_t kShortSentenceChars = 48u;
    constexpr std::size_t kShortSentenceTerms = 6u;
    constexpr std::size_t kMaxMergedChars = 220u;

    for (std::size_t i = 1; i < ranges.size(); ++i) {
        const auto next = ranges[i];
        const std::size_t next_len = next.second - next.first;
        const std::size_t next_terms = term_count_for(next.first, next.second);
        const std::size_t current_len = current.second - current.first;

        const bool current_is_short = current_len < kShortSentenceChars || current_term_count < kShortSentenceTerms;
        const bool next_is_short = next_len < kShortSentenceChars || next_terms < kShortSentenceTerms;
        const bool can_merge = current.second <= next.first && current_len + next_len <= kMaxMergedChars;

        if (can_merge && (current_is_short || next_is_short)) {
            current.second = next.second;
            current_term_count += next_terms;
            continue;
        }

        merged.push_back(current);
        current = next;
        current_term_count = next_terms;
    }

    merged.push_back(current);
    return merged;
}

AtomSplitResult split_atom_ranges(std::string_view text) {
    AtomSplitResult result;
    std::size_t start = 0;
    std::size_t cursor = 0;

    auto trim_end = [&](std::size_t end) {
        while (end > start) {
            const char ch = text[end - 1];
            if (ch == ' ' || ch == '\t' || ch == '\r' || ch == '\n' || ch == '\v' || ch == '\f') {
                --end;
            } else {
                break;
            }
        }
        return end;
    };

    auto emit_range = [&](const std::size_t end) {
        const std::size_t trimmed_end = trim_end(end);
        if (trimmed_end > start) {
            result.ranges.emplace_back(start, trimmed_end);
        }
        start = end;
    };

    while (cursor < text.size()) {
        const char ch = text[cursor];
        if (is_sentence_terminator(ch) && !is_decimal_point(text, cursor) && !is_abbreviation_period(text, cursor)) {
            std::size_t end = cursor + 1;
            while (end < text.size() && is_closing_punctuation(text[end])) {
                ++end;
            }
            while (end < text.size()) {
                const char ws = text[end];
                if (ws == ' ' || ws == '\t' || ws == '\v' || ws == '\f' || ws == '\r' || ws == '\n') {
                    ++end;
                } else {
                    break;
                }
            }
            emit_range(end);
            result.used_sentence_split = true;
            cursor = end;
            continue;
        }

        ++cursor;
    }

    if (start < text.size()) {
        const std::size_t trimmed_end = trim_end(text.size());
        if (trimmed_end > start) {
            result.ranges.emplace_back(start, trimmed_end);
        }
    }

    if (result.ranges.empty()) {
        const std::size_t trimmed_end = trim_end(text.size());
        if (trimmed_end > 0) {
            result.ranges.emplace_back(0, trimmed_end);
        }
    }

    if (result.ranges.size() > 1u) {
        result.ranges = merge_short_sentence_ranges(text, result.ranges);
    }

    return result;
}

std::string make_atom_id(
    const TxtImportRecord& record,
    const TxtParagraphRecord& paragraph,
    const std::size_t atom_index,
    const TxtAtomKind kind,
    const std::size_t start_offset,
    const std::size_t end_offset,
    const std::uint64_t checksum
) {
    std::ostringstream out;
    out << "txt:" << record.source_checksum
        << ":p" << paragraph.paragraph_index
        << ":a" << atom_index
        << ":" << atom_kind_name(kind)
        << ":" << start_offset
        << "-" << end_offset
        << ":" << checksum;
    return out.str();
}

std::string normalize_for_search(std::string_view text) {
    std::string normalized;
    normalized.reserve(text.size());

    bool in_space = true;
    for (const unsigned char raw_ch : text) {
        if (std::isalnum(raw_ch)) {
            normalized.push_back(static_cast<char>(std::tolower(raw_ch)));
            in_space = false;
        } else if (!in_space) {
            normalized.push_back(' ');
            in_space = true;
        }
    }

    while (!normalized.empty() && normalized.back() == ' ') {
        normalized.pop_back();
    }

    return normalized;
}

bool is_word_boundary_char(const char ch) {
    return !std::isalnum(static_cast<unsigned char>(ch));
}

std::size_t count_normalized_occurrences(std::string_view normalized_text, std::string_view needle) {
    if (needle.empty() || normalized_text.empty() || needle.size() > normalized_text.size()) {
        return 0;
    }

    std::size_t count = 0;
    std::size_t pos = 0;
    while (true) {
        pos = normalized_text.find(needle, pos);
        if (pos == std::string_view::npos) {
            break;
        }
        const bool left_ok = pos == 0 || is_word_boundary_char(normalized_text[pos - 1]);
        const std::size_t end = pos + needle.size();
        const bool right_ok = end >= normalized_text.size() || is_word_boundary_char(normalized_text[end]);
        if (left_ok && right_ok) {
            ++count;
        }
        pos += needle.size();
    }
    return count;
}

std::vector<std::string> extract_search_terms(std::string_view text) {
    std::vector<std::string> terms;
    std::string term;
    term.reserve(32);

    for (const unsigned char raw_ch : text) {
        if (std::isalnum(raw_ch)) {
            term.push_back(static_cast<char>(std::tolower(raw_ch)));
            continue;
        }
        if (!term.empty()) {
            terms.push_back(term);
            term.clear();
        }
    }
    if (!term.empty()) {
        terms.push_back(term);
    }

    std::sort(terms.begin(), terms.end());
    terms.erase(std::unique(terms.begin(), terms.end()), terms.end());
    return terms;
}

std::vector<std::string> extract_ordered_search_terms(std::string_view text) {
    std::vector<std::string> terms;
    std::string term;
    term.reserve(32);

    for (const unsigned char raw_ch : text) {
        if (std::isalnum(raw_ch)) {
            term.push_back(static_cast<char>(std::tolower(raw_ch)));
            continue;
        }
        if (!term.empty()) {
            terms.push_back(term);
            term.clear();
        }
    }
    if (!term.empty()) {
        terms.push_back(term);
    }
    return terms;
}

std::string lower_ascii(std::string_view text) {
    std::string out;
    out.reserve(text.size());
    for (const unsigned char raw_ch : text) {
        out.push_back(static_cast<char>(std::tolower(raw_ch)));
    }
    return out;
}

struct AtomTextAnalysis {
    std::vector<std::string> ordered_terms;
    std::string normalized_text;
    std::string lower_text;
    std::size_t newline_count = 0;
    std::size_t sentence_mark_count = 0;
    std::size_t period_count = 0;
};

AtomTextAnalysis analyze_atom_text(std::string_view text) {
    AtomTextAnalysis analysis;
    analysis.ordered_terms.reserve(std::max<std::size_t>(4u, text.size() / 6u));
    analysis.normalized_text.reserve(text.size());
    analysis.lower_text.reserve(text.size());

    std::string current_term;
    current_term.reserve(32);
    bool in_space = true;

    for (const unsigned char raw_ch : text) {
        const char ch = static_cast<char>(raw_ch);
        analysis.lower_text.push_back(static_cast<char>(std::tolower(raw_ch)));

        if (ch == '\n') {
            ++analysis.newline_count;
        } else if (ch == '!' || ch == '?') {
            ++analysis.sentence_mark_count;
        } else if (ch == '.') {
            ++analysis.period_count;
        }

        if (std::isalnum(raw_ch)) {
            const char lower = static_cast<char>(std::tolower(raw_ch));
            analysis.normalized_text.push_back(lower);
            current_term.push_back(lower);
            in_space = false;
        } else {
            if (!in_space) {
                analysis.normalized_text.push_back(' ');
                in_space = true;
            }
            if (!current_term.empty()) {
                analysis.ordered_terms.push_back(current_term);
                current_term.clear();
            }
        }
    }

    if (!current_term.empty()) {
        analysis.ordered_terms.push_back(current_term);
    }
    while (!analysis.normalized_text.empty() && analysis.normalized_text.back() == ' ') {
        analysis.normalized_text.pop_back();
    }

    return analysis;
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

std::string zero_pad_int(int value, int width) {
    std::string out = std::to_string(value);
    while (static_cast<int>(out.size()) < width) {
        out.insert(out.begin(), '0');
    }
    return out;
}

bool parse_uint(std::string_view text, int& out) {
    if (text.empty() || !std::all_of(text.begin(), text.end(), [](const char ch) {
            return std::isdigit(static_cast<unsigned char>(ch)) != 0;
        })) {
        return false;
    }
    try {
        out = std::stoi(std::string(text));
        return true;
    } catch (...) {
        return false;
    }
}

std::string normalize_date_signature(int year, int month, int day) {
    return zero_pad_int(year, 4) + "-" + zero_pad_int(month, 2) + "-" + zero_pad_int(day, 2);
}

bool append_iso_date_signature(std::string_view text, std::size_t pos, std::string& out, std::size_t& consumed) {
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

    out = normalize_date_signature(year, month, day);
    consumed = 10;
    return true;
}

bool append_month_date_signature(std::string_view text, std::size_t pos, std::string& out, std::size_t& consumed) {
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
    while (cursor < text.size() && std::isspace(static_cast<unsigned char>(text[cursor])) != 0) {
        ++cursor;
    }
    const std::size_t day_start = cursor;
    while (cursor < text.size() && std::isdigit(static_cast<unsigned char>(text[cursor])) != 0) {
        ++cursor;
    }
    if (cursor == day_start) {
        return false;
    }
    int day = 0;
    if (!parse_uint(text.substr(day_start, cursor - day_start), day) || day < 1 || day > 31) {
        return false;
    }
    while (cursor < text.size() && std::isspace(static_cast<unsigned char>(text[cursor])) != 0) {
        ++cursor;
    }
    if (cursor < text.size() && text[cursor] == ',') {
        ++cursor;
    }
    while (cursor < text.size() && std::isspace(static_cast<unsigned char>(text[cursor])) != 0) {
        ++cursor;
    }
    const std::size_t year_start = cursor;
    while (cursor < text.size() && std::isdigit(static_cast<unsigned char>(text[cursor])) != 0) {
        ++cursor;
    }
    if (cursor - year_start < 4) {
        return false;
    }
    int year = 0;
    if (!parse_uint(text.substr(year_start, cursor - year_start), year) || year < 1000 || year > 9999) {
        return false;
    }

    out = normalize_date_signature(year, month, day);
    consumed = cursor - pos;
    return true;
}

std::vector<std::string> extract_date_signatures(std::string_view text) {
    std::vector<std::string> signatures;
    for (std::size_t pos = 0; pos < text.size(); ++pos) {
        std::string signature;
        std::size_t consumed = 0;
        if (append_iso_date_signature(text, pos, signature, consumed)) {
            signatures.push_back(signature);
            pos += consumed > 0 ? consumed - 1 : 0;
            continue;
        }
        if (std::isalpha(static_cast<unsigned char>(text[pos])) != 0 &&
            append_month_date_signature(text, pos, signature, consumed)) {
            signatures.push_back(signature);
            pos += consumed > 0 ? consumed - 1 : 0;
            continue;
        }
    }
    std::sort(signatures.begin(), signatures.end());
    signatures.erase(std::unique(signatures.begin(), signatures.end()), signatures.end());
    return signatures;
}

std::string normalize_numeric_signature(std::string_view token) {
    std::string out;
    out.reserve(token.size());
    for (const unsigned char raw_ch : token) {
        if (std::isdigit(raw_ch) != 0) {
            out.push_back(static_cast<char>(raw_ch));
        } else if (raw_ch == '.' || raw_ch == '%' || raw_ch == '-' || std::isalpha(raw_ch) != 0) {
            out.push_back(static_cast<char>(std::tolower(raw_ch)));
        }
    }
    while (!out.empty() && out.front() == '$') {
        out.erase(out.begin());
    }
    return out;
}

std::vector<std::string> extract_numeric_signatures(std::string_view text) {
    std::vector<std::string> signatures;
    for (std::size_t pos = 0; pos < text.size(); ++pos) {
        std::size_t cursor = pos;
        if (!(std::isdigit(static_cast<unsigned char>(text[cursor])) != 0 || text[cursor] == '$')) {
            continue;
        }
        if (text[cursor] == '$') {
            ++cursor;
        }
        if (cursor >= text.size() || std::isdigit(static_cast<unsigned char>(text[cursor])) == 0) {
            continue;
        }

        bool saw_digit = false;
        while (cursor < text.size()) {
            const unsigned char ch = static_cast<unsigned char>(text[cursor]);
            if (std::isdigit(ch) != 0) {
                saw_digit = true;
                ++cursor;
                continue;
            }
            if ((ch == '.' || ch == ',') && cursor + 1 < text.size() &&
                std::isdigit(static_cast<unsigned char>(text[cursor + 1])) != 0) {
                ++cursor;
                continue;
            }
            break;
        }
        while (cursor < text.size() && std::isalpha(static_cast<unsigned char>(text[cursor])) != 0) {
            ++cursor;
        }
        if (cursor < text.size() && text[cursor] == '%') {
            ++cursor;
        }

        if (!saw_digit) {
            continue;
        }

        const std::string normalized = normalize_numeric_signature(text.substr(pos, cursor - pos));
        if (!normalized.empty() &&
            std::any_of(normalized.begin(), normalized.end(), [](const char ch) {
                return std::isdigit(static_cast<unsigned char>(ch)) != 0;
            })) {
            signatures.push_back(normalized);
        }
        pos = cursor > 0 ? cursor - 1 : pos;
    }

    std::sort(signatures.begin(), signatures.end());
    signatures.erase(std::unique(signatures.begin(), signatures.end()), signatures.end());
    return signatures;
}

std::string normalize_abbreviation_signature(std::string_view token) {
    std::string out;
    out.reserve(token.size());
    for (const unsigned char raw_ch : token) {
        if (std::isalpha(raw_ch) != 0 || raw_ch == '.') {
            out.push_back(static_cast<char>(std::tolower(raw_ch)));
        }
    }
    while (!out.empty() && out.front() == '.') {
        out.erase(out.begin());
    }
    while (!out.empty() && out.back() == '.') {
        out.pop_back();
    }
    return out;
}

std::vector<std::string> extract_abbreviation_signatures(std::string_view text) {
    std::vector<std::string> signatures;
    std::size_t pos = 0;
    while (pos < text.size()) {
        while (pos < text.size() && std::isspace(static_cast<unsigned char>(text[pos])) != 0) {
            ++pos;
        }
        const std::size_t start = pos;
        while (pos < text.size()) {
            const unsigned char ch = static_cast<unsigned char>(text[pos]);
            if (std::isalpha(ch) != 0 || ch == '.') {
                ++pos;
            } else {
                break;
            }
        }
        if (pos > start) {
            const std::string_view token = text.substr(start, pos - start);
            const std::string normalized = normalize_abbreviation_signature(token);
            if (is_abbreviation_token(token) && !normalized.empty()) {
                signatures.push_back(normalized);
            }
        }
        while (pos < text.size() && std::ispunct(static_cast<unsigned char>(text[pos])) != 0 &&
               text[pos] != '.' && text[pos] != '_') {
            ++pos;
        }
        if (pos == start) {
            ++pos;
        }
    }

    std::sort(signatures.begin(), signatures.end());
    signatures.erase(std::unique(signatures.begin(), signatures.end()), signatures.end());
    return signatures;
}

std::string trim_copy_local(std::string_view text) {
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

bool starts_with_word(std::string_view text, std::string_view word) {
    if (text.size() < word.size()) {
        return false;
    }
    if (text.substr(0, word.size()) != word) {
        return false;
    }
    if (text.size() == word.size()) {
        return true;
    }
    const char next = text[word.size()];
    return next == ' ' || next == '\t' || next == '\n' || next == '\r' || next == '?' || next == ':' || next == ',';
}

struct QuerySignals {
    bool is_what = false;
    bool is_how = false;
    bool is_where = false;
    bool is_why = false;
    bool is_who = false;
    bool is_when = false;
    bool is_duplicate = false;
    bool is_unique = false;
    bool is_change = false;
    bool is_near_duplicate = false;
    std::vector<std::string> boost_terms;
};

struct QueryShapeSignals {
    std::vector<std::string> date_signatures;
    std::vector<std::string> numeric_signatures;
    std::vector<std::string> abbreviation_signatures;
};

QueryShapeSignals extract_text_shape_signals(std::string_view text) {
    return QueryShapeSignals{
        extract_date_signatures(text),
        extract_numeric_signatures(text),
        extract_abbreviation_signatures(text)
    };
}

std::size_t count_signature_matches(
    const std::vector<std::string>& haystack,
    const std::vector<std::string>& needles
) {
    if (haystack.empty() || needles.empty()) {
        return 0;
    }
    std::size_t matches = 0;
    for (const auto& needle : needles) {
        if (std::find(haystack.begin(), haystack.end(), needle) != haystack.end()) {
            ++matches;
        }
    }
    return matches;
}

struct StructuralQueryFilters {
    std::string cleaned_query;
    std::string section_filter;
    std::string heading_filter;
    bool heading_only = false;
    bool has_section_filter = false;
    bool has_heading_filter = false;
};

std::string_view first_clause_name(std::string_view query, std::size_t pos) {
    const std::string_view rest = query.substr(pos);
    const std::string_view heading_contains = "heading contains";
    const std::string_view section_contains = "section contains";
    const std::string_view heading_colon = "heading:";
    const std::string_view section_colon = "section:";
    if (rest.rfind(heading_contains, 0) == 0) {
        return heading_contains;
    }
    if (rest.rfind(section_contains, 0) == 0) {
        return section_contains;
    }
    if (rest.rfind(heading_colon, 0) == 0) {
        return heading_colon;
    }
    if (rest.rfind(section_colon, 0) == 0) {
        return section_colon;
    }
    return {};
}

QuerySignals analyze_query_signals(std::string_view query, const std::vector<std::string>& terms) {
    QuerySignals signals;
    const std::string lower_query = lower_ascii(query);
    signals.is_what = starts_with_word(lower_query, "what");
    signals.is_how = starts_with_word(lower_query, "how");
    signals.is_where = starts_with_word(lower_query, "where");
    signals.is_why = starts_with_word(lower_query, "why");
    signals.is_who = starts_with_word(lower_query, "who");
    signals.is_when = starts_with_word(lower_query, "when");
    signals.is_duplicate = lower_query.find("duplicate") != std::string::npos || lower_query.find("repeated") != std::string::npos;
    signals.is_unique = lower_query.find("unique") != std::string::npos;
    signals.is_change = lower_query.find("changed value") != std::string::npos ||
                        lower_query.find("changed date") != std::string::npos ||
                        lower_query.find("changed entity") != std::string::npos ||
                        lower_query.find("value changed") != std::string::npos ||
                        lower_query.find("date changed") != std::string::npos ||
                        lower_query.find("entity changed") != std::string::npos ||
                        lower_query.find("change value") != std::string::npos ||
                        lower_query.find("change date") != std::string::npos ||
                        lower_query.find("change entity") != std::string::npos;
    signals.is_near_duplicate = lower_query.find("near duplicate") != std::string::npos ||
                                lower_query.find("near duplicates") != std::string::npos;
    signals.boost_terms = terms;

    const std::vector<std::string> stopwords = {
        "what", "how", "where", "why", "who", "when", "which", "is", "are", "do", "does", "did", "a", "an", "the", "to", "of", "in"
    };
    std::vector<std::string> filtered;
    filtered.reserve(terms.size());
    for (const auto& term : terms) {
        if (std::find(stopwords.begin(), stopwords.end(), term) == stopwords.end()) {
            filtered.push_back(term);
        }
    }
    if (!filtered.empty()) {
        signals.boost_terms = std::move(filtered);
    }
    return signals;
}

bool is_query_space(const char ch) {
    const unsigned char raw = static_cast<unsigned char>(ch);
    return std::isspace(raw) != 0;
}

std::size_t skip_spaces(std::string_view text, std::size_t pos) {
    while (pos < text.size() && is_query_space(text[pos])) {
        ++pos;
    }
    return pos;
}

std::size_t consume_clause_value(std::string_view query, std::size_t pos, std::string& value) {
    value.clear();
    pos = skip_spaces(query, pos);
    if (pos >= query.size()) {
        return pos;
    }

    const char quote = query[pos];
    if (quote == '"' || quote == '\'') {
        ++pos;
        while (pos < query.size() && query[pos] != quote) {
            value.push_back(query[pos]);
            ++pos;
        }
        if (pos < query.size() && query[pos] == quote) {
            ++pos;
        }
        return pos;
    }

    while (pos < query.size()) {
        value.push_back(query[pos]);
        ++pos;
    }
    return pos;
}

StructuralQueryFilters parse_structural_query_filters(std::string_view query) {
    StructuralQueryFilters filters;
    std::size_t cursor = 0;

    auto append_clean = [&](std::string_view chunk) {
        if (chunk.empty()) {
            return;
        }
        if (!filters.cleaned_query.empty() && !is_query_space(filters.cleaned_query.back())) {
            filters.cleaned_query.push_back(' ');
        }
        filters.cleaned_query.append(chunk.begin(), chunk.end());
    };

    while (cursor < query.size()) {
        const std::string lower_remaining = lower_ascii(query.substr(cursor));
        const std::size_t heading_contains_pos = lower_remaining.find("heading contains");
        const std::size_t section_contains_pos = lower_remaining.find("section contains");
        const std::size_t section_pos = lower_remaining.find("section:");
        const std::size_t heading_pos = lower_remaining.find("heading:");

        std::size_t next_clause_pos = std::string::npos;
        enum class ClauseKind { None, HeadingContains, SectionContains, Section, Heading };
        ClauseKind clause_kind = ClauseKind::None;

        auto consider = [&](std::size_t pos, ClauseKind kind) {
            if (pos == std::string::npos) {
                return;
            }
            if (next_clause_pos == std::string::npos || pos < next_clause_pos) {
                next_clause_pos = pos;
                clause_kind = kind;
            }
        };

        consider(heading_contains_pos, ClauseKind::HeadingContains);
        consider(section_contains_pos, ClauseKind::SectionContains);
        consider(section_pos, ClauseKind::Section);
        consider(heading_pos, ClauseKind::Heading);

        if (clause_kind == ClauseKind::None) {
            append_clean(query.substr(cursor));
            break;
        }

        append_clean(query.substr(cursor, next_clause_pos));
        cursor += next_clause_pos;

        if (clause_kind == ClauseKind::HeadingContains) {
            cursor += std::string_view("heading contains").size();
            std::string value;
            cursor = consume_clause_value(query, cursor, value);
            filters.heading_filter = trim_copy_local(value);
            filters.has_heading_filter = !filters.heading_filter.empty();
            filters.heading_only = true;
            continue;
        }
        if (clause_kind == ClauseKind::SectionContains) {
            cursor += std::string_view("section contains").size();
            std::string value;
            cursor = consume_clause_value(query, cursor, value);
            filters.section_filter = trim_copy_local(value);
            filters.has_section_filter = !filters.section_filter.empty();
            continue;
        }
        if (clause_kind == ClauseKind::Section) {
            cursor += std::string_view("section:").size();
            std::string value;
            cursor = consume_clause_value(query, cursor, value);
            filters.section_filter = trim_copy_local(value);
            filters.has_section_filter = !filters.section_filter.empty();
            continue;
        }
        if (clause_kind == ClauseKind::Heading) {
            cursor += std::string_view("heading:").size();
            std::string value;
            cursor = consume_clause_value(query, cursor, value);
            filters.heading_filter = trim_copy_local(value);
            filters.has_heading_filter = !filters.heading_filter.empty();
            filters.heading_only = true;
            continue;
        }
    }

    filters.cleaned_query = trim_copy_local(filters.cleaned_query);
    return filters;
}

bool matches_structural_filters(
    const TxtAtomSearchIndex& index,
    const TxtAtomRecord& atom,
    const StructuralQueryFilters& filters
) {
    if (!filters.has_section_filter && !filters.has_heading_filter) {
        return true;
    }
    if (!index.source_record) {
        return false;
    }
    if (atom.section_index >= index.source_record->sections.size()) {
        return false;
    }

    const auto& section = index.source_record->sections[atom.section_index];
    const std::string normalized_heading = atom.section_index < index.normalized_section_headings.size()
        ? index.normalized_section_headings[atom.section_index]
        : normalize_for_search(section.heading_text);

    auto contains_filter_text = [](const std::string& haystack, const std::string& needle) {
        if (needle.empty()) {
            return false;
        }
        if (haystack.find(needle) != std::string::npos) {
            return true;
        }
        const std::vector<std::string> filter_terms = extract_search_terms(needle);
        if (filter_terms.empty()) {
            return false;
        }
        for (const auto& term : filter_terms) {
            if (haystack.find(term) == std::string::npos) {
                return false;
            }
        }
        return true;
    };

    if (filters.has_section_filter) {
        const std::string normalized_section_filter = normalize_for_search(filters.section_filter);
        if (!contains_filter_text(normalized_heading, normalized_section_filter)) {
            return false;
        }
    }

    if (filters.has_heading_filter) {
        const std::string normalized_heading_filter = normalize_for_search(filters.heading_filter);
        if (normalized_heading_filter.empty()) {
            return false;
        }
        const std::string normalized_atom_text = normalize_for_search(atom.text);
        if (!contains_filter_text(normalized_atom_text, normalized_heading_filter) &&
            !contains_filter_text(normalized_heading, normalized_heading_filter)) {
            return false;
        }
    }

    return true;
}

enum class QueryIntent : std::uint8_t {
    TitleLike,
    QuestionLike,
    ConceptLike
};

bool looks_like_title_cased_query(std::string_view query) {
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

    for (const unsigned char raw_ch : query) {
        if (std::isalnum(raw_ch)) {
            word.push_back(static_cast<char>(raw_ch));
        } else {
            flush_word();
        }
    }
    flush_word();

    return saw_word && saw_title_cased_word && !saw_lowercase_word;
}

QueryIntent classify_query_intent(std::string_view query, const std::vector<std::string>& terms) {
    const std::string lower_query = lower_ascii(query);
    const bool short_query = terms.size() <= 3u && query.size() <= 40u;
    const bool title_markup =
        query.find('"') != std::string_view::npos ||
        query.find('\'') != std::string_view::npos ||
        query.find(':') != std::string_view::npos ||
        query.find(" - ") != std::string_view::npos ||
        query.find(" | ") != std::string_view::npos;
    const bool has_question_word =
        starts_with_word(lower_query, "what") ||
        starts_with_word(lower_query, "how") ||
        starts_with_word(lower_query, "where") ||
        starts_with_word(lower_query, "why") ||
        starts_with_word(lower_query, "who") ||
        starts_with_word(lower_query, "when");
    const bool has_question_mark = query.find('?') != std::string_view::npos;
    const bool looks_like_title = looks_like_title_cased_query(query);
    if (title_markup || (short_query && terms.size() == 1u && !has_question_word && !has_question_mark)) {
        return QueryIntent::TitleLike;
    }
    if (short_query && terms.size() <= 3u && looks_like_title && !has_question_word && !has_question_mark) {
        return QueryIntent::TitleLike;
    }
    if (has_question_word || has_question_mark) {
        return QueryIntent::QuestionLike;
    }
    return QueryIntent::ConceptLike;
}

double compute_overlap_ratio(std::size_t matched_terms, std::size_t query_term_count) {
    if (query_term_count == 0) {
        return 0.0;
    }
    return static_cast<double>(matched_terms) / static_cast<double>(query_term_count);
}

double calibrate_search_score(
    const double raw_score,
    const std::size_t matched_terms,
    const std::size_t query_term_count,
    const std::size_t phrase_matches,
    const double proximity_score,
    const bool exact_text_match,
    const QueryIntent query_intent,
    const bool title_like_atom,
    const bool cover_like_atom,
    const bool body_like_atom,
    const TxtAtomKind atom_kind,
    const std::size_t atom_text_length,
    const std::size_t atom_term_count,
    const bool is_heading_atom
) {
    double factor = 1.0;
    if (exact_text_match) {
        factor += 0.30;
    }
    if (phrase_matches > 0) {
        factor += std::min<double>(0.18 * static_cast<double>(phrase_matches), 0.36);
    }
    if (proximity_score > 0.0) {
        factor += std::min<double>(0.15, proximity_score / 20.0);
    }

    const double coverage = compute_overlap_ratio(matched_terms, query_term_count);
    if (coverage > 0.0) {
        factor += std::min<double>(0.20, coverage * 0.16);
    }

    if (query_intent == QueryIntent::TitleLike) {
        if (title_like_atom) {
            factor += 0.12;
        }
        if (cover_like_atom) {
            factor -= 0.05;
        }
    } else if (query_intent == QueryIntent::QuestionLike) {
        if (body_like_atom) {
            factor += 0.08;
        }
        if (cover_like_atom && !exact_text_match) {
            factor -= 0.08;
        }
    }

    if (query_term_count > 0 && matched_terms == query_term_count && !exact_text_match) {
        factor += 0.08;
    }

    if (is_heading_atom) {
        factor += 0.08;
    }

    if (atom_kind == TxtAtomKind::Paragraph) {
        factor += 0.10;
    } else {
        factor -= 0.05;
    }

    if (atom_text_length <= 32u || atom_term_count <= 3u) {
        factor -= 0.18;
    } else if (atom_text_length <= 64u || atom_term_count <= 5u) {
        factor -= 0.10;
    } else if (atom_text_length >= 260u) {
        factor -= 0.04;
    }

    if (factor < 0.50) {
        factor = 0.50;
    } else if (factor > 1.60) {
        factor = 1.60;
    }

    return std::max(0.0, raw_score) * factor;
}

std::vector<std::pair<std::size_t, std::size_t>> sentence_ranges(std::string_view text) {
    std::vector<std::pair<std::size_t, std::size_t>> ranges;
    std::size_t start = 0;
    std::size_t cursor = 0;

    auto trim_end = [&](std::size_t end) {
        while (end > start) {
            const char ch = text[end - 1];
            if (ch == ' ' || ch == '\t' || ch == '\r' || ch == '\n' || ch == '\v' || ch == '\f') {
                --end;
            } else {
                break;
            }
        }
        return end;
    };

    while (cursor < text.size()) {
        const char ch = text[cursor];
        if (is_sentence_terminator(ch) && !is_decimal_point(text, cursor) && !is_abbreviation_period(text, cursor)) {
            std::size_t end = cursor + 1;
            while (end < text.size() && is_closing_punctuation(text[end])) {
                ++end;
            }
            while (end < text.size()) {
                const char ws = text[end];
                if (ws == ' ' || ws == '\t' || ws == '\r' || ws == '\n' || ws == '\v' || ws == '\f') {
                    ++end;
                } else {
                    break;
                }
            }
            const std::size_t trimmed_end = trim_end(end);
            if (trimmed_end > start) {
                ranges.emplace_back(start, trimmed_end);
            }
            start = end;
            cursor = end;
            continue;
        }
        ++cursor;
    }

    if (start < text.size()) {
        const std::size_t trimmed_end = trim_end(text.size());
        if (trimmed_end > start) {
            ranges.emplace_back(start, trimmed_end);
        }
    }

    if (ranges.empty() && !text.empty()) {
        ranges.emplace_back(0, text.size());
    }

    return ranges;
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

void add_atom(
    TxtAtomIndex& index,
    const TxtImportRecord& record,
    const TxtParagraphRecord& paragraph,
    const std::size_t atom_index,
    const std::size_t local_start,
    const std::size_t local_end,
    const TxtAtomKind kind
) {
    TxtAtomRecord atom;
    atom.kind = kind;
    atom.paragraph_index = paragraph.paragraph_index;
    atom.section_index = paragraph.section_index;
    atom.atom_index = atom_index;
    atom.start_offset = paragraph.start_offset + local_start;
    atom.end_offset = paragraph.start_offset + local_end;
    atom.text = paragraph.text.substr(local_start, local_end - local_start);
    atom.is_heading = paragraph.is_heading;
    atom.checksum = fnv1a64(std::span<const std::uint8_t>(
        reinterpret_cast<const std::uint8_t*>(atom.text.data()),
        atom.text.size()
    ));
    atom.atom_id = make_atom_id(record, paragraph, atom_index, kind, atom.start_offset, atom.end_offset, atom.checksum);

    const std::size_t index_position = index.atoms.size();
    index.atom_id_to_index.emplace(atom.atom_id, index_position);
    index.text_to_indices[atom.text].push_back(index_position);
    index.checksum_to_indices[atom.checksum].push_back(index_position);
    index.atoms.emplace_back(std::move(atom));
}

} // namespace

TxtAtomIndex build_txt_atom_index(const TxtImportRecord& record, std::string& error) {
    error.clear();

    TxtAtomIndex index;
    for (const auto& paragraph : record.paragraphs) {
        if (paragraph.text.empty()) {
            continue;
        }

        std::vector<std::pair<std::size_t, std::size_t>> ranges;
        TxtAtomKind kind = TxtAtomKind::Paragraph;
        if (should_keep_whole_paragraph(paragraph)) {
            ranges.emplace_back(0u, paragraph.text.size());
        } else {
            const auto split = split_atom_ranges(paragraph.text);
            ranges = split.ranges;
            kind = split.used_sentence_split && ranges.size() > 1u ? TxtAtomKind::Sentence : TxtAtomKind::Paragraph;
        }

        for (std::size_t atom_index = 0; atom_index < ranges.size(); ++atom_index) {
            const auto [local_start, local_end] = ranges[atom_index];
            add_atom(index, record, paragraph, atom_index, local_start, local_end, kind);
        }
    }

    if (index.atoms.empty()) {
        error = "No atoms were produced from the input";
    }

    return index;
}

const TxtAtomRecord* find_txt_atom_by_id(const TxtAtomIndex& index, std::string_view atom_id) {
    const auto it = index.atom_id_to_index.find(std::string(atom_id));
    if (it == index.atom_id_to_index.end()) {
        return nullptr;
    }
    if (it->second >= index.atoms.size()) {
        return nullptr;
    }
    return &index.atoms[it->second];
}

std::vector<const TxtAtomRecord*> find_txt_atoms_by_text(const TxtAtomIndex& index, std::string_view text) {
    std::vector<const TxtAtomRecord*> matches;
    const auto it = index.text_to_indices.find(std::string(text));
    if (it == index.text_to_indices.end()) {
        return matches;
    }
    matches.reserve(it->second.size());
    for (const std::size_t position : it->second) {
        if (position < index.atoms.size()) {
            matches.push_back(&index.atoms[position]);
        }
    }
    return matches;
}

bool write_txt_atom_manifest(const TxtImportRecord& record, const TxtAtomIndex& index, const std::filesystem::path& path, std::string& error) {
    std::string out;
    out.reserve(1024 + index.atoms.size() * 256);

    out += "format=ContextVaultTxtAtomManifest\n";
    out += "source_kind=";
    out += (record.source_kind == ImportSourceKind::ChatGPT) ? "chatgpt" : "txt";
    out += "\n";
    out += "source_path=";
    out += record.source_path.string();
    out += "\n";
    out += "title=";
    out += record.title;
    out += "\n";
    out += "source_checksum=" + std::to_string(record.source_checksum) + "\n";
    out += "section_count=" + std::to_string(record.sections.size()) + "\n";
    out += "date_count=" + std::to_string(record.dates.size()) + "\n";
    out += "numeric_count=" + std::to_string(record.numerics.size()) + "\n";
    out += "paragraph_count=" + std::to_string(record.paragraphs.size()) + "\n";
    out += "atom_count=" + std::to_string(index.atoms.size()) + "\n";

    auto append_escaped = [&out](std::string_view text) {
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
    };

    for (const auto& section : record.sections) {
        out += "\n[section ";
        out += std::to_string(section.section_index);
        out += "]\n";
        out += "heading_paragraph_index=" + std::to_string(section.heading_paragraph_index) + "\n";
        out += "start_paragraph_index=" + std::to_string(section.start_paragraph_index) + "\n";
        out += "end_paragraph_index=" + std::to_string(section.end_paragraph_index) + "\n";
        out += "heading_text=";
        append_escaped(section.heading_text);
        out += "\n";
    }

    for (const auto& atom : index.atoms) {
        out += "\n[atom ";
        out += std::to_string(atom.paragraph_index);
        out += ':';
        out += std::to_string(atom.atom_index);
        out += "]\n";
        out += "atom_id=" + atom.atom_id + "\n";
        out += "kind=" + atom_kind_name(atom.kind) + "\n";
        out += "section_index=" + std::to_string(atom.section_index) + "\n";
        out += "is_heading=";
        out += atom.is_heading ? "yes" : "no";
        out += "\n";
        out += "start_offset=" + std::to_string(atom.start_offset) + "\n";
        out += "end_offset=" + std::to_string(atom.end_offset) + "\n";
        out += "checksum=" + std::to_string(atom.checksum) + "\n";
        out += "text=";
        for (const char ch : atom.text) {
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
        out += "\n";
    }

    const std::vector<std::uint8_t> bytes(out.begin(), out.end());
    return write_file(path, bytes, error);
}

std::uint64_t make_phrase_fingerprint(std::string_view normalized_text, std::size_t term_count);
std::string make_leading_signature(std::string_view normalized_text, std::size_t max_terms = 10);
std::string make_pattern_family_key(std::string_view normalized_text, std::size_t leading_terms = 8, std::size_t trailing_terms = 6);
std::string normalize_change_probe_value(std::string_view value);
struct ResidualChange {
    bool valid = false;
    std::string kind;
    std::string left;
    std::string right;
};
ResidualChange detect_residual_change(const std::vector<std::string>& left_terms, const std::vector<std::string>& right_terms);
double jaccard_similarity_terms(const std::vector<std::string>& lhs, const std::vector<std::string>& rhs);
double jaccard_similarity_hashes(const std::vector<std::uint64_t>& lhs, const std::vector<std::uint64_t>& rhs);
std::size_t count_term_hits_normalized(std::string_view text, const std::vector<std::string>& terms);
std::string first_distinct_value(const std::vector<std::string>& lhs, const std::vector<std::string>& rhs);
std::uint64_t hash_text64(std::string_view text);
std::vector<std::uint64_t> make_term_shingles(const std::vector<std::string>& terms, std::string_view fallback_text);
std::uint64_t make_simhash_signature(
    const std::vector<std::string>& terms,
    const std::unordered_map<std::string, std::vector<std::size_t>>& term_to_indices,
    std::string_view fallback_text,
    double fallback_weight
);
std::uint64_t make_simhash_band_key(std::uint64_t signature, std::size_t band);

TxtAtomSearchIndex build_txt_atom_search_index(const TxtImportRecord& record, const TxtAtomIndex& index, std::string& error) {
    error.clear();

    TxtAtomSearchIndex search_index;
    search_index.atom_index = &index;
    search_index.source_record = &record;
    search_index.atom_terms.reserve(index.atoms.size());
    search_index.atom_term_sequences.reserve(index.atoms.size());
    search_index.normalized_atom_texts.reserve(index.atoms.size());
    search_index.lower_atom_texts.reserve(index.atoms.size());
    search_index.normalized_section_headings.reserve(index.atoms.size());
    search_index.atom_term_counts.reserve(index.atoms.size());
    search_index.atom_is_title_like.reserve(index.atoms.size());
    search_index.atom_is_cover_like.reserve(index.atoms.size());
    search_index.atom_has_what_cue.reserve(index.atoms.size());
    search_index.atom_has_how_form_cue.reserve(index.atoms.size());
    search_index.atom_has_how_collapse_cue.reserve(index.atoms.size());
    search_index.atom_has_how_cause_cue.reserve(index.atoms.size());
    search_index.atom_has_how_using_cue.reserve(index.atoms.size());
    search_index.atom_has_how_study_cue.reserve(index.atoms.size());
    search_index.atom_has_where_cue.reserve(index.atoms.size());
    search_index.atom_has_why_cue.reserve(index.atoms.size());
    search_index.atom_has_when_cue.reserve(index.atoms.size());
    search_index.atom_has_who_cue.reserve(index.atoms.size());
    search_index.change_index_ready = false;
    search_index.duplicate_support_ready = false;

    std::vector<std::string> normalized_section_headings(record.sections.size());
    for (std::size_t section_index = 0; section_index < record.sections.size(); ++section_index) {
        normalized_section_headings[section_index] = normalize_for_search(record.sections[section_index].heading_text);
    }

    for (std::size_t atom_index = 0; atom_index < index.atoms.size(); ++atom_index) {
        const auto& atom = index.atoms[atom_index];
        const AtomTextAnalysis atom_analysis = analyze_atom_text(atom.text);
        std::vector<std::string> ordered_terms = atom_analysis.ordered_terms;
        std::vector<std::string> terms = ordered_terms;
        std::sort(terms.begin(), terms.end());
        terms.erase(std::unique(terms.begin(), terms.end()), terms.end());
        const std::string normalized_atom_text = atom_analysis.normalized_text;
        const std::string normalized_section_heading =
            atom.section_index < normalized_section_headings.size()
                ? normalized_section_headings[atom.section_index]
                : std::string();
        const std::size_t newline_count = atom_analysis.newline_count;
        const std::size_t sentence_count = atom_analysis.sentence_mark_count;
        const std::size_t period_count = atom_analysis.period_count;
        const bool title_like_atom = terms.size() <= 18u &&
            atom.text.size() <= 220u &&
            newline_count <= 3u &&
            (sentence_count + period_count) <= 1u;
        const bool cover_like_atom = terms.size() <= 30u &&
            atom.text.size() <= 260u &&
            newline_count >= 2u &&
            (sentence_count + period_count) <= 2u;
        const auto atom_contains_any = [](std::string_view text, const std::array<std::string_view, 6>& needles) {
            for (const std::string_view needle : needles) {
                if (!needle.empty() && text.find(needle) != std::string::npos) {
                    return true;
                }
            }
            return false;
        };
        const std::string& lower_atom = atom_analysis.lower_text;
        search_index.normalized_atom_texts.push_back(normalized_atom_text);
        search_index.lower_atom_texts.push_back(lower_atom);
        search_index.normalized_section_headings.push_back(normalized_section_heading);
        search_index.atom_term_counts.push_back(terms.size());
        search_index.atom_is_title_like.push_back(title_like_atom);
        search_index.atom_is_cover_like.push_back(cover_like_atom);
        search_index.atom_has_what_cue.push_back(atom_contains_any(lower_atom, {" is ", " are ", " means ", " refers to ", " described by ", ""}));
        search_index.atom_has_how_form_cue.push_back(atom_contains_any(lower_atom, {" form ", " forms ", " formed ", " forming ", "", ""}));
        search_index.atom_has_how_collapse_cue.push_back(atom_contains_any(lower_atom, {" collapse ", " collapsed ", " collapsing ", "", "", ""}));
        search_index.atom_has_how_cause_cue.push_back(atom_contains_any(lower_atom, {" cause ", " caused ", " causes ", " because ", " due to ", ""}));
        search_index.atom_has_how_using_cue.push_back(atom_contains_any(lower_atom, {" using ", " by ", " through ", "", "", ""}));
        search_index.atom_has_how_study_cue.push_back(atom_contains_any(lower_atom, {" studied ", " study ", " observing ", " observed ", "", ""}));
        search_index.atom_has_where_cue.push_back(atom_contains_any(lower_atom, {" found ", " located ", " center ", " centers ", " at the ", " in the "}));
        search_index.atom_has_why_cue.push_back(atom_contains_any(lower_atom, {" because ", " due to ", " since ", " so ", "", ""}));
        search_index.atom_has_when_cue.push_back(atom_contains_any(lower_atom, {" when ", " after ", " before ", "", "", ""}));
        search_index.atom_has_who_cue.push_back(atom_contains_any(lower_atom, {" scientists ", " people ", " researchers ", "", "", ""}));
        search_index.atom_term_sequences.push_back(std::move(ordered_terms));
        if (terms.empty()) {
            search_index.atom_terms.emplace_back();
            continue;
        }

        for (const auto& term : terms) {
            search_index.term_to_indices[term].push_back(atom_index);
        }
        search_index.atom_terms.push_back(std::move(terms));
    }

    if (search_index.atom_index == nullptr || index.atoms.empty()) {
        error = "Search index has no atoms";
    }

    return search_index;
}

bool build_txt_change_index(const TxtImportRecord& record, const TxtAtomIndex& index, TxtAtomSearchIndex& search_index, std::string& error) {
    error.clear();
    (void)record;

    if (search_index.change_index_ready) {
        return true;
    }
    if (search_index.atom_index == nullptr || search_index.source_record == nullptr) {
        error = "Search index is missing source pointers";
        return false;
    }

    search_index.change_records.clear();
    search_index.change_key_to_indices.clear();
    search_index.change_kind_to_indices.clear();
    search_index.change_family_to_indices.clear();
    search_index.residual_records.clear();
    search_index.residual_key_to_indices.clear();
    search_index.residual_kind_to_indices.clear();
    search_index.residual_family_to_indices.clear();

    search_index.change_records.reserve(index.atoms.size());
    for (std::size_t left_index = 0; left_index < index.atoms.size(); ++left_index) {
        const auto& left_atom = index.atoms[left_index];
        for (std::size_t right_index = left_index + 1; right_index < index.atoms.size(); ++right_index) {
            const auto& right_atom = index.atoms[right_index];
            if (left_atom.section_index != right_atom.section_index) {
                continue;
            }

            const double similarity = jaccard_similarity_terms(search_index.atom_terms[left_index], search_index.atom_terms[right_index]);
            const QueryShapeSignals left_shape = extract_text_shape_signals(left_atom.text);
            const QueryShapeSignals right_shape = extract_text_shape_signals(right_atom.text);
            const auto& left_dates = left_shape.date_signatures;
            const auto& right_dates = right_shape.date_signatures;
            const auto& left_numbers = left_shape.numeric_signatures;
            const auto& right_numbers = right_shape.numeric_signatures;
            const auto& left_abbr = left_shape.abbreviation_signatures;
            const auto& right_abbr = right_shape.abbreviation_signatures;
            const bool has_date_signal = !left_dates.empty() || !right_dates.empty();
            const bool has_numeric_signal = !left_numbers.empty() || !right_numbers.empty();
            const bool has_abbreviation_signal = !left_abbr.empty() || !right_abbr.empty();
            const std::size_t left_term_count = search_index.atom_term_counts[left_index];
            const std::size_t right_term_count = search_index.atom_term_counts[right_index];
            const bool clause_length_skew = left_term_count > right_term_count + 2u || right_term_count > left_term_count + 2u;
            const double change_similarity_threshold = has_date_signal
                ? 0.45
                : clause_length_skew
                    ? 0.10
                    : has_numeric_signal
                    ? 0.55
                    : has_abbreviation_signal
                        ? 0.55
                        : 0.60;
            if (similarity < change_similarity_threshold) {
                continue;
            }
            if (search_index.normalized_atom_texts[left_index] == search_index.normalized_atom_texts[right_index]) {
                continue;
            }

            std::string change_kind;
            std::string left_value;
            std::string right_value;

            if (!left_dates.empty() || !right_dates.empty()) {
                if (left_dates == right_dates) {
                    continue;
                }
                change_kind = "change-date";
                left_value = first_distinct_value(left_dates, right_dates);
                right_value = first_distinct_value(right_dates, left_dates);
            } else if (!left_numbers.empty() || !right_numbers.empty()) {
                if (left_numbers == right_numbers) {
                    continue;
                }
                change_kind = "change-number";
                left_value = first_distinct_value(left_numbers, right_numbers);
                right_value = first_distinct_value(right_numbers, left_numbers);
            } else if (!left_abbr.empty() || !right_abbr.empty()) {
                if (left_abbr == right_abbr) {
                    continue;
                }
                change_kind = "change-entity";
                left_value = first_distinct_value(left_abbr, right_abbr);
                right_value = first_distinct_value(right_abbr, left_abbr);
            } else {
                const ResidualChange residual_change = detect_residual_change(
                    search_index.atom_term_sequences[left_index],
                    search_index.atom_term_sequences[right_index]
                );
                if (residual_change.valid) {
                    change_kind = residual_change.kind;
                    left_value = residual_change.left;
                    right_value = residual_change.right;
                } else {
                    change_kind = "change-entity";
                    left_value = first_distinct_value(search_index.atom_terms[left_index], search_index.atom_terms[right_index]);
                    right_value = first_distinct_value(search_index.atom_terms[right_index], search_index.atom_terms[left_index]);
                    if (left_value.empty() || right_value.empty()) {
                        continue;
                    }
                }
            }

            if (change_kind == "change-replace" && (left_value.empty() || right_value.empty())) {
                left_value = first_distinct_value(search_index.atom_terms[left_index], search_index.atom_terms[right_index]);
                right_value = first_distinct_value(search_index.atom_terms[right_index], search_index.atom_terms[left_index]);
                if (left_value.empty() || right_value.empty()) {
                    continue;
                }
            }

            left_value = normalize_change_probe_value(left_value);
            right_value = normalize_change_probe_value(right_value);
            if (change_kind == "change-insert") {
                if (right_value.empty()) {
                    continue;
                }
            } else if (change_kind == "change-delete") {
                if (left_value.empty()) {
                    continue;
                }
            } else {
                if (left_value.empty() || right_value.empty() || left_value == right_value) {
                    continue;
                }
            }

            TxtChangeRecord record_entry;
            record_entry.left_atom_index = left_index;
            record_entry.right_atom_index = right_index;
            record_entry.change_kind = change_kind;
            record_entry.left_value = left_value;
            record_entry.right_value = right_value;
            record_entry.family_key = tp::make_leading_signature(search_index.normalized_atom_texts[left_index], 8);
            record_entry.similarity = similarity;

            const std::size_t record_index = search_index.change_records.size();
            search_index.change_records.push_back(std::move(record_entry));
            const std::string key = change_kind + "|" + left_value + "->" + right_value;
            search_index.change_key_to_indices[key].push_back(record_index);
            search_index.change_key_to_indices[change_kind + "|" + right_value + "->" + left_value].push_back(record_index);
            search_index.change_kind_to_indices[change_kind].push_back(record_index);
            search_index.change_family_to_indices[change_kind + "|" + search_index.change_records.back().family_key].push_back(record_index);
            if (is_residual_change_kind(change_kind)) {
                const std::size_t residual_index = search_index.residual_records.size();
                search_index.residual_records.push_back(TxtResidualRecord{
                    record_index,
                    change_kind,
                    search_index.change_records.back().family_key
                });
                search_index.residual_key_to_indices[key].push_back(residual_index);
                search_index.residual_key_to_indices[change_kind + "|" + right_value + "->" + left_value].push_back(residual_index);
                search_index.residual_kind_to_indices[change_kind].push_back(residual_index);
                search_index.residual_family_to_indices[change_kind + "|" + search_index.change_records.back().family_key].push_back(residual_index);
            }
        }
    }

    search_index.change_index_ready = true;
    return true;
}

bool build_txt_duplicate_support_index(const TxtAtomIndex& index, TxtAtomSearchIndex& search_index, std::string& error) {
    error.clear();

    if (search_index.duplicate_support_ready) {
        return true;
    }
    if (search_index.atom_index == nullptr) {
        error = "Search index is missing source atom index";
        return false;
    }

    const std::size_t atom_count = index.atoms.size();
    search_index.atom_phrase_fingerprints.clear();
    search_index.atom_phrase_fingerprint_group_sizes.clear();
    search_index.phrase_fingerprint_to_indices.clear();
    search_index.atom_family_keys.clear();
    search_index.atom_family_group_sizes.clear();
    search_index.atom_duplicate_group_sizes.clear();
    search_index.family_key_to_indices.clear();
    search_index.atom_shingles.clear();
    search_index.shingle_to_indices.clear();
    search_index.atom_simhashes.clear();
    search_index.simhash_band_to_indices.clear();

    search_index.atom_phrase_fingerprints.reserve(atom_count);
    search_index.atom_phrase_fingerprint_group_sizes.reserve(atom_count);
    search_index.atom_family_keys.reserve(atom_count);
    search_index.atom_family_group_sizes.reserve(atom_count);
    search_index.atom_duplicate_group_sizes.reserve(atom_count);
    search_index.atom_shingles.reserve(atom_count);
    search_index.atom_simhashes.reserve(atom_count);

    for (std::size_t atom_index = 0; atom_index < atom_count; ++atom_index) {
        if (atom_index >= search_index.normalized_atom_texts.size() ||
            atom_index >= search_index.atom_term_counts.size() ||
            atom_index >= search_index.atom_terms.size() ||
            atom_index >= search_index.atom_shingles.size()) {
            error = "Duplicate support index is missing atom analysis";
            return false;
        }

        const auto& atom = index.atoms[atom_index];
        const std::string& normalized_atom_text = search_index.normalized_atom_texts[atom_index];
        const std::size_t term_count = search_index.atom_term_counts[atom_index];
        const std::string family_key = make_pattern_family_key(normalized_atom_text);
        const std::uint64_t phrase_fingerprint = make_phrase_fingerprint(normalized_atom_text, term_count);
        const std::vector<std::uint64_t> shingles = make_term_shingles(search_index.atom_term_sequences[atom_index], normalized_atom_text);
        const std::uint64_t simhash = make_simhash_signature(search_index.atom_terms[atom_index], search_index.term_to_indices, normalized_atom_text, 0.35);

        search_index.atom_family_keys.push_back(family_key);
        search_index.family_key_to_indices[family_key].push_back(atom_index);
        search_index.atom_phrase_fingerprints.push_back(phrase_fingerprint);
        search_index.phrase_fingerprint_to_indices[phrase_fingerprint].push_back(atom_index);
        search_index.atom_shingles.push_back(shingles);
        for (const std::uint64_t shingle : shingles) {
            search_index.shingle_to_indices[shingle].push_back(atom_index);
        }
        search_index.atom_simhashes.push_back(simhash);
        for (std::size_t band = 0; band < 4u; ++band) {
            search_index.simhash_band_to_indices[make_simhash_band_key(simhash, band)].push_back(atom_index);
        }

        const auto checksum_it = index.checksum_to_indices.find(atom.checksum);
        search_index.atom_duplicate_group_sizes.push_back(
            checksum_it != index.checksum_to_indices.end() ? checksum_it->second.size() : 1u
        );
    }

    for (std::size_t atom_index = 0; atom_index < atom_count; ++atom_index) {
        const auto family_it = search_index.family_key_to_indices.find(search_index.atom_family_keys[atom_index]);
        search_index.atom_family_group_sizes.push_back(
            family_it != search_index.family_key_to_indices.end() ? family_it->second.size() : 1u
        );

        const auto phrase_it = search_index.phrase_fingerprint_to_indices.find(search_index.atom_phrase_fingerprints[atom_index]);
        search_index.atom_phrase_fingerprint_group_sizes.push_back(
            phrase_it != search_index.phrase_fingerprint_to_indices.end() ? phrase_it->second.size() : 1u
        );
    }

    search_index.duplicate_support_ready = true;
    return true;
}

namespace {

std::vector<std::string> extract_quoted_phrases(std::string_view query) {
    std::vector<std::string> phrases;
    std::size_t pos = 0;
    while (pos < query.size()) {
        const std::size_t open = query.find('"', pos);
        if (open == std::string_view::npos) {
            break;
        }
        const std::size_t close = query.find('"', open + 1);
        if (close == std::string_view::npos) {
            break;
        }
        if (close > open + 1) {
            phrases.emplace_back(query.substr(open + 1, close - open - 1));
        }
        pos = close + 1;
    }
    return phrases;
}

struct NearClause {
    std::string left;
    std::string right;
    std::size_t distance = 0;
    bool valid = false;
};

struct ChangeQuery {
    bool valid = false;
    std::string kind;
    std::string left;
    std::string right;
};

NearClause parse_near_clause(std::string_view query) {
    const std::string lower_query = lower_ascii(query);
    const std::size_t near_pos = lower_query.find("near/");
    if (near_pos == std::string::npos) {
        return {};
    }

    std::size_t left_end = near_pos;
    while (left_end > 0 && std::isspace(static_cast<unsigned char>(lower_query[left_end - 1]))) {
        --left_end;
    }
    std::size_t left_start = left_end;
    while (left_start > 0 && std::isalnum(static_cast<unsigned char>(lower_query[left_start - 1]))) {
        --left_start;
    }

    std::size_t num_start = near_pos + 5;
    std::size_t num_end = num_start;
    while (num_end < lower_query.size() && std::isdigit(static_cast<unsigned char>(lower_query[num_end]))) {
        ++num_end;
    }
    if (num_end == num_start) {
        return {};
    }

    std::size_t right_start = num_end;
    while (right_start < lower_query.size() && std::isspace(static_cast<unsigned char>(lower_query[right_start]))) {
        ++right_start;
    }
    std::size_t right_end = right_start;
    while (right_end < lower_query.size() && std::isalnum(static_cast<unsigned char>(lower_query[right_end]))) {
        ++right_end;
    }
    if (left_start == left_end || right_start == right_end) {
        return {};
    }

    NearClause clause;
    clause.left = lower_query.substr(left_start, left_end - left_start);
    clause.right = lower_query.substr(right_start, right_end - right_start);
    try {
        clause.distance = static_cast<std::size_t>(std::stoul(std::string(lower_query.substr(num_start, num_end - num_start))));
    } catch (...) {
        return {};
    }
    clause.valid = !clause.left.empty() && !clause.right.empty();
    return clause;
}

ChangeQuery parse_change_query(std::string_view query) {
    const std::string lower_query = lower_ascii(query);
    struct KeywordKind {
        std::string_view keyword;
        std::string_view kind;
    };
    static const KeywordKind kKeywords[] = {
        {"changed value", "change-number"},
        {"changed date", "change-date"},
        {"changed entity", "change-entity"},
        {"change value", "change-number"},
        {"change date", "change-date"},
        {"change entity", "change-entity"},
        {"value changed", "change-number"},
        {"date changed", "change-date"},
        {"entity changed", "change-entity"},
        {"inserted", "change-insert"},
        {"deleted", "change-delete"},
        {"replaced", "change-replace"},
        {"insert ", "change-insert"},
        {"delete ", "change-delete"},
        {"replace ", "change-replace"}
    };

    std::size_t keyword_pos = std::string::npos;
    std::string_view keyword_text;
    std::string_view kind;
    for (const auto& entry : kKeywords) {
        const std::size_t pos = lower_query.find(entry.keyword);
        if (pos != std::string::npos && (keyword_pos == std::string::npos || pos < keyword_pos)) {
            keyword_pos = pos;
            keyword_text = entry.keyword;
            kind = entry.kind;
        }
    }
    if (keyword_pos == std::string::npos) {
        return {};
    }

    const std::size_t arrow_pos = lower_query.find("->", keyword_pos);
    ChangeQuery result;
    result.kind = std::string(kind);
    if (arrow_pos == std::string::npos) {
        std::string_view payload = query.substr(keyword_pos + keyword_text.size());
        result.left.clear();
        result.right = normalize_change_probe_value(trim_copy_local(payload));
        result.valid = true;
        return result;
    }

    result.valid = arrow_pos > keyword_pos + keyword_text.size();
    if (!result.valid) {
        return {};
    }
    std::string_view left_raw = query.substr(keyword_pos + keyword_text.size(), arrow_pos - (keyword_pos + keyword_text.size()));
    std::string_view right_raw = query.substr(arrow_pos + 2);
    result.left = normalize_change_probe_value(trim_copy_local(left_raw));
    result.right = normalize_change_probe_value(trim_copy_local(right_raw));
    if (result.kind == "change-number") {
        const bool left_date = result.left.size() == 10u && result.left.find('-') != std::string::npos;
        const bool right_date = result.right.size() == 10u && result.right.find('-') != std::string::npos;
        if (left_date && right_date) {
            result.kind = "change-date";
        } else if (!result.left.empty() && !result.right.empty() &&
                   std::any_of(result.left.begin(), result.left.end(), [](const char ch) { return std::isdigit(static_cast<unsigned char>(ch)) != 0; }) &&
                   std::any_of(result.right.begin(), result.right.end(), [](const char ch) { return std::isdigit(static_cast<unsigned char>(ch)) != 0; })) {
            result.kind = "change-number";
        } else {
            result.kind = "change-entity";
        }
    }
    return result;
}

bool satisfies_near_clause(const std::vector<std::string>& terms, const NearClause& clause) {
    if (!clause.valid || terms.empty()) {
        return false;
    }
    std::vector<std::size_t> left_positions;
    std::vector<std::size_t> right_positions;
    left_positions.reserve(terms.size());
    right_positions.reserve(terms.size());
    for (std::size_t i = 0; i < terms.size(); ++i) {
        if (terms[i] == clause.left) {
            left_positions.push_back(i);
        }
        if (terms[i] == clause.right) {
            right_positions.push_back(i);
        }
    }
    for (const std::size_t left : left_positions) {
        for (const std::size_t right : right_positions) {
            const std::size_t gap = (left > right) ? (left - right) : (right - left);
            if (gap <= clause.distance) {
                return true;
            }
        }
    }
    return false;
}

bool contains_term_sequence(
    const std::vector<std::string>& haystack,
    const std::vector<std::string>& needle,
    std::size_t& first_match_index
) {
    first_match_index = 0;
    if (needle.empty() || haystack.size() < needle.size()) {
        return false;
    }
    for (std::size_t i = 0; i + needle.size() <= haystack.size(); ++i) {
        bool matches = true;
        for (std::size_t j = 0; j < needle.size(); ++j) {
            if (haystack[i + j] != needle[j]) {
                matches = false;
                break;
            }
        }
        if (matches) {
            first_match_index = i;
            return true;
        }
    }
    return false;
}

double compute_near_score(const std::vector<std::string>& terms, const NearClause& clause) {
    if (!clause.valid || terms.empty()) {
        return 0.0;
    }
    std::size_t best_gap = std::numeric_limits<std::size_t>::max();
    for (std::size_t i = 0; i < terms.size(); ++i) {
        if (terms[i] != clause.left) {
            continue;
        }
        for (std::size_t j = 0; j < terms.size(); ++j) {
            if (terms[j] != clause.right) {
                continue;
            }
            const std::size_t gap = (i > j) ? (i - j) : (j - i);
            if (gap < best_gap) {
                best_gap = gap;
            }
        }
    }
    if (best_gap == std::numeric_limits<std::size_t>::max() || best_gap > clause.distance) {
        return 0.0;
    }

    const double closeness = static_cast<double>(clause.distance - best_gap + 1u) /
                             static_cast<double>(clause.distance + 1u);
    return 2.5 + (closeness * 4.0);
}

std::string make_leading_signature(std::string_view normalized_text, const std::size_t max_terms = 10) {
    if (normalized_text.empty()) {
        return {};
    }

    std::string signature;
    signature.reserve(std::min<std::size_t>(normalized_text.size(), max_terms * 8u));
    std::size_t terms = 0;
    bool in_token = false;
    for (const char ch : normalized_text) {
        if (ch == ' ') {
            if (in_token) {
                ++terms;
                in_token = false;
                if (terms >= max_terms) {
                    break;
                }
            }
            if (!signature.empty() && signature.back() != ' ') {
                signature.push_back(' ');
            }
            continue;
        }
        signature.push_back(ch);
        in_token = true;
    }

    while (!signature.empty() && signature.back() == ' ') {
        signature.pop_back();
    }
    return signature;
}

std::string make_trailing_signature_local(std::string_view normalized_text, const std::size_t max_terms = 6) {
    if (normalized_text.empty()) {
        return {};
    }

    std::vector<std::string_view> terms;
    std::size_t pos = 0;
    while (pos < normalized_text.size()) {
        while (pos < normalized_text.size() && normalized_text[pos] == ' ') {
            ++pos;
        }
        const std::size_t start = pos;
        while (pos < normalized_text.size() && normalized_text[pos] != ' ') {
            ++pos;
        }
        if (start < pos) {
            terms.emplace_back(normalized_text.substr(start, pos - start));
        }
    }

    if (terms.empty()) {
        return std::string(normalized_text);
    }

    const std::size_t first_term = terms.size() > max_terms ? terms.size() - max_terms : 0u;
    std::string signature;
    for (std::size_t i = first_term; i < terms.size(); ++i) {
        if (!signature.empty()) {
            signature.push_back(' ');
        }
        signature.append(terms[i]);
    }
    return signature;
}

std::uint64_t make_phrase_fingerprint(std::string_view normalized_text, std::size_t term_count) {
    const std::string leading = tp::make_leading_signature(normalized_text, 8);
    const std::string trailing = make_trailing_signature_local(normalized_text, 6);
    std::string material;
    material.reserve(leading.size() + trailing.size() + 32);
    material += leading;
    material.push_back('|');
    material += trailing;
    material.push_back('|');
    material += std::to_string(term_count);
    material.push_back('|');
    material += std::to_string(normalized_text.size() / 16u);
    return fnv1a64(std::span<const std::uint8_t>(
        reinterpret_cast<const std::uint8_t*>(material.data()),
        material.size()
    ));
}

std::size_t count_occurrences(std::string_view text, char needle) {
    return static_cast<std::size_t>(std::count(text.begin(), text.end(), needle));
}

bool is_title_like_block(std::string_view text, std::size_t term_count) {
    const std::size_t newline_count = count_occurrences(text, '\n');
    const std::size_t sentence_count = static_cast<std::size_t>(std::count_if(text.begin(), text.end(), [](const char ch) {
        return ch == '!' || ch == '?' ;
    }));
    std::size_t period_count = 0;
    for (std::size_t pos = 0; pos < text.size(); ++pos) {
        if (text[pos] == '.' && !is_decimal_point(text, pos) && !is_abbreviation_period(text, pos)) {
            ++period_count;
        }
    }
    return term_count <= 18u &&
           text.size() <= 220u &&
           newline_count <= 3u &&
           (sentence_count + period_count) <= 1u;
}

bool is_cover_like_block(std::string_view text, std::size_t term_count) {
    const std::size_t newline_count = count_occurrences(text, '\n');
    const std::size_t sentence_count = static_cast<std::size_t>(std::count_if(text.begin(), text.end(), [](const char ch) {
        return ch == '!' || ch == '?';
    }));
    std::size_t period_count = 0;
    for (std::size_t pos = 0; pos < text.size(); ++pos) {
        if (text[pos] == '.' && !is_decimal_point(text, pos) && !is_abbreviation_period(text, pos)) {
            ++period_count;
        }
    }
    return term_count <= 30u &&
           text.size() <= 260u &&
           newline_count >= 2u &&
           (sentence_count + period_count) <= 2u;
}

} // namespace

std::vector<TxtAtomSearchHit> search_txt_atoms(
    TxtAtomSearchIndex& index,
    std::string_view query,
    std::size_t max_results,
    std::string& error,
    const bool all_occurrences
) {
    error.clear();
    std::vector<TxtAtomSearchHit> results;
    if (!index.atom_index || index.atom_index->atoms.empty()) {
        error = "Search index is empty";
        return results;
    }
    if (max_results == 0) {
        return results;
    }

    const StructuralQueryFilters structural_filters = parse_structural_query_filters(query);
    const std::string cleaned_query = structural_filters.cleaned_query;
    const std::vector<std::string> query_terms = extract_search_terms(cleaned_query);
    const std::vector<std::string> query_phrases = extract_quoted_phrases(cleaned_query);
    const std::vector<std::string> ordered_query_terms = extract_ordered_search_terms(cleaned_query);
    const NearClause near_clause = parse_near_clause(cleaned_query);
    const QuerySignals query_signals = analyze_query_signals(cleaned_query, query_terms);
    const QueryShapeSignals query_shape_signals {
        extract_date_signatures(cleaned_query),
        extract_numeric_signatures(cleaned_query),
        extract_abbreviation_signatures(cleaned_query)
    };
    const QueryIntent query_intent = classify_query_intent(cleaned_query, query_terms);
    const ChangeQuery change_query = parse_change_query(cleaned_query);
    const std::string normalized_cleaned_query = normalize_for_search(cleaned_query);
    const std::vector<std::uint64_t> query_shingles = make_term_shingles(ordered_query_terms, normalized_cleaned_query);
    if (query_terms.empty() && normalized_cleaned_query.empty() &&
        !structural_filters.has_section_filter && !structural_filters.has_heading_filter) {
        error = "Query is empty";
        return results;
    }

    if (all_occurrences) {
        std::vector<TxtAtomSearchHit> search_results;
        search_results.reserve(index.atom_index->atoms.size());
        const std::string normalized_search_query = normalized_cleaned_query.empty()
            ? normalize_for_search(cleaned_query)
            : normalized_cleaned_query;
        for (std::size_t atom_index = 0; atom_index < index.atom_index->atoms.size(); ++atom_index) {
            const auto& atom = index.atom_index->atoms[atom_index];
            if (!matches_structural_filters(index, atom, structural_filters)) {
                continue;
            }

            const std::string& normalized_atom = index.normalized_atom_texts[atom_index];
            const std::size_t occurrence_count = count_normalized_occurrences(normalized_atom, normalized_search_query);
            if (occurrence_count == 0u) {
                continue;
            }

            for (std::size_t occurrence_index = 0; occurrence_index < occurrence_count; ++occurrence_index) {
                TxtAtomSearchHit hit;
                hit.atom = &atom;
                hit.score = 1.0;
                hit.calibrated_score = 1.0;
                hit.matched_terms = query_terms.empty() ? 1u : query_terms.size();
                hit.phrase_matches = query_phrases.empty() ? 0u : 1u;
                hit.proximity_score = 0.0;
                hit.exact_text_match = !normalized_cleaned_query.empty() && normalized_atom == normalized_cleaned_query;
                if (index.duplicate_support_ready) {
                    hit.duplicate_group_size = atom_index < index.atom_duplicate_group_sizes.size()
                        ? index.atom_duplicate_group_sizes[atom_index]
                        : 1u;
                    hit.phrase_fingerprint = atom_index < index.atom_phrase_fingerprints.size()
                        ? index.atom_phrase_fingerprints[atom_index]
                        : 0u;
                    hit.phrase_fingerprint_group_size = atom_index < index.atom_phrase_fingerprint_group_sizes.size()
                        ? index.atom_phrase_fingerprint_group_sizes[atom_index]
                        : 1u;
                } else {
                    hit.duplicate_group_size = 1u;
                    hit.phrase_fingerprint = 0u;
                    hit.phrase_fingerprint_group_size = 1u;
                }
                hit.shingle_group_size = 1u;
                if (index.duplicate_support_ready && atom_index < index.atom_family_keys.size()) {
                    hit.pattern_family_key = index.atom_family_keys[atom_index];
                    hit.family_group_size = atom_index < index.atom_family_group_sizes.size()
                        ? index.atom_family_group_sizes[atom_index]
                        : 1u;
                }
                hit.match_reason = "search occurrence";
                search_results.push_back(std::move(hit));
            }
        }

        std::sort(search_results.begin(), search_results.end(), [](const TxtAtomSearchHit& lhs, const TxtAtomSearchHit& rhs) {
            if (!lhs.atom || !rhs.atom) {
                return lhs.atom != nullptr;
            }
            if (lhs.atom->paragraph_index != rhs.atom->paragraph_index) {
                return lhs.atom->paragraph_index < rhs.atom->paragraph_index;
            }
            if (lhs.atom->start_offset != rhs.atom->start_offset) {
                return lhs.atom->start_offset < rhs.atom->start_offset;
            }
            return lhs.atom->atom_index < rhs.atom->atom_index;
        });
        if (search_results.size() > max_results) {
            search_results.resize(max_results);
        }
        return search_results;
    }

    if (change_query.valid) {
        if (!build_txt_change_index(*index.source_record, *index.atom_index, index, error)) {
            return results;
        }
        const std::string change_key = change_query.kind + "|" + change_query.left + "->" + change_query.right;
        std::vector<std::size_t> record_indices;
        const bool residual_query = is_residual_change_kind(change_query.kind);
        if (residual_query) {
            const auto key_it = index.residual_key_to_indices.find(change_key);
            if (key_it != index.residual_key_to_indices.end()) {
                record_indices.reserve(key_it->second.size());
                for (const std::size_t residual_index : key_it->second) {
                    if (residual_index < index.residual_records.size()) {
                        record_indices.push_back(index.residual_records[residual_index].change_record_index);
                    }
                }
            } else {
                const auto kind_it = index.residual_kind_to_indices.find(change_query.kind);
                if (kind_it != index.residual_kind_to_indices.end()) {
                    record_indices.reserve(kind_it->second.size());
                    for (const std::size_t residual_index : kind_it->second) {
                        if (residual_index < index.residual_records.size()) {
                            record_indices.push_back(index.residual_records[residual_index].change_record_index);
                        }
                    }
                } else {
                    for (const auto& entry : index.residual_key_to_indices) {
                        if (entry.first.rfind(change_query.kind + "|", 0) == 0) {
                            for (const std::size_t residual_index : entry.second) {
                                if (residual_index < index.residual_records.size()) {
                                    record_indices.push_back(index.residual_records[residual_index].change_record_index);
                                }
                            }
                        }
                    }
                }
            }
        } else {
            const auto key_it = index.change_key_to_indices.find(change_key);
            if (key_it != index.change_key_to_indices.end()) {
                record_indices = key_it->second;
            } else {
                const auto kind_it = index.change_kind_to_indices.find(change_query.kind);
                if (kind_it != index.change_kind_to_indices.end()) {
                    record_indices = kind_it->second;
                } else {
                    for (const auto& entry : index.change_key_to_indices) {
                        if (entry.first.rfind(change_query.kind + "|", 0) == 0) {
                            record_indices.insert(record_indices.end(), entry.second.begin(), entry.second.end());
                        }
                    }
                }
            }
        }

        std::vector<TxtAtomSearchHit> change_results;
        for (const std::size_t record_index : record_indices) {
            if (record_index >= index.change_records.size()) {
                continue;
            }
            const auto& record = index.change_records[record_index];
            const auto* atom = &index.atom_index->atoms[record.right_atom_index];
            const auto* left_atom = &index.atom_index->atoms[record.left_atom_index];
            TxtAtomSearchHit hit;
            hit.atom = atom;
            hit.score = 12.0 * record.similarity;
            hit.near_duplicate_similarity = record.similarity;
            hit.change_context_overlap = count_term_hits_normalized(left_atom->text, query_terms) +
                                         count_term_hits_normalized(atom->text, query_terms);
            hit.exact_change_value_match =
                (record.left_value == change_query.left && record.right_value == change_query.right) ||
                (record.left_value == change_query.right && record.right_value == change_query.left);
            if (hit.exact_change_value_match) {
                hit.score += 6.0;
            }
            if (hit.change_context_overlap > 0) {
                hit.score += static_cast<double>(hit.change_context_overlap) * 0.75;
            }
            if (index.duplicate_support_ready) {
                hit.duplicate_group_size = record.right_atom_index < index.atom_duplicate_group_sizes.size()
                    ? index.atom_duplicate_group_sizes[record.right_atom_index]
                    : 1u;
                hit.phrase_fingerprint = record.right_atom_index < index.atom_phrase_fingerprints.size()
                    ? index.atom_phrase_fingerprints[record.right_atom_index]
                    : 0u;
                hit.phrase_fingerprint_group_size = record.right_atom_index < index.atom_phrase_fingerprint_group_sizes.size()
                    ? index.atom_phrase_fingerprint_group_sizes[record.right_atom_index]
                    : 1u;
                if (record.right_atom_index < index.atom_family_keys.size()) {
                    hit.pattern_family_key = index.atom_family_keys[record.right_atom_index];
                }
            } else {
                hit.duplicate_group_size = 1u;
                hit.phrase_fingerprint = 0u;
                hit.phrase_fingerprint_group_size = 1u;
            }
            if (index.duplicate_support_ready && record.right_atom_index < index.atom_family_keys.size()) {
                hit.pattern_family_key = index.atom_family_keys[record.right_atom_index];
            }
            hit.change_kind = record.change_kind;
            hit.change_left = record.left_value;
            hit.change_right = record.right_value;
            hit.calibrated_score = hit.score;
            hit.match_reason = hit.exact_change_value_match ? "exact change value" : record.change_kind;
            change_results.push_back(std::move(hit));
        }

        std::sort(change_results.begin(), change_results.end(), [](const TxtAtomSearchHit& lhs, const TxtAtomSearchHit& rhs) {
            if (lhs.exact_change_value_match != rhs.exact_change_value_match) {
                return lhs.exact_change_value_match > rhs.exact_change_value_match;
            }
            if (lhs.score != rhs.score) {
                return lhs.score > rhs.score;
            }
            if (lhs.change_context_overlap != rhs.change_context_overlap) {
                return lhs.change_context_overlap > rhs.change_context_overlap;
            }
            if (lhs.change_kind != rhs.change_kind) {
                return lhs.change_kind < rhs.change_kind;
            }
            const std::size_t lhs_len = lhs.atom ? lhs.atom->text.size() : 0;
            const std::size_t rhs_len = rhs.atom ? rhs.atom->text.size() : 0;
            if (lhs_len != rhs_len) {
                return lhs_len < rhs_len;
            }
            return lhs.atom && rhs.atom ? lhs.atom->paragraph_index < rhs.atom->paragraph_index : lhs.atom != nullptr;
        });
        if (change_results.size() > max_results) {
            change_results.resize(max_results);
        }
        return change_results;
    }

    if (query_signals.is_duplicate || query_signals.is_near_duplicate || query_signals.is_unique) {
        if (!index.duplicate_support_ready) {
            if (!build_txt_duplicate_support_index(*index.atom_index, index, error)) {
                return {};
            }
        }
        std::vector<TxtAtomSearchHit> duplicate_results;
        duplicate_results.reserve(index.atom_index->atoms.size());
        std::unordered_set<std::size_t> seen_duplicate_atoms;
        const std::uint64_t query_simhash = make_simhash_signature(query_terms, index.term_to_indices, normalized_cleaned_query, 1.0);
        std::unordered_map<std::size_t, std::size_t> simhash_bucket_sizes;
        std::unordered_map<std::size_t, std::size_t> shingle_bucket_sizes;
        std::vector<std::size_t> simhash_candidates;
        std::vector<std::size_t> shingle_candidates;
        std::unordered_set<std::size_t> seen_simhash_candidates;
        std::unordered_set<std::size_t> seen_shingle_candidates;

        for (std::size_t band = 0; band < 4u; ++band) {
            const std::uint64_t band_key = make_simhash_band_key(query_simhash, band);
            const auto bucket_it = index.simhash_band_to_indices.find(band_key);
            if (bucket_it == index.simhash_band_to_indices.end()) {
                continue;
            }
            const auto& bucket = bucket_it->second;
            for (const std::size_t atom_index : bucket) {
                if (!seen_simhash_candidates.insert(atom_index).second) {
                    continue;
                }
                simhash_candidates.push_back(atom_index);
                const std::size_t bucket_size = bucket.size();
                const auto size_it = simhash_bucket_sizes.find(atom_index);
                if (size_it == simhash_bucket_sizes.end() || bucket_size > size_it->second) {
                    simhash_bucket_sizes[atom_index] = bucket_size;
                }
            }
        }

        for (const std::uint64_t shingle : query_shingles) {
            const auto bucket_it = index.shingle_to_indices.find(shingle);
            if (bucket_it == index.shingle_to_indices.end()) {
                continue;
            }
            const auto& bucket = bucket_it->second;
            for (const std::size_t atom_index : bucket) {
                if (!seen_shingle_candidates.insert(atom_index).second) {
                    continue;
                }
                shingle_candidates.push_back(atom_index);
                const std::size_t bucket_size = bucket.size();
                const auto size_it = shingle_bucket_sizes.find(atom_index);
                if (size_it == shingle_bucket_sizes.end() || bucket_size > size_it->second) {
                    shingle_bucket_sizes[atom_index] = bucket_size;
                }
            }
        }

        if (query_signals.is_near_duplicate) {
            constexpr std::size_t kNearDuplicateHammingThreshold = 12u;
            std::vector<std::size_t> hamming_matches;
            hamming_matches.reserve(index.atom_index->atoms.size());
            for (std::size_t atom_index = 0; atom_index < index.atom_simhashes.size(); ++atom_index) {
                const std::size_t hamming_distance = static_cast<std::size_t>(std::popcount(query_simhash ^ index.atom_simhashes[atom_index]));
                if (hamming_distance <= kNearDuplicateHammingThreshold) {
                    hamming_matches.push_back(atom_index);
                }
            }

            const std::size_t hamming_bucket_size = hamming_matches.size();
            for (const std::size_t atom_index : hamming_matches) {
                if (!seen_simhash_candidates.insert(atom_index).second) {
                    const auto size_it = simhash_bucket_sizes.find(atom_index);
                    if (size_it == simhash_bucket_sizes.end() || hamming_bucket_size > size_it->second) {
                        simhash_bucket_sizes[atom_index] = hamming_bucket_size;
                    }
                    continue;
                }
                simhash_candidates.push_back(atom_index);
                simhash_bucket_sizes[atom_index] = hamming_bucket_size;
            }
        }

        auto append_duplicate_hit = [&](std::size_t atom_index, double similarity, std::size_t bucket_size, std::size_t simhash_bucket_size) {
            if (atom_index >= index.atom_index->atoms.size()) {
                return;
            }
            if (!seen_duplicate_atoms.insert(atom_index).second) {
                return;
            }
            const auto& atom = index.atom_index->atoms[atom_index];
            const bool title_like_atom = atom_index < index.atom_is_title_like.size()
                ? index.atom_is_title_like[atom_index]
                : false;
            const bool cover_like_atom = atom_index < index.atom_is_cover_like.size()
                ? index.atom_is_cover_like[atom_index]
                : false;
            TxtAtomSearchHit hit;
            hit.atom = &atom;
            hit.near_duplicate_similarity = similarity;
            hit.score = similarity * 10.0;
            hit.calibrated_score = hit.score;
            hit.matched_terms = index.atom_term_counts[atom_index];
            hit.shingle_similarity = query_shingles.empty()
                ? 0.0
                : jaccard_similarity_hashes(query_shingles, index.atom_shingles[atom_index]);
            hit.duplicate_group_size = atom_index < index.atom_duplicate_group_sizes.size()
                ? index.atom_duplicate_group_sizes[atom_index]
                : 1u;
            hit.phrase_fingerprint = index.atom_phrase_fingerprints[atom_index];
            hit.phrase_fingerprint_group_size = atom_index < index.atom_phrase_fingerprint_group_sizes.size()
                ? index.atom_phrase_fingerprint_group_sizes[atom_index]
                : bucket_size;
            const auto shingle_it = shingle_bucket_sizes.find(atom_index);
            hit.shingle_group_size = shingle_it == shingle_bucket_sizes.end()
                ? 1u
                : shingle_it->second;
            if (atom.atom_index < index.atom_family_keys.size()) {
                hit.pattern_family_key = index.atom_family_keys[atom.atom_index];
                hit.family_group_size = atom_index < index.atom_family_group_sizes.size()
                    ? index.atom_family_group_sizes[atom_index]
                    : 1u;
            }
            const auto simhash_it = simhash_bucket_sizes.find(atom_index);
            hit.simhash_bucket_size = std::max(
                bucket_size,
                simhash_it == simhash_bucket_sizes.end()
                    ? simhash_bucket_size
                    : simhash_it->second
            );
            hit.rare_residual = hit.duplicate_group_size == 1u && bucket_size == 1u;
            const double family_strength = static_cast<double>(std::max({hit.duplicate_group_size, hit.phrase_fingerprint_group_size, hit.simhash_bucket_size, hit.shingle_group_size}));
            if (query_signals.is_near_duplicate) {
                hit.score += similarity * 1.5;
                hit.score += hit.shingle_similarity * 2.0;
                hit.score += family_strength * 0.25;
                if (hit.rare_residual) {
                    hit.score += 0.8;
                } else if (bucket_size > 1u) {
                    hit.score += 0.35;
                }
            } else if (query_signals.is_duplicate) {
                hit.score += hit.shingle_similarity * 1.2;
                hit.score += family_strength * 0.45;
                if (hit.rare_residual) {
                    hit.score += 1.1;
                } else if (hit.duplicate_group_size > 1u) {
                    hit.score += 0.9;
                }
            } else if (query_signals.is_unique) {
                const bool strict_unique =
                    hit.family_group_size == 1u &&
                    hit.duplicate_group_size == 1u &&
                    hit.phrase_fingerprint_group_size == 1u &&
                    hit.simhash_bucket_size == 1u &&
                    hit.shingle_group_size == 1u;
                if (!strict_unique) {
                    return;
                }
                hit.score += 2.5;
                if (hit.rare_residual) {
                    hit.score += 1.0;
                }
            } else {
                hit.score += static_cast<double>(bucket_size);
                if (hit.duplicate_group_size > 1u) {
                    hit.score += 0.8;
                }
            }
            if (title_like_atom) {
                hit.score += 0.15;
            }
            if (cover_like_atom) {
                hit.score -= 0.1;
            }
            hit.calibrated_score = hit.score;
            if (query_signals.is_unique) {
                hit.match_reason = "unique-only";
            } else if (hit.rare_residual && hit.simhash_bucket_size > 1u) {
                hit.match_reason = "residual family";
            } else if (hit.rare_residual) {
                hit.match_reason = "rare residual";
            } else if (hit.duplicate_group_size > 1u) {
                hit.match_reason = "duplicate group";
            } else if (hit.shingle_group_size > 1u) {
                hit.match_reason = "shingle family";
            } else {
                hit.match_reason = "unique block";
            }
            duplicate_results.push_back(std::move(hit));
        };

        for (const auto& entry : index.atom_index->text_to_indices) {
            const auto& bucket = entry.second;
            if (bucket.size() <= 1u) {
                continue;
            }
            for (const std::size_t atom_index : bucket) {
                append_duplicate_hit(atom_index, 1.0, bucket.size(), 1u);
            }
        }

        for (const std::size_t atom_index : simhash_candidates) {
            if (atom_index >= index.atom_simhashes.size()) {
                continue;
            }
            const double similarity = 1.0 - (static_cast<double>(std::popcount(query_simhash ^ index.atom_simhashes[atom_index])) / 64.0);
            if (similarity <= 0.0) {
                continue;
            }
            const std::size_t bucket_size = simhash_bucket_sizes.count(atom_index) ? simhash_bucket_sizes[atom_index] : 1u;
            if (!query_signals.is_near_duplicate && similarity < 0.60) {
                continue;
            }
            append_duplicate_hit(atom_index, similarity, bucket_size, bucket_size);
        }

        for (const std::size_t atom_index : shingle_candidates) {
            if (atom_index >= index.atom_shingles.size()) {
                continue;
            }
            const std::size_t bucket_size = shingle_bucket_sizes.count(atom_index) ? shingle_bucket_sizes[atom_index] : 1u;
            const double similarity = query_shingles.empty()
                ? 0.0
                : jaccard_similarity_hashes(query_shingles, index.atom_shingles[atom_index]);
            if (similarity <= 0.0) {
                continue;
            }
            append_duplicate_hit(atom_index, similarity, bucket_size, 1u);
        }

        if (query_signals.is_unique && duplicate_results.empty()) {
            for (std::size_t atom_index = 0; atom_index < index.atom_index->atoms.size(); ++atom_index) {
                const std::size_t family_group_size = atom_index < index.atom_family_group_sizes.size()
                    ? index.atom_family_group_sizes[atom_index]
                    : 1u;
                const std::size_t duplicate_group_size = atom_index < index.atom_duplicate_group_sizes.size()
                    ? index.atom_duplicate_group_sizes[atom_index]
                    : 1u;
                if (family_group_size == 1u && duplicate_group_size == 1u) {
                    append_duplicate_hit(atom_index, 0.0, 1u, 1u);
                }
            }
        }

        for (const auto& entry : index.phrase_fingerprint_to_indices) {
            const auto& bucket = entry.second;
            if (bucket.empty()) {
                continue;
            }

            for (const std::size_t atom_index : bucket) {
                double best_similarity = 0.0;
                for (const std::size_t other_index : bucket) {
                    if (other_index == atom_index) {
                        continue;
                    }
                    const double similarity = jaccard_similarity_terms(
                        index.atom_terms[atom_index],
                        index.atom_terms[other_index]
                    );
                    if (similarity > best_similarity) {
                        best_similarity = similarity;
                    }
                }

                if (query_signals.is_unique) {
                    if (bucket.size() == 1u) {
                        append_duplicate_hit(atom_index, 0.0, bucket.size(), 1u);
                    }
                } else if (query_signals.is_duplicate || query_signals.is_near_duplicate) {
                    const std::size_t duplicate_group_size = atom_index < index.atom_duplicate_group_sizes.size()
                        ? index.atom_duplicate_group_sizes[atom_index]
                        : 1u;
                    if (bucket.size() > 1u || duplicate_group_size > 1u) {
                        append_duplicate_hit(atom_index, best_similarity, bucket.size(), 1u);
                    }
                }
            }
        }

        if (duplicate_results.empty()) {
            for (std::size_t atom_index = 0; atom_index < index.atom_index->atoms.size(); ++atom_index) {
                const auto& atom = index.atom_index->atoms[atom_index];
                double best_similarity = 0.0;
                std::size_t best_bucket_size = 1u;
                for (std::size_t other_index = 0; other_index < index.atom_index->atoms.size(); ++other_index) {
                    if (other_index == atom_index) {
                        continue;
                    }
                    if (index.atom_index->atoms[other_index].section_index != atom.section_index) {
                        continue;
                    }
                    const double similarity = jaccard_similarity_terms(
                        index.atom_terms[atom_index],
                        index.atom_terms[other_index]
                    );
                    if (similarity > best_similarity) {
                        best_similarity = similarity;
                        best_bucket_size = 2u;
                    }
                }
                if (best_similarity >= 0.50) {
                    append_duplicate_hit(atom_index, best_similarity, best_bucket_size, 1u);
                }
            }
        }

        std::sort(duplicate_results.begin(), duplicate_results.end(), [](const TxtAtomSearchHit& lhs, const TxtAtomSearchHit& rhs) {
            if (lhs.duplicate_group_size != rhs.duplicate_group_size) {
                return lhs.duplicate_group_size > rhs.duplicate_group_size;
            }
            if (lhs.near_duplicate_similarity != rhs.near_duplicate_similarity) {
                return lhs.near_duplicate_similarity > rhs.near_duplicate_similarity;
            }
            if (lhs.shingle_similarity != rhs.shingle_similarity) {
                return lhs.shingle_similarity > rhs.shingle_similarity;
            }
            if (lhs.simhash_bucket_size != rhs.simhash_bucket_size) {
                return lhs.simhash_bucket_size > rhs.simhash_bucket_size;
            }
            if (lhs.phrase_fingerprint_group_size != rhs.phrase_fingerprint_group_size) {
                return lhs.phrase_fingerprint_group_size > rhs.phrase_fingerprint_group_size;
            }
            if (lhs.score != rhs.score) {
                return lhs.score > rhs.score;
            }
            const std::size_t lhs_len = lhs.atom ? lhs.atom->text.size() : 0;
            const std::size_t rhs_len = rhs.atom ? rhs.atom->text.size() : 0;
            if (lhs_len != rhs_len) {
                return lhs_len < rhs_len;
            }
            return lhs.atom && rhs.atom ? lhs.atom->paragraph_index < rhs.atom->paragraph_index : lhs.atom != nullptr;
        });
        duplicate_results.erase(std::unique(duplicate_results.begin(), duplicate_results.end(), [](const TxtAtomSearchHit& lhs, const TxtAtomSearchHit& rhs) {
            return lhs.atom && rhs.atom && lhs.atom->atom_id == rhs.atom->atom_id;
        }), duplicate_results.end());
        if (duplicate_results.size() > max_results) {
            duplicate_results.resize(max_results);
        }
        return duplicate_results;
    }

    const std::size_t atom_count = index.atom_index->atoms.size();
    std::vector<std::size_t> candidates;
    std::vector<bool> seen(atom_count, false);
    const bool query_shortlist_mode = max_results <= 3u;
    if (query_terms.empty() && !structural_filters.has_section_filter && !structural_filters.has_heading_filter) {
        candidates.reserve(atom_count);
        for (std::size_t atom_index = 0; atom_index < atom_count; ++atom_index) {
            candidates.push_back(atom_index);
        }
    } else {
        std::vector<std::size_t> query_term_order(query_terms.size());
        for (std::size_t i = 0; i < query_terms.size(); ++i) {
            query_term_order[i] = i;
        }
        std::sort(query_term_order.begin(), query_term_order.end(), [&](std::size_t lhs, std::size_t rhs) {
            const auto lhs_it = index.term_to_indices.find(query_terms[lhs]);
            const auto rhs_it = index.term_to_indices.find(query_terms[rhs]);
            const std::size_t lhs_df = lhs_it == index.term_to_indices.end() ? std::numeric_limits<std::size_t>::max() : lhs_it->second.size();
            const std::size_t rhs_df = rhs_it == index.term_to_indices.end() ? std::numeric_limits<std::size_t>::max() : rhs_it->second.size();
            if (lhs_df != rhs_df) {
                return lhs_df < rhs_df;
            }
            return query_terms[lhs] < query_terms[rhs];
        });

        const std::size_t focus_term_count = query_shortlist_mode
            ? std::min<std::size_t>(2u, query_term_order.size())
            : query_term_order.size();

        auto add_term_candidates = [&](std::size_t term_limit) {
            for (std::size_t rank = 0; rank < term_limit; ++rank) {
                const std::string& term = query_terms[query_term_order[rank]];
                const auto it = index.term_to_indices.find(term);
                if (it == index.term_to_indices.end()) {
                    continue;
                }
                for (const std::size_t atom_index : it->second) {
                    if (atom_index < atom_count && !seen[atom_index]) {
                        seen[atom_index] = true;
                        candidates.push_back(atom_index);
                    }
                }
            }
        };

        add_term_candidates(focus_term_count);
        if (!query_shortlist_mode || candidates.size() < 24u) {
            add_term_candidates(query_term_order.size());
        }

        if (candidates.empty()) {
            // Fall back to a full scan only when no indexed term hits exist.
            candidates.reserve(atom_count);
            for (std::size_t atom_index = 0; atom_index < atom_count; ++atom_index) {
                candidates.push_back(atom_index);
            }
        }
    }

    std::vector<std::size_t> matched_terms(atom_count, 0);
    if (query_shortlist_mode && candidates.size() > 24u) {
        struct CandidatePriority {
            std::size_t atom_index;
            double priority;
        };

        std::vector<CandidatePriority> prioritized_candidates;
        prioritized_candidates.reserve(candidates.size());

        for (const std::size_t atom_index : candidates) {
            const auto& atom = index.atom_index->atoms[atom_index];
            if (!matches_structural_filters(index, atom, structural_filters)) {
                continue;
            }

            double priority = 0.0;
            const std::string& normalized_atom = index.normalized_atom_texts[atom_index];
            const auto& atom_terms = index.atom_terms[atom_index];
            const auto& atom_sequence = index.atom_term_sequences[atom_index];
            const bool title_like_atom = atom_index < index.atom_is_title_like.size()
                ? index.atom_is_title_like[atom_index]
                : false;
            const bool cover_like_atom = atom_index < index.atom_is_cover_like.size()
                ? index.atom_is_cover_like[atom_index]
                : false;

            const bool strong_query_shape =
                atom.is_heading ||
                (!normalized_cleaned_query.empty() &&
                 (normalized_atom == normalized_cleaned_query || normalized_atom.find(normalized_cleaned_query) != std::string::npos)) ||
                (!query_phrases.empty()) ||
                (query_phrases.empty() && ordered_query_terms.size() >= 2u &&
                 [&]() {
                     std::size_t first_match_index = 0;
                     return contains_term_sequence(atom_sequence, ordered_query_terms, first_match_index);
                 }()) ||
                (!query_terms.empty() && std::binary_search(atom_terms.begin(), atom_terms.end(), query_terms.front()));
            if (!strong_query_shape && !title_like_atom && !cover_like_atom && matched_terms[atom_index] == 0) {
                continue;
            }

            if (atom.text == cleaned_query) {
                priority += 120.0;
            }
            if (!normalized_cleaned_query.empty()) {
                if (normalized_atom == normalized_cleaned_query) {
                    priority += 90.0;
                } else if (normalized_atom.find(normalized_cleaned_query) != std::string::npos) {
                    priority += 35.0;
                }
            }
            if (!query_phrases.empty()) {
                for (const auto& phrase : query_phrases) {
                    const std::string normalized_phrase = normalize_for_search(phrase);
                    if (!normalized_phrase.empty() && normalized_atom.find(normalized_phrase) != std::string::npos) {
                        priority += 25.0;
                        break;
                    }
                }
            }
            if (query_phrases.empty() && ordered_query_terms.size() >= 2u &&
                [&]() {
                    std::size_t first_match_index = 0;
                    return contains_term_sequence(atom_sequence, ordered_query_terms, first_match_index);
                }()) {
                priority += 18.0;
            }
            if (atom.is_heading) {
                priority += 12.0;
            }
            if (title_like_atom) {
                priority += 6.0;
            }
            if (cover_like_atom) {
                priority -= 4.0;
            }
            if (!query_terms.empty()) {
                std::size_t overlap = 0;
                for (const auto& term : query_terms) {
                    if (std::binary_search(atom_terms.begin(), atom_terms.end(), term)) {
                        ++overlap;
                    }
                }
                priority += static_cast<double>(overlap) * 8.0;
            }
            if (!query_signals.is_what && !query_signals.is_how && !query_signals.is_where &&
                !query_signals.is_why && !query_signals.is_who && !query_signals.is_when &&
                !title_like_atom && !cover_like_atom) {
                priority += 1.0;
            }
            prioritized_candidates.push_back({atom_index, priority});
        }

        const std::size_t shortlist_limit = std::min<std::size_t>(32u, prioritized_candidates.size());
        if (prioritized_candidates.size() > shortlist_limit) {
            std::nth_element(
                prioritized_candidates.begin(),
                prioritized_candidates.begin() + shortlist_limit,
                prioritized_candidates.end(),
                [](const CandidatePriority& lhs, const CandidatePriority& rhs) {
                    if (lhs.priority != rhs.priority) {
                        return lhs.priority > rhs.priority;
                    }
                    return lhs.atom_index < rhs.atom_index;
                }
            );
            prioritized_candidates.resize(shortlist_limit);
            std::sort(
                prioritized_candidates.begin(),
                prioritized_candidates.end(),
                [](const CandidatePriority& lhs, const CandidatePriority& rhs) {
                    if (lhs.priority != rhs.priority) {
                        return lhs.priority > rhs.priority;
                    }
                    return lhs.atom_index < rhs.atom_index;
                }
            );
        }

        candidates.clear();
        candidates.reserve(prioritized_candidates.size());
        for (const auto& entry : prioritized_candidates) {
            candidates.push_back(entry.atom_index);
        }
    }

    std::vector<double> scores(atom_count, 0.0);
    std::vector<double> shingle_scores(atom_count, 0.0);
    std::vector<std::size_t> phrase_matches(atom_count, 0);
    std::vector<double> proximity_scores(atom_count, 0.0);
    std::vector<bool> exact_text_match(atom_count, false);
    const bool body_preferring_query = query_intent != QueryIntent::TitleLike;
    const bool title_preferring_query = query_intent == QueryIntent::TitleLike;
    const std::string normalized_section_filter = structural_filters.has_section_filter
        ? normalize_for_search(structural_filters.section_filter)
        : std::string();
    const std::string normalized_heading_filter = structural_filters.has_heading_filter
        ? normalize_for_search(structural_filters.heading_filter)
        : std::string();
    struct PrecomputedQueryPhrase {
        std::string normalized;
        std::vector<std::string> terms;
    };
    std::vector<PrecomputedQueryPhrase> precomputed_query_phrases;
    precomputed_query_phrases.reserve(query_phrases.size());
    for (const auto& phrase : query_phrases) {
        PrecomputedQueryPhrase entry;
        entry.normalized = normalize_for_search(phrase);
        entry.terms = extract_search_terms(phrase);
        precomputed_query_phrases.push_back(std::move(entry));
    }
    const auto contains_any = [](std::string_view haystack, const std::array<std::string_view, 6>& needles) {
        for (const std::string_view needle : needles) {
            if (!needle.empty() && haystack.find(needle) != std::string::npos) {
                return true;
            }
        }
        return false;
    };

    for (const auto& term : query_terms) {
        const auto it = index.term_to_indices.find(term);
        if (it == index.term_to_indices.end()) {
            continue;
        }
        const double term_weight = 1.0 / static_cast<double>(std::max<std::size_t>(1, it->second.size()));
        for (const std::size_t atom_index : it->second) {
            scores[atom_index] += term_weight;
            matched_terms[atom_index] += 1;
        }
    }

    for (const std::size_t atom_index : candidates) {
        const auto& atom = index.atom_index->atoms[atom_index];
        if (!matches_structural_filters(index, atom, structural_filters)) {
            continue;
        }
        const std::string& normalized_atom = index.normalized_atom_texts[atom_index];
        const std::string& normalized_section_heading = atom_index < index.normalized_section_headings.size()
            ? index.normalized_section_headings[atom_index]
            : normalized_atom;
        const bool section_filter_matches_heading = structural_filters.has_section_filter &&
            !normalized_section_filter.empty() &&
            normalized_section_heading.find(normalized_section_filter) != std::string::npos;
        const auto& atom_sequence = index.atom_term_sequences[atom_index];
        const QueryShapeSignals atom_shape_signals = extract_text_shape_signals(atom.text);
        const auto& atom_date_signatures = atom_shape_signals.date_signatures;
        const auto& atom_numeric_signatures = atom_shape_signals.numeric_signatures;
        const auto& atom_abbreviation_signatures = atom_shape_signals.abbreviation_signatures;
        const bool title_like_atom = atom_index < index.atom_is_title_like.size()
            ? index.atom_is_title_like[atom_index]
            : false;
        const bool cover_like_atom = atom_index < index.atom_is_cover_like.size()
            ? index.atom_is_cover_like[atom_index]
            : false;
        const bool body_like_atom = !title_like_atom && !cover_like_atom;

        if (section_filter_matches_heading) {
            if (atom.is_heading || atom.paragraph_index == index.source_record->sections[atom.section_index].heading_paragraph_index) {
                scores[atom_index] += 8.0;
            } else {
                scores[atom_index] += 1.0;
            }
        }

        const std::size_t date_matches = count_signature_matches(atom_date_signatures, query_shape_signals.date_signatures);
        if (date_matches > 0) {
            scores[atom_index] += 7.5 * static_cast<double>(date_matches);
            if (date_matches == query_shape_signals.date_signatures.size() && !query_shape_signals.date_signatures.empty()) {
                scores[atom_index] += 4.0;
            }
            if (query_signals.is_when) {
                scores[atom_index] += 2.0;
            }
        } else if (!query_shape_signals.date_signatures.empty() && query_signals.is_when) {
            scores[atom_index] -= 2.5;
        }

        if (query_signals.is_when) {
            if (!atom_date_signatures.empty()) {
                scores[atom_index] += 1.8;
            } else {
                scores[atom_index] -= 0.8;
            }
            if (!query_shape_signals.date_signatures.empty() && date_matches == 0) {
                scores[atom_index] -= 1.0;
            }
        }

        const std::size_t numeric_matches = count_signature_matches(atom_numeric_signatures, query_shape_signals.numeric_signatures);
        const std::size_t abbreviation_matches = count_signature_matches(atom_abbreviation_signatures, query_shape_signals.abbreviation_signatures);
        if (numeric_matches > 0) {
            scores[atom_index] += 4.5 * static_cast<double>(numeric_matches);
            if (numeric_matches == query_shape_signals.numeric_signatures.size() && !query_shape_signals.numeric_signatures.empty()) {
                scores[atom_index] += 2.0;
            }
            if (atom.text.find('$') != std::string::npos || atom.text.find('%') != std::string::npos) {
                scores[atom_index] += 0.4;
            }
        }
        if (abbreviation_matches > 0) {
            scores[atom_index] += 4.5 * static_cast<double>(abbreviation_matches);
            if (abbreviation_matches == query_shape_signals.abbreviation_signatures.size() &&
                !query_shape_signals.abbreviation_signatures.empty()) {
                scores[atom_index] += 2.0;
            }
            if (std::count_if(atom.text.begin(), atom.text.end(), [](const char ch) {
                    return ch == '.';
                }) >= 2u) {
                scores[atom_index] += 0.4;
            }
        } else if (!query_shape_signals.abbreviation_signatures.empty()) {
            scores[atom_index] -= 1.0;
        }

        if (structural_filters.has_heading_filter) {
            if (atom.is_heading) {
                scores[atom_index] += 6.0;
            }
            if (!normalized_heading_filter.empty()) {
                if (normalized_atom.find(normalized_heading_filter) != std::string::npos) {
                    scores[atom_index] += 4.5;
                }
                if (normalized_section_heading.find(normalized_heading_filter) != std::string::npos) {
                    scores[atom_index] += 2.0;
                }
            }
        }
        if (atom.text == cleaned_query) {
            scores[atom_index] += 10.0;
            exact_text_match[atom_index] = true;
        }
        if (!normalized_cleaned_query.empty() && normalized_atom == normalized_cleaned_query) {
            scores[atom_index] += 5.0;
            exact_text_match[atom_index] = true;
        }
        if (!normalized_cleaned_query.empty() && normalized_atom.find(normalized_cleaned_query) != std::string::npos) {
            scores[atom_index] += 1.5;
        }
        for (const auto& phrase : precomputed_query_phrases) {
            if (phrase.normalized.empty()) {
                continue;
            }
            std::size_t first_phrase_index = 0;
            if (contains_term_sequence(atom_sequence, phrase.terms, first_phrase_index)) {
                ++phrase_matches[atom_index];
                double phrase_boost = 6.5;
                if (body_preferring_query) {
                    if (cover_like_atom) {
                        phrase_boost = 0.15;
                    } else if (title_like_atom) {
                        phrase_boost = 3.0;
                    }
                } else if (title_preferring_query) {
                    if (cover_like_atom) {
                        phrase_boost = 1.0;
                    } else if (title_like_atom) {
                        phrase_boost = 4.2;
                    }
                }
                scores[atom_index] += phrase_boost;
                if (first_phrase_index == 0) {
                    scores[atom_index] += 0.75;
                }
            } else if (normalized_atom.find(phrase.normalized) != std::string::npos) {
                ++phrase_matches[atom_index];
                double phrase_boost = 3.2;
                if (body_preferring_query) {
                    if (cover_like_atom) {
                        phrase_boost = 0.1;
                    } else if (title_like_atom) {
                        phrase_boost = 1.4;
                    }
                } else if (title_preferring_query) {
                    if (cover_like_atom) {
                        phrase_boost = 0.9;
                    } else if (title_like_atom) {
                        phrase_boost = 2.2;
                    }
                }
                scores[atom_index] += phrase_boost;
            }
        }
        if (query_phrases.empty() && ordered_query_terms.size() >= 2) {
            std::size_t ordered_match_index = 0;
            if (contains_term_sequence(atom_sequence, ordered_query_terms, ordered_match_index)) {
                double ordered_boost = 2.8;
                if (body_preferring_query) {
                    if (cover_like_atom) {
                        ordered_boost = 0.35;
                    } else if (title_like_atom) {
                        ordered_boost = 1.0;
                    }
                } else if (title_preferring_query) {
                    if (cover_like_atom) {
                        ordered_boost = 0.85;
                    } else if (title_like_atom) {
                        ordered_boost = 1.8;
                    }
                }
                scores[atom_index] += ordered_boost;
                if (ordered_match_index == 0) {
                    scores[atom_index] += 0.75;
                }
                ++phrase_matches[atom_index];
            }
        }

        const double coverage = compute_overlap_ratio(matched_terms[atom_index], query_terms.size());
        if (coverage > 0.0) {
            scores[atom_index] += coverage * 2.0;
        }
        if (matched_terms[atom_index] == query_terms.size() && !query_terms.empty()) {
            scores[atom_index] += 1.0;
        }
        const double near_score = compute_near_score(atom_sequence, near_clause);
        if (near_score > 0.0) {
            proximity_scores[atom_index] = near_score;
            scores[atom_index] += near_score;
        }

        const double shingle_similarity = query_shingles.empty()
            ? 0.0
            : (index.duplicate_support_ready && atom_index < index.atom_shingles.size()
                ? jaccard_similarity_hashes(query_shingles, index.atom_shingles[atom_index])
                : jaccard_similarity_hashes(query_shingles, make_term_shingles(index.atom_term_sequences[atom_index], normalized_atom)));
        if (shingle_similarity > 0.0) {
            shingle_scores[atom_index] = shingle_similarity;
            scores[atom_index] += shingle_similarity * 2.2;
        }

        if (body_preferring_query && cover_like_atom && !exact_text_match[atom_index]) {
            scores[atom_index] -= 5.0;
        }

        if (!query_shape_signals.numeric_signatures.empty() && numeric_matches == 0 && !exact_text_match[atom_index]) {
            scores[atom_index] -= 0.6;
        }
        if (!query_shape_signals.abbreviation_signatures.empty() && abbreviation_matches == 0 && !exact_text_match[atom_index]) {
            scores[atom_index] -= 0.8;
        }

        if (!exact_text_match[atom_index] && phrase_matches[atom_index] == 0 && proximity_scores[atom_index] <= 0.0) {
            if (body_preferring_query) {
                if (cover_like_atom) {
                    scores[atom_index] -= 3.6;
                } else if (title_like_atom && !body_like_atom) {
                    scores[atom_index] -= 0.8;
                }
            } else if (title_preferring_query) {
                if (cover_like_atom) {
                    scores[atom_index] -= 0.7;
                } else if (body_like_atom) {
                    scores[atom_index] -= 0.2;
                }
            }
        }

        const std::size_t atom_words = std::max<std::size_t>(1, index.atom_term_counts[atom_index]);
        scores[atom_index] += 0.4 / static_cast<double>(atom_words);
        scores[atom_index] += 0.15 / static_cast<double>(std::max<std::size_t>(1, atom.text.size() / 40u + 1u));

        if (query_signals.is_what && index.atom_has_what_cue[atom_index]) {
            scores[atom_index] += 1.8;
        }
        if (query_signals.is_how) {
            if (index.atom_has_how_form_cue[atom_index]) {
                scores[atom_index] += 3.5;
            }
            if (index.atom_has_how_collapse_cue[atom_index]) {
                scores[atom_index] += 3.0;
            }
            if (index.atom_has_how_cause_cue[atom_index]) {
                scores[atom_index] += 2.6;
            }
            if (index.atom_has_how_using_cue[atom_index]) {
                scores[atom_index] += 1.8;
            }
            if (index.atom_has_how_study_cue[atom_index]) {
                scores[atom_index] -= 0.9;
            }
        }
        if (query_signals.is_where && index.atom_has_where_cue[atom_index]) {
            scores[atom_index] += 1.8;
        }
        if (query_signals.is_why && index.atom_has_why_cue[atom_index]) {
            scores[atom_index] += 1.8;
        }
        if (query_signals.is_when && index.atom_has_when_cue[atom_index]) {
            scores[atom_index] += 1.4;
        }
        if (query_signals.is_who && index.atom_has_who_cue[atom_index]) {
            scores[atom_index] += 1.0;
        }

        if ((structural_filters.has_section_filter || structural_filters.has_heading_filter) &&
            query_terms.empty() && query_phrases.empty() && ordered_query_terms.empty() && !query_signals.is_what &&
            !query_signals.is_how && !query_signals.is_where && !query_signals.is_why &&
            !query_signals.is_who && !query_signals.is_when) {
            scores[atom_index] += 0.5;
        }
    }

    std::unordered_map<std::uint64_t, TxtAtomSearchHit> best_by_checksum;
    best_by_checksum.reserve(candidates.size());

    const auto atom_shape_rank = [](const TxtAtomSearchHit& hit) {
        const auto* atom = hit.atom;
        if (atom == nullptr) {
            return std::tuple<int, int, int, std::size_t>{0, 0, 0, 0};
        }
        const std::size_t length = atom->text.size();
        const int heading_rank = atom->is_heading ? 1 : 0;
        const int paragraph_rank = atom->kind == TxtAtomKind::Paragraph ? 1 : 0;
        const int not_tiny_rank = length > 32u ? 1 : 0;
        return std::tuple<int, int, int, std::size_t>{
            heading_rank,
            paragraph_rank,
            not_tiny_rank,
            length
        };
    };

    for (const std::size_t atom_index : candidates) {
        if (scores[atom_index] <= 0.0) {
            continue;
        }
        const auto& atom = index.atom_index->atoms[atom_index];
        const bool title_like_atom = atom_index < index.atom_is_title_like.size()
            ? index.atom_is_title_like[atom_index]
            : false;
        const bool cover_like_atom = atom_index < index.atom_is_cover_like.size()
            ? index.atom_is_cover_like[atom_index]
            : false;
        const bool body_like_atom = !title_like_atom && !cover_like_atom;
        const bool is_heading_atom = atom.is_heading;
        TxtAtomSearchHit hit;
        hit.atom = &atom;
        hit.score = scores[atom_index];
        hit.calibrated_score = calibrate_search_score(
            hit.score,
            matched_terms[atom_index],
            query_terms.size(),
            phrase_matches[atom_index],
            proximity_scores[atom_index],
            exact_text_match[atom_index],
            query_intent,
            title_like_atom,
            cover_like_atom,
            body_like_atom,
            atom.kind,
            atom.text.size(),
            index.atom_term_counts[atom_index],
            is_heading_atom
        );
        hit.matched_terms = matched_terms[atom_index];
        hit.phrase_matches = phrase_matches[atom_index];
        hit.proximity_score = proximity_scores[atom_index];
        hit.shingle_similarity = shingle_scores[atom_index];
        if (index.duplicate_support_ready) {
            hit.shingle_group_size = 1u;
            for (const std::uint64_t shingle : index.atom_shingles[atom_index]) {
                const auto shingle_it = index.shingle_to_indices.find(shingle);
                if (shingle_it != index.shingle_to_indices.end() && shingle_it->second.size() > hit.shingle_group_size) {
                    hit.shingle_group_size = shingle_it->second.size();
                }
            }
            hit.duplicate_group_size = atom_index < index.atom_duplicate_group_sizes.size()
                ? index.atom_duplicate_group_sizes[atom_index]
                : 1u;
            hit.phrase_fingerprint = atom_index < index.atom_phrase_fingerprints.size()
                ? index.atom_phrase_fingerprints[atom_index]
                : 0u;
        } else {
            hit.shingle_group_size = 1u;
            hit.duplicate_group_size = 1u;
            hit.phrase_fingerprint = 0u;
        }
        hit.exact_text_match = exact_text_match[atom_index];

        const auto it = best_by_checksum.find(atom.checksum);
        if (it == best_by_checksum.end()) {
            best_by_checksum.emplace(atom.checksum, hit);
            continue;
        }

        const auto& existing = it->second;
        const bool better =
            (hit.exact_text_match != existing.exact_text_match && hit.exact_text_match) ||
            (hit.phrase_matches != existing.phrase_matches && hit.phrase_matches > existing.phrase_matches) ||
            (hit.proximity_score != existing.proximity_score && hit.proximity_score > existing.proximity_score) ||
            (hit.calibrated_score != existing.calibrated_score && hit.calibrated_score > existing.calibrated_score) ||
            (atom_shape_rank(hit) > atom_shape_rank(existing)) ||
            (hit.score > existing.score) ||
            (hit.score == existing.score && hit.matched_terms > existing.matched_terms) ||
            (hit.score == existing.score && hit.matched_terms == existing.matched_terms &&
             hit.atom && existing.atom && hit.atom->paragraph_index < existing.atom->paragraph_index);
        if (better) {
            it->second = hit;
        }
    }

    if (index.duplicate_support_ready) {
        std::unordered_map<std::string, TxtAtomSearchHit> best_by_family;
        best_by_family.reserve(best_by_checksum.size());
        for (const auto& entry : best_by_checksum) {
            const auto* atom = entry.second.atom;
            if (atom == nullptr || atom->atom_index >= index.atom_family_keys.size()) {
                continue;
            }
            const std::string& family_key = index.atom_family_keys[atom->atom_index];
            const auto it = best_by_family.find(family_key);
            if (it == best_by_family.end()) {
                best_by_family.emplace(family_key, entry.second);
                continue;
            }

            const auto& existing = it->second;
            const bool better =
                (entry.second.exact_text_match != existing.exact_text_match && entry.second.exact_text_match) ||
                (entry.second.phrase_matches != existing.phrase_matches && entry.second.phrase_matches > existing.phrase_matches) ||
                (entry.second.proximity_score != existing.proximity_score && entry.second.proximity_score > existing.proximity_score) ||
                (entry.second.calibrated_score != existing.calibrated_score &&
                 entry.second.calibrated_score > existing.calibrated_score) ||
                (atom_shape_rank(entry.second) > atom_shape_rank(existing)) ||
                (entry.second.score > existing.score) ||
                (entry.second.score == existing.score && entry.second.matched_terms > existing.matched_terms) ||
                (entry.second.score == existing.score && entry.second.matched_terms == existing.matched_terms &&
                 entry.second.atom && existing.atom &&
                 entry.second.atom->paragraph_index < existing.atom->paragraph_index);
            if (better) {
                it->second = entry.second;
            }
        }

        results.reserve(best_by_family.size());
        for (const auto& entry : best_by_family) {
            TxtAtomSearchHit hit = entry.second;
            hit.family_collapsed = true;
            hit.pattern_family_key = entry.first;
            hit.family_group_size = hit.atom && hit.atom->atom_index < index.atom_family_group_sizes.size()
                ? index.atom_family_group_sizes[hit.atom->atom_index]
                : 1u;
            if (hit.exact_text_match) {
                hit.match_reason = "exact text match";
            } else if (hit.phrase_matches > 0) {
                hit.match_reason = "phrase match";
            } else if (hit.proximity_score > 0.0) {
                hit.match_reason = "proximity match";
            } else if (hit.matched_terms > 0) {
                hit.match_reason = "term overlap";
            } else {
                hit.match_reason = "family collapse";
            }
            results.emplace_back(std::move(hit));
        }
    } else {
        results.reserve(best_by_checksum.size());
        for (const auto& entry : best_by_checksum) {
            results.emplace_back(entry.second);
        }
    }

    const auto result_less = [atom_shape_rank](const TxtAtomSearchHit& lhs, const TxtAtomSearchHit& rhs) {
        if (lhs.exact_text_match != rhs.exact_text_match) {
            return lhs.exact_text_match > rhs.exact_text_match;
        }
        if (lhs.phrase_matches != rhs.phrase_matches) {
            return lhs.phrase_matches > rhs.phrase_matches;
        }
        if (lhs.proximity_score != rhs.proximity_score) {
            return lhs.proximity_score > rhs.proximity_score;
        }
        if (lhs.calibrated_score != rhs.calibrated_score) {
            return lhs.calibrated_score > rhs.calibrated_score;
        }
        if (lhs.score != rhs.score) {
            return lhs.score > rhs.score;
        }
        if (lhs.matched_terms != rhs.matched_terms) {
            return lhs.matched_terms > rhs.matched_terms;
        }
        if (lhs.family_collapsed != rhs.family_collapsed) {
            return lhs.family_collapsed > rhs.family_collapsed;
        }
        const auto lhs_shape = atom_shape_rank(lhs);
        const auto rhs_shape = atom_shape_rank(rhs);
        if (lhs_shape != rhs_shape) {
            return lhs_shape > rhs_shape;
        }
        const std::size_t lhs_len = lhs.atom ? lhs.atom->text.size() : 0;
        const std::size_t rhs_len = rhs.atom ? rhs.atom->text.size() : 0;
        if (lhs_len != rhs_len) {
            return lhs_len < rhs_len;
        }
        if (lhs.atom->paragraph_index != rhs.atom->paragraph_index) {
            return lhs.atom->paragraph_index < rhs.atom->paragraph_index;
        }
        if (lhs.atom->start_offset != rhs.atom->start_offset) {
            return lhs.atom->start_offset < rhs.atom->start_offset;
        }
        return lhs.atom->atom_index < rhs.atom->atom_index;
    };

    if (results.size() > max_results && max_results <= 3u) {
        std::partial_sort(results.begin(), results.begin() + max_results, results.end(), result_less);
    } else {
        std::sort(results.begin(), results.end(), result_less);
    }

    if (results.size() > max_results) {
        results.resize(max_results);
    }

    return results;
}

std::uint64_t make_phrase_fingerprint(std::string_view normalized_text, std::size_t term_count) {
    const std::string leading = tp::make_leading_signature(normalized_text, 8);
    const std::string trailing = make_trailing_signature_local(normalized_text, 6);
    std::string material;
    material.reserve(leading.size() + trailing.size() + 32);
    material += leading;
    material.push_back('|');
    material += trailing;
    material.push_back('|');
    material += std::to_string(term_count);
    material.push_back('|');
    material += std::to_string(normalized_text.size() / 16u);
    return fnv1a64(std::span<const std::uint8_t>(
        reinterpret_cast<const std::uint8_t*>(material.data()),
        material.size()
    ));
}

std::uint64_t hash_text64(std::string_view text) {
    return fnv1a64(std::span<const std::uint8_t>(
        reinterpret_cast<const std::uint8_t*>(text.data()),
        text.size()
    ));
}

std::uint64_t make_simhash_signature(
    const std::vector<std::string>& terms,
    const std::unordered_map<std::string, std::vector<std::size_t>>& term_to_indices,
    std::string_view fallback_text,
    const double fallback_weight
) {
    constexpr std::size_t kBits = 64u;
    std::array<double, kBits> accum{};
    bool saw_feature = false;

    auto add_feature = [&](std::string_view feature, double weight) {
        if (feature.empty() || weight <= 0.0) {
            return;
        }
        const std::uint64_t feature_hash = hash_text64(feature);
        for (std::size_t bit = 0; bit < kBits; ++bit) {
            const double delta = ((feature_hash >> bit) & 1ULL) != 0 ? weight : -weight;
            accum[bit] += delta;
        }
        saw_feature = true;
    };

    for (const auto& term : terms) {
        const auto it = term_to_indices.find(term);
        const double df = it == term_to_indices.end() ? 1.0 : static_cast<double>(it->second.size());
        const double weight = 1.0 / std::sqrt(df + 1.0);
        add_feature(term, weight);
    }

    if (!saw_feature && !fallback_text.empty()) {
        add_feature(fallback_text, fallback_weight);
    }

    std::uint64_t signature = 0;
    for (std::size_t bit = 0; bit < kBits; ++bit) {
        if (accum[bit] >= 0.0) {
            signature |= (1ULL << bit);
        }
    }

    if (signature == 0 && !fallback_text.empty()) {
        signature = hash_text64(fallback_text);
    }
    return signature;
}

std::uint64_t make_simhash_band_key(std::uint64_t signature, std::size_t band) {
    constexpr std::size_t kBandBits = 16u;
    const std::uint64_t slice = (signature >> (band * kBandBits)) & 0xFFFFULL;
    return (static_cast<std::uint64_t>(band) << kBandBits) | slice;
}

std::vector<std::uint64_t> make_term_shingles(const std::vector<std::string>& terms, std::string_view fallback_text) {
    std::vector<std::uint64_t> shingles;
    if (terms.size() >= 3u) {
        shingles.reserve(terms.size() - 2u);
        for (std::size_t i = 0; i + 2u < terms.size(); ++i) {
            std::string material;
            material.reserve(terms[i].size() + terms[i + 1].size() + terms[i + 2].size() + 2u);
            material += terms[i];
            material.push_back('|');
            material += terms[i + 1];
            material.push_back('|');
            material += terms[i + 2];
            shingles.push_back(hash_text64(material));
        }
    } else if (!fallback_text.empty()) {
        shingles.push_back(hash_text64(fallback_text));
    } else if (!terms.empty()) {
        std::string material;
        for (const auto& term : terms) {
            if (!material.empty()) {
                material.push_back('|');
            }
            material += term;
        }
        shingles.push_back(hash_text64(material));
    }

    std::sort(shingles.begin(), shingles.end());
    shingles.erase(std::unique(shingles.begin(), shingles.end()), shingles.end());
    return shingles;
}

ResidualChange detect_residual_change(const std::vector<std::string>& left_terms, const std::vector<std::string>& right_terms) {
    ResidualChange result;
    if (left_terms.empty() || right_terms.empty()) {
        return result;
    }

    const std::size_t limit = std::min(left_terms.size(), right_terms.size());
    std::size_t prefix = 0;
    while (prefix < limit && left_terms[prefix] == right_terms[prefix]) {
        ++prefix;
    }

    std::size_t suffix = 0;
    while (suffix + prefix < limit &&
           left_terms[left_terms.size() - 1u - suffix] == right_terms[right_terms.size() - 1u - suffix]) {
        ++suffix;
    }

    const std::size_t left_mid_begin = prefix;
    const std::size_t left_mid_end = left_terms.size() > suffix ? left_terms.size() - suffix : left_terms.size();
    const std::size_t right_mid_begin = prefix;
    const std::size_t right_mid_end = right_terms.size() > suffix ? right_terms.size() - suffix : right_terms.size();
    const std::size_t left_mid_size = left_mid_end > left_mid_begin ? left_mid_end - left_mid_begin : 0u;
    const std::size_t right_mid_size = right_mid_end > right_mid_begin ? right_mid_end - right_mid_begin : 0u;

    auto join_terms = [](const std::vector<std::string>& terms, std::size_t begin, std::size_t end) {
        std::string out;
        for (std::size_t i = begin; i < end && i < terms.size(); ++i) {
            if (!out.empty()) {
                out.push_back(' ');
            }
            out += terms[i];
        }
        return out;
    };

    if (left_mid_size == 0u && right_mid_size == 0u) {
        return result;
    }

    if (left_mid_size == 0u && right_mid_size > 0u) {
        result.valid = true;
        result.kind = "change-insert";
        result.left.clear();
        result.right = join_terms(right_terms, right_mid_begin, right_mid_end);
        return result;
    }

    if (right_mid_size == 0u && left_mid_size > 0u) {
        result.valid = true;
        result.kind = "change-delete";
        result.left = join_terms(left_terms, left_mid_begin, left_mid_end);
        result.right.clear();
        return result;
    }

    if (left_mid_size > 0u && right_mid_size > 0u && left_mid_size <= 3u && right_mid_size <= 3u) {
        result.valid = true;
        result.kind = "change-replace";
        result.left = join_terms(left_terms, left_mid_begin, left_mid_end);
        result.right = join_terms(right_terms, right_mid_begin, right_mid_end);
        return result;
    }

    return result;
}

std::string make_pattern_family_key(std::string_view normalized_text, const std::size_t leading_terms, const std::size_t trailing_terms) {
    if (normalized_text.empty()) {
        return {};
    }
    const std::string leading = tp::make_leading_signature(normalized_text, leading_terms);
    const std::string trailing = make_trailing_signature_local(normalized_text, trailing_terms);
    std::string key;
    key.reserve(leading.size() + trailing.size() + 8u);
    key += leading;
    key.push_back('|');
    key += trailing;
    key.push_back('|');
    key += std::to_string(normalized_text.size() / 24u);
    return key;
}

std::string make_leading_signature(std::string_view normalized_text, const std::size_t max_terms) {
    if (normalized_text.empty()) {
        return {};
    }

    std::string signature;
    signature.reserve(std::min<std::size_t>(normalized_text.size(), max_terms * 8u));
    std::size_t terms = 0;
    bool in_token = false;
    for (const char ch : normalized_text) {
        if (ch == ' ') {
            if (in_token) {
                ++terms;
                in_token = false;
                if (terms >= max_terms) {
                    break;
                }
            }
            if (!signature.empty() && signature.back() != ' ') {
                signature.push_back(' ');
            }
            continue;
        }
        signature.push_back(ch);
        in_token = true;
    }

    while (!signature.empty() && signature.back() == ' ') {
        signature.pop_back();
    }
    return signature;
}

std::string normalize_change_probe_value(std::string_view value) {
    const std::vector<std::string> dates = extract_date_signatures(value);
    if (!dates.empty()) {
        return dates.front();
    }
    const std::vector<std::string> numerics = extract_numeric_signatures(value);
    if (!numerics.empty()) {
        return numerics.front();
    }
    const std::vector<std::string> abbreviations = extract_abbreviation_signatures(value);
    if (!abbreviations.empty()) {
        return abbreviations.front();
    }
    return normalize_for_search(value);
}

double jaccard_similarity_terms(const std::vector<std::string>& lhs, const std::vector<std::string>& rhs) {
    if (lhs.empty() || rhs.empty()) {
        return 0.0;
    }

    std::vector<std::string> left = lhs;
    std::vector<std::string> right = rhs;
    std::sort(left.begin(), left.end());
    std::sort(right.begin(), right.end());
    left.erase(std::unique(left.begin(), left.end()), left.end());
    right.erase(std::unique(right.begin(), right.end()), right.end());

    std::size_t i = 0;
    std::size_t j = 0;
    std::size_t intersection = 0;
    while (i < left.size() && j < right.size()) {
        if (left[i] == right[j]) {
            ++intersection;
            ++i;
            ++j;
        } else if (left[i] < right[j]) {
            ++i;
        } else {
            ++j;
        }
    }

    const std::size_t union_size = left.size() + right.size() - intersection;
    if (union_size == 0) {
        return 0.0;
    }
    return static_cast<double>(intersection) / static_cast<double>(union_size);
}

double jaccard_similarity_hashes(const std::vector<std::uint64_t>& lhs, const std::vector<std::uint64_t>& rhs) {
    if (lhs.empty() || rhs.empty()) {
        return 0.0;
    }

    std::vector<std::uint64_t> left = lhs;
    std::vector<std::uint64_t> right = rhs;
    std::sort(left.begin(), left.end());
    std::sort(right.begin(), right.end());
    left.erase(std::unique(left.begin(), left.end()), left.end());
    right.erase(std::unique(right.begin(), right.end()), right.end());

    std::size_t i = 0;
    std::size_t j = 0;
    std::size_t intersection = 0;
    while (i < left.size() && j < right.size()) {
        if (left[i] == right[j]) {
            ++intersection;
            ++i;
            ++j;
        } else if (left[i] < right[j]) {
            ++i;
        } else {
            ++j;
        }
    }

    const std::size_t union_size = left.size() + right.size() - intersection;
    if (union_size == 0) {
        return 0.0;
    }
    return static_cast<double>(intersection) / static_cast<double>(union_size);
}

std::size_t count_term_hits_normalized(std::string_view text, const std::vector<std::string>& terms) {
    if (terms.empty()) {
        return 0;
    }
    const std::string normalized_text = normalize_for_search(text);
    std::size_t hits = 0;
    for (const auto& term : terms) {
        if (normalized_text.find(term) != std::string::npos) {
            ++hits;
        }
    }
    return hits;
}

std::string first_distinct_value(const std::vector<std::string>& lhs, const std::vector<std::string>& rhs) {
    for (const auto& value : lhs) {
        if (std::find(rhs.begin(), rhs.end(), value) == rhs.end()) {
            return value;
        }
    }
    return lhs.empty() ? std::string() : lhs.front();
}

} // namespace tp
