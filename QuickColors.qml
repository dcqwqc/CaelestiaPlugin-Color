pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services

// Color plugin-owned quick UI, shared by Wallpaper & style → Colours and the
// plugin settings. The shell only hosts this component; all persistence,
// wallpaper bindings, and palette generation stay in the Color plugin.
ColumnLayout {
    id: root

    Layout.fillWidth: true
    spacing: Tokens.spacing.small

    property string wheelTarget: "primary"
    property real wheelHue: 0.96
    property real wheelTone: 0.58
    property real wheelSaturation: 0.74
    property bool spectrumDragging: false
    property var overrides: ({})
    property var profileState: ({ profiles: {}, bindings: {}, activeProfileId: null })
    readonly property real lightTone: Math.min(0.96, wheelTone + 0.24)
    readonly property real darkTone: Math.max(0.08, wheelTone - 0.25)
    readonly property color lightPreview: Qt.hsla(wheelHue, wheelSaturation, lightTone, 1)
    readonly property color basePreview: Qt.hsla(wheelHue, wheelSaturation, wheelTone, 1)
    readonly property color darkPreview: Qt.hsla(wheelHue, wheelSaturation, darkTone, 1)
    readonly property string saveHelper: Qt.resolvedUrl("scripts/save_colors.py").toString().replace("file://", "")
    readonly property string profileHelper: Qt.resolvedUrl("scripts/color_profiles.py").toString().replace("file://", "")
    readonly property string overridesPath: Quickshell.env("HOME") + "/.config/caelestia/color_overrides.json"
    readonly property string profilesPath: Quickshell.env("HOME") + "/.config/caelestia/wallpaper_profiles.json"
    readonly property string wallpaperPath: Quickshell.env("HOME") + "/.local/state/caelestia/wallpaper/path.txt"

    function cleanHex(value): string {
        const raw = String(value ?? "").trim().replace("#", "");
        return /^[a-fA-F0-9]{6}$/.test(raw) ? raw.toLowerCase() : "";
    }
    function run(args): void {
        Quickshell.execDetached([root.saveHelper].concat(args));
    }
    function profileRun(args): void {
        Quickshell.execDetached([root.profileHelper].concat(args));
    }
    function refreshProfiles(): void {
        if (!profileStateProc.running)
            profileStateProc.running = true;
    }

    function hueFromHex(value): real {
        const hex = root.cleanHex(value);
        if (!hex) return 0.96;
        const r = parseInt(hex.slice(0, 2), 16) / 255;
        const g = parseInt(hex.slice(2, 4), 16) / 255;
        const b = parseInt(hex.slice(4, 6), 16) / 255;
        const max = Math.max(r, g, b), min = Math.min(r, g, b), delta = max - min;
        if (delta === 0) return 0;
        let h = max === r ? (g - b) / delta : max === g ? (b - r) / delta + 2 : (r - g) / delta + 4;
        return ((h / 6) + 1) % 1;
    }

    function toneFromHex(value): real {
        const hex = root.cleanHex(value);
        if (!hex) return 0.58;
        const r = parseInt(hex.slice(0, 2), 16) / 255;
        const g = parseInt(hex.slice(2, 4), 16) / 255;
        const b = parseInt(hex.slice(4, 6), 16) / 255;
        return (Math.max(r, g, b) + Math.min(r, g, b)) / 2;
    }

    function saturationFromHex(value): real {
        const hex = root.cleanHex(value);
        if (!hex) return 0.74;
        const r = parseInt(hex.slice(0, 2), 16) / 255;
        const g = parseInt(hex.slice(2, 4), 16) / 255;
        const b = parseInt(hex.slice(4, 6), 16) / 255;
        const max = Math.max(r, g, b), min = Math.min(r, g, b);
        const d = max - min, l = (max + min) / 2;
        return d < 0.00001 ? 0 : d / (1 - Math.abs(2 * l - 1));
    }

    function loadWheel(): void {
        if (root.spectrumDragging)
            return;
        const active = root.profileState.activeProfile || ({});
        const value = active[root.wheelTarget]
            || root.overrides[root.wheelTarget]
            || (root.wheelTarget === "primary"
                ? Colours.palette.m3primary.toString() : Colours.palette.m3secondary.toString());
        root.wheelHue = root.hueFromHex(value);
        root.wheelTone = root.toneFromHex(value);
        root.wheelSaturation = root.saturationFromHex(value);
        // A neutral original still needs a chromatic plane to select from.
        if (root.wheelSaturation < 0.08)
            root.wheelSaturation = 0.74;
    }

    function updateSpectrumPosition(x: real, y: real, width: real, height: real): void {
        // Hue wraps at the top/bottom edge. Keep the circle fully inside the field.
        const xFraction = Math.max(0.04, Math.min(0.96, x / Math.max(1, width)));
        const yFraction = Math.max(0.001, Math.min(0.999, y / Math.max(1, height)));
        root.wheelTone = 1 - xFraction;
        root.wheelHue = yFraction;
    }

    function applySpectrum(): void {
        const hex = root.cleanHex(root.basePreview.toString());
        if (!hex) return;
        if (root.profileState.activeProfileId)
            root.profileRun(["edit", "--id", root.profileState.activeProfileId, "--" + root.wheelTarget, hex]);
        else
            root.run(["--" + root.wheelTarget, hex]);
    }


    FileView {
        path: root.overridesPath
        watchChanges: true
        printErrors: false
        onLoaded: {
            try { root.overrides = JSON.parse(text() || "{}"); }
            catch (e) { root.overrides = {}; }
            root.loadWheel();
        }
        onFileChanged: reload()
        onLoadFailed: root.overrides = ({})
    }

    Process {
        id: profileStateProc
        command: [root.profileHelper, "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.profileState = JSON.parse(text);
                    root.loadWheel();
                } catch (e) {
                    console.warn("Quick colors cannot load profiles", e);
                }
            }
        }
    }

    FileView {
        path: root.profilesPath
        watchChanges: true
        printErrors: false
        onLoaded: root.refreshProfiles()
        onFileChanged: reload()
        onLoadFailed: root.refreshProfiles()
    }
    FileView {
        path: root.wallpaperPath
        watchChanges: true
        printErrors: false
        onLoaded: root.refreshProfiles()
        onFileChanged: reload()
    }
    Component.onCompleted: root.refreshProfiles()

    RowLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.small

        StyledText {
            Layout.fillWidth: true
            text: root.profileState.activeProfileId
                ? qsTr("Wallpaper · %1").arg(root.profileState.activeProfile?.name || qsTr("Profile"))
                : qsTr("Global colors")
            font: Tokens.font.label.medium
            color: Colours.palette.m3onSurfaceVariant
            elide: Text.ElideRight
        }

        IconTextButton {
            icon: root.profileState.activeProfileId ? "link_off" : "add_circle"
            text: root.profileState.activeProfileId ? qsTr("Unlink") : qsTr("Save for wallpaper")
            type: IconTextButton.Text
            onClicked: root.profileState.activeProfileId
                ? root.profileRun(["unlink"])
                : root.profileRun(["create"])
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.small

        IconTextButton {
            icon: "palette"
            text: qsTr("Primary")
            type: root.wheelTarget === "primary" ? IconTextButton.Tonal : IconTextButton.Text
            onClicked: {
                root.wheelTarget = "primary";
                root.loadWheel();
            }
        }
        IconTextButton {
            icon: "colors"
            text: qsTr("Accent")
            type: root.wheelTarget === "accent" ? IconTextButton.Tonal : IconTextButton.Text
            onClicked: {
                root.wheelTarget = "accent";
                root.loadWheel();
            }
        }

        Item { Layout.fillWidth: true }

        IconTextButton {
            icon: "undo"
            text: qsTr("Undo")
            enabled: !!root.profileState.canUndo
            type: IconTextButton.Text
            onClicked: root.profileRun(["undo"])
        }
    }

    Item {
        id: spectrumField
        Layout.fillWidth: true
        implicitHeight: 232
        // Works on the global palette by default; if a wallpaper profile is
        // linked, only that profile is edited instead of changing global colors.
        // Rainbow HUE runs vertically; tonal brightness runs left (light)
        // to right (dark), so all three markers represent real field colors.
        StyledRect {
            id: spectrumSurface
            anchors.fill: parent
            radius: Tokens.rounding.large
            clip: true
            color: Colours.palette.m3surfaceContainer
            border.width: 1
            border.color: Colours.palette.m3outlineVariant

            Canvas {
                id: spectrum
                anchors.fill: parent
                renderTarget: Canvas.Image
                onPaint: {
                    const ctx = getContext("2d");
                    ctx.clearRect(0, 0, width, height);
                    const rows = Math.max(100, Math.ceil(height));
                    for (let row = 0; row < rows; ++row) {
                        const hue = row / rows;
                        const g = ctx.createLinearGradient(0, 0, width, 0);
                        // Use the same HSL coordinates as the markers. The
                        // mid-tones retain hue; white/black live at the edges.
                        for (let i = 0; i <= 20; ++i)
                            g.addColorStop(i / 20, Qt.hsla(hue, root.wheelSaturation, 1 - i / 20, 1).toString());
                        ctx.fillStyle = g;
                        ctx.fillRect(0, row * height / rows, width, height / rows + 1);
                    }
                }
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()
                Connections {
                    target: root
                    function onWheelSaturationChanged(): void { spectrum.requestPaint(); }
                }
            }

            // Three simple white rings. Only Base (large) is draggable.
            // Satellites share the Base hue and follow horizontally.
            component SpectrumRing : Rectangle {
                required property real tone
                required property real hue
                required property int diameter
                x: Math.max(2, Math.min(spectrumSurface.width - width - 2,
                    (1 - tone) * spectrumSurface.width - width / 2))
                y: Math.max(2, Math.min(spectrumSurface.height - height - 2,
                    hue * spectrumSurface.height - height / 2))
                width: diameter
                height: diameter
                radius: width / 2
                color: "transparent"
                border.width: diameter > 30 ? 3 : 2
                border.color: "#ffffff"
                Behavior on x {
                    enabled: !root.spectrumDragging
                    NumberAnimation { duration: 100; easing.type: Easing.OutCubic }
                }
                Behavior on y {
                    enabled: !root.spectrumDragging
                    NumberAnimation { duration: 100; easing.type: Easing.OutCubic }
                }
            }

            SpectrumRing { tone: root.lightTone; hue: root.wheelHue; diameter: 19; z: 2 }
            SpectrumRing { tone: root.darkTone; hue: root.wheelHue; diameter: 19; z: 2 }
            SpectrumRing { tone: root.wheelTone; hue: root.wheelHue; diameter: 34; z: 3 }

            MouseArea {
                anchors.fill: parent
                enabled: spectrumField.enabled
                z: 5
                preventStealing: true
                onPressed: event => {
                    root.spectrumDragging = true;
                    root.updateSpectrumPosition(event.x, event.y, width, height);
                }
                onPositionChanged: event => {
                    if (pressed)
                        root.updateSpectrumPosition(event.x, event.y, width, height);
                }
                onReleased: {
                    root.applySpectrum();
                    root.spectrumDragging = false;
                }
                onCanceled: {
                    root.spectrumDragging = false;
                    root.loadWheel();
                }
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.small
        Repeater {
            model: [
                { label: qsTr("Light"), tone: "light" },
                { label: qsTr("Base"), tone: "base" },
                { label: qsTr("Dark"), tone: "dark" }
            ]
            delegate: StyledRect {
                required property var modelData
                Layout.fillWidth: true
                implicitHeight: 54
                radius: Tokens.rounding.medium
                color: Colours.tPalette.m3surfaceContainer
                RowLayout {
                    anchors.fill: parent
                    anchors.margins: Tokens.padding.small
                    spacing: Tokens.spacing.extraSmall
                    Rectangle {
                        implicitWidth: 22
                        implicitHeight: 22
                        radius: width / 2
                        color: modelData.tone === "light" ? root.lightPreview
                            : modelData.tone === "base" ? root.basePreview : root.darkPreview
                        border.width: 1
                        border.color: Colours.palette.m3outlineVariant
                    }
                    StyledText {
                        text: modelData.label
                        font: Tokens.font.label.small
                        color: Colours.palette.m3onSurface
                    }
                }
            }
        }
    }

    StyledText {
        Layout.fillWidth: true
        text: root.profileState.activeProfileId
            ? qsTr("Linked profile · Drag to preview. Release to apply.")
            : qsTr("Drag to preview. Release to set global colors or save a wallpaper profile.")
        color: Colours.palette.m3outline
        font: Tokens.font.label.small
        wrapMode: Text.Wrap
    }


    CollapsibleSection {
        title: qsTr("Saved wallpaper profiles")
        description: qsTr("Link a saved color profile to this wallpaper, or keep the global colors.")
        expanded: false
        showBackground: false

        Repeater {
            model: Object.keys(root.profileState.profiles || ({}))
            delegate: IconTextButton {
                required property string modelData
                Layout.fillWidth: true
                text: root.profileState.profiles[modelData]?.name || qsTr("Unnamed")
                icon: modelData === root.profileState.activeProfileId
                    ? "radio_button_checked" : "radio_button_unchecked"
                type: modelData === root.profileState.activeProfileId ? IconTextButton.Tonal : IconTextButton.Text
                onClicked: root.profileRun(["link", "--id", modelData])
            }
        }
    }
}
