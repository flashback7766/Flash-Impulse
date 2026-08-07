pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Hyprland

/**
 * Manages a HyprlandFocusGrab that's to be shared by all windows.
 * "Persistent" is for windows that should always be included but not closed on dismiss, like bar and onscreen keyboard.
 * "Dismissable" is for stuff like sidebars
 */ 
Singleton {
    id: root

    signal dismissed()

    property list<var> persistent: []
    property list<var> dismissable: []

    function dismiss() {
        root.dismissable = [];
        root.dismissed();
    }

    Component.onCompleted: {
        console.log("[GlobalFocusGrab] Initialized");
    }

    function addPersistent(window) {
        if (root.persistent.indexOf(window) === -1) {
            root.persistent.push(window);
        }
    }

    function removePersistent(window) {
        var index = root.persistent.indexOf(window);
        if (index !== -1) {
            root.persistent.splice(index, 1);
        }
    }

    function addDismissable(window) {
        if (root.dismissable.indexOf(window) === -1) {
            root.dismissable.push(window);
        }
    }

    function removeDismissable(window) {
        var index = root.dismissable.indexOf(window);
        if (index !== -1) {
            root.dismissable.splice(index, 1);
        }
    }

    /**
     * Does this item, or anything under it, hold focus?
     *
     * Was `element?.activeFocus || Array.from(element?.children).some(...)`.
     * The optional chaining guarded the property read but not the call around
     * it: with no element, `element?.children` is undefined and Array.from
     * throws "Value is undefined and could not be converted to an object". The
     * only caller passes `w?.contentItem`, which is undefined for any
     * dismissable window that has not built its content yet — so this threw out
     * of the `windows` binding below, leaving the focus grab watching the wrong
     * set and panels not dismissing when they should.
     *
     * The explicit loop also stops allocating: the old form built a throwaway
     * array at every level of the recursion, on every re-evaluation of a
     * binding that re-runs whenever anything gains or loses focus.
     */
    function hasActive(element) {
        if (!element) return false;
        if (element.activeFocus) return true;
        const children = element.children;
        if (!children) return false;
        for (let i = 0; i < children.length; i++) {
            if (root.hasActive(children[i])) return true;
        }
        return false;
    }

    HyprlandFocusGrab {
        id: grab
        windows: root.dismissable.every(w => !w?.focusable) || root.dismissable.some(w => hasActive(w?.contentItem)) ? [...root.dismissable, ...root.persistent] : [...root.dismissable]
        active: root.dismissable.length > 0
        onCleared: () => {
            root.dismiss();
        }
    }

}
