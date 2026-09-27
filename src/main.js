const electron = require("electron");
const child_process = require("child_process");
const fs = require("fs");
const os = require("os");
const path = require("path");
const {
    placeFocusedWindowByPlacementWithFeedback,
    placeFocusedWindowByActionWithFeedback,
    placeProcessWindowByActionWithFeedback,
    placePidWindowByPlacementWithFeedback,
    placeProcessWindowByPlacementWithFeedback,
    moveMouseToApplicationWindowCenter,
    moveMouseToDisplayTargetWithFeedback
} = require("./window-control");
const { normalizeLauncherKey } = require("./launcher-key");
const {
    isReservedLauncherShortcut,
    resolveAppShortcut
} = require("./launcher-shortcuts");
const {
    buildLauncherItems,
    findLauncherItemForKey
} = require("./launcher-items");
const { buildReadableOverlayTarget } = require("./launcher-overlay-view");
const { setupControlServer } = require("./control-server");
const {
    createGokit5SerialListener,
    mapGokit5ButtonToInputPhrase
} = require("./gokit5-serial");
const {
    resolveOpenPath,
    findAppProcessPidByOpenPath,
    findChromeAppProcessPid
} = require("./web-app-runtime");
const {
    DEFAULT_CONFIG_PATH,
    buildSettingsRows,
    readConfig,
    saveDockItemSettings,
    writeConfig
} = require("./settings-config");
const {
    resolveDockOverlayBounds
} = require("./dock-overlay");
const {
    createDockVisibilityController
} = require("./dock-visibility");
var dock_items = [], display_items = [];
const dock_query_module_path = path.join(
    __dirname,
    "..",
    "native",
    "dock-query",
    "build",
    "Release",
    "dock_query.node"
);
var dock_query = null;
var CONFIG = readConfig();
const dock_cache_path = path.join(electron.app.getPath("userData"), "dock-items-cache.json");
const dock_poll_interval_ms = 120;
const dock_show_poll_interval_ms = 70;
const dock_show_timeout_ms = 1600;
var dock_poll_timer = null;
var last_dock_signature = "";
var dock_tracking_active = false;
var dock_query_inflight = false;
var overlay_open_t0 = 0;
var dock_open_sequence = 0;
var dock_overlay_layout = null;
var launcher_click_targets = [];
var launcher_mouse_tap_active = false;
var dock_visibility_controller = createDockVisibilityController();
const arrow_control_apply_delay_ms = 90;
const app_launch_place_retry_delay_ms = 60;
const app_launch_place_timeout_ms = 1600;
var control_server_handle = null;
var gokit5_serial_handle = null;
var settings_window = null;
var gokit5_action_inflight = Promise.resolve();
var mouse_feedback_window = null;
var mouse_feedback_hide_timer = null;
var gokit5_status = {
    enabled: false,
    status: "not_started",
    portPath: ""
};

// Keep the app out of the Dock; interaction is via tray + global shortcut.
electron.app.dock.hide();

