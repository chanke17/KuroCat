"""HID census rules mirrored from Sources/PeripheralClassifier.swift.

An empty or missing device list must clear external keyboard/mouse flags
so the last unplugged device does not stay on screen.
"""

MOUSE_KEYWORDS = [
    "mouse", "trackball", "trackpad", "mx master", "mx anywhere", "mx vertical",
    "deathadder", "viper", "basilisk", "superlight", "g pro", "g304", "g305", "g502",
    "magic mouse", "aerox", "model o", "model d", "pulsar", "lamzu", "zowie", "finalmouse",
]


def looks_like_mouse(product: str) -> bool:
    lower = product.lower()
    return any(word in lower for word in MOUSE_KEYWORDS)


def classify(devices):
    built_kb = built_tp = False
    ext_kb = set()
    ext_mouse = set()
    for dev in devices:
        transport = dev["transport"]
        product = dev["product"]
        if transport.lower() == "virtual" or "karabiner" in product.lower() or "virtual" in product.lower():
            continue
        internal = (
            dev["built_in"]
            or transport.lower() in ("fifo", "spi")
            or "apple internal" in product.lower()
        )
        if internal:
            if dev["usage"] == "keyboard":
                built_kb = True
            elif dev["usage"] == "mouse":
                built_tp = True
            continue
        ident = (dev["vid"], dev["pid"], dev["loc"], product)
        if dev["usage"] == "keyboard":
            ext_kb.add(ident)
        elif dev["usage"] == "mouse":
            ext_mouse.add(ident)
    for comp in ext_kb & ext_mouse:
        if looks_like_mouse(comp[3]):
            ext_kb.discard(comp)
        else:
            ext_mouse.discard(comp)
    return {
        "built_kb": built_kb,
        "built_tp": built_tp,
        "ext_kb": bool(ext_kb),
        "ext_mouse": bool(ext_mouse),
    }


def refresh(devices):
    """Nil and empty enumerations are the same empty census."""
    flags = classify([] if devices is None else devices)
    return flags, (not flags["ext_kb"]), (not flags["ext_mouse"])


def dev(**kwargs):
    base = {"usage": "keyboard", "built_in": False, "transport": "USB", "product": "", "vid": 1, "pid": 2, "loc": 3}
    base.update(kwargs)
    return base


def main():
    empty = {"built_kb": False, "built_tp": False, "ext_kb": False, "ext_mouse": False}
    flags, reset_kb, reset_mouse = refresh(None)
    assert flags == empty and reset_kb and reset_mouse
    flags, reset_kb, reset_mouse = refresh([])
    assert flags == empty and reset_kb and reset_mouse

    flags, reset_kb, reset_mouse = refresh([
        dev(usage="keyboard", built_in=True, transport="SPI", product="Apple Internal Keyboard"),
        dev(usage="mouse", built_in=True, transport="SPI", product="Apple Internal Trackpad", vid=9),
        dev(usage="keyboard", product="Keychron Q1", vid=4, pid=5, loc=6),
        dev(usage="mouse", product="Keychron Q1", vid=4, pid=5, loc=6),
        dev(usage="keyboard", product="Karabiner Virtual HID", transport="Virtual", vid=7),
    ])
    assert flags["built_kb"] and flags["built_tp"]
    assert flags["ext_kb"] and not flags["ext_mouse"]
    assert not reset_kb and reset_mouse

    flags, _, reset_mouse = refresh([
        dev(usage="keyboard", product="MX Master 3", vid=8, pid=1, loc=2),
        dev(usage="mouse", product="MX Master 3", vid=8, pid=1, loc=2),
    ])
    assert not flags["ext_kb"] and flags["ext_mouse"] and not reset_mouse

    # Last matching device removed: stale external state must clear.
    flags, reset_kb, reset_mouse = refresh([])
    assert flags == empty and reset_kb and reset_mouse
    print("PASS: empty HID census clears peripherals; composite keyboard/mouse interfaces are disambiguated")


if __name__ == "__main__":
    main()
