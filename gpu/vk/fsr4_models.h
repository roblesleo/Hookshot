// (fork) AMD FSR 4's model, chosen (vk_fsr4.cpp). AMD's upscaler library carries four FSR 4 networks, each a class:
// ffxProvider_FSR4 (FP8, RDNA 4), _Int8 (RDNA 3), _Int8_Navi2 (RDNA 2) and ffxProvider_FSR4Lite_Int8 (APUs, handhelds). It
// asks each IsSupported(device), in that order, and runs the first that says yes; where none does (an NVIDIA or Intel GPU,
// a Ryzen APU AMD does not list) FSR 4 is not offered at all. Here one INT8 model can be made to say yes: the classes'
// vtables are found by their MSVC RTTI names in the loaded library and slot 2, IsSupported, points at model_supported.
//
// The safeguards (the review of NotRexed/Hookshot#1469):
// - only for the one file whose layout is known: amd_fidelityfx_upscaler_vk.dll of FSR SDK 2.4 (FSR 4.1.2), checked by its
//   SHA-256 before it is loaded; any other file is loaded and left alone, and FSR 4 is AMD's own choice there;
// - with Auto, AMD's own answer passes through, and only where AMD offers no FSR 4 at all does INT8 Lite stand in;
// - FP8 is never forced: it needs FP8 hardware (RDNA 4), where AMD offers it itself;
// - the file on disk is never changed.
// The model classes and their order are as OptiScaler (github.com/optiscaler/OptiScaler) documents them; no code of it here.
#pragma once

#include <atomic>
#include <cstdint>
#include <cstring>
#include <string>
#include <vector>

#ifdef _WIN32
#include <windows.h>
#endif

