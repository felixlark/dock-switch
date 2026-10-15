const test = require("node:test");
const assert = require("node:assert/strict");

const {
    moveMouseToApplicationWindowCenter,
    moveMouseToBoundsCenter,
    moveApplicationWindowWithFeedback,
    moveMouseToDisplayTargetWithFeedback,
    movePidWindowWithFeedback,
    placeFocusedWindowByPlacementWithFeedback,
    placeFocusedWindowByAction,
    placeProcessWindowByPlacementWithFeedback,
    placeProcessWindowByPlacement,
    placePidWindowByPlacementWithFeedback,
    resolveBoundsForAction,
    resolveBoundsForPlacement
} = require("../src/window-control");

test("Feishu placement and mouse centering resolve localized runtime names", () => {
    for (const requested of ["Feishu", "飞书", "Lark"]) {
        for (const runtime of ["Feishu", "飞书", "Lark"]) {
            const moves = [];
            const dockQuery = {
                getApplicationWindowBounds: ({ name }) => name === runtime ? { x: 0, y: 0, w: 800, h: 600 } : null,
                moveApplicationWindow: payload => {
                    moves.push(payload);
                    return payload.name === runtime;
                },
                moveMouse: () => true
            };
            const display = makeDisplay({ id: 1, internal: true, x: 0, y: 0, width: 1512, height: 982 });
            const screen = { getAllDisplays: () => [display], getPrimaryDisplay: () => display };
            assert.equal(placeProcessWindowByPlacement(requested, dockQuery, screen, "internal_fill"), true);
            assert.equal(moves.at(-1).name, runtime);
            assert.equal(moveMouseToApplicationWindowCenter(requested, dockQuery), true);
        }
    }
});

function makeDisplay({ id, label, internal, x, y, width, height, workArea }) {
    return {
        id,
        label,
        internal,
        bounds: { x, y, width, height },
        workArea: workArea || { x, y, width, height }
    };
}

test("resolveBoundsForPlacement rejects removed side_fill placement", () => {
    const displays = [
        makeDisplay({
            id: 1,
            label: "Internal Display",
            internal: true,
            x: 0,
            y: 0,
            width: 1512,
            height: 982,
            workArea: { x: 0, y: 33, width: 1512, height: 875 }
        }),
        makeDisplay({
            id: 4,
            label: "External Display",
            internal: false,
            x: -579,
            y: -1440,
            width: 2560,
            height: 1440,
            workArea: { x: -579, y: -1410, width: 2560, height: 1410 }
        }),
        makeDisplay({
            id: 5,
            label: "Side Monitor",
            internal: false,
            x: -2499,
            y: -1080,
            width: 1920,
            height: 1080,
            workArea: { x: -2499, y: -1050, width: 1920, height: 1050 }
        })
    ];

    assert.equal(resolveBoundsForPlacement("side_fill", displays, displays[0]), null);
});

test("resolveBoundsForPlacement uses side_left_fill and falls back to internal when side display is offline", () => {
    const displays = [
        makeDisplay({
            id: 1,
            label: "Internal Display",
            internal: true,
            x: 0,
            y: 0,
            width: 1512,
            height: 982,
            workArea: { x: 0, y: 33, width: 1512, height: 875 }
        }),
        makeDisplay({
            id: 4,
            label: "External Display",
            internal: false,
            x: -579,
            y: -1440,
            width: 2560,
            height: 1440,
            workArea: { x: -579, y: -1410, width: 2560, height: 1410 }
        })
    ];

    assert.deepEqual(
        resolveBoundsForPlacement("side_left_fill", displays, displays[0]),
        { x: 0, y: 33, w: 1512, h: 875 }
    );
});

