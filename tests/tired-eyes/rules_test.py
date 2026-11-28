"""Clock-window rules for 0:00–6:00 tired eyes. Mirrors TiredEyesMode in Sources/CatPhysics.swift."""

def is_late_night_hour(hour: int) -> bool:
    return 0 <= hour < 6


def target_level(mode: str, is_late_night: bool) -> float:
    if mode == "auto":
        return 1.0 if is_late_night else 0.0
    if mode == "always":
        return 1.0
    if mode == "off":
        return 0.0
    raise AssertionError(mode)


def main() -> None:
    for hour in range(24):
        late = is_late_night_hour(hour)
        assert late == (hour < 6), hour
        assert target_level("auto", late) == (1.0 if hour < 6 else 0.0)
    assert target_level("always", False) == 1.0
    assert target_level("always", True) == 1.0
    assert target_level("off", True) == 0.0
    assert target_level("off", False) == 0.0
    # Hunting damps the rendered lid: tiredness * (1 - hunt * 0.78), clamped.
    def effective(tiredness: float, hunt: float) -> float:
        return max(0.0, min(1.0, tiredness * (1.0 - hunt * 0.78)))
    assert effective(1.0, 0.0) == 1.0
    assert abs(effective(1.0, 1.0) - 0.22) < 1e-9
    assert effective(0.0, 1.0) == 0.0
    print("PASS: late-night window is hours 0–5; auto/always/off targets; hunt damps lids")


if __name__ == "__main__":
    main()