namespace mkwvk::fsr4_models {

/// What is asked for: the FSR 4 model row (opts.fsr4_model) or RX_VK_FSR4_MODEL over it
enum Model { AUTO = 0, INT8 = 1, INT8_RDNA2 = 2, INT8_LITE = 3, kModels = 4 };
/// The upscaler library this works on: FSR SDK 2.4's (tag v2.4.0), as scripts/ffx_sdk.py pins it
constexpr const char* kUpscalerSha256 = "4a7e895af6e0b615d40a84d59eb8c2b1054ad91cdd0c739567940270d51bdab7";

#ifdef _WIN32
struct ModelClass {
    const char* label;
    const char* rtti;
    void** vtable = nullptr;
    bool (*amd)(void*, void*) = nullptr;
    std::atomic<int> said{-1};
};
inline ModelClass g_classes[4] = {
    {"FP8", ".?AVffxProvider_FSR4@@"},
    {"INT8", ".?AVffxProvider_FSR4_Int8@@"},
    {"INT8 RDNA2", ".?AVffxProvider_FSR4_Int8_Navi2@@"},
    {"INT8 Lite", ".?AVffxProvider_FSR4Lite_Int8@@"},
};
/// The class index that says yes now (1 INT8, 2 INT8 RDNA2, 3 INT8 Lite), or -1: AMD's own answers
inline std::atomic<int> g_forced{-1};
inline bool g_hooked = false;

inline bool model_supported(void* self, void* device) {
    void** vt = *static_cast<void***>(self);
    for (int i = 0; i < 4; i++) {
        ModelClass& c = g_classes[i];
        if (c.vtable != vt) continue;
        const int forced = g_forced.load(std::memory_order_relaxed);
        return forced < 0 ? (c.amd ? c.amd(self, device) : false) : forced == i;
    }
    return false;
}

inline bool section(HMODULE m, const char* name, uint8_t** start, size_t* size) {
    uint8_t* base = reinterpret_cast<uint8_t*>(m);
    auto* nt = reinterpret_cast<IMAGE_NT_HEADERS*>(base + reinterpret_cast<IMAGE_DOS_HEADER*>(base)->e_lfanew);
    IMAGE_SECTION_HEADER* sec = IMAGE_FIRST_SECTION(nt);
    for (unsigned i = 0; i < nt->FileHeader.NumberOfSections; i++, sec++)
        if (!strncmp(reinterpret_cast<const char*>(sec->Name), name, 8)) {
            *start = base + sec->VirtualAddress, *size = sec->Misc.VirtualSize;
            return true;
        }
    return false;
}
/// A class's vtable by its RTTI name (x64 MSVC): the type descriptor holds the name 16 bytes in; a complete object locator
/// (signature 1, offset 0) names that descriptor and itself by RVA; the vtable starts one pointer after a pointer to it
inline void** class_vtable(HMODULE m, const char* rtti) {
    uint8_t* base = reinterpret_cast<uint8_t*>(m);
    uint8_t *data, *rdata;
    size_t data_size, rdata_size;
    if (!section(m, ".data", &data, &data_size) || !section(m, ".rdata", &rdata, &rdata_size)) return nullptr;
    const size_t len = strlen(rtti) + 1;
    uint8_t* name = nullptr;
    for (size_t i = 16; i + len <= data_size && !name; i++)
        if (!memcmp(data + i, rtti, len)) name = data + i;
    if (!name) return nullptr;
    const uint32_t td = (uint32_t)((name - 16) - base);
    for (size_t i = 0; i + 24 <= rdata_size; i += 4) {
        const uint32_t* col = reinterpret_cast<const uint32_t*>(rdata + i);
        if (col[0] != 1 || col[1] != 0 || col[3] != td) continue;
        if (col[5] != (uint32_t)(reinterpret_cast<const uint8_t*>(col) - base)) continue;
        const uint64_t at = reinterpret_cast<uint64_t>(col);
        for (size_t j = 0; j + 16 <= rdata_size; j += 8)
            if (*reinterpret_cast<const uint64_t*>(rdata + j) == at) return reinterpret_cast<void**>(rdata + j + 8);
    }
    return nullptr;
}

/// A file's SHA-256 in lower-case hex (Windows' CNG, loaded at run time: nothing more to link), "" when it cannot be read
inline std::string sha256_file(const std::string& path) {
    typedef LONG(WINAPI * Open)(void**, LPCWSTR, LPCWSTR, ULONG);
    typedef LONG(WINAPI * Create)(void*, void**, PUCHAR, ULONG, PUCHAR, ULONG, ULONG);
    typedef LONG(WINAPI * Data)(void*, PUCHAR, ULONG, ULONG);
    typedef LONG(WINAPI * Finish)(void*, PUCHAR, ULONG, ULONG);
    typedef LONG(WINAPI * Destroy)(void*);
    typedef LONG(WINAPI * Close)(void*, ULONG);
    HMODULE b = LoadLibraryA("bcrypt.dll");
    if (!b) return "";
    auto open = (Open)GetProcAddress(b, "BCryptOpenAlgorithmProvider");
    auto create = (Create)GetProcAddress(b, "BCryptCreateHash");
    auto data = (Data)GetProcAddress(b, "BCryptHashData");
    auto finish = (Finish)GetProcAddress(b, "BCryptFinishHash");
    auto destroy = (Destroy)GetProcAddress(b, "BCryptDestroyHash");
    auto close = (Close)GetProcAddress(b, "BCryptCloseAlgorithmProvider");
    if (!open || !create || !data || !finish || !destroy || !close) return "";
    FILE* f = fopen(path.c_str(), "rb");
    if (!f) return "";
    void *alg = nullptr, *h = nullptr;
    std::string hex;
    if (open(&alg, L"SHA256", nullptr, 0) == 0 && create(alg, &h, nullptr, 0, nullptr, 0, 0) == 0) {
        std::vector<unsigned char> buf(1 << 20);
        size_t n;
        bool ok = true;
        while (ok && (n = fread(buf.data(), 1, buf.size(), f)) > 0) ok = data(h, buf.data(), (ULONG)n, 0) == 0;
        unsigned char out[32];
        if (ok && finish(h, out, 32, 0) == 0) {
            static const char* d = "0123456789abcdef";
            for (unsigned char c : out) hex += d[c >> 4], hex += d[c & 15];
        }
    }
    if (h) destroy(h);
    if (alg) close(alg, 0);
    fclose(f);
    return hex;
}

/// Before the loader in dir is loaded: its upscaler library loaded and its model classes hooked, when its SHA-256 is the
/// pinned one. Returns what the log says of it
inline std::string prepare(const std::string& dir) {
    if (g_hooked) return "the FSR 4 model choice is on";
    const std::string path = dir + "\\amd_fidelityfx_upscaler_vk.dll";
    const std::string sha = sha256_file(path);
    if (sha.empty()) return "no amd_fidelityfx_upscaler_vk.dll beside it: AMD's own choice of FSR 4 model";
    if (sha != kUpscalerSha256)
        return "amd_fidelityfx_upscaler_vk.dll is not FSR SDK 2.4's (SHA-256 " + sha.substr(0, 16) +
               "...): AMD's own choice of FSR 4 model, nothing changed in it";
    HMODULE m = LoadLibraryExA(path.c_str(), nullptr, LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR | LOAD_LIBRARY_SEARCH_DEFAULT_DIRS);
    if (!m) return "amd_fidelityfx_upscaler_vk.dll did not load: AMD's own choice of FSR 4 model";
    std::string found;
    for (ModelClass& c : g_classes) {
        c.vtable = class_vtable(m, c.rtti);
        if (!c.vtable) continue;
        DWORD old = 0;
        if (!VirtualProtect(&c.vtable[2], sizeof(void*), PAGE_READWRITE, &old)) {
            c.vtable = nullptr;
            continue;
        }
        c.amd = reinterpret_cast<bool (*)(void*, void*)>(c.vtable[2]);
        c.vtable[2] = reinterpret_cast<void*>(&model_supported);
        VirtualProtect(&c.vtable[2], sizeof(void*), old, &old);
        found += (found.empty() ? "" : ", ") + std::string(c.label);
    }
    g_hooked = !found.empty();
    return g_hooked ? "FSR SDK 2.4's upscaler library (SHA-256 checked): the FSR 4 model can be chosen (" + found + ")"
                    : "FSR SDK 2.4's upscaler library, but its model classes were not found: AMD's own choice";
}
/// The class to say yes for a model asked for (-1: AMD's answers)
inline int forced_class(int model) { return model == INT8 ? 1 : model == INT8_RDNA2 ? 2 : model == INT8_LITE ? 3 : -1; }
inline const char* label(int model) {
    static const char* const t[kModels] = {"AMD's choice", "INT8", "INT8 RDNA2", "INT8 Lite"};
    return t[model >= 0 && model < kModels ? model : 0];
}
#else
inline bool g_hooked = false;
inline std::atomic<int> g_forced{-1};
inline std::string prepare(const std::string&) { return ""; }
inline int forced_class(int) { return -1; }
inline const char* label(int) { return "AMD's choice"; }
#endif

}  // namespace mkwvk::fsr4_models