test("resolveBoundsForPlacement uses the external display work area for external_fill", () => {
    const displays = [
        makeDisplay({
            id: 1,
            label: "Internal Display",
            internal: true,
            x: 0,
            y: 0,
            width: 1512,
            height: 982,
            workArea: { x: 0, y: 33, width: 1512, height: 875 }
        }),
        makeDisplay({
            id: 5,
            label: "Side Monitor",
            internal: false,
            x: -2499,
            y: -1080,
            width: 1920,
            height: 1080,
            workArea: { x: -2499, y: -1050, width: 1920, height: 1050 }
        }),
        makeDisplay({
            id: 4,
            label: "External Display",
            internal: false,
            x: -579,
            y: -1440,
            width: 2560,
            height: 1440,
            workArea: { x: -579, y: -1410, width: 2560, height: 1410 }
        })
    ];

    assert.deepEqual(
        resolveBoundsForPlacement("external_fill", displays, displays[0]),
        { x: -579, y: -1410, w: 2560, h: 1410 }
    );
});

test("resolveBoundsForAction routes arrows to physical displays in the current four-display layout", () => {
    const displays = [
        makeDisplay({
            id: 1,
            label: "Internal Display",
            internal: true,
            x: 0,
            y: 0,
            width: 1512,
            height: 982,
            workArea: { x: 0, y: 33, width: 1512, height: 875 }
        }),
        makeDisplay({
            id: 2,
            label: "Left Side Display",
            internal: false,
            x: -2444,
            y: -1080,
            width: 1920,
            height: 1080,
            workArea: { x: -2444, y: -1050, width: 1920, height: 1050 }
        }),
        makeDisplay({
            id: 5,
            label: "External Display",
            internal: false,
            x: -524,
            y: -1440,
            width: 2560,
            height: 1440,
            workArea: { x: -524, y: -1410, width: 2560, height: 1410 }
        }),
        makeDisplay({
            id: 3,
            label: "Right Side Display",
            internal: false,
            x: 2036,
            y: -1080,
            width: 1920,
            height: 1080,
            workArea: { x: 2036, y: -1050, width: 1920, height: 1050 }
        }),
        makeDisplay({
            id: 5,
            label: "External Display",
            internal: false,
            x: -524,
            y: -1440,
            width: 2560,
            height: 1440,
            workArea: { x: -524, y: -1410, width: 2560, height: 1410 }
        })
    ];

    assert.deepEqual(resolveBoundsForAction("up", displays, displays[0], displays[0]), {
        x: -524,
        y: -1410,
        w: 2560,
        h: 1410
    });
    assert.deepEqual(resolveBoundsForAction("down", displays, displays[0], displays[3]), {
        x: 0,
        y: 33,
        w: 1512,
        h: 875
    });
    assert.deepEqual(resolveBoundsForAction("left", displays, displays[0], displays[0]), {
        x: -2444,
        y: -1050,
        w: 1920,
        h: 1050
    });
    assert.deepEqual(resolveBoundsForAction("right", displays, displays[0], displays[0]), {
        x: 2036,
        y: -1050,
        w: 1920,
        h: 1050
    });
});

test("resolveBoundsForAction tiles the current display with bracket actions", () => {
    const displays = [
        makeDisplay({
            id: 1,
            label: "Internal Display",
            internal: true,
            x: 0,
            y: 0,
            width: 1512,
            height: 982,
            workArea: { x: 0, y: 33, width: 1512, height: 875 }
        }),
        makeDisplay({
            id: 5,
            label: "External Display",
            internal: false,
            x: -524,
            y: -1440,
            width: 2560,
            height: 1440,
            workArea: { x: -524, y: -1410, width: 2560, height: 1410 }
        })
    ];

    assert.deepEqual(resolveBoundsForAction("current_left", displays, displays[0], displays[1]), {
        x: -524,
        y: -1410,
        w: 1280,
        h: 1410
    });
    assert.deepEqual(resolveBoundsForAction("current_right", displays, displays[0], displays[1]), {
        x: 756,
        y: -1410,
        w: 1280,
        h: 1410
    });
});

