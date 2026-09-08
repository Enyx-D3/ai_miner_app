#include "internal.h"

#include <algorithm>
#include <cstring>
#include <limits>

namespace tp {

namespace {
constexpr char kPredictorMagicV2[4] = {'T', 'P', 'P', '2'};
constexpr char kPredictorMagicV3[4] = {'T', 'P', 'P', '3'};
constexpr std::uint64_t kContextPartMask = (1ull << 21u) - 1ull;

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

std::uint64_t make_context_key(const std::uint32_t previous_2, const std::uint32_t previous_1) {
    return (static_cast<std::uint64_t>(previous_2) << 32u) |
           static_cast<std::uint64_t>(previous_1);
}

std::uint64_t make_context_key(const std::uint32_t previous_3, const std::uint32_t previous_2, const std::uint32_t previous_1) {
    return ((static_cast<std::uint64_t>(previous_3) & kContextPartMask) << 42u) |
           ((static_cast<std::uint64_t>(previous_2) & kContextPartMask) << 21u) |
            (static_cast<std::uint64_t>(previous_1) & kContextPartMask);
}

bool Predictor::load(const std::filesystem::path& path, std::string& error) {
    file_hash_ = fnv1a64_file(path, error);
    if (!error.empty()) return false;

    std::ifstream in(path, std::ios::binary);
    if (!in) {
        error = "Could not open predictor: " + path.string();
        return false;
    }

    char magic[4]{};
    in.read(magic, 4);
    if (!in) {
        error = "Invalid predictor header";
        return false;
    }

    const bool is_v2 = std::memcmp(magic, kPredictorMagicV2, 4) == 0;
    const bool is_v3 = std::memcmp(magic, kPredictorMagicV3, 4) == 0;
    if (!is_v2 && !is_v3) {
        error = "Invalid predictor magic";
        return false;
    }

    std::uint32_t version = 0;
    std::uint32_t vocab_count = 0;
    std::uint32_t unigram_count = 0;
    std::uint32_t bigram_count = 0;
    std::uint32_t trigram_count = 0;
    std::uint32_t quadgram_count = 0;

    if (!read_u32(in, version) ||
        !read_u32(in, top_k_) ||
        !read_u32(in, vocab_count) ||
        !read_u32(in, unigram_count) ||
        !read_u32(in, bigram_count) ||
        !read_u32(in, trigram_count)) {
        error = "Truncated predictor header";
        return false;
    }

    if ((is_v2 && version != 2u) || (is_v3 && version != 3u) || top_k_ == 0 || top_k_ > kMaxTopK || vocab_count < 2u || vocab_count > kContextTokenLimit) {
        error = "Unsupported predictor version or settings";
        return false;
    }

    if (version >= 3u) {
        if (!read_u32(in, quadgram_count)) {
            error = "Truncated predictor header";
            return false;
        }
    }

    id_to_token_.clear();
    id_to_token_.reserve(vocab_count);
    token_to_id_.clear();
    token_to_id_.reserve(vocab_count * 2u);

    for (std::uint32_t id = 0; id < vocab_count; ++id) {
        std::uint16_t length = 0;
        if (!read_u16(in, length)) {
            error = "Truncated vocabulary record";
            return false;
        }
        std::string token(length, '\0');
        if (length > 0) {
            in.read(token.data(), length);
            if (!in) {
                error = "Truncated vocabulary bytes";
                return false;
            }
        }
        id_to_token_.push_back(token);
        token_to_id_.emplace(token, id);
    }

    unigram_.resize(unigram_count);
    for (auto& id : unigram_) {
        if (!read_u32(in, id) || id >= vocab_count) {
            error = "Invalid unigram entry";
            return false;
        }
    }

    bigrams_.clear();
    bigrams_.reserve(bigram_count * 2u);
    for (std::uint32_t i = 0; i < bigram_count; ++i) {
        std::uint32_t context = 0;
        if (!read_u32(in, context)) {
            error = "Truncated bigram entry";
            return false;
        }
        const int count_int = in.get();
        if (count_int == std::char_traits<char>::eof()) {
            error = "Truncated bigram entry";
            return false;
        }
        const auto count = static_cast<std::uint8_t>(count_int);
        if (count > top_k_) {
            error = "Invalid bigram candidate count";
            return false;
        }
        std::vector<std::uint32_t> candidates(count);
        for (auto& id : candidates) {
            if (!read_u32(in, id) || id >= vocab_count) {
                error = "Invalid bigram candidate";
                return false;
            }
        }
        bigrams_.emplace(context, std::move(candidates));
    }

    trigrams_.clear();
    trigrams_.reserve(trigram_count * 2u);
    for (std::uint32_t i = 0; i < trigram_count; ++i) {
        std::uint64_t context = 0;
        if (!read_u64(in, context)) {
            error = "Truncated trigram entry";
            return false;
        }
        const int count_int = in.get();
        if (count_int == std::char_traits<char>::eof()) {
            error = "Truncated trigram entry";
            return false;
        }
        const auto count = static_cast<std::uint8_t>(count_int);
        if (count > top_k_) {
            error = "Invalid trigram candidate count";
            return false;
        }
        std::vector<std::uint32_t> candidates(count);
        for (auto& id : candidates) {
            if (!read_u32(in, id) || id >= vocab_count) {
                error = "Invalid trigram candidate";
                return false;
            }
        }
        trigrams_.emplace(context, std::move(candidates));
    }

    quadgrams_.clear();
    quadgrams_.reserve(quadgram_count * 2u);
    for (std::uint32_t i = 0; i < quadgram_count; ++i) {
        std::uint64_t context = 0;
        if (!read_u64(in, context)) {
            error = "Truncated quadgram entry";
            return false;
        }
        const int count_int = in.get();
        if (count_int == std::char_traits<char>::eof()) {
            error = "Truncated quadgram entry";
            return false;
        }
        const auto count = static_cast<std::uint8_t>(count_int);
        if (count > top_k_) {
            error = "Invalid quadgram candidate count";
            return false;
        }
        std::vector<std::uint32_t> candidates(count);
        for (auto& id : candidates) {
            if (!read_u32(in, id) || id >= vocab_count) {
                error = "Invalid quadgram candidate";
                return false;
            }
        }
        quadgrams_.emplace(context, std::move(candidates));
    }

    return true;
}

CandidateSpan Predictor::predict(
    const std::uint32_t previous_3,
    const std::uint32_t previous_2,
    const std::uint32_t previous_1
) const {
    static thread_local std::vector<std::uint32_t> buffer;
    buffer.clear();

    const std::vector<std::uint32_t>* selected = nullptr;
    if (const auto quad = quadgrams_.find(make_context_key(previous_3, previous_2, previous_1)); quad != quadgrams_.end()) {
        selected = &quad->second;
    } else if (const auto tri = trigrams_.find(make_context_key(previous_2, previous_1)); tri != trigrams_.end()) {
        selected = &tri->second;
    } else if (const auto bi = bigrams_.find(previous_1); bi != bigrams_.end()) {
        selected = &bi->second;
    } else if (!unigram_.empty()) {
        selected = &unigram_;
    }

    if (selected == nullptr) {
        return {nullptr, 0};
    }

    buffer = *selected;
    if (buffer.size() > kMaxTopK) {
        buffer.resize(kMaxTopK);
    }
    return {buffer.data(), static_cast<std::uint8_t>(buffer.size())};
}

std::optional<std::uint32_t> Predictor::find_token_id(const std::string_view token) const {
    const auto it = token_to_id_.find(std::string(token));
    if (it == token_to_id_.end()) return std::nullopt;
    return it->second;
}

std::string_view Predictor::token_bytes(const std::uint32_t token_id) const {
    if (token_id >= id_to_token_.size()) return {};
    return id_to_token_[token_id];
}

} // namespace tp
