#include "internal.h"

#include <limits>

namespace tp {

std::vector<std::uint8_t> read_file(const std::filesystem::path& path, std::string& error) {
    std::ifstream in(path, std::ios::binary);
    if (!in) {
        error = "Could not open input file: " + path.string();
        return {};
    }

    in.seekg(0, std::ios::end);
    const std::streamoff size = in.tellg();
    if (size < 0) {
        error = "Could not determine file size: " + path.string();
        return {};
    }
    in.seekg(0, std::ios::beg);

    std::vector<std::uint8_t> data(static_cast<std::size_t>(size));
    if (size > 0) {
        in.read(reinterpret_cast<char*>(data.data()), size);
        if (!in) {
            error = "Could not read file: " + path.string();
            return {};
        }
    }
    return data;
}

bool write_file(const std::filesystem::path& path, const std::span<const std::uint8_t> data, std::string& error) {
    std::ofstream out(path, std::ios::binary | std::ios::trunc);
    if (!out) {
        error = "Could not open output file: " + path.string();
        return false;
    }
    if (!data.empty()) {
        out.write(reinterpret_cast<const char*>(data.data()), static_cast<std::streamsize>(data.size()));
    }
    if (!out) {
        error = "Could not write output file: " + path.string();
        return false;
    }
    return true;
}

std::uint64_t fnv1a64(const std::span<const std::uint8_t> data) {
    std::uint64_t hash = 14695981039346656037ull;
    for (const std::uint8_t byte : data) {
        hash ^= byte;
        hash *= 1099511628211ull;
    }
    return hash;
}

std::uint64_t fnv1a64_file(const std::filesystem::path& path, std::string& error) {
    const auto data = read_file(path, error);
    if (!error.empty()) {
        return 0;
    }
    return fnv1a64(data);
}

void write_u16(std::ostream& out, const std::uint16_t value) {
    const std::array<char, 2> b{
        static_cast<char>(value & 0xffu),
        static_cast<char>((value >> 8u) & 0xffu)
    };
    out.write(b.data(), b.size());
}

void write_u32(std::ostream& out, const std::uint32_t value) {
    std::array<char, 4> b{};
    for (std::size_t i = 0; i < b.size(); ++i) {
        b[i] = static_cast<char>((value >> (8u * i)) & 0xffu);
    }
    out.write(b.data(), b.size());
}

void write_u64(std::ostream& out, const std::uint64_t value) {
    std::array<char, 8> b{};
    for (std::size_t i = 0; i < b.size(); ++i) {
        b[i] = static_cast<char>((value >> (8u * i)) & 0xffu);
    }
    out.write(b.data(), b.size());
}

bool read_u16(std::istream& in, std::uint16_t& value) {
    std::array<unsigned char, 2> b{};
    in.read(reinterpret_cast<char*>(b.data()), b.size());
    if (!in) return false;
    value = static_cast<std::uint16_t>(b[0]) |
            (static_cast<std::uint16_t>(b[1]) << 8u);
    return true;
}

bool read_u32(std::istream& in, std::uint32_t& value) {
    std::array<unsigned char, 4> b{};
    in.read(reinterpret_cast<char*>(b.data()), b.size());
    if (!in) return false;
    value = 0;
    for (std::size_t i = 0; i < b.size(); ++i) {
        value |= static_cast<std::uint32_t>(b[i]) << (8u * i);
    }
    return true;
}

bool read_u64(std::istream& in, std::uint64_t& value) {
    std::array<unsigned char, 8> b{};
    in.read(reinterpret_cast<char*>(b.data()), b.size());
    if (!in) return false;
    value = 0;
    for (std::size_t i = 0; i < b.size(); ++i) {
        value |= static_cast<std::uint64_t>(b[i]) << (8u * i);
    }
    return true;
}

void write_varuint(std::ostream& out, std::uint64_t value) {
    while (value >= 0x80u) {
        out.put(static_cast<char>((value & 0x7fu) | 0x80u));
        value >>= 7u;
    }
    out.put(static_cast<char>(value));
}

bool read_varuint(std::istream& in, std::uint64_t& value) {
    value = 0;
    unsigned shift = 0;
    while (shift < 64) {
        const int c = in.get();
        if (c == std::char_traits<char>::eof()) {
            return false;
        }
        const auto byte = static_cast<std::uint8_t>(c);
        value |= static_cast<std::uint64_t>(byte & 0x7fu) << shift;
        if ((byte & 0x80u) == 0) {
            return true;
        }
        shift += 7u;
    }
    return false;
}

} // namespace tp