test("resolveBoundsForPlacement supports side-left compatibility and side-right fill", () => {
    const displays = [
        makeDisplay({
            id: 1,
            label: "Internal Display",
            internal: true,
            x: 0,
            y: 0,
            width: 1512,
            height: 982,
            workArea: { x: 0, y: 33, width: 1512, height: 875 }
        }),
        makeDisplay({
            id: 2,
            label: "Left Side Display",
            internal: false,
            x: -2444,
            y: -1080,
            width: 1920,
            height: 1080,
            workArea: { x: -2444, y: -1050, width: 1920, height: 1050 }
        }),
        makeDisplay({
            id: 3,
            label: "Right Side Display",
            internal: false,
            x: 2036,
            y: -1080,
            width: 1920,
            height: 1080,
            workArea: { x: 2036, y: -1050, width: 1920, height: 1050 }
        }),
        makeDisplay({
            id: 5,
            label: "External Display",
            internal: false,
            x: -524,
            y: -1440,
            width: 2560,
            height: 1440,
            workArea: { x: -524, y: -1410, width: 2560, height: 1410 }
        })
    ];

    assert.equal(resolveBoundsForPlacement("side_fill", displays, displays[0]), null);
    assert.deepEqual(resolveBoundsForPlacement("side_left_fill", displays, displays[0]), {
        x: -2444,
        y: -1050,
        w: 1920,
        h: 1050
    });
    assert.deepEqual(resolveBoundsForPlacement("side_right_fill", displays, displays[0]), {
        x: 2036,
        y: -1050,
        w: 1920,
        h: 1050
    });
});

test("resolveBoundsForPlacement supports fill and half placements on each symbolic display", () => {
    const displays = [
        makeDisplay({
            id: 1,
            label: "Internal Display",
            internal: true,
            x: 0,
            y: 0,
            width: 1512,
            height: 982,
            workArea: { x: 0, y: 33, width: 1512, height: 875 }
        }),
        makeDisplay({
            id: 2,
            label: "Left Side Display",
            internal: false,
            x: -2444,
            y: -1080,
            width: 1920,
            height: 1080,
            workArea: { x: -2444, y: -1050, width: 1920, height: 1050 }
        }),
        makeDisplay({
            id: 3,
            label: "Right Side Display",
            internal: false,
            x: 2036,
            y: -1080,
            width: 1920,
            height: 1080,
            workArea: { x: 2036, y: -1050, width: 1920, height: 1050 }
        }),
        makeDisplay({
            id: 5,
            label: "External Display",
            internal: false,
            x: -524,
            y: -1440,
            width: 2560,
            height: 1440,
            workArea: { x: -524, y: -1410, width: 2560, height: 1410 }
        })
    ];

    assert.deepEqual(resolveBoundsForPlacement("internal_left_half", displays, displays[0]), {
        x: 0,
        y: 33,
        w: 756,
        h: 875
    });
    assert.deepEqual(resolveBoundsForPlacement("side_right_right_half", displays, displays[0]), {
        x: 2996,
        y: -1050,
        w: 960,
        h: 1050
    });
    assert.deepEqual(resolveBoundsForPlacement("side_left_left_half", displays, displays[0]), {
        x: -2444,
        y: -1050,
        w: 960,
        h: 1050
    });
});