electron.app.on("ready", () => {
    try {
        dock_query = require(dock_query_module_path);
    } catch (e) {
        electron.dialog.showErrorBox(
            "dock-query addon failed to load",
            `${e.message}\n\nExpected: ${dock_query_module_path}`
        );
        return;
    }

    // Create a transparent launcher window that covers the visible Dock.
    electron.win = new electron.BrowserWindow({
        show: false,
        frame: false,
        resizable: false,
        movable: false,
        alwaysOnTop: true,
        acceptFirstMouse: true,
        transparent: true,
        backgroundColor: "#00000000",
        hasShadow: false,
        webPreferences: {
            enableRemoteModule: true,
            nodeIntegration: true,
            contextIsolation: false
        },
    });

    electron.win.loadURL(`file://${__dirname}/index.html`);
    electron.win.setAlwaysOnTop(true, "screen-saver");
    electron.win.webContents.on("before-input-event", handle_launcher_before_input);

    electron.win.on("blur", function() {
        // Hide whenever focus is lost so the launcher behaves like a transient palette.
        hide_launcher_window();
    });

    // F20 toggles the launcher and refreshes Dock/display data each time it opens.
    electron.globalShortcut.register("F20", () => {
        if (!ensure_tcc_permissions()) {
            return;
        }
        if (electron.win.isVisible()) {
            hide_launcher_window();
        } else {
            open_launcher_with_programmatic_dock();
        }
    });

    var trayIconPath = path.join(__dirname, "icon@2x.png");
    var trayIcon = electron.nativeImage.createFromPath(trayIconPath);
    if (process.platform === "darwin" && trayIcon && !trayIcon.isEmpty()) {
        trayIcon.setTemplateImage(true);
    }
    electron.tray = new electron.Tray(trayIcon);
    const contextMenu = electron.Menu.buildFromTemplate([
        { label: "Settings...", click: open_settings_window },
        { label: "Quit", role: "quit" }
    ]);
    electron.tray.setContextMenu(contextMenu);
    electron.Menu.setApplicationMenu(electron.Menu.buildFromTemplate([
        {
            label: "dock-switch",
            submenu: [
                { label: "Settings...", accelerator: "Command+,", click: open_settings_window },
                { type: "separator" },
                { role: "services" },
                { type: "separator" },
                { role: "hide" },
                { role: "hideOthers" },
                { role: "unhide" },
                { type: "separator" },
                { role: "quit" }
            ]
        },
        { role: "editMenu" },
        { role: "viewMenu" },
        { role: "windowMenu" }
    ]));
    // Uncomment for renderer debugging.
    // electron.win.webContents.openDevTools();

    electron.ipcMain.handle('hide-window', (event, path) => {
        // Renderer uses this to close after handling a key press.
        hide_launcher_window();
        electron.app.hide();
    });

    electron.ipcMain.on("arrow-window-control", (event, action) => {
        run_arrow_window_control(action);
    });

    electron.ipcMain.on("launch-app-with-placement", (event, item) => {
        launch_app_with_placement(item);
    });

    electron.ipcMain.on("place-focused-window", (event, placement) => {
        place_focused_window(String(placement || ""));
    });

    electron.ipcMain.on("move-mouse-to-app-window-center", (event, appName) => {
        move_mouse_to_application_window_center(String(appName || ""));
    });

    electron.ipcMain.handle("settings:get-state", () => {
        return get_settings_state(true);
    });

    electron.ipcMain.handle("settings:save-config", (event, updates) => {
        return save_settings_config(updates);
    });
    fs.watchFile(DEFAULT_CONFIG_PATH, { interval: 500 }, (current, previous) => {
        if (current.mtimeMs === previous.mtimeMs) return;
        try {
            reload_config();
            send_launcher_update();
        } catch (e) {
            console.error("Failed to reload config after settings change:", e);
        }
    });

    dock_items = read_dock_cache();
    const controlDeps = {
        captureLauncher: capture_launcher_from_control,
        dockQuery: dock_query,
        electronScreen: electron.screen,
        ensurePermissions: ensure_tcc_permissions,
        getGokit5Status: get_gokit5_status,
        hideLauncher: hide_launcher_from_control,
        showMouseFeedback: show_mouse_feedback,
        showLauncher: show_launcher_from_control
    };
    control_server_handle = setupControlServer(controlDeps);
    gokit5_serial_handle = setup_gokit5_serial_listener(controlDeps);
});

electron.app.on("before-quit", () => {
    if (gokit5_serial_handle && typeof gokit5_serial_handle.stop === "function") {
        gokit5_serial_handle.stop();
        gokit5_serial_handle = null;
    }
    if (control_server_handle && typeof control_server_handle.cleanup === "function") {
        control_server_handle.cleanup();
        control_server_handle = null;
    }
    stop_launcher_mouse_tap();
    if (mouse_feedback_hide_timer) {
        clearTimeout(mouse_feedback_hide_timer);
        mouse_feedback_hide_timer = null;
    }
    if (mouse_feedback_window && !mouse_feedback_window.isDestroyed()) {
        mouse_feedback_window.close();
        mouse_feedback_window = null;
    }
    if (settings_window && !settings_window.isDestroyed()) {
        settings_window.close();
        settings_window = null;
    }
    fs.unwatchFile(DEFAULT_CONFIG_PATH);
});

