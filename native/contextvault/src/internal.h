#pragma once

#include <array>
#include <cstddef>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <optional>
#include <span>
#include <string>
#include <string_view>
#include <unordered_map>
#include <utility>
#include <vector>

namespace tp {

constexpr std::uint32_t kBosId = 0;
constexpr std::uint32_t kUnkId = 1;
constexpr std::uint32_t kFormatVersion = 3;
constexpr std::uint32_t kMaxTopK = 16;
constexpr std::uint32_t kContextTokenLimit = 1u << 21;

struct Segment {
    enum class Kind : std::uint8_t { Token, Raw };
    Kind kind;
    std::size_t offset;
    std::size_t length;
};

std::vector<Segment> tokenize_exact(std::span<const std::uint8_t> bytes);
bool is_word_byte(std::uint8_t byte);
bool is_boundary_token(std::string_view token);

struct CandidateSpan {
    const std::uint32_t* data = nullptr;
    std::uint8_t size = 0;
};

struct EncodeStats {
    std::uint64_t token_count = 0;
    std::uint64_t r1_count = 0;
    std::uint64_t rank2_16_count = 0;
    std::uint64_t punct_count = 0;
    std::uint64_t literal_ref_count = 0;
    std::uint64_t literal_count = 0;
    std::uint64_t literal_bytes = 0;
    std::uint64_t r1_bytes = 0;
    std::uint64_t rank2_16_bytes = 0;
    std::uint64_t punct_bytes = 0;
    std::uint64_t literal_ref_bytes = 0;
    std::uint64_t literal_output_bytes = 0;
    std::uint64_t escape_bytes = 0;
};

enum class ImportSourceKind : std::uint8_t {
    Txt,
    ChatGPT
};

struct TxtParagraphRecord {
    std::string message_id;
    std::string conversation_title;
    std::string role;
    std::string timestamp;
    std::size_t paragraph_index = 0;
    std::size_t section_index = 0;
    std::size_t start_offset = 0;
    std::size_t end_offset = 0;
    std::size_t start_line = 0;
    std::size_t end_line = 0;
    bool is_heading = false;
    std::uint64_t checksum = 0;
    std::string text;
};

struct TxtSectionRecord {
    std::size_t section_index = 0;
    std::size_t heading_paragraph_index = 0;
    std::size_t start_paragraph_index = 0;
    std::size_t end_paragraph_index = 0;
    std::string heading_text;
};

struct TxtDateRecord {
    std::size_t paragraph_index = 0;
    std::size_t start_offset = 0;
    std::size_t end_offset = 0;
    std::string raw_text;
    std::string normalized_date;
};

enum class TxtNumericKind : std::uint8_t {
    Number,
    Amount,
    Percentage
};

struct TxtNumericRecord {
    TxtNumericKind kind = TxtNumericKind::Number;
    std::size_t paragraph_index = 0;
    std::size_t start_offset = 0;
    std::size_t end_offset = 0;
    std::string raw_text;
    std::string normalized_value;
};

struct TxtImportRecord {
    std::filesystem::path source_path;
    std::string title;
    ImportSourceKind source_kind = ImportSourceKind::Txt;
    std::uint64_t source_checksum = 0;
    std::size_t char_window_chars = 0;
    struct TxtCharShardRecord {
        std::size_t shard_index = 0;
        std::size_t start_offset = 0;
        std::size_t end_offset = 0;
    };
    std::vector<TxtCharShardRecord> char_shards;
    std::vector<TxtSectionRecord> sections;
    std::vector<TxtDateRecord> dates;
    std::vector<TxtNumericRecord> numerics;
    std::vector<TxtParagraphRecord> paragraphs;
};

enum class TxtAtomKind : std::uint8_t {
    Paragraph,
    Sentence
};

struct TxtAtomRecord {
    std::string atom_id;
    TxtAtomKind kind = TxtAtomKind::Paragraph;
    std::size_t paragraph_index = 0;
    std::size_t section_index = 0;
    std::size_t atom_index = 0;
    std::size_t start_offset = 0;
    std::size_t end_offset = 0;
    bool is_heading = false;
    std::uint64_t checksum = 0;
    std::string text;
};

struct TxtAtomIndex {
    std::vector<TxtAtomRecord> atoms;
    std::unordered_map<std::string, std::size_t> atom_id_to_index;
    std::unordered_map<std::string, std::vector<std::size_t>> text_to_indices;
    std::unordered_map<std::uint64_t, std::vector<std::size_t>> checksum_to_indices;
};

struct TxtAtomSearchHit {
    const TxtAtomRecord* atom = nullptr;
    double score = 0.0;
    double calibrated_score = 0.0;
    double near_duplicate_similarity = 0.0;
    double shingle_similarity = 0.0;
    std::size_t simhash_bucket_size = 1;
    std::string pattern_family_key;
    std::size_t family_group_size = 1;
    std::size_t matched_terms = 0;
    std::size_t phrase_matches = 0;
    double proximity_score = 0.0;
    std::size_t duplicate_group_size = 1;
    std::size_t phrase_fingerprint_group_size = 1;
    std::size_t shingle_group_size = 1;
    std::uint64_t phrase_fingerprint = 0;
    bool rare_residual = false;
    bool exact_text_match = false;
    bool family_collapsed = false;
    std::string change_kind;
    std::string change_left;
    std::string change_right;
    std::size_t change_context_overlap = 0;
    bool exact_change_value_match = false;
    std::string match_reason;
};

struct TxtChangeRecord {
    std::size_t left_atom_index = 0;
    std::size_t right_atom_index = 0;
    std::string change_kind;
    std::string left_value;
    std::string right_value;
    std::string family_key;
    double similarity = 0.0;
};

struct TxtResidualRecord {
    std::size_t change_record_index = 0;
    std::string residual_kind;
    std::string family_key;
};

struct TxtAtomSearchIndex {
    const TxtAtomIndex* atom_index = nullptr;
    const TxtImportRecord* source_record = nullptr;
    bool change_index_ready = false;
    bool duplicate_support_ready = false;
    std::unordered_map<std::string, std::vector<std::size_t>> term_to_indices;
    std::vector<std::vector<std::string>> atom_terms;
    std::vector<std::vector<std::string>> atom_term_sequences;
    std::vector<std::vector<std::uint64_t>> atom_shingles;
    std::vector<std::string> normalized_atom_texts;
    std::vector<std::string> lower_atom_texts;
    std::vector<std::string> normalized_section_headings;
    std::vector<std::size_t> atom_term_counts;
    std::vector<bool> atom_is_title_like;
    std::vector<bool> atom_is_cover_like;
    std::vector<bool> atom_has_what_cue;
    std::vector<bool> atom_has_how_form_cue;
    std::vector<bool> atom_has_how_collapse_cue;
    std::vector<bool> atom_has_how_cause_cue;
    std::vector<bool> atom_has_how_using_cue;
    std::vector<bool> atom_has_how_study_cue;
    std::vector<bool> atom_has_where_cue;
    std::vector<bool> atom_has_why_cue;
    std::vector<bool> atom_has_when_cue;
    std::vector<bool> atom_has_who_cue;
    std::vector<std::uint64_t> atom_phrase_fingerprints;
    std::vector<std::size_t> atom_phrase_fingerprint_group_sizes;
    std::unordered_map<std::uint64_t, std::vector<std::size_t>> phrase_fingerprint_to_indices;
    std::vector<std::string> atom_family_keys;
    std::vector<std::size_t> atom_family_group_sizes;
    std::vector<std::size_t> atom_duplicate_group_sizes;
    std::unordered_map<std::string, std::vector<std::size_t>> family_key_to_indices;
    std::unordered_map<std::uint64_t, std::vector<std::size_t>> shingle_to_indices;
    std::vector<std::uint64_t> atom_simhashes;
    std::unordered_map<std::uint64_t, std::vector<std::size_t>> simhash_band_to_indices;
    std::vector<TxtChangeRecord> change_records;
    std::unordered_map<std::string, std::vector<std::size_t>> change_key_to_indices;
    std::unordered_map<std::string, std::vector<std::size_t>> change_kind_to_indices;
    std::unordered_map<std::string, std::vector<std::size_t>> change_family_to_indices;
    std::vector<TxtResidualRecord> residual_records;
    std::unordered_map<std::string, std::vector<std::size_t>> residual_key_to_indices;
    std::unordered_map<std::string, std::vector<std::size_t>> residual_kind_to_indices;
    std::unordered_map<std::string, std::vector<std::size_t>> residual_family_to_indices;
};

class Predictor {
public:
    bool load(const std::filesystem::path& path, std::string& error);