test("placeFocusedWindowByAction centers the mouse on arrow target displays", () => {
    const displays = [
        makeDisplay({
            id: 1,
            label: "Internal Display",
            internal: true,
            x: 0,
            y: 0,
            width: 1512,
            height: 982,
            workArea: { x: 0, y: 33, width: 1512, height: 875 }
        }),
        makeDisplay({
            id: 2,
            label: "Left Side Display",
            internal: false,
            x: -2444,
            y: -1080,
            width: 1920,
            height: 1080,
            workArea: { x: -2444, y: -1050, width: 1920, height: 1050 }
        }),
        makeDisplay({
            id: 3,
            label: "Right Side Display",
            internal: false,
            x: 2036,
            y: -1080,
            width: 1920,
            height: 1080,
            workArea: { x: 2036, y: -1050, width: 1920, height: 1050 }
        }),
        makeDisplay({
            id: 5,
            label: "External Display",
            internal: false,
            x: -524,
            y: -1440,
            width: 2560,
            height: 1440,
            workArea: { x: -524, y: -1410, width: 2560, height: 1410 }
        })
    ];
    const moves = [];
    const mouseMoves = [];
    const dockQuery = {
        getFocusedWindowBounds: () => ({ x: 10, y: 40, w: 500, h: 400 }),
        moveFocusedWindow: payload => {
            moves.push(payload);
            return true;
        },
        moveMouse: payload => {
            mouseMoves.push(payload);
            return true;
        }
    };
    const electronScreen = {
        getAllDisplays: () => displays,
        getPrimaryDisplay: () => displays[0]
    };

    assert.equal(placeFocusedWindowByAction(dockQuery, electronScreen, "right"), true);
    assert.deepEqual(moves[0], { x: 2036, y: -1050, w: 1920, h: 1050 });
    assert.deepEqual(mouseMoves[0], { x: 2996, y: -525 });
});

test("placeFocusedWindowByPlacementWithFeedback returns a consistent feedback point", () => {
    const displays = [
        makeDisplay({
            id: 1,
            label: "Internal Display",
            internal: true,
            x: 0,
            y: 0,
            width: 1512,
            height: 982,
            workArea: { x: 0, y: 33, width: 1512, height: 875 }
        })
    ];
    const mouseMoves = [];
    const dockQuery = {
        moveFocusedWindow: () => true,
        moveMouse: payload => {
            mouseMoves.push(payload);
            return true;
        }
    };
    const electronScreen = {
        getAllDisplays: () => displays,
        getPrimaryDisplay: () => displays[0]
    };

    const result = placeFocusedWindowByPlacementWithFeedback(dockQuery, electronScreen, "internal_fill");

    assert.equal(result.ok, true);
    assert.deepEqual(result.feedbackPoint, { x: 756, y: 471 });
    assert.deepEqual(mouseMoves, [{ x: 756, y: 471 }]);
});

test("placeProcessWindowByPlacementWithFeedback returns a consistent feedback point", () => {
    const displays = [
        makeDisplay({
            id: 1,
            label: "Internal Display",
            internal: true,
            x: 0,
            y: 0,
            width: 1512,
            height: 982,
            workArea: { x: 0, y: 33, width: 1512, height: 875 }
        })
    ];
    const moveRequests = [];
    const mouseMoves = [];
    const dockQuery = {
        moveApplicationWindow: payload => {
            moveRequests.push(payload);
            return true;
        },
        moveMouse: payload => {
            mouseMoves.push(payload);
            return true;
        }
    };
    const electronScreen = {
        getAllDisplays: () => displays,
        getPrimaryDisplay: () => displays[0]
    };

    const result = placeProcessWindowByPlacementWithFeedback("Terminal", dockQuery, electronScreen, "internal_fill");

    assert.equal(result.ok, true);
    assert.deepEqual(result.feedbackPoint, { x: 756, y: 471 });
    assert.deepEqual(moveRequests[0], { name: "Terminal", x: 0, y: 33, w: 1512, h: 875 });
    assert.deepEqual(mouseMoves, [{ x: 756, y: 471 }]);
});

