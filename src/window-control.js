const {
    getDisplayArea,
    getDisplayForTarget,
    getExternalDisplay,
    getInternalDisplay,
    resolveDisplayCenterPoint
} = require("./display-targets");
const { normalizeAppName } = require("./launcher-items");

var APPLICATION_RUNTIME_NAME_ALIASES = Object.freeze({
    "微信": ["WeChat"]
});

function applicationRuntimeNameCandidates(processName) {
    var name = String(processName || "");
    if (!name) return [];
    var candidates = [name];
    var aliases = normalizeAppName(name) === "feishu"
        ? ["Feishu", "飞书", "Lark"]
        : APPLICATION_RUNTIME_NAME_ALIASES[name] || [];
    for (var i = 0; i < aliases.length; i++) {
        if (aliases[i] && !candidates.includes(aliases[i])) {
            candidates.push(aliases[i]);
        }
    }
    return candidates;
}

function getAvailableDisplays(dockQuery, electronScreen) {
    // AX window bounds align with Electron's screen coordinates on macOS.
    // Native NSScreen snapshots are useful for debugging, but not for target
    // bounds resolution because their Y origin does not match AX window bounds.
    return electronScreen.getAllDisplays();
}

function getPrimaryDisplay(dockQuery, electronScreen, displays) {
    return electronScreen.getPrimaryDisplay();
}

function getDisplayForRect(displays, rect) {
    if (!Array.isArray(displays) || displays.length === 0 || !rect) return null;
    var cx = rect.x + rect.w / 2;
    var cy = rect.y + rect.h / 2;

    for (var i = 0; i < displays.length; i++) {
        var d = displays[i];
        if (!d || !d.bounds) continue;
        var b = d.bounds;
        if (cx >= b.x && cx < b.x + b.width && cy >= b.y && cy < b.y + b.height) {
            return d;
        }
    }

    var best = null;
    var bestDist = Number.POSITIVE_INFINITY;
    for (var j = 0; j < displays.length; j++) {
        var s = displays[j];
        if (!s || !s.bounds) continue;
        var sb = s.bounds;
        var dx = 0;
        if (cx < sb.x) dx = sb.x - cx;
        else if (cx > sb.x + sb.width) dx = cx - (sb.x + sb.width);
        var dy = 0;
        if (cy < sb.y) dy = sb.y - cy;
        else if (cy > sb.y + sb.height) dy = cy - (sb.y + sb.height);
        var dist = dx * dx + dy * dy;
        if (dist < bestDist) {
            bestDist = dist;
            best = s;
        }
    }
    return best;
}

function boundsForDisplay(display) {
    var area = getDisplayArea(display);
    if (!area) return null;
    return { x: area.x, y: area.y, w: area.width, h: area.height };
}

function normalizeBounds(bounds) {
    if (!bounds || ![bounds.x, bounds.y, bounds.w, bounds.h].every(Number.isFinite) ||
        bounds.w <= 0 || bounds.h <= 0) {
        return null;
    }
    return {
        x: Math.round(bounds.x),
        y: Math.round(bounds.y),
        w: Math.round(bounds.w),
        h: Math.round(bounds.h)
    };
}

function pointForBoundsCenter(bounds) {
    var rect = normalizeBounds(bounds);
    if (!rect) return null;
    return {
        x: Math.round(rect.x + rect.w / 2),
        y: Math.round(rect.y + rect.h / 2)
    };
}

function moveMouseToPoint(dockQuery, point) {
    if (!dockQuery || typeof dockQuery.moveMouse !== "function") {
        return null;
    }
    if (!point || !Number.isFinite(point.x) || !Number.isFinite(point.y)) return null;
    try {
        var ok = !!dockQuery.moveMouse({
            x: point.x,
            y: point.y
        });
        return ok ? { x: point.x, y: point.y } : null;
    } catch (e) {
        return null;
    }
}

function actionResult(ok, feedbackPoint) {
    return {
        ok: !!ok,
        feedbackPoint: feedbackPoint || null
    };
}

function clickMouseAtPoint(dockQuery, point) {
    if (!dockQuery || typeof dockQuery.clickMouse !== "function") {
        return false;
    }
    if (!point || !Number.isFinite(point.x) || !Number.isFinite(point.y)) return false;
    try {
        return !!dockQuery.clickMouse({
            x: point.x,
            y: point.y
        });
    } catch (e) {
        return false;
    }
}

