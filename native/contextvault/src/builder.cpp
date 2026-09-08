#include "internal.h"

#include <algorithm>
#include <cstring>
#include <map>
#include <set>

namespace tp {

namespace {
constexpr char kPredictorMagic[4] = {'T', 'P', 'P', '3'};

using Count = std::uint64_t;
using NextCounts = std::unordered_map<std::uint32_t, Count>;

std::vector<std::uint32_t> top_candidates(
    const NextCounts& counts,
    const std::uint32_t top_k
) {
    std::vector<std::pair<std::uint32_t, Count>> items(counts.begin(), counts.end());
    std::sort(items.begin(), items.end(), [](const auto& a, const auto& b) {
        if (a.second != b.second) return a.second > b.second;
        return a.first < b.first;
    });
    if (items.size() > top_k) items.resize(top_k);

    std::vector<std::uint32_t> result;
    result.reserve(items.size());
    for (const auto& [id, count] : items) {
        (void)count;
        result.push_back(id);
    }
    return result;
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

} // namespace

int build_predictor_impl(
    const std::filesystem::path& corpus_path,
    const std::filesystem::path& predictor_path,
    const std::uint32_t vocabulary_size,
    const std::uint32_t top_k,
    std::string& error
) {
    if (vocabulary_size < 2 || top_k == 0 || top_k > kMaxTopK || vocabulary_size > kContextTokenLimit) {
        error = "vocabulary_size must be >= 2, <= 2097152 and top_k must be between 1 and 16";
        return 1;
    }

    const auto corpus = read_file(corpus_path, error);
    if (!error.empty()) return 2;
    const auto segments = tokenize_exact(corpus);

    std::unordered_map<std::string, Count> token_counts;
    token_counts.reserve(65536);
    for (const auto& segment : segments) {
        if (segment.kind == Segment::Kind::Raw) continue;
        const std::string token(
            reinterpret_cast<const char*>(corpus.data() + segment.offset),
            segment.length
        );
        ++token_counts[token];
    }

    std::vector<std::pair<std::string, Count>> sorted_tokens(token_counts.begin(), token_counts.end());
    std::sort(sorted_tokens.begin(), sorted_tokens.end(), [](const auto& a, const auto& b) {
        if (a.second != b.second) return a.second > b.second;
        return a.first < b.first;
    });

    const std::size_t keep = std::min<std::size_t>(
        sorted_tokens.size(),
        static_cast<std::size_t>(vocabulary_size - 2u)
    );

    std::vector<std::string> id_to_token;
    id_to_token.reserve(keep + 2);
    id_to_token.emplace_back("<BOS>");
    id_to_token.emplace_back("<UNK>");
    for (std::size_t i = 0; i < keep; ++i) {
        id_to_token.push_back(sorted_tokens[i].first);
    }

    std::unordered_map<std::string, std::uint32_t> token_to_id;
    token_to_id.reserve(id_to_token.size() * 2u);
    for (std::uint32_t id = 0; id < id_to_token.size(); ++id) {
        token_to_id.emplace(id_to_token[id], id);
    }

    NextCounts unigrams;
    std::unordered_map<std::uint32_t, NextCounts> bigrams;
    std::unordered_map<std::uint64_t, NextCounts> trigrams;
    std::unordered_map<std::uint64_t, NextCounts> quadgrams;
    unigrams.reserve(id_to_token.size());
    bigrams.reserve(id_to_token.size());
    trigrams.reserve(id_to_token.size() * 2u);
    quadgrams.reserve(id_to_token.size() * 2u);

    std::uint32_t previous_3 = kBosId;
    std::uint32_t previous_2 = kBosId;
    std::uint32_t previous_1 = kBosId;

    for (const auto& segment : segments) {
        if (segment.kind == Segment::Kind::Raw) continue;
        const std::string token(
            reinterpret_cast<const char*>(corpus.data() + segment.offset),
            segment.length
        );
        const auto it = token_to_id.find(token);
        const std::uint32_t actual = it == token_to_id.end() ? kUnkId : it->second;

        ++unigrams[actual];
        ++bigrams[previous_1][actual];
        ++trigrams[make_context_key(previous_2, previous_1)][actual];
        ++quadgrams[make_context_key(previous_3, previous_2, previous_1)][actual];

        advance_context(previous_3, previous_2, previous_1, token, actual);
    }

    const auto unigram_top = top_candidates(unigrams, top_k);

    std::vector<std::pair<std::uint32_t, std::vector<std::uint32_t>>> bigram_rows;
    bigram_rows.reserve(bigrams.size());
    for (const auto& [context, counts] : bigrams) {
        bigram_rows.emplace_back(context, top_candidates(counts, top_k));
    }
    std::sort(bigram_rows.begin(), bigram_rows.end(), [](const auto& a, const auto& b) {
        return a.first < b.first;
    });

    std::vector<std::pair<std::uint64_t, std::vector<std::uint32_t>>> trigram_rows;
    trigram_rows.reserve(trigrams.size());
    for (const auto& [context, counts] : trigrams) {
        trigram_rows.emplace_back(context, top_candidates(counts, top_k));
    }
    std::sort(trigram_rows.begin(), trigram_rows.end(), [](const auto& a, const auto& b) {
        return a.first < b.first;
    });

    std::vector<std::pair<std::uint64_t, std::vector<std::uint32_t>>> quadgram_rows;
    quadgram_rows.reserve(quadgrams.size());
    for (const auto& [context, counts] : quadgrams) {
        quadgram_rows.emplace_back(context, top_candidates(counts, top_k));
    }
    std::sort(quadgram_rows.begin(), quadgram_rows.end(), [](const auto& a, const auto& b) {
        return a.first < b.first;
    });

    std::ofstream out(predictor_path, std::ios::binary | std::ios::trunc);
    if (!out) {
        error = "Could not open predictor output: " + predictor_path.string();
        return 2;
    }

    out.write(kPredictorMagic, 4);
    write_u32(out, kFormatVersion);
    write_u32(out, top_k);
    write_u32(out, static_cast<std::uint32_t>(id_to_token.size()));
    write_u32(out, static_cast<std::uint32_t>(unigram_top.size()));
    write_u32(out, static_cast<std::uint32_t>(bigram_rows.size()));
    write_u32(out, static_cast<std::uint32_t>(trigram_rows.size()));
    write_u32(out, static_cast<std::uint32_t>(quadgram_rows.size()));

    for (const auto& token : id_to_token) {
        if (token.size() > 65535u) {
            error = "A vocabulary token exceeds 65535 bytes";
            return 1;
        }
        write_u16(out, static_cast<std::uint16_t>(token.size()));
        out.write(token.data(), static_cast<std::streamsize>(token.size()));
    }

    for (const auto id : unigram_top) write_u32(out, id);

    for (const auto& [context, candidates] : bigram_rows) {
        write_u32(out, context);
        out.put(static_cast<char>(candidates.size()));
        for (const auto id : candidates) write_u32(out, id);
    }

    for (const auto& [context, candidates] : trigram_rows) {
        write_u64(out, context);
        out.put(static_cast<char>(candidates.size()));
        for (const auto id : candidates) write_u32(out, id);
    }

    for (const auto& [context, candidates] : quadgram_rows) {
        write_u64(out, context);
        out.put(static_cast<char>(candidates.size()));
        for (const auto id : candidates) write_u32(out, id);
    }

    if (!out) {
        error = "Failed while writing predictor file";
        return 2;
    }

    return 0;
}

} // namespace tp