function mouse_feedback_html() {
    return `<!doctype html>
<html>
<head>
<meta charset="utf-8">
<style>
html, body {
    width: 100%;
    height: 100%;
    margin: 0;
    overflow: hidden;
    background: transparent;
}
#ring {
    position: absolute;
    left: 50%;
    top: 50%;
    width: 54px;
    height: 54px;
    margin-left: -27px;
    margin-top: -27px;
    border-radius: 50%;
    background:
        radial-gradient(circle, transparent 58%, rgba(10, 132, 255, 0.88) 61%, rgba(10, 132, 255, 0.88) 66%, transparent 69%),
        radial-gradient(circle, transparent 48%, rgba(255, 255, 255, 0.42) 51%, rgba(255, 255, 255, 0.42) 56%, transparent 59%);
    filter: drop-shadow(0 0 10px rgba(255, 255, 255, 0.28));
    opacity: 0;
    transform: scale(0.72);
    will-change: opacity, transform;
}
#ring.pulse {
    animation: pulse 560ms ease-out forwards;
}
@keyframes pulse {
    0% { opacity: 0; transform: scale(0.72); }
    14% { opacity: 0.95; transform: scale(0.94); }
    46% { opacity: 0.78; transform: scale(1.22); }
    100% { opacity: 0; transform: scale(1.54); }
}
</style>
</head>
<body>
<div id="ring"></div>
<script>
const { ipcRenderer } = require("electron");
const ring = document.getElementById("ring");
ipcRenderer.on("pulse", () => {
    ring.classList.remove("pulse");
    void ring.offsetWidth;
    ring.classList.add("pulse");
});
</script>
</body>
</html>`;
}

function get_mouse_feedback_window() {
    if (mouse_feedback_window && !mouse_feedback_window.isDestroyed()) {
        return mouse_feedback_window;
    }

    mouse_feedback_window = new electron.BrowserWindow({
        show: false,
        frame: false,
        transparent: true,
        resizable: false,
        movable: false,
        focusable: false,
        skipTaskbar: true,
        alwaysOnTop: true,
        hasShadow: false,
        fullscreenable: false,
        width: 96,
        height: 96,
        webPreferences: {
            nodeIntegration: true,
            contextIsolation: false
        }
    });
    mouse_feedback_window.setIgnoreMouseEvents(true);
    mouse_feedback_window.setAlwaysOnTop(true, "screen-saver");
    mouse_feedback_window.loadURL(`data:text/html;charset=utf-8,${encodeURIComponent(mouse_feedback_html())}`);
    mouse_feedback_window.on("closed", () => {
        mouse_feedback_window = null;
    });
    return mouse_feedback_window;
}

function schedule_mouse_feedback_hide() {
    if (mouse_feedback_hide_timer) {
        clearTimeout(mouse_feedback_hide_timer);
    }
    mouse_feedback_hide_timer = setTimeout(() => {
        mouse_feedback_hide_timer = null;
        if (mouse_feedback_window && !mouse_feedback_window.isDestroyed()) {
            mouse_feedback_window.hide();
        }
    }, 380);
}

function show_mouse_feedback(point) {
    if (!point || !Number.isFinite(point.x) || !Number.isFinite(point.y)) {
        return false;
    }

    const size = 96;
    const win = get_mouse_feedback_window();
    win.setBounds({
        x: Math.round(point.x - size / 2),
        y: Math.round(point.y - size / 2),
        width: size,
        height: size
    }, false);
    win.showInactive();
    const send_pulse = () => {
        if (win && !win.isDestroyed()) {
            win.webContents.send("pulse");
            schedule_mouse_feedback_hide();
        }
    };
    if (win.webContents.isLoading()) {
        win.webContents.once("did-finish-load", send_pulse);
    } else {
        send_pulse();
    }
    return true;
}

function reload_config() {
    CONFIG = readConfig(DEFAULT_CONFIG_PATH);
    return CONFIG;
}

function send_launcher_update() {
    if (electron.win && !electron.win.isDestroyed()) {
        electron.win.webContents.send("update-ui", dock_items, CONFIG, dock_overlay_layout);
    }
}

