#pragma once

#include "CatPhysics.hpp"
#include "../../shared/SkinSpec.hpp"

namespace dazed_skin {

inline bool matches(const SkinSpec& skin) {
    return skin.renderStyle == SkinRenderStyle::Dazed || (skin.builtIn && skin.id == "builtin:4");
}

inline float sleepPose(const CatPhysics& physics) {
    float t = std::clamp(physics.lieIntensity.value, 0.0f, 1.0f);
    return t * t * (3.0f - 2.0f * t);
}

struct ArmPose {
    Pt shoulder;
    Pt control;
    Pt wrist;
};

inline ArmPose keyArm(Pt top, const Spring2D& paw, Pt rest, float travel, bool left) {
    float side = left ? -1.0f : 1.0f;
    ArmPose idle{{top.x + side * 2.0f, top.y + 13.0f},
                 {top.x + side * 9.0f, top.y + 20.0f},
                 {top.x + side * 8.0f, top.y + 34.0f}};
    if (travel <= 2.5f) return idle;
    float blend = 1.0f;
    if (travel < 24.0f) {
        float keyTravel = std::hypot(paw.x.target - rest.x, paw.y.target - rest.y);
        float end = std::clamp(keyTravel * 0.82f, 8.0f, 24.0f);
        float t = std::min(1.0f, (travel - 2.5f) / (end - 2.5f));
        blend = t * t * (3.0f - 2.0f * t);
    }

    constexpr float upperArm = 29.0f;
    constexpr float forearm = 34.0f;
    Pt target = paw.point();
    Pt shoulder{idle.shoulder.x + side * 2.0f * blend, idle.shoulder.y};
    float dx = target.x - shoulder.x;
    float dy = target.y - shoulder.y;
    float distance = std::hypot(dx, dy);
    Pt direction = distance > 0.001f ? Pt{dx / distance, dy / distance} : Pt{0.0f, 1.0f};
    // Keep a small elbow bend at maximum reach.
    float reach = std::clamp(distance, 18.0f, upperArm + forearm - 2.0f);
    float along = (upperArm * upperArm - forearm * forearm + reach * reach) / (2.0f * reach);
    float outward = -side * std::sqrt(std::max(0.0f, upperArm * upperArm - along * along));
    Pt elbow{shoulder.x + direction.x * along - direction.y * outward,
             shoulder.y + direction.y * along + direction.x * outward};
    Pt wrist{shoulder.x + direction.x * reach, shoulder.y + direction.y * reach};
    // The existing sleeve path is a quadratic. Place its control point so it passes through the solved elbow.
    constexpr float joint = upperArm / (upperArm + forearm);
    constexpr float before = 1.0f - joint;
    constexpr float weight = 2.0f * before * joint;
    Pt control{(elbow.x - before * before * shoulder.x - joint * joint * wrist.x) / weight,
               (elbow.y - before * before * shoulder.y - joint * joint * wrist.y) / weight};
    auto lerp = [blend](Pt from, Pt to) {
        return Pt{from.x + (to.x - from.x) * blend, from.y + (to.y - from.y) * blend};
    };
    return {shoulder, lerp(idle.control, control), lerp(idle.wrist, wrist)};
}

class Callout {
public:
    static constexpr float lifetime = 1.65f;

    void update(const CatPhysics& physics) {
        // CatPhysics can be reset when the pose is recovered, including its animation clock.
        if (physics.time < started_) *this = {};

        bool lifted = physics.isScruffDragging_ && physics.scruffDrag.value > 0.18f;
        bool petted = physics.petHeadIntensity >= (petted_ ? 0.26f : 0.65f);
        bool wokeUp = asleep_ && physics.sleepiness < 0.24f;
        if (physics.sleepiness > 0.76f) asleep_ = true;
        if (wokeUp) asleep_ = false;

        Line next = Line::None;
        if (lifted && !lifted_) next = Line::PickedUp;
        else if (!lifted && wokeUp) next = Line::WokeUp;
        else if (!lifted && petted && !petted_) next = Line::Petted;
        lifted_ = lifted;
        petted_ = petted;

        if (next != Line::None && (line_ == Line::None || age(physics.time) >= 5.0f)) {
            line_ = next;
            started_ = physics.time;
        }
    }

    float age(float now) const { return now - started_; }

    const wchar_t* text(float now) const {
        if (age(now) >= lifetime) return nullptr;
        switch (line_) {
            case Line::PickedUp: return L"\u8001\u5927\uFF01";
            case Line::Petted: return L"\u8001\u5927\uFF5E";
            case Line::WokeUp: return L"\u8001\u5927\u2026";
            case Line::None: return nullptr;
        }
        return nullptr;
    }

private:
    enum class Line { None, PickedUp, Petted, WokeUp };
    Line line_ = Line::None;
    float started_ = 0.0f;
    bool lifted_ = false;
    bool petted_ = false;
    bool asleep_ = false;
};

} // namespace dazed_skin
