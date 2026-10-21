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

function statusLabel(online, connecting, state) {
    if (!online) return connecting ? "Connecting…" : "Volumio unreachable";
    return state.status === "play" ? "Playing" : state.status === "pause" ? "Paused" : "Stopped";
}

function barLabel(online, state) {
    if (!online) return "Volumio · offline";
    var title = String(state.title || "Volumio").replace(/\s+/g, " ");
    return title.length > 24 ? title.substring(0, 23) + "…" : title;
}

function safeTooltip(state) {
    return [state.title, state.artist, state.album].filter(function(s) { return !!s; })
        .join(" — ").replace(/[<>]/g, "").replace(/\s+/g, " ").substring(0, 300);
}