function moveMouseToDisplayCenterPoint(dockQuery, display) {
    return moveMouseToPoint(dockQuery, resolveDisplayCenterPoint(display));
}

function moveMouseToDisplayCenter(dockQuery, display) {
    return !!moveMouseToDisplayCenterPoint(dockQuery, display);
}

function moveMouseToBoundsCenterPoint(dockQuery, bounds) {
    return moveMouseToPoint(dockQuery, pointForBoundsCenter(bounds));
}

function moveMouseToBoundsCenter(dockQuery, bounds) {
    return !!moveMouseToBoundsCenterPoint(dockQuery, bounds);
}

function moveMouseToBoundsDisplayCenter(dockQuery, electronScreen, bounds) {
    if (!bounds) return false;
    var displays = getAvailableDisplays(dockQuery, electronScreen);
    if (!Array.isArray(displays) || displays.length === 0) return false;
    return moveMouseToDisplayCenter(dockQuery, getDisplayForRect(displays, bounds));
}

function moveMouseToApplicationWindowCenter(processName, dockQuery) {
    if (!processName || !dockQuery || typeof dockQuery.getApplicationWindowBounds !== "function") {
        return false;
    }
    var candidates = applicationRuntimeNameCandidates(processName);
    for (var i = 0; i < candidates.length; i++) {
        try {
            var rect = dockQuery.getApplicationWindowBounds({ name: candidates[i] });
            if (moveMouseToBoundsCenter(dockQuery, rect)) {
                return true;
            }
        } catch (e) {
            // try the next runtime name candidate
        }
    }
    return false;
}

function moveMouseToApplicationDisplay(processName, dockQuery, electronScreen) {
    if (!processName || !dockQuery || typeof dockQuery.getApplicationWindowBounds !== "function") {
        return false;
    }
    try {
        var rect = dockQuery.getApplicationWindowBounds({ name: String(processName) });
        if (!rect || ![rect.x, rect.y, rect.w, rect.h].every(Number.isFinite) || rect.w <= 0 || rect.h <= 0) {
            return false;
        }
        return moveMouseToBoundsDisplayCenter(dockQuery, electronScreen, rect);
    } catch (e) {
        return false;
    }
}

function resolveBoundsForAction(action, displays, primaryDisplay, currentDisplay) {
    var currentArea = getDisplayArea(currentDisplay);

    if (action === "current_left") {
        if (!currentArea) return null;
        var leftW = Math.floor(currentArea.width / 2);
        return { x: currentArea.x, y: currentArea.y, w: leftW, h: currentArea.height };
    }

    if (action === "current_right") {
        if (!currentArea) return null;
        var rightW = Math.floor(currentArea.width / 2);
        return {
            x: currentArea.x + rightW,
            y: currentArea.y,
            w: currentArea.width - rightW,
            h: currentArea.height
        };
    }

    if (action === "fill") {
        var b = currentDisplay && currentDisplay.bounds;
        if (b) {
            return { x: b.x, y: b.y, w: b.width, h: b.height };
        }
        if (!currentArea) return null;
        return { x: currentArea.x, y: currentArea.y, w: currentArea.width, h: currentArea.height };
    }

    var actionTargets = {
        up: "external",
        down: "internal",
        left: "side_left",
        right: "side_right"
    };
    var targetName = actionTargets[action];
    if (targetName) {
        return boundsForDisplay(getDisplayForTarget(targetName, displays, primaryDisplay));
    }

    return null;
}

