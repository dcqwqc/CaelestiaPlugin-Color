pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.modules.nexus.common
import qs.services

ColumnLayout {
    id: root

    property var settings: null
    property var overrides: ({})
    property string pickerTarget: ""
    property var profileState: ({ profiles: {}, bindings: {}, activeProfileId: null })
    property string wheelTarget: "primary"
    property real wheelHue: 0.96
    // A two-dimensional spectrum: vertical hue, horizontal tonal brightness.
    // Base is the only draggable anchor. Light and Dark follow automatically.
    property real wheelTone: 0.58
    property real wheelSaturation: 0.74
    readonly property real lightTone: Math.min(0.96, wheelTone + 0.24)
    readonly property real darkTone: Math.max(0.08, wheelTone - 0.25)
    readonly property color basePreview: Qt.hsla(wheelHue, wheelSaturation, wheelTone, 1)
    readonly property color lightPreview: Qt.hsla(wheelHue, wheelSaturation, lightTone, 1)
    readonly property color darkPreview: Qt.hsla(wheelHue, wheelSaturation, darkTone, 1)
    property bool spectrumDragging: false
    readonly property string profileHelper: Qt.resolvedUrl("scripts/color_profiles.py").toString().replace("file://", "")
    readonly property string profilesPath: Quickshell.env("HOME") + "/.config/caelestia/wallpaper_profiles.json"
    readonly property string wallpaperPath: Quickshell.env("HOME") + "/.local/state/caelestia/wallpaper/path.txt"
    readonly property string saveHelper: Qt.resolvedUrl("scripts/save_colors.py").toString().replace("file://", "")
    readonly property string overridesPath: Quickshell.env("HOME") + "/.config/caelestia/color_overrides.json"

    Layout.fillWidth: true
    spacing: Tokens.spacing.extraSmall

    function cleanHex(value): string {
        const s = String(value ?? "").trim().replace("#", "");
        return /^[0-9a-fA-F]{6}$/.test(s) ? s.toLowerCase() : "";
    }

    function valueFor(key, fallback): string {
        const v = root.cleanHex(root.overrides[key]);
        return v ? "#" + v : fallback;
    }

    function run(args): void {
        Quickshell.execDetached([root.saveHelper].concat(args));
    }

    function setValue(key, value): void {
        const clean = root.cleanHex(value);
        if (!clean)
            return;
        if (key === "primary") root.run(["--primary", clean]);
        else if (key === "hyprland_border") root.run(["--border", clean]);
        else if (key === "folder_color") root.run(["--folder", clean]);
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

    function resetValue(key): void {
        if (key === "primary") root.run(["--reset-primary"]);
        else if (key === "hyprland_border") root.run(["--reset-border"]);
        else if (key === "folder_color") root.run(["--reset-folder"]);
    }

    function ingest(raw): void {
        try { root.overrides = JSON.parse(raw || "{}"); }
        catch (e) { root.overrides = {}; }
    }

    FileView {
        id: configView
        path: root.overridesPath
        watchChanges: true
        printErrors: false
        onLoaded: {
            root.ingest(text());
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
                    console.warn("Cannot read wallpaper color profiles:", e);
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

    Process {
        id: picker
        command: ["hyprpicker", "--format=hex", "--no-fancy", "--lowercase-hex", "--quiet"]
        stdout: StdioCollector {
            onStreamFinished: {
                const clean = root.cleanHex(text);
                if (clean && root.pickerTarget)
                    root.setValue(root.pickerTarget, clean);
            }
        }
    }

    SectionHeader {
        first: true
        text: qsTr("Color")
    }

    StyledText {
        Layout.fillWidth: true
        text: qsTr("Shell colour overrides only. OpenRGB lighting lives in the separate OpenRGB plugin.")
        color: Colours.palette.m3outline
        font: Tokens.font.body.medium
        wrapMode: Text.Wrap
    }

    ColourRow {
        keyName: "primary"
        label: qsTr("System accent")
        fallback: Colours.palette.m3primary
    }

    ColourRow {
        keyName: "hyprland_border"
        label: qsTr("Hyprland border")
        fallback: Colours.palette.m3primary
    }

    ColourRow {
        keyName: "folder_color"
        label: qsTr("Folder icons")
        fallback: Colours.palette.m3primary
    }

    SectionHeader { text: qsTr("Wallpaper-linked profiles") }

    StyledText {
        Layout.fillWidth: true
        text: root.profileState.activeProfileId
            ? qsTr("Linked: %1").arg(root.profileState.activeProfile?.name || qsTr("Unnamed"))
            : qsTr("No profile linked. Your global colors remain unchanged.")
        color: Colours.palette.m3outline
        font: Tokens.font.body.medium
        wrapMode: Text.Wrap
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.small
        IconTextButton {
            icon: "add_circle"
            text: qsTr("Save colors as profile")
            type: IconTextButton.Tonal
            onClicked: root.profileRun(["create"])
        }
        IconTextButton {
            icon: "link_off"
            text: qsTr("Unlink")
            enabled: !!root.profileState.activeProfileId
            type: IconTextButton.Text
            onClicked: root.profileRun(["unlink"])
        }
    }

    Repeater {
        model: Object.keys(root.profileState.profiles || ({}))
        delegate: IconTextButton {
            required property string modelData
            Layout.fillWidth: true
            icon: modelData === root.profileState.activeProfileId ? "radio_button_checked" : "radio_button_unchecked"
            text: root.profileState.profiles[modelData]?.name || qsTr("Untitled")
            type: modelData === root.profileState.activeProfileId ? IconTextButton.Tonal : IconTextButton.Text
            onClicked: root.profileRun(["link", "--id", modelData])
        }
    }

    SectionHeader { text: qsTr("Color spectrum") }

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

            // These two smaller markers are derived tones, not independent
            // controls. Their positions follow the primary Base marker.
            Rectangle {
                id: lightMarker
                x: Math.max(2, Math.min(spectrumSurface.width - width - 2,
                    (1 - root.lightTone) * spectrumSurface.width - width / 2))
                y: Math.max(2, Math.min(spectrumSurface.height - height - 2,
                    root.wheelHue * spectrumSurface.height - height / 2))
                width: 24
                height: 24
                radius: width / 2
                color: root.lightPreview
                border.width: 2
                border.color: "#303030"
                z: 2
                Behavior on x {
                    NumberAnimation { duration: 105; easing.type: Easing.OutCubic }
                }
                Behavior on y {
                    NumberAnimation { duration: 105; easing.type: Easing.OutCubic }
                }
                Text {
                    anchors.centerIn: parent
                    text: "L"
                    font.pixelSize: 11
                    font.weight: Font.Bold
                    color: "#171717"
                }
            }
            Rectangle {
                id: darkMarker
                x: Math.max(2, Math.min(spectrumSurface.width - width - 2,
                    (1 - root.darkTone) * spectrumSurface.width - width / 2))
                y: Math.max(2, Math.min(spectrumSurface.height - height - 2,
                    root.wheelHue * spectrumSurface.height - height / 2))
                width: 24
                height: 24
                radius: width / 2
                color: root.darkPreview
                border.width: 2
                border.color: "#f5f5f5"
                z: 2
                Behavior on x {
                    NumberAnimation { duration: 105; easing.type: Easing.OutCubic }
                }
                Behavior on y {
                    NumberAnimation { duration: 105; easing.type: Easing.OutCubic }
                }
                Text {
                    anchors.centerIn: parent
                    text: "D"
                    font.pixelSize: 11
                    font.weight: Font.Bold
                    color: "#ffffff"
                }
            }
            Rectangle {
                id: baseMarker
                x: Math.max(2, Math.min(spectrumSurface.width - width - 2,
                    (1 - root.wheelTone) * spectrumSurface.width - width / 2))
                y: Math.max(2, Math.min(spectrumSurface.height - height - 2,
                    root.wheelHue * spectrumSurface.height - height / 2))
                width: 39
                height: 39
                radius: width / 2
                color: root.basePreview
                border.width: 3
                border.color: "#ffffff"
                z: 3
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: -3
                    radius: width / 2
                    color: "transparent"
                    border.width: 1
                    border.color: "#252525"
                }
                Text {
                    anchors.centerIn: parent
                    text: "B"
                    font.pixelSize: 13
                    font.weight: Font.Bold
                    color: root.wheelTone > 0.58 ? "#171717" : "#ffffff"
                }
            }

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
            ? qsTr("Editing this wallpaper profile. Drag Base; Light and Dark follow. Release to apply.")
            : qsTr("Editing global colors. Drag Base; Light and Dark follow. Release to apply. Link a profile above for wallpaper-specific colors.")
        color: Colours.palette.m3outline
        font: Tokens.font.label.small
        wrapMode: Text.Wrap
    }

    SectionHeader { text: qsTr("Palette presets") }

    RowLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.small

        IconTextButton {
            icon: "light_mode"
            text: qsTr("Neutral light")
            type: IconTextButton.Tonal
            onClicked: root.run(["--preset", "neutral-light"])
        }
        IconTextButton {
            icon: "dark_mode"
            text: qsTr("Neutral dark")
            type: IconTextButton.Tonal
            onClicked: root.run(["--preset", "neutral-dark"])
        }
        IconTextButton {
            icon: "restart_alt"
            text: qsTr("Generated")
            type: IconTextButton.Text
            onClicked: root.run(["--preset", "clear-palette"])
        }
    }

    StyledText {
        Layout.fillWidth: true
        text: qsTr("On this Caelestia build, Wallpaper & style → Colours also exposes exact per-role Material and terminal palette editing. Those overrides are stored by this plugin in color_overrides.json.")
        color: Colours.palette.m3outline
        font: Tokens.font.label.small
        wrapMode: Text.Wrap
    }

    component ColourRow : StyledRect {
        id: row
        required property string keyName
        required property string label
        required property color fallback
        Layout.fillWidth: true
        implicitHeight: content.implicitHeight + Tokens.padding.medium * 2
        radius: Tokens.rounding.large
        color: Colours.tPalette.m3surfaceContainer

        RowLayout {
            id: content
            anchors.fill: parent
            anchors.margins: Tokens.padding.medium
            spacing: Tokens.spacing.medium

            StyledRect {
                implicitWidth: 32
                implicitHeight: 32
                radius: Tokens.rounding.medium
                color: root.valueFor(row.keyName, row.fallback)
                border.width: 1
                border.color: Colours.palette.m3outlineVariant
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                StyledText { text: row.label; font: Tokens.font.body.medium }
                StyledText {
                    text: root.valueFor(row.keyName, row.fallback).toUpperCase()
                    color: Colours.palette.m3outline
                    font: Tokens.font.label.small
                }
            }

            IconButton {
                icon: "colorize"
                type: IconButton.Tonal
                isRound: true
                onClicked: {
                    root.pickerTarget = row.keyName;
                    if (!picker.running) picker.running = true;
                }
            }
            IconButton {
                icon: "restart_alt"
                visible: root.overrides[row.keyName] !== undefined
                type: IconButton.Text
                isRound: true
                onClicked: root.resetValue(row.keyName)
            }
        }
    }
}
