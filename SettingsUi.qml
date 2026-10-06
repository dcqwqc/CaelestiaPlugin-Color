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