function resolveBoundsForPlacement(placement, displays, primaryDisplay) {
    if (!Array.isArray(displays) || displays.length === 0) return null;

    function leftHalfBounds(display) {
        var area = getDisplayArea(display);
        if (!area) return null;
        var halfW = Math.floor(area.width / 2);
        return {
            x: area.x,
            y: area.y,
            w: halfW,
            h: area.height
        };
    }

    function rightHalfBounds(display) {
        var area = getDisplayArea(display);
        if (!area) return null;
        var halfW = Math.floor(area.width / 2);
        return {
            x: area.x + halfW,
            y: area.y,
            w: area.width - halfW,
            h: area.height
        };
    }

    function boundsForTargetPlacement(targetName, placementName) {
        var display = getDisplayForTarget(targetName, displays, primaryDisplay);
        if (!display) return null;
        if (placementName === "fill") return boundsForDisplay(display);
        if (placementName === "left_half") return leftHalfBounds(display);
        if (placementName === "right_half") return rightHalfBounds(display);
        return null;
    }

    var genericPlacement = String(placement || "").match(/^(internal|external|side_left|side_right)_(fill|left_half|right_half)$/);
    if (genericPlacement) {
        return boundsForTargetPlacement(genericPlacement[1], genericPlacement[2]);
    }

    if (placement === "external_left_half") {
        var externalLeft = getExternalDisplay(displays, primaryDisplay, null);
        if (externalLeft) {
            return leftHalfBounds(externalLeft);
        }

        var internalLeft = getInternalDisplay(displays, primaryDisplay) || primaryDisplay || displays[0];
        return leftHalfBounds(internalLeft);
    }

    if (placement === "external_right_half") {
        var external = getExternalDisplay(displays, primaryDisplay, null);
        if (external) {
            return rightHalfBounds(external);
        }

        var internal = getInternalDisplay(displays, primaryDisplay) || primaryDisplay || displays[0];
        return rightHalfBounds(internal);
    }

    if (placement === "internal_fill") {
        return boundsForDisplay(getDisplayForTarget("internal", displays, primaryDisplay));
    }

    if (placement === "external_fill") {
        return boundsForDisplay(getDisplayForTarget("external", displays, primaryDisplay));
    }

    if (placement === "side_left_fill") {
        return boundsForDisplay(getDisplayForTarget("side_left", displays, primaryDisplay));
    }

    if (placement === "side_right_fill") {
        return boundsForDisplay(getDisplayForTarget("side_right", displays, primaryDisplay));
    }

    return null;
}

function placeFocusedWindowByPlacement(dockQuery, electronScreen, placement) {
    return placeFocusedWindowByPlacementWithFeedback(dockQuery, electronScreen, placement).ok;
}

function moveMouseToDisplayTargetWithFeedback(dockQuery, electronScreen, targetName) {
    if (!dockQuery || !targetName) return actionResult(false);
    var displays = getAvailableDisplays(dockQuery, electronScreen);
    if (!Array.isArray(displays) || displays.length === 0) return actionResult(false);
    var primary = getPrimaryDisplay(dockQuery, electronScreen, displays);
    var display = getDisplayForTarget(String(targetName), displays, primary);
    if (!display) return actionResult(false);
    var point = moveMouseToDisplayCenterPoint(dockQuery, display);
    if (point) {
        clickMouseAtPoint(dockQuery, point);
    }
    return actionResult(!!point, point);
}

function moveMouseToDisplayTarget(dockQuery, electronScreen, targetName) {
    return moveMouseToDisplayTargetWithFeedback(dockQuery, electronScreen, targetName).ok;
}

function placeFocusedWindowByPlacementWithFeedback(dockQuery, electronScreen, placement) {
    if (!dockQuery || !placement) return actionResult(false);
    if (typeof dockQuery.moveFocusedWindow !== "function") {
        return actionResult(false);
    }

    var displays = getAvailableDisplays(dockQuery, electronScreen);
    if (!Array.isArray(displays) || displays.length === 0) return actionResult(false);
    var primary = getPrimaryDisplay(dockQuery, electronScreen, displays);
    var target = resolveBoundsForPlacement(placement, displays, primary);
    if (!target || target.w <= 0 || target.h <= 0) return actionResult(false);

    var payload = {
        x: Math.round(target.x),
        y: Math.round(target.y),
        w: Math.round(target.w),
        h: Math.round(target.h)
    };
    var moved = !!dockQuery.moveFocusedWindow(payload);
    return actionResult(moved, moved ? moveMouseToBoundsCenterPoint(dockQuery, target) : null);
}

function placeFocusedWindowByAction(dockQuery, electronScreen, action) {
    return placeFocusedWindowByActionWithFeedback(dockQuery, electronScreen, action).ok;
}