function open_settings_window() {
    if (open_native_settings_window()) {
        return;
    }

    if (settings_window && !settings_window.isDestroyed()) {
        settings_window.show();
        settings_window.focus();
        return;
    }

    settings_window = new electron.BrowserWindow({
        width: 980,
        height: 680,
        minWidth: 840,
        minHeight: 560,
        title: "Dock Switch Settings",
        titleBarStyle: "hiddenInset",
        trafficLightPosition: { x: 20, y: 20 },
        backgroundColor: "#f5f5f7",
        vibrancy: "sidebar",
        visualEffectState: "active",
        show: false,
        webPreferences: {
            nodeIntegration: true,
            contextIsolation: false
        }
    });
    settings_window.loadURL(`file://${__dirname}/settings.html`);
    settings_window.once("ready-to-show", () => {
        if (settings_window && !settings_window.isDestroyed()) {
            settings_window.show();
        }
    });
    settings_window.on("closed", () => {
        settings_window = null;
    });
}

function native_settings_executable_path() {
    const candidates = [
        path.join(process.resourcesPath || "", "DockSwitchSettings.app", "Contents", "MacOS", "DockSwitchSettings"),
        path.join(__dirname, "..", "native", "settings-app", "build", "DockSwitchSettings.app", "Contents", "MacOS", "DockSwitchSettings")
    ];
    return candidates.find(candidate => candidate && fs.existsSync(candidate)) || "";
}

function open_native_settings_window() {
    const executablePath = native_settings_executable_path();
    if (!executablePath) return false;
    try {
        get_settings_dock_items(true);
        const child = child_process.spawn(executablePath, [
            "--config",
            DEFAULT_CONFIG_PATH,
            "--dock-cache",
            dock_cache_path
        ], {
            detached: true,
            stdio: "ignore"
        });
        child.unref();
        return true;
    } catch (e) {
        console.error("Failed to open native settings:", e);
        return false;
    }
}

function get_settings_dock_items(refreshLive) {
    if (refreshLive && dock_query) {
        try {
            dock_items = query_live_dock_items();
            if (dock_items.length > 0) {
                write_dock_cache(dock_items);
            }
        } catch (e) {
            if (!Array.isArray(dock_items) || dock_items.length === 0) {
                dock_items = read_dock_cache();
            }
        }
    }
    return Array.isArray(dock_items) ? dock_items : [];
}

function get_settings_state(refreshLive) {
    const currentDockItems = get_settings_dock_items(refreshLive);
    return {
        ok: true,
        configPath: DEFAULT_CONFIG_PATH,
        rows: buildSettingsRows(currentDockItems, CONFIG),
        reservedKeys: ["COMMAND_LEFT", "COMMAND_RIGHT"]
    };
}

function save_settings_config(updates) {
    try {
        const currentDockItems = get_settings_dock_items(true);
        const result = saveDockItemSettings(CONFIG, currentDockItems, updates);
        if (!result.ok) {
            return result;
        }
        writeConfig(result.config, DEFAULT_CONFIG_PATH);
        reload_config();
        send_launcher_update();
        return Object.assign({}, get_settings_state(false), {
            saved: true
        });
    } catch (e) {
        return {
            ok: false,
            errors: [{
                type: "write_failed",
                message: e.message || String(e)
            }]
        };
    }
}

function query_live_dock_items() {
    var items = dock_query.getDockItems();
    if (!Array.isArray(items)) return [];
    return items
        .filter(item => item && item.pos && Number.isFinite(item.pos.x) && Number.isFinite(item.pos.y))
        .sort((a, b) => a.pos.x - b.pos.x);
}

function query_dock_items_async(cb) {
    setImmediate(() => {
        try {
            cb(null, query_live_dock_items());
        } catch (e) {
            cb(e);
        }
    });
}

function write_dock_cache(items) {
    try {
        fs.writeFileSync(dock_cache_path, JSON.stringify(items), "utf8");
    } catch (e) {
        // best effort
    }
}

function read_dock_cache() {
    try {
        if (!fs.existsSync(dock_cache_path)) return [];
        var raw = fs.readFileSync(dock_cache_path, "utf8");
        var parsed = JSON.parse(raw);
        return Array.isArray(parsed) ? parsed : [];
    } catch (e) {
        return [];
    }
}

function get_visible_dock_items(items) {
    return (items || []).filter(item =>
        item &&
        item.name &&
        item.name !== "Trash" &&
        item.name !== "Downloads" &&
        item.pos &&
        Number.isFinite(item.pos.x) &&
        Number.isFinite(item.pos.y)
    );
}

function dock_signature(items) {
    return items.map(item => `${item.name}:${item.pos.x},${item.pos.y}`).join("|");
}

