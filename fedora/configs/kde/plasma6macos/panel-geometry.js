// panel-geometry.js — Plasma 6 Desktop Scripting API
// Re-shapes the two pack panels the way the static appletsrc can't set reliably
// across Plasma versions:
//   • bottom dock  → floating, centered, content-sized, bigger icons
//   • top menu bar → thinner (smaller tray / "tweak" icons)
//
// floating/alignment/lengthMode landed in the Plasma 6.6 scripting API; wrap the
// optional ones in try/catch so older Plasma still applies the heights.
var allPanels = panels();
for (var i = 0; i < allPanels.length; i++) {
    var p = allPanels[i];
    if (p.location == "bottom") {
        p.height = 60;                            // thicker dock → bigger icons
        try { p.floating = true; } catch (e) {}    // detached from the edge
        try { p.alignment = "center"; } catch (e) {}  // centered horizontally
        try { p.lengthMode = "fit"; } catch (e) {}    // width hugs the icons
    } else if (p.location == "top") {
        p.height = 28;                            // thinner bar → smaller icons
    }
}