function placeFocusedWindowByActionWithFeedback(dockQuery, electronScreen, action) {
    if (!dockQuery) return actionResult(false);
    if (action === "fill") {
        var fullscreened = typeof dockQuery.fullscreenFocusedWindow === "function"
            ? !!dockQuery.fullscreenFocusedWindow()
            : false;
        return actionResult(fullscreened);
    }
    if (typeof dockQuery.getFocusedWindowBounds !== "function" ||
        typeof dockQuery.moveFocusedWindow !== "function") {
        return actionResult(false);
    }

    var rect = dockQuery.getFocusedWindowBounds();
    if (!rect || ![rect.x, rect.y, rect.w, rect.h].every(Number.isFinite) || rect.w <= 0 || rect.h <= 0) {
        return actionResult(false);
    }

    var displays = getAvailableDisplays(dockQuery, electronScreen);
    if (!Array.isArray(displays) || displays.length === 0) return actionResult(false);
    var primary = getPrimaryDisplay(dockQuery, electronScreen, displays);
    var current = getDisplayForRect(displays, rect);
    if (!current) return actionResult(false);

    var target = resolveBoundsForAction(action, displays, primary, current);
    if (!target || target.w <= 0 || target.h <= 0) return actionResult(false);

    var payload = {
        x: Math.round(target.x),
        y: Math.round(target.y),
        w: Math.round(target.w),
        h: Math.round(target.h)
    };
    var moved = !!dockQuery.moveFocusedWindow(payload);
    return actionResult(moved, moved ? moveMouseToBoundsCenterPoint(dockQuery, target) : null);
}

function placeProcessWindowByAction(processName, dockQuery, electronScreen, action) {
    return placeProcessWindowByActionWithFeedback(processName, dockQuery, electronScreen, action).ok;
}

function placeProcessWindowByActionWithFeedback(processName, dockQuery, electronScreen, action) {
    if (!processName || !dockQuery) return actionResult(false);
    if (action === "fill") {
        var fullscreened = typeof dockQuery.fullscreenApplicationWindow === "function"
            ? !!dockQuery.fullscreenApplicationWindow({ name: processName })
            : false;
        return actionResult(fullscreened);
    }
    if (typeof dockQuery.getApplicationWindowBounds !== "function" ||
        typeof dockQuery.moveApplicationWindow !== "function") {
        return actionResult(false);
    }

    var rect = dockQuery.getApplicationWindowBounds({ name: processName });
    if (!rect || ![rect.x, rect.y, rect.w, rect.h].every(Number.isFinite) || rect.w <= 0 || rect.h <= 0) {
        return actionResult(false);
    }

    var displays = getAvailableDisplays(dockQuery, electronScreen);
    if (!Array.isArray(displays) || displays.length === 0) return actionResult(false);
    var primary = getPrimaryDisplay(dockQuery, electronScreen, displays);
    var current = getDisplayForRect(displays, rect);
    if (!current) return actionResult(false);

    var target = resolveBoundsForAction(action, displays, primary, current);
    if (!target || target.w <= 0 || target.h <= 0) return actionResult(false);

    var payload = {
        name: processName,
        x: Math.round(target.x),
        y: Math.round(target.y),
        w: Math.round(target.w),
        h: Math.round(target.h)
    };
    var moved = !!dockQuery.moveApplicationWindow(payload);
    return actionResult(moved, moved ? moveMouseToBoundsCenterPoint(dockQuery, target) : null);
}

function placeProcessWindowByPlacement(processName, dockQuery, electronScreen, placement) {
    return placeProcessWindowByPlacementWithFeedback(processName, dockQuery, electronScreen, placement).ok;
}