function open_launcher_with_programmatic_dock() {
    overlay_open_t0 = Date.now();
    stop_dock_tracking();
    const sequence = ++dock_open_sequence;
    dock_tracking_active = true;
    dock_query_inflight = false;
    display_items = electron.screen.getAllDisplays();
    electron.win.webContents.send("update-display", display_items);
    dock_visibility_controller.showDock()
        .catch(error => {
            console.error("Failed to show Dock programmatically", error && error.message ? error.message : error);
        })
        .finally(() => {
            wait_for_stable_dock_items(sequence);
        });
}

function show_launcher_from_control() {
    if (!ensure_tcc_permissions()) {
        return false;
    }
    if (electron.win && electron.win.isVisible()) {
        hide_launcher_window();
    }
    open_launcher_with_programmatic_dock();
    return true;
}

function hide_launcher_from_control() {
    hide_launcher_window();
    return true;
}

async function capture_launcher_from_control(command) {
    if (!electron.win || electron.win.isDestroyed() || !electron.win.isVisible()) {
        return { ok: false, error: "launcher is not visible" };
    }

    const rawOutputPath = String(command && command.outputPath || "").trim();
    if (!rawOutputPath) {
        return { ok: false, error: "outputPath is required" };
    }
    const outputPath = path.resolve(rawOutputPath);

    await electron.win.webContents.executeJavaScript("document.fonts && document.fonts.ready", true)
        .catch(() => {});
    const image = await electron.win.webContents.capturePage();
    fs.mkdirSync(path.dirname(outputPath), { recursive: true });
    fs.writeFileSync(outputPath, image.toPNG());
    const size = image.getSize();
    return {
        ok: true,
        path: outputPath,
        width: size.width,
        height: size.height
    };
}

function hide_launcher_window() {
    stop_launcher_mouse_tap();
    stop_dock_tracking();
    dock_visibility_controller.restoreDock();
    if (electron.win && !electron.win.isDestroyed()) {
        electron.win.hide();
    }
}

function get_item_placement(item) {
    if (!item) return "";
    if (item.placement) return String(item.placement);
    if (item.kind === "web_app") return "internal_fill";
    return "";
}

function activate_launcher_item_from_main(item) {
    if (!item || !item.name) return;
    const placement = get_item_placement(item);
    hide_launcher_window();
    electron.app.hide();
    setTimeout(() => {
        if (placement) {
            launch_app_with_placement({
                name: item.name,
                placement,
                open_path: item.open_path,
                app_url: item.app_url
            });
        } else {
            open_item_target(item);
        }
    }, 40);
}

function point_in_rect(point, rect) {
    return point &&
        rect &&
        point.x >= rect.x &&
        point.x <= rect.x + rect.width &&
        point.y >= rect.y &&
        point.y <= rect.y + rect.height;
}

function compute_launcher_click_targets() {
    if (!dock_overlay_layout || !dock_overlay_layout.windowBounds) return [];
    const visible = get_visible_dock_items(dock_items);
    const launcherItems = buildLauncherItems(visible, CONFIG.dock_items);
    return launcherItems.map((entry, index) => {
        const overlayItem = dock_overlay_layout.items.find(item =>
            item && entry.dockItem && item.name === entry.dockItem.name
        ) || dock_overlay_layout.items[index];
        const target = buildReadableOverlayTarget(entry.item, overlayItem, dock_overlay_layout, {
            reservedTop: 34
        });
        if (!target) return null;
        return {
            item: entry.item,
            rect: {
                x: dock_overlay_layout.windowBounds.x + target.targetStyle.left,
                y: dock_overlay_layout.windowBounds.y + target.targetStyle.top,
                width: target.targetStyle.width,
                height: target.targetStyle.height
            }
        };
    }).filter(Boolean);
}

function handle_launcher_mouse_down(event) {
    if (!electron.win || electron.win.isDestroyed() || !electron.win.isVisible()) return;
    const point = {
        x: Number(event && event.x),
        y: Number(event && event.y)
    };
    if (!Number.isFinite(point.x) || !Number.isFinite(point.y)) return;
    const hit = launcher_click_targets.find(target => point_in_rect(point, target.rect));
    if (!hit) return;
    activate_launcher_item_from_main(hit.item);
}

