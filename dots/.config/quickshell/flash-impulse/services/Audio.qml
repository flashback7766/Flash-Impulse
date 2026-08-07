pragma Singleton
pragma ComponentBehavior: Bound
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

/**
 * A nice wrapper for default Pipewire audio sink and source.
 */
Singleton {
    id: root

    // Misc props
    property bool ready: Pipewire.defaultAudioSink?.ready ?? false
    property PwNode sink: Pipewire.defaultAudioSink
    property PwNode source: Pipewire.defaultAudioSource
    readonly property real hardMaxValue: 2.00 // People keep joking about setting volume to 5172% so...
    property string audioTheme: Config.options.sounds.theme
    property real value: sink?.audio.volume ?? 0
    
    // Both take a node that can be null. A delegate showing a stream keeps its
    // binding alive for a moment after the stream goes away — modelData is
    // already null while the item is still on screen — so these get called with
    // nothing at all every time an app stops playing audio. That was the
    // "Cannot read property 'properties' of null" in the log.
    function friendlyDeviceName(node) {
        if (!node) return Translation.tr("Unknown");
        return (node.nickname || node.description || node.name || Translation.tr("Unknown"));
    }
    function appNodeDisplayName(node) {
        if (!node) return Translation.tr("Unknown");
        return (node.properties?.["application.name"] || node.description || node.name || Translation.tr("Unknown"));
    }

    // Lists
    function correctType(node, isSink) {
        return (node.isSink === isSink) && node.audio
    }
    function appNodes(isSink) {
        return Pipewire.nodes.values.filter((node) => { // Should be list<PwNode> but it breaks ScriptModel
            return root.correctType(node, isSink) && node.isStream
        })
    }
    function devices(isSink) {
        return Pipewire.nodes.values.filter(node => {
            return root.correctType(node, isSink) && !node.isStream
        })
    }
    readonly property list<var> outputAppNodes: root.appNodes(true)
    readonly property list<var> inputAppNodes: root.appNodes(false)
    readonly property list<var> outputDevices: root.devices(true)
    readonly property list<var> inputDevices: root.devices(false)

    // Signals
    signal sinkProtectionTriggered(string reason);

    // Controls
    // Every one of these is reachable from a global shortcut, so they fire
    // whether or not there is a device to act on — during a Pipewire restart,
    // or on a machine that genuinely has no sink, sink is null and these used
    // to throw straight out of the keybind.
    function toggleMute() {
        if (!root.sink?.audio) return;
        root.sink.audio.muted = !root.sink.audio.muted
    }

    function toggleMicMute() {
        if (!root.source?.audio) return;
        root.source.audio.muted = !root.source.audio.muted
    }

    // Finer steps below 10%, where the same absolute change is far more audible.
    function volumeStep() {
        return root.value < 0.1 ? 0.01 : 0.02;
    }

    function incrementVolume() {
        if (!root.sink?.audio) return;
        root.sink.audio.volume = Math.min(1, root.sink.audio.volume + root.volumeStep());
    }

    function decrementVolume() {
        if (!root.sink?.audio) return;
        // Clamped at 0. The increment path had its Math.min from the start but
        // this one just subtracted, so holding volume-down past silence drove
        // the volume negative — after which the same number of presses back up
        // did nothing audible, because it was climbing out of the hole first.
        root.sink.audio.volume = Math.max(0, root.sink.audio.volume - root.volumeStep());
    }

    function setDefaultSink(node) {
        Pipewire.preferredDefaultAudioSink = node;
    }

    function setDefaultSource(node) {
        Pipewire.preferredDefaultAudioSource = node;
    }

    // Internals
    PwObjectTracker {
        objects: [sink, source]
    }

    Connections { // Protection against sudden volume changes
        target: sink?.audio ?? null
        property bool lastReady: false
        property real lastVolume: 0
        function onVolumeChanged() {
            if (!Config.options.audio.protection.enable) return;
            const newVolume = sink.audio.volume;
            // when resuming from suspend, we should not write volume to avoid pipewire volume reset issues
            if (isNaN(newVolume) || newVolume === undefined || newVolume === null) {
                lastReady = false;
                lastVolume = 0;
                return;
            }
            if (!lastReady) {
                lastVolume = newVolume;
                lastReady = true;
                return;
            }
            const maxAllowedIncrease = Config.options.audio.protection.maxAllowedIncrease / 100; 
            const maxAllowed = Config.options.audio.protection.maxAllowed / 100;

            if (newVolume - lastVolume > maxAllowedIncrease) {
                sink.audio.volume = lastVolume;
                root.sinkProtectionTriggered(Translation.tr("Illegal increment"));
            } else if (newVolume > maxAllowed || newVolume > root.hardMaxValue) {
                root.sinkProtectionTriggered(Translation.tr("Exceeded max allowed"));
                sink.audio.volume = Math.min(lastVolume, maxAllowed);
            }
            lastVolume = sink.audio.volume;
        }
    }

    function playSystemSound(soundName) {
        const ogaPath = `/usr/share/sounds/${root.audioTheme}/stereo/${soundName}.oga`;
        const oggPath = `/usr/share/sounds/${root.audioTheme}/stereo/${soundName}.ogg`;

        // Try playing .oga first
        let command = [
            "ffplay",
            "-nodisp",
            "-autoexit",
            ogaPath
        ];
        Quickshell.execDetached(command);

        // Also try playing .ogg (ffplay will just fail silently if file doesn't exist)
        command = [
            "ffplay",
            "-nodisp",
            "-autoexit",
            oggPath
        ];
        Quickshell.execDetached(command);
    }
}