test("placePidWindowByPlacementWithFeedback returns a consistent feedback point", () => {
    const displays = [
        makeDisplay({
            id: 1,
            label: "Internal Display",
            internal: true,
            x: 0,
            y: 0,
            width: 1512,
            height: 982,
            workArea: { x: 0, y: 33, width: 1512, height: 875 }
        })
    ];
    const mouseMoves = [];
    const dockQuery = {
        moveApplicationWindowByPid: () => true,
        moveMouse: payload => {
            mouseMoves.push(payload);
            return true;
        }
    };
    const electronScreen = {
        getAllDisplays: () => displays,
        getPrimaryDisplay: () => displays[0]
    };

    const result = placePidWindowByPlacementWithFeedback(123, dockQuery, electronScreen, "internal_fill");

    assert.equal(result.ok, true);
    assert.deepEqual(result.feedbackPoint, { x: 756, y: 471 });
    assert.deepEqual(mouseMoves, [{ x: 756, y: 471 }]);
});

test("explicit app and pid moves follow the moved bounds and return feedback points", () => {
    const mouseMoves = [];
    const dockQuery = {
        moveApplicationWindow: () => true,
        moveApplicationWindowByPid: () => true,
        moveMouse: payload => {
            mouseMoves.push(payload);
            return true;
        }
    };

    const appResult = moveApplicationWindowWithFeedback("Preview", dockQuery, {
        x: 10,
        y: 20,
        w: 300,
        h: 200
    });
    const pidResult = movePidWindowWithFeedback(321, dockQuery, {
        x: -500,
        y: -900,
        w: 1000,
        h: 800
    });

    assert.deepEqual(appResult, { ok: true, feedbackPoint: { x: 160, y: 120 } });
    assert.deepEqual(pidResult, { ok: true, feedbackPoint: { x: 0, y: -500 } });
    assert.deepEqual(mouseMoves, [{ x: 160, y: 120 }, { x: 0, y: -500 }]);
});

test("moveMouseToDisplayTargetWithFeedback moves to the target display center", () => {
    const displays = [
        makeDisplay({
            id: 1,
            label: "Internal Display",
            internal: true,
            x: 0,
            y: 0,
            width: 1512,
            height: 982,
            workArea: { x: 0, y: 33, width: 1512, height: 875 }
        }),
        makeDisplay({
            id: 2,
            label: "External Display",
            internal: false,
            x: -524,
            y: -1440,
            width: 2560,
            height: 1440,
            workArea: { x: -524, y: -1410, width: 2560, height: 1410 }
        }),
        makeDisplay({
            id: 3,
            label: "Right Side Display",
            internal: false,
            x: 2036,
            y: -1080,
            width: 1920,
            height: 1080,
            workArea: { x: 2036, y: -1050, width: 1920, height: 1050 }
        })
    ];
    const mouseMoves = [];
    const mouseClicks = [];
    const dockQuery = {
        moveMouse: payload => {
            mouseMoves.push(payload);
            return true;
        },
        clickMouse: payload => {
            mouseClicks.push(payload);
            return true;
        }
    };
    const electronScreen = {
        getAllDisplays: () => displays,
        getPrimaryDisplay: () => displays[0]
    };

    const right = moveMouseToDisplayTargetWithFeedback(dockQuery, electronScreen, "side_right");
    const external = moveMouseToDisplayTargetWithFeedback(dockQuery, electronScreen, "external");

    assert.deepEqual(right, { ok: true, feedbackPoint: { x: 2996, y: -525 } });
    assert.deepEqual(external, { ok: true, feedbackPoint: { x: 756, y: -705 } });
    assert.deepEqual(mouseMoves, [{ x: 2996, y: -525 }, { x: 756, y: -705 }]);
    assert.deepEqual(mouseClicks, [{ x: 2996, y: -525 }, { x: 756, y: -705 }]);
});