function start_launcher_mouse_tap() {
    stop_launcher_mouse_tap();
    launcher_click_targets = compute_launcher_click_targets();
    if (!dock_query || typeof dock_query.startMouseDownTap !== "function") return;
    try {
        dock_query.startMouseDownTap(handle_launcher_mouse_down);
        launcher_mouse_tap_active = true;
    } catch (e) {
        launcher_mouse_tap_active = false;
    }
}

function stop_launcher_mouse_tap() {
    launcher_click_targets = [];
    if (!launcher_mouse_tap_active) return;
    launcher_mouse_tap_active = false;
    if (dock_query && typeof dock_query.stopMouseDownTap === "function") {
        try {
            dock_query.stopMouseDownTap();
        } catch (e) {
            // best effort
        }
    }
}

function wait_for_stable_dock_items(sequence) {
    const deadline = Date.now() + dock_show_timeout_ms;
    let lastSig = "";
    let stableCount = 0;
    let lastItems = [];

    const poll = () => {
        if (sequence !== dock_open_sequence || !dock_tracking_active) {
            return;
        }

        let items = [];
        try {
            items = query_live_dock_items();
        } catch (e) {
            items = [];
        }

        const visible = get_visible_dock_items(items);
        if (visible.length > 0) {
            const sig = dock_signature(visible);
            lastItems = items;
            if (sig === lastSig) {
                stableCount += 1;
            } else {
                stableCount = 1;
                lastSig = sig;
            }

            if (stableCount >= 2) {
                show_stable_dock_overlay(items, sig);
                return;
            }
        }

        if (Date.now() >= deadline) {
            const fallbackItems = get_visible_dock_items(lastItems).length > 0 ? lastItems : dock_items;
            if (get_visible_dock_items(fallbackItems).length > 0) {
                const sig = dock_signature(get_visible_dock_items(fallbackItems));
                show_stable_dock_overlay(fallbackItems, sig);
            } else {
                schedule_next_dock_refresh();
            }
            return;
        }

        dock_poll_timer = setTimeout(poll, dock_show_poll_interval_ms);
    };

    poll();
}

function show_stable_dock_overlay(items, sig) {
    if (!dock_tracking_active) return;
    dock_items = Array.isArray(items) ? items : [];
    if (dock_items.length === 0) {
        schedule_next_dock_refresh();
        return;
    }

    write_dock_cache(dock_items);
    if (show_window()) {
        last_dock_signature = sig || dock_signature(get_visible_dock_items(dock_items));
        start_launcher_mouse_tap();
        send_launcher_update();
    }
    schedule_next_dock_refresh();
}

function start_dock_tracking() {
    stop_dock_tracking();
    dock_tracking_active = true;
    refresh_dock_overlay(true);
}

function stop_dock_tracking() {
    dock_tracking_active = false;
    dock_query_inflight = false;
    dock_open_sequence += 1;
    dock_overlay_layout = null;
    if (dock_poll_timer) {
        clearTimeout(dock_poll_timer);
        dock_poll_timer = null;
    }
}

function run_arrow_window_control(action) {
    hide_launcher_window();
    electron.app.hide();
    setTimeout(() => {
        try {
            // Arrow commands should act on the real frontmost window, even when an app
            // has multiple windows (for example profile-bound Chrome windows).
            var result = placeFocusedWindowByActionWithFeedback(dock_query, electron.screen, action);
            if (!result.ok) {
                var processName = focused_process_name();
                if (processName) {
                    result = placeProcessWindowByActionWithFeedback(processName, dock_query, electron.screen, action);
                }
            }
            if (result && result.feedbackPoint) {
                show_mouse_feedback(result.feedbackPoint);
            }
        } catch (e) {
            // Ignore windows that cannot be moved/resized.
        }
    }, arrow_control_apply_delay_ms);
}

