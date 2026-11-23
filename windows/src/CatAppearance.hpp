#pragma once
#define NOMINMAX
#include <windows.h>
#include <cstdint>
#include <algorithm>
#include <cmath>

enum class AppLanguage : int {
    Auto = 0,
    English = 1,
    ZhCN = 2
};

inline bool isChineseUI(AppLanguage lang) {
    if (lang == AppLanguage::English) return false;
    if (lang == AppLanguage::ZhCN) return true;
    LANGID lid = GetUserDefaultUILanguage();
    return PRIMARYLANGID(lid) == LANG_CHINESE;
}

inline const wchar_t* trW(AppLanguage lang, const wchar_t* en, const wchar_t* zh) {
    return isChineseUI(lang) ? zh : en;
}

struct RGBColor {
    uint8_t r = 22;
    uint8_t g = 22;
    uint8_t b = 24;

    float luminance() const {
        return (0.299f * r + 0.587f * g + 0.114f * b) / 255.0f;
    }

    DWORD pack() const {
        return ((DWORD)r) | ((DWORD)g << 8) | ((DWORD)b << 16);
    }

    static RGBColor unpack(DWORD v) {
        return { (uint8_t)(v & 0xFF), (uint8_t)((v >> 8) & 0xFF), (uint8_t)((v >> 16) & 0xFF) };
    }

    RGBColor darkened(float amount) const {
        float f = std::max(0.0f, 1.0f - amount);
        return { (uint8_t)(r * f), (uint8_t)(g * f), (uint8_t)(b * f) };
    }

    RGBColor lightened(float amount) const {
        float t = std::clamp(amount, 0.0f, 1.0f);
        return {
            (uint8_t)(r + (255 - r) * t),
            (uint8_t)(g + (255 - g) * t),
            (uint8_t)(b + (255 - b) * t)
        };
    }
};

enum class FurPattern : int {
    Solid = 0,
    Colorpoint = 1,
    Tuxedo = 2,
    Tabby = 3,
    Calico = 4,
    Spotted = 5
};

enum class CatBreedPreset : int {
    ClassicBlack = 0,
    Siamese = 1,
    OrangeTabby = 2,
    SilverTabby = 3,
    Tuxedo = 4,
    Calico = 5,
    Ragdoll = 6,
    BritishBlue = 7,
    WhitePersian = 8,
    GoldenMaineCoon = 9
};

enum class TieStyle : int {
    Necktie = 0,
    BowTie = 1
};

enum class TieColorTheme : int {
    Cyan = 0,
    Crimson = 1,
    Navy = 2,
    Emerald = 3,
    Amber = 4,
    Lavender = 5
};

enum class TiePattern : int {
    ScottishGrid = 0,
    DiagonalStripe = 1,
    PolkaDot = 2,
    Solid = 3
};

enum class TiredEyesMode : int {
    AutoLateNight = 0,
    AlwaysOn = 1,
    Off = 2
};

struct TiePalette {
    RGBColor base;
    RGBColor dark;
    RGBColor light;
    RGBColor accent;
};

inline TiePalette getTiePalette(TieColorTheme t) {
    switch (t) {
        case TieColorTheme::Cyan:     return { {87, 217, 230},  {36, 143, 163},  {224, 252, 255}, {26, 102, 122} };
        case TieColorTheme::Crimson:  return { {230, 89, 99},   {153, 46, 56},   {255, 235, 209}, {56, 122, 97} };
        case TieColorTheme::Navy:     return { {82, 133, 199},  {46, 82, 138},   {224, 240, 255}, {242, 201, 92} };
        case TieColorTheme::Emerald:  return { {71, 184, 143},  {36, 117, 89},   {219, 250, 237}, {240, 209, 97} };
        case TieColorTheme::Amber:    return { {245, 189, 82},  {173, 117, 41},  {255, 245, 214}, {102, 66, 36} };
        case TieColorTheme::Lavender: return { {184, 156, 235}, {122, 92, 179},  {245, 237, 255}, {87, 61, 138} };
    }
    return { {87, 217, 230}, {36, 143, 163}, {224, 252, 255}, {26, 102, 122} };
}

