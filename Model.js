.pragma library

function addressFromBar(config) {
    var layout = config && config.layout ? config.layout : {};
    var sections = ["left", "centerBegin", "center", "centerEnd", "tray", "right"];
    for (var s = 0; s < sections.length; ++s) {
        var entries = layout[sections[s]] || [];
        for (var i = 0; i < entries.length; ++i) {
            if (entries[i].id === "delormous.volumio")
                return String(entries[i].address || "http://volumio.local");
        }
    }
    return "http://volumio.local";
}

function iconModeFromBar(config) {
    var layout = config && config.layout ? config.layout : {};
    var sections = ["left", "centerBegin", "center", "centerEnd", "tray", "right"];
    for (var s = 0; s < sections.length; ++s) {
        var entries = layout[sections[s]] || [];
        for (var i = 0; i < entries.length; ++i) {
            if (entries[i].id === "delormous.volumio")
                return entries[i].barIcon === "scope" ? "scope" : "cover";
        }
    }
    return "cover";
}

function statusLabel(online, connecting, state) {
    if (!online) return connecting ? "Connecting…" : "Volumio unreachable";
    return state.status === "play" ? "Playing" : state.status === "pause" ? "Paused" : "Stopped";
}

function validTime(value) {
    return typeof value === "number" && isFinite(value) && value >= 0;
}

function formatTime(seconds) {
    if (!validTime(seconds)) return "--:--";
    var total = Math.floor(seconds);
    var minutes = Math.floor(total / 60);
    var rest = String(total % 60).padStart(2, "0");
    return minutes >= 60 ? Math.floor(minutes / 60) + ":" + String(minutes % 60).padStart(2, "0") + ":" + rest
        : minutes + ":" + rest;
}

// Waveforms used by the bar oscilloscope. Phase is in radians, so shapes with
// the same period can be blended sample by sample for the morph.
function waveValue(shape, phase) {
    if (shape === "saw") {
        var cycles = phase / (2 * Math.PI);
        return 2 * (cycles - Math.floor(cycles)) - 1;
    }
    if (shape === "square") return Math.sin(phase) >= 0 ? 1 : -1;
    if (shape === "triangle") return (2 / Math.PI) * Math.asin(Math.sin(phase));
    return Math.sin(phase);
}

function smoothstep(t) {
    t = Math.max(0, Math.min(1, t));
    return t * t * (3 - 2 * t);
}

function blendWave(fromShape, toShape, phase, mix) {
    mix = Math.max(0, Math.min(1, mix));
    var from = waveValue(fromShape, phase);
    var to = waveValue(toShape, phase);
    return from + (to - from) * mix;
}

function safeTooltip(state) {
    return [state.title, state.artist, state.album].filter(function(s) { return !!s; })
        .join(" — ").replace(/[<>]/g, "").replace(/\s+/g, " ").substring(0, 300);
}