    CandidateSpan predict(std::uint32_t previous_3, std::uint32_t previous_2, std::uint32_t previous_1) const;
    std::optional<std::uint32_t> find_token_id(std::string_view token) const;
    std::string_view token_bytes(std::uint32_t token_id) const;
    const std::vector<std::string>& tokens() const noexcept { return id_to_token_; }

    std::uint64_t file_hash() const noexcept { return file_hash_; }
    std::uint32_t top_k() const noexcept { return top_k_; }
    std::size_t vocabulary_size() const noexcept { return id_to_token_.size(); }

private:
    std::uint32_t top_k_ = 0;
    std::uint64_t file_hash_ = 0;
    std::vector<std::string> id_to_token_;
    std::unordered_map<std::string, std::uint32_t> token_to_id_;
    std::vector<std::uint32_t> unigram_;
    std::unordered_map<std::uint32_t, std::vector<std::uint32_t>> bigrams_;
    std::unordered_map<std::uint64_t, std::vector<std::uint32_t>> trigrams_;
    std::unordered_map<std::uint64_t, std::vector<std::uint32_t>> quadgrams_;
};

std::uint64_t make_context_key(std::uint32_t previous_2, std::uint32_t previous_1);
std::uint64_t make_context_key(std::uint32_t previous_3, std::uint32_t previous_2, std::uint32_t previous_1);

std::vector<std::uint8_t> read_file(const std::filesystem::path& path, std::string& error);
bool write_file(const std::filesystem::path& path, std::span<const std::uint8_t> data, std::string& error);
TxtImportRecord import_txt_bytes(
    std::span<const std::uint8_t> bytes,
    const std::filesystem::path& source_path,
    std::string& error,
    bool compute_paragraph_checksums = false
);
TxtImportRecord import_chatgpt_bytes(
    std::span<const std::uint8_t> bytes,
    const std::filesystem::path& source_path,
    std::string& error,
    bool compute_paragraph_checksums = false
);
TxtImportRecord import_txt_file(const std::filesystem::path& path, std::string& error, bool compute_paragraph_checksums = false);
TxtImportRecord import_source_record(ImportSourceKind kind, const std::filesystem::path& path, std::string& error, bool compute_paragraph_checksums = false);
bool write_txt_manifest(
    const TxtImportRecord& record,
    const std::filesystem::path& path,
    std::string& error,
    std::optional<double> compression_time_ms = std::nullopt
);
TxtAtomIndex build_txt_atom_index(const TxtImportRecord& record, std::string& error);
const TxtAtomRecord* find_txt_atom_by_id(const TxtAtomIndex& index, std::string_view atom_id);
std::vector<const TxtAtomRecord*> find_txt_atoms_by_text(const TxtAtomIndex& index, std::string_view text);
bool write_txt_atom_manifest(const TxtImportRecord& record, const TxtAtomIndex& index, const std::filesystem::path& path, std::string& error);
TxtAtomSearchIndex build_txt_atom_search_index(const TxtImportRecord& record, const TxtAtomIndex& index, std::string& error);
bool build_txt_change_index(const TxtImportRecord& record, const TxtAtomIndex& index, TxtAtomSearchIndex& search_index, std::string& error);
bool build_txt_duplicate_support_index(const TxtAtomIndex& index, TxtAtomSearchIndex& search_index, std::string& error);
std::vector<TxtAtomSearchHit> search_txt_atoms(
    TxtAtomSearchIndex& index,
    std::string_view query,
    std::size_t max_results,
    std::string& error,
    bool all_occurrences = false
);

std::vector<std::uint8_t> encode_bytes(
    std::span<const std::uint8_t> input,
    const Predictor& predictor,
    std::string& error,
    EncodeStats* stats = nullptr
);

std::vector<std::uint8_t> decode_bytes(
    std::span<const std::uint8_t> input,
    const Predictor& predictor,
    std::string& error
);

std::uint64_t fnv1a64(std::span<const std::uint8_t> data);
std::uint64_t fnv1a64_file(const std::filesystem::path& path, std::string& error);

void write_u16(std::ostream& out, std::uint16_t value);
void write_u32(std::ostream& out, std::uint32_t value);
void write_u64(std::ostream& out, std::uint64_t value);
bool read_u16(std::istream& in, std::uint16_t& value);
bool read_u32(std::istream& in, std::uint32_t& value);
bool read_u64(std::istream& in, std::uint64_t& value);
void write_varuint(std::ostream& out, std::uint64_t value);
bool read_varuint(std::istream& in, std::uint64_t& value);

int build_predictor_impl(
    const std::filesystem::path& corpus_path,
    const std::filesystem::path& predictor_path,
    std::uint32_t vocabulary_size,
    std::uint32_t top_k,
    std::string& error
);

int encode_file_impl(
    const std::filesystem::path& input_path,
    const std::filesystem::path& output_path,
    const std::filesystem::path& predictor_path,
    std::string& error
);

int decode_file_impl(
    const std::filesystem::path& input_path,
    const std::filesystem::path& output_path,
    const std::filesystem::path& predictor_path,
    std::string& error
);

} // namespace tp