function launch_app_with_placement(item) {
    if (!item || !item.name || !item.placement) {
        return;
    }

    open_item_target(item);
    var deadline = Date.now() + app_launch_place_timeout_ms;
    var tryPlace = () => {
        if (!dock_query) {
            return;
        }
        try {
            var directAppPid = findAppProcessPidByOpenPath(item.open_path);
            if (Number.isFinite(directAppPid) && directAppPid > 0) {
                var directPidResult = placePidWindowByPlacementWithFeedback(
                    directAppPid,
                    dock_query,
                    electron.screen,
                    String(item.placement)
                );
                if (directPidResult.ok) {
                    show_mouse_feedback(directPidResult.feedbackPoint);
                    return;
                }
            }

            var chromeAppPid = findChromeAppProcessPid(item.app_url);
            if (Number.isFinite(chromeAppPid) && chromeAppPid > 0) {
                var pidResult = placePidWindowByPlacementWithFeedback(
                    chromeAppPid,
                    dock_query,
                    electron.screen,
                    String(item.placement)
                );
                if (pidResult.ok) {
                    show_mouse_feedback(pidResult.feedbackPoint);
                    return;
                }
            }

            var result = placeProcessWindowByPlacementWithFeedback(
                String(item.name),
                dock_query,
                electron.screen,
                String(item.placement)
            );
            if (result.ok) {
                show_mouse_feedback(result.feedbackPoint);
                return;
            }
        } catch (e) {
            // retry until deadline
        }

        if (Date.now() < deadline) {
            setTimeout(tryPlace, app_launch_place_retry_delay_ms);
        }
    };

    setTimeout(tryPlace, app_launch_place_retry_delay_ms);
}

function move_mouse_to_application_window_center(appName) {
    if (!appName) {
        return;
    }
    var deadline = Date.now() + app_launch_place_timeout_ms;
    var tryMove = () => {
        try {
            if (moveMouseToApplicationWindowCenter(appName, dock_query)) {
                return;
            }
        } catch (e) {
            // retry until deadline
        }

        if (Date.now() < deadline) {
            setTimeout(tryMove, app_launch_place_retry_delay_ms);
        }
    };

    setTimeout(tryMove, app_launch_place_retry_delay_ms);
}

function place_focused_window(placement) {
    if (!placement) {
        return;
    }

    hide_launcher_window();
    electron.app.hide();
    setTimeout(() => {
        try {
            var result = placeFocusedWindowByPlacementWithFeedback(dock_query, electron.screen, placement);
            if (result && result.feedbackPoint) {
                show_mouse_feedback(result.feedbackPoint);
            }
        } catch (e) {
            // Ignore windows that cannot be moved/resized.
        }
    }, arrow_control_apply_delay_ms);
}

function setup_gokit5_serial_listener(controlDeps) {
    if (process.env.DOCK_SWITCH_GOKIT5 === "0") {
        gokit5_status = {
            enabled: false,
            status: "disabled",
            portPath: ""
        };
        return null;
    }

    gokit5_status = {
        enabled: true,
        status: "starting",
        portPath: ""
    };
    var listener = createGokit5SerialListener({
        onStatus: status => {
            gokit5_status = Object.assign({
                enabled: true,
                updatedAt: new Date().toISOString()
            }, status || {});
        },
        onAction: (action, event) => {
            if (!action) return;
            var inputPhrase = "";
            if (dock_query
                && typeof dock_query.isCommandPressed === "function"
                && dock_query.isCommandPressed()) {
                inputPhrase = mapGokit5ButtonToInputPhrase(event && event.button);
            }
            gokit5_action_inflight = gokit5_action_inflight
                .catch(() => {})
                .then(() => {
                    if (inputPhrase && typeof dock_query.insertText === "function") {
                        return {
                            ok: !!dock_query.insertText({ text: inputPhrase }),
                            phrase: inputPhrase
                        };
                    }
                    if (action.mouse_target) {
                        var result = moveMouseToDisplayTargetWithFeedback(
                            dock_query,
                            electron.screen,
                            action.mouse_target
                        );
                        if (result.feedbackPoint) {
                            show_mouse_feedback(result.feedbackPoint);
                        }
                        return result;
                    }
                    return launch_app_with_placement(action);
                })
                .catch(() => {});
        }
    });
    listener.start();
    return listener;
}

function get_gokit5_status() {
    var status = Object.assign({}, gokit5_status);
    if (gokit5_serial_handle && typeof gokit5_serial_handle.getPortPath === "function") {
        status.portPath = gokit5_serial_handle.getPortPath() || status.portPath || "";
        status.running = typeof gokit5_serial_handle.isRunning === "function"
            ? gokit5_serial_handle.isRunning()
            : true;
    } else {
        status.running = false;
    }
    return status;
}

