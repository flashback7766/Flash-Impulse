import QtQuick

/**
 * A Loader that builds its content the first time it's wanted, and drops it
 * again once it has been unwanted for a while.
 *
 * The two sidebars are the most expensive things this shell builds — well over
 * a hundred megabytes of items each, once they've actually been on screen.
 * Keeping them around makes reopening instant, which is worth paying for while
 * you're going back and forth with them and worth nothing at all once you've
 * moved on to something else. So: keep them, then let them go.
 *
 * `holdOff` is how the content says "not right now". A half-typed message, an
 * answer still streaming in, a command waiting for approval — all of that lives
 * in the very tree this would destroy.
 */
Loader {
    id: root

    property bool wanted: false
    property bool holdOff: false
    // Zero keeps the content loaded once built, which is the old behaviour.
    property int unloadDelay: 300000

    active: false

    onWantedChanged: {
        if (root.wanted) {
            unloadTimer.stop();
            root.active = true;
        } else if (root.active && root.unloadDelay > 0) {
            unloadTimer.restart();
        }
    }

    Timer {
        id: unloadTimer
        interval: root.unloadDelay
        onTriggered: {
            // Re-checked here rather than folded into a binding: content that
            // happens to be busy when the timer fires should get the full delay
            // over again, not be dropped the moment it goes quiet.
            if (root.wanted || root.holdOff) {
                unloadTimer.restart();
                return;
            }
            root.active = false;
        }
    }
}