struct CatAppearance {
    int presetID = 0; // 0..9 for breed preset, -1 for custom
    FurPattern pattern = FurPattern::Solid;
    float furLength = 0.0f; // 0.0..1.0
    RGBColor primaryColor   = { 22, 22, 24 };
    RGBColor secondaryColor = { 41, 41, 46 };
    RGBColor tertiaryColor  = { 61, 61, 66 };
    RGBColor eyeColor       = { 201, 242, 64 };

    bool isDarkCoat() const { return primaryColor.luminance() < 0.28f; }
    bool useLongFurPipeline() const { return furLength >= 0.30f; }
};

inline CatAppearance makeBreedPreset(CatBreedPreset p) {
    CatAppearance a;
    a.presetID = (int)p;
    switch (p) {
        case CatBreedPreset::ClassicBlack:
            a.pattern = FurPattern::Solid; a.furLength = 0.0f;
            a.primaryColor = {22,22,24}; a.secondaryColor = {41,41,46}; a.tertiaryColor = {61,61,66}; a.eyeColor = {201,242,64};
            break;
        case CatBreedPreset::Siamese:
            a.pattern = FurPattern::Colorpoint; a.furLength = 0.0f;
            a.primaryColor = {241,231,213}; a.secondaryColor = {45,33,27}; a.tertiaryColor = {115,87,69}; a.eyeColor = {94,199,250};
            break;
        case CatBreedPreset::OrangeTabby:
            a.pattern = FurPattern::Tabby; a.furLength = 0.18f;
            a.primaryColor = {237,158,71}; a.secondaryColor = {184,92,28}; a.tertiaryColor = {250,237,214}; a.eyeColor = {242,194,51};
            break;
        case CatBreedPreset::SilverTabby:
            a.pattern = FurPattern::Tabby; a.furLength = 0.12f;
            a.primaryColor = {194,199,204}; a.secondaryColor = {61,66,74}; a.tertiaryColor = {242,245,247}; a.eyeColor = {122,214,112};
            break;
        case CatBreedPreset::Tuxedo:
            a.pattern = FurPattern::Tuxedo; a.furLength = 0.08f;
            a.primaryColor = {26,27,31}; a.secondaryColor = {245,246,247}; a.tertiaryColor = {224,227,232}; a.eyeColor = {242,199,61};
            break;
        case CatBreedPreset::Calico:
            a.pattern = FurPattern::Calico; a.furLength = 0.16f;
            a.primaryColor = {247,242,232}; a.secondaryColor = {230,128,46}; a.tertiaryColor = {41,36,36}; a.eyeColor = {237,184,56};
            break;
        case CatBreedPreset::Ragdoll:
            a.pattern = FurPattern::Colorpoint; a.furLength = 0.95f;
            a.primaryColor = {247,244,237}; a.secondaryColor = {92,79,71}; a.tertiaryColor = {163,145,133}; a.eyeColor = {82,189,250};
            break;
        case CatBreedPreset::BritishBlue:
            a.pattern = FurPattern::Solid; a.furLength = 0.32f;
            a.primaryColor = {112,122,138}; a.secondaryColor = {82,92,107}; a.tertiaryColor = {153,163,179}; a.eyeColor = {245,163,46};
            break;
        case CatBreedPreset::WhitePersian:
            a.pattern = FurPattern::Solid; a.furLength = 1.0f;
            a.primaryColor = {249,247,245}; a.secondaryColor = {230,227,222}; a.tertiaryColor = {252,252,252}; a.eyeColor = {115,224,250};
            break;
        case CatBreedPreset::GoldenMaineCoon:
            a.pattern = FurPattern::Tabby; a.furLength = 0.92f;
            a.primaryColor = {222,173,107}; a.secondaryColor = {122,77,38}; a.tertiaryColor = {247,237,217}; a.eyeColor = {209,219,71};
            break;
    }
    return a;
}
