// panel-layout.js — Plasma 6 Desktop Scripting API
// Configures a macOS-style layout: top menu bar + bottom floating icon dock.
// Clock: 24-hour format + date display (us, altgr-intl keyboard is set by --keyboard).
//
// RE-RUN BEHAVIOR: This script clears ALL existing panels before rebuilding.
// Running it twice will NOT stack duplicate panels, but any manual panel
// customizations (added widgets, repositioned items, applet settings) will
// be lost. This is intentional: setup scripts favor determinism over
// preserving manual tweaks.
//
// TO MANUALLY RESET: Open System Settings → Workspace Behavior → Desktop →
// (right-click desktop) → Configure Desktop → Panels, and restore from there.
// Or run: qdbus6 org.kde.plasma.shell /PlasmaShell evaluateScript "$(cat panel-layout.js)"
//
// Plasma version target: 6.x (tested on Plasma 6.4 / Fedora 42)

// ── Idempotency guard: remove all existing panels ────────────────────────────
var existingPanels = panels();
for (var i = 0; i < existingPanels.length; i++) {
    existingPanels[i].remove();
}

// ── TOP panel — macOS menu bar ───────────────────────────────────────────────
// Contains: global app menu (left) + spacer + system tray + clock (right)
var topBar = new Panel;
topBar.location = "top";
topBar.height = 26;

// Global menu: app menus appear in the top bar (requires appmenu-gtk3-module
// for GTK apps; KDE/Qt apps work natively).
topBar.addWidget("org.kde.plasma.appmenu");

// Spacer pushes the tray/clock group to the right
topBar.addWidget("org.kde.plasma.panelspacer");

// System tray (notifications, network, audio, etc.)
topBar.addWidget("org.kde.plasma.systemtray");

// Digital clock — 24h format + date
var clock = topBar.addWidget("org.kde.plasma.digitalclock");
clock.currentConfigGroup = ["Appearance"];
clock.writeConfig("use24hFormat", 2);   // 0=12h, 1=locale, 2=24h
clock.writeConfig("showDate", true);

// ── BOTTOM dock — floating Icons-Only Task Manager ───────────────────────────
// Behaves as a macOS-style Dock: shows running + pinned app icons.
var dock = new Panel;
dock.location = "bottom";
dock.height = 56;

// Icons-Only Task Manager: shows running apps as icons, supports pinning
dock.addWidget("org.kde.plasma.icontasks");

// macOS-style floating, centered, content-sized dock. These Panel properties
// landed in the Plasma 6.6 scripting API; wrap them in try/catch so older Plasma
// (6.4/6.5) degrades to a full-width dock instead of aborting the rest of the
// script. On older Plasma, set Floating + Center alignment manually from the
// panel's "More Options" menu after first login.
try {
    dock.floating = true;       // detached from the screen edge (macOS look)
    dock.alignment = "center";  // centered horizontally
    dock.lengthMode = "fit";    // width hugs the icons instead of spanning full-width
} catch (e) {
    // Older Plasma scripting API — floating/alignment/lengthMode not exposed.
}