test("placeFocusedWindowByAction follows bracket tiling to the moved window center", () => {
    const displays = [
        makeDisplay({
            id: 1,
            label: "Internal Display",
            internal: true,
            x: 0,
            y: 0,
            width: 1512,
            height: 982,
            workArea: { x: 0, y: 33, width: 1512, height: 875 }
        })
    ];
    const mouseMoves = [];
    const dockQuery = {
        getFocusedWindowBounds: () => ({ x: 10, y: 40, w: 500, h: 400 }),
        moveFocusedWindow: () => true,
        moveMouse: payload => {
            mouseMoves.push(payload);
            return true;
        }
    };
    const electronScreen = {
        getAllDisplays: () => displays,
        getPrimaryDisplay: () => displays[0]
    };

    assert.equal(placeFocusedWindowByAction(dockQuery, electronScreen, "current_left"), true);
    assert.deepEqual(mouseMoves, [{ x: 378, y: 471 }]);
});

test("moveMouseToBoundsCenter centers on valid window bounds", () => {
    const mouseMoves = [];
    const dockQuery = {
        moveMouse: payload => {
            mouseMoves.push(payload);
            return true;
        }
    };

    assert.equal(moveMouseToBoundsCenter(dockQuery, { x: -401, y: -1201, w: 1201, h: 801 }), true);
    assert.deepEqual(mouseMoves[0], { x: 200, y: -800 });
});

test("moveMouseToBoundsCenter rejects invalid bounds", () => {
    const mouseMoves = [];
    const dockQuery = {
        moveMouse: payload => {
            mouseMoves.push(payload);
            return true;
        }
    };

    assert.equal(moveMouseToBoundsCenter(dockQuery, { x: 10, y: 20, w: 0, h: 50 }), false);
    assert.equal(moveMouseToBoundsCenter(dockQuery, { x: 10, y: Number.NaN, w: 50, h: 50 }), false);
    assert.deepEqual(mouseMoves, []);
});

test("moveMouseToApplicationWindowCenter centers on the app window", () => {
    const mouseMoves = [];
    const dockQuery = {
        getApplicationWindowBounds: () => ({ x: -400, y: -1200, w: 1200, h: 800 }),
        moveMouse: payload => {
            mouseMoves.push(payload);
            return true;
        }
    };
    assert.equal(moveMouseToApplicationWindowCenter("Codex", dockQuery), true);
    assert.deepEqual(mouseMoves[0], { x: 200, y: -800 });
});

test("moveMouseToApplicationWindowCenter falls back from WeChat dock label to runtime app name", () => {
    const boundsRequests = [];
    const mouseMoves = [];
    const dockQuery = {
        getApplicationWindowBounds: ({ name }) => {
            boundsRequests.push(name);
            if (name === "微信") throw new Error("Application process not found");
            if (name === "WeChat") return { x: 10, y: 30, w: 800, h: 600 };
            throw new Error(`Unexpected app ${name}`);
        },
        moveMouse: payload => {
            mouseMoves.push(payload);
            return true;
        }
    };

    assert.equal(moveMouseToApplicationWindowCenter("微信", dockQuery), true);
    assert.deepEqual(boundsRequests, ["微信", "WeChat"]);
    assert.deepEqual(mouseMoves[0], { x: 410, y: 330 });
});

test("placeProcessWindowByPlacement falls back from WeChat dock label to runtime app name", () => {
    const displays = [
        makeDisplay({
            id: 1,
            label: "Internal Display",
            internal: true,
            x: 0,
            y: 0,
            width: 1512,
            height: 982,
            workArea: { x: 0, y: 33, width: 1512, height: 875 }
        })
    ];
    const moveRequests = [];
    const dockQuery = {
        moveApplicationWindow: payload => {
            moveRequests.push(payload);
            if (payload.name === "微信") throw new Error("Application process not found");
            return payload.name === "WeChat";
        }
    };
    const electronScreen = {
        getAllDisplays: () => displays,
        getPrimaryDisplay: () => displays[0]
    };

    assert.equal(placeProcessWindowByPlacement("微信", dockQuery, electronScreen, "internal_fill"), true);
    assert.deepEqual(moveRequests.map(request => request.name), ["微信", "WeChat"]);
    assert.deepEqual(moveRequests[1], { name: "WeChat", x: 0, y: 33, w: 1512, h: 875 });
});