function open_item_target(item) {
    if (!item) {
        return;
    }

    var openPath = String(item.open_path || "").trim();
    if (openPath) {
        child_process.execFile("open", [resolveOpenPath(openPath)], () => {});
        return;
    }

    child_process.execFile("open", ["-a", String(item.name)], () => {});
}

function focused_process_name() {
    try {
        if (dock_query && typeof dock_query.getFocusedApplicationName === "function") {
            var name = String(dock_query.getFocusedApplicationName() || "").trim();
            if (name && name !== "dock-switch" && name !== "Electron") {
                return name;
            }
        }
    } catch (e) {
        // ignore
    }
    return "";
}

function handle_launcher_before_input(event, input) {
    if (!electron.win || !electron.win.isVisible() || !input) {
        return;
    }
    if (input.type !== "keyDown" || input.isAutoRepeat) {
        return;
    }

    var normalizedKey = normalizeLauncherKey(input.key, input.code);
    var launcherItem = findLauncherItemForKey(get_visible_dock_items(dock_items), CONFIG.dock_items, normalizedKey);
    if (launcherItem) {
        event.preventDefault();
        activate_launcher_item_from_main(launcherItem);
        return;
    }

    var shortcutApp = resolveAppShortcut(normalizedKey);
    if (shortcutApp) {
        event.preventDefault();
        electron.win.webContents.send("activate-app-shortcut", shortcutApp);
        return;
    }

    if (isReservedLauncherShortcut(normalizedKey)) {
        event.preventDefault();
        hide_launcher_window();
        electron.app.hide();
    }
}

function refresh_dock_overlay(force_send) {
    if (!dock_tracking_active) {
        return;
    }
    if (dock_query_inflight) {
        schedule_next_dock_refresh();
        return;
    }
    dock_query_inflight = true;
    query_dock_items_async((err, items) => {
        dock_query_inflight = false;
        if (!dock_tracking_active) {
            return;
        }

        if (err) {
            schedule_next_dock_refresh();
            return;
        }

        dock_items = Array.isArray(items) ? items : [];
        if (dock_items.length === 0) {
            schedule_next_dock_refresh();
            return;
        }
        write_dock_cache(dock_items);

        var visible = get_visible_dock_items(dock_items);
        if (visible.length === 0) {
            schedule_next_dock_refresh();
            return;
        }

        var sig = dock_signature(visible);
        show_window();
        if (force_send || sig !== last_dock_signature) {
            last_dock_signature = sig;
            send_launcher_update();
        }
        schedule_next_dock_refresh();
    });
}

function schedule_next_dock_refresh() {
    if (!dock_tracking_active) return;
    if (dock_poll_timer) {
        clearTimeout(dock_poll_timer);
    }
    dock_poll_timer = setTimeout(() => {
        refresh_dock_overlay(false);
    }, dock_poll_interval_ms);
}

function ensure_tcc_permissions() {
    if (!ensure_accessibility_permission()) {
        return false;
    }
    return true;
}

function ensure_accessibility_permission() {
    if (electron.systemPreferences.isTrustedAccessibilityClient(false)) {
        return true;
    }

    // Trigger the native Accessibility prompt.
    electron.systemPreferences.isTrustedAccessibilityClient(true);
    var action = electron.dialog.showMessageBoxSync({
        type: "warning",
        buttons: ["Open Accessibility Settings", "Cancel"],
        defaultId: 0,
        cancelId: 1,
        message: "dock-switch needs Accessibility permission",
        detail: "Enable dock-switch in Privacy & Security > Accessibility, then reopen the app."
    });
    if (action === 0) {
        electron.shell.openExternal("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility");
    }
    return false;
}

function show_window() {
    var visible = get_visible_dock_items(dock_items);
    if (visible.length === 0) {
        return false;
    }
    var layout = resolveDockOverlayBounds(visible, electron.screen.getAllDisplays(), {
        edgePadding: 10,
        minSize: 80
    });
    if (!layout || !layout.windowBounds) {
        return false;
    }

    var bounds = layout.windowBounds;
    dock_overlay_layout = layout;
    electron.win.width = bounds.width;
    electron.win.height = bounds.height;
    electron.win.setBounds(bounds, false);
    electron.app.show();
    electron.win.show();
    electron.win.moveTop();
    electron.win.focus();
    return true;
}