function placeProcessWindowByPlacementWithFeedback(processName, dockQuery, electronScreen, placement) {
    if (!processName || !dockQuery || !placement) return actionResult(false);
    if (typeof dockQuery.moveApplicationWindow !== "function") {
        return actionResult(false);
    }

    var displays = getAvailableDisplays(dockQuery, electronScreen);
    if (!Array.isArray(displays) || displays.length === 0) return actionResult(false);
    var primary = getPrimaryDisplay(dockQuery, electronScreen, displays);
    var target = resolveBoundsForPlacement(placement, displays, primary);
    if (!target || target.w <= 0 || target.h <= 0) return actionResult(false);

    var payload = {
        x: Math.round(target.x),
        y: Math.round(target.y),
        w: Math.round(target.w),
        h: Math.round(target.h)
    };
    var candidates = applicationRuntimeNameCandidates(processName);
    for (var i = 0; i < candidates.length; i++) {
        try {
            if (dockQuery.moveApplicationWindow(Object.assign({ name: candidates[i] }, payload))) {
                return actionResult(true, moveMouseToBoundsCenterPoint(dockQuery, target));
            }
        } catch (e) {
            // try the next runtime name candidate
        }
    }
    return actionResult(false);
}

function placePidWindowByPlacement(processPid, dockQuery, electronScreen, placement) {
    return placePidWindowByPlacementWithFeedback(processPid, dockQuery, electronScreen, placement).ok;
}

function placePidWindowByPlacementWithFeedback(processPid, dockQuery, electronScreen, placement) {
    if (!Number.isFinite(processPid) || processPid <= 0 || !dockQuery || !placement) return actionResult(false);
    if (typeof dockQuery.moveApplicationWindowByPid !== "function") {
        return actionResult(false);
    }

    var displays = getAvailableDisplays(dockQuery, electronScreen);
    if (!Array.isArray(displays) || displays.length === 0) return actionResult(false);
    var primary = getPrimaryDisplay(dockQuery, electronScreen, displays);
    var target = resolveBoundsForPlacement(placement, displays, primary);
    if (!target || target.w <= 0 || target.h <= 0) return actionResult(false);

    var payload = {
        pid: Math.round(processPid),
        x: Math.round(target.x),
        y: Math.round(target.y),
        w: Math.round(target.w),
        h: Math.round(target.h)
    };
    var moved = !!dockQuery.moveApplicationWindowByPid(payload);
    return actionResult(moved, moved ? moveMouseToBoundsCenterPoint(dockQuery, target) : null);
}

function moveApplicationWindowWithFeedback(processName, dockQuery, bounds) {
    var target = normalizeBounds(bounds);
    if (!processName || !dockQuery || !target || typeof dockQuery.moveApplicationWindow !== "function") {
        return actionResult(false);
    }
    var moved = !!dockQuery.moveApplicationWindow({
        name: String(processName),
        x: target.x,
        y: target.y,
        w: target.w,
        h: target.h
    });
    return actionResult(moved, moved ? moveMouseToBoundsCenterPoint(dockQuery, target) : null);
}

function movePidWindowWithFeedback(processPid, dockQuery, bounds) {
    var target = normalizeBounds(bounds);
    if (!Number.isFinite(processPid) || processPid <= 0 || !dockQuery || !target ||
        typeof dockQuery.moveApplicationWindowByPid !== "function") {
        return actionResult(false);
    }
    var moved = !!dockQuery.moveApplicationWindowByPid({
        pid: Math.round(processPid),
        x: target.x,
        y: target.y,
        w: target.w,
        h: target.h
    });
    return actionResult(moved, moved ? moveMouseToBoundsCenterPoint(dockQuery, target) : null);
}

module.exports = {
    getDisplayForRect,
    moveApplicationWindowWithFeedback,
    moveMouseToApplicationDisplay,
    moveMouseToApplicationWindowCenter,
    moveMouseToBoundsCenter,
    moveMouseToBoundsCenterPoint,
    moveMouseToBoundsDisplayCenter,
    moveMouseToDisplayCenter,
    moveMouseToDisplayCenterPoint,
    moveMouseToDisplayTarget,
    moveMouseToDisplayTargetWithFeedback,
    movePidWindowWithFeedback,
    resolveBoundsForAction,
    resolveBoundsForPlacement,
    placeFocusedWindowByPlacement,
    placeFocusedWindowByPlacementWithFeedback,
    placeFocusedWindowByAction,
    placeFocusedWindowByActionWithFeedback,
    placeProcessWindowByAction,
    placeProcessWindowByActionWithFeedback,
    placeProcessWindowByPlacement,
    placeProcessWindowByPlacementWithFeedback,
    placePidWindowByPlacement,
    placePidWindowByPlacementWithFeedback
};
