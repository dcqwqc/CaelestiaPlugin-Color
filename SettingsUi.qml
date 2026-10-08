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
        const color = root.cleanHex(value);
        if (!color) return 0.96;
        const r = parseInt(color.slice(0, 2), 16) / 255;
        const g = parseInt(color.slice(2, 4), 16) / 255;
        const b = parseInt(color.slice(4, 6), 16) / 255;
        const max = Math.max(r, g, b), min = Math.min(r, g, b), delta = max - min;
        if (delta === 0) return 0;
        let h = max === r ? (g - b) / delta : max === g ? (b - r) / delta + 2 : (r - g) / delta + 4;
        return ((h / 6) + 1) % 1;
    }

    function loadWheel(): void {
        const active = root.profileState.activeProfile || ({});
        root.wheelHue = root.hueFromHex(active[root.wheelTarget]);
    }

    function applyWheel(): void {
        if (!root.profileState.activeProfileId) return;
        const hex = root.cleanHex(Qt.hsla(root.wheelHue, 0.68, 0.60, 1).toString());
        if (hex)
            root.profileRun(["edit", "--id", root.profileState.activeProfileId, "--" + root.wheelTarget, hex]);
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
        onLoaded: root.ingest(text())
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

    SectionHeader { text: qsTr("Harmony wheel") }

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
        id: hueTrack
        Layout.fillWidth: true
        implicitHeight: 44
        enabled: !!root.profileState.activeProfileId
        opacity: enabled ? 1 : 0.45

        Canvas {
            id: spectrum
            anchors.fill: parent
            onPaint: {
                const ctx = getContext("2d");
                ctx.clearRect(0, 0, width, height);
                const gradient = ctx.createLinearGradient(12, 0, width - 12, 0);
                const hues = ["#f26868", "#efcc67", "#83d887", "#70cbd0", "#8598e8", "#d187db", "#f26868"];
                for (let i = 0; i < hues.length; ++i)
                    gradient.addColorStop(i / (hues.length - 1), hues[i]);
                ctx.fillStyle = gradient;
                ctx.beginPath();
                ctx.roundedRect(12, 11, width - 24, 22, 11, 11);
                ctx.fill();
            }
            onWidthChanged: requestPaint()
        }

        Rectangle {
            x: 12 + root.wheelHue * (hueTrack.width - 24) - width / 2
            anchors.verticalCenter: parent.verticalCenter
            width: 27
            height: 27
            radius: width / 2
            color: Qt.hsla(root.wheelHue, 0.68, 0.60, 1)
            border.width: 2
            border.color: Colours.palette.m3onSurface
        }

        MouseArea {
            anchors.fill: parent
            onPressed: event => root.wheelHue = Math.max(0, Math.min(1, (event.x - 12) / (hueTrack.width - 24)))
            onPositionChanged: event => {
                if (pressed) root.wheelHue = Math.max(0, Math.min(1, (event.x - 12) / (hueTrack.width - 24)));
            }
            onReleased: root.applyWheel()
        }
    }

    StyledText {
        Layout.fillWidth: true
        text: qsTr("Drag one dot. Material 3 generates tonal shades and contrasting secondary/tertiary colors. Advanced exact color settings remain below.")
        color: Colours.palette.m3outline
        font: Tokens.font.label.small
        wrapMode: Text.Wrap
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.medium
        Repeater {
            model: [Colours.palette.m3primary, Colours.palette.m3primaryContainer, Colours.palette.m3secondary, Colours.palette.m3tertiary]
            delegate: StyledRect {
                required property color modelData
                Layout.fillWidth: true
                implicitHeight: 30
                radius: Tokens.rounding.medium
                color: modelData
            }
        }
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
