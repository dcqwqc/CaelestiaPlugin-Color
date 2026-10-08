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
import dcqwqc.color

ColumnLayout {
    id: root

    property var settings: null
    property var overrides: ({})
    property string pickerTarget: ""
    property var profileState: ({ profiles: {}, bindings: {}, activeProfileId: null })
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

    SectionHeader { text: qsTr("Wallpaper color profiles") }

    StyledRect {
        Layout.fillWidth: true
        implicitHeight: wallpaperDetails.implicitHeight + Tokens.padding.medium * 2
        color: Colours.tPalette.m3surfaceContainer
        radius: Tokens.rounding.large

        RowLayout {
            id: wallpaperDetails
            anchors.fill: parent
            anchors.margins: Tokens.padding.medium
            spacing: Tokens.spacing.medium

            StyledRect {
                implicitWidth: 82
                implicitHeight: 55
                radius: Tokens.rounding.medium
                color: Colours.tPalette.m3surfaceContainerHigh
                clip: true
                Image {
                    anchors.fill: parent
                    asynchronous: true
                    cache: false
                    source: Wallpapers.current
                    fillMode: Image.PreserveAspectCrop
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.extraSmall
                StyledText {
                    Layout.fillWidth: true
                    text: root.profileState.activeProfileId
                        ? root.profileState.activeProfile?.name || qsTr("Unnamed profile")
                        : qsTr("Global colors")
                    color: Colours.palette.m3onSurface
                    font: Tokens.font.body.medium
                    elide: Text.ElideRight
                }
                StyledText {
                    Layout.fillWidth: true
                    text: root.profileState.activeProfileId
                        ? qsTr("Bound to current wallpaper")
                        : qsTr("No linked profile — editing global colors")
                    color: Colours.palette.m3outline
                    font: Tokens.font.label.small
                    wrapMode: Text.Wrap
                }
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.extraSmall
        IconTextButton {
            icon: "add"
            text: qsTr("New profile")
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
        IconTextButton {
            icon: "undo"
            text: qsTr("Undo")
            enabled: !!root.profileState.canUndo
            type: IconTextButton.Text
            onClicked: root.profileRun(["undo"])
        }
    }

    CollapsibleSection {
        title: qsTr("Saved profiles (%1)").arg(Object.keys(root.profileState.profiles || ({})).length)
        description: qsTr("Select a profile to link it to the current wallpaper. Profiles can be reused across wallpapers.")
        expanded: false
        showBackground: true

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
    }

    CollapsibleSection {
        visible: !!root.profileState.activeProfileId
        title: qsTr("Manage current profile")
        expanded: false

        StyledText {
            text: qsTr("Rename this profile")
            color: Colours.palette.m3outline
            font: Tokens.font.label.small
        }
        StyledRect {
            Layout.fillWidth: true
            implicitHeight: 42
            radius: Tokens.rounding.medium
            color: Colours.tPalette.m3surfaceContainerHighest
            StyledTextField {
                id: profileNameField
                anchors.fill: parent
                anchors.leftMargin: Tokens.padding.medium
                anchors.rightMargin: Tokens.padding.medium
                text: root.profileState.activeProfile?.name || ""
                onEditingFinished: {
                    if (root.profileState.activeProfileId && text.trim())
                        root.profileRun(["edit", "--id", root.profileState.activeProfileId,
                                         "--name", text.trim()]);
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.extraSmall
            IconTextButton {
                icon: "content_copy"
                text: qsTr("Duplicate")
                type: IconTextButton.Tonal
                onClicked: root.profileRun(["duplicate", "--id", root.profileState.activeProfileId])
            }
            IconTextButton {
                icon: "delete"
                text: root.confirmDeleteId === root.profileState.activeProfileId ? qsTr("Confirm delete") : qsTr("Delete")
                type: IconTextButton.Text
                onClicked: {
                    if (root.confirmDeleteId === root.profileState.activeProfileId) {
                        root.profileRun(["delete", "--id", root.profileState.activeProfileId]);
                        root.confirmDeleteId = "";
                    } else {
                        root.confirmDeleteId = root.profileState.activeProfileId;
                    }
                }
            }
            IconTextButton {
                visible: root.confirmDeleteId === root.profileState.activeProfileId
                icon: "close"
                text: qsTr("Cancel")
                type: IconTextButton.Text
                onClicked: root.confirmDeleteId = ""
            }
        }
    }

    // The exact same plugin-owned picker is mounted at the top of
    // Wallpaper & style → Colours. Do not maintain two separate pickers.
    QuickColors {
        Layout.fillWidth: true
    }

    CollapsibleSection {
        title: qsTr("Advanced color editing")
        description: qsTr("Edit an exact Material 3 role without losing generated tones. The standard Caelestia role editor remains available.")
        expanded: false
        showBackground: true

        ColourRow {
            keyName: "primary"
            label: qsTr("Global system primary")
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

        StyledText {
            text: root.profileState.activeProfileId
                ? qsTr("Exact color for linked profile")
                : qsTr("Create or link a profile for profile-specific role overrides")
            color: Colours.palette.m3outline
            font: Tokens.font.label.small
            wrapMode: Text.Wrap
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small
            StyledRect {
                Layout.fillWidth: true
                implicitHeight: 38
                radius: Tokens.rounding.medium
                color: Colours.tPalette.m3surfaceContainerHigh
                StyledTextField {
                    id: exactRole
                    anchors.fill: parent
                    anchors.leftMargin: Tokens.padding.small
                    anchors.rightMargin: Tokens.padding.small
                    text: root.editedRole
                    placeholderText: qsTr("Material role")
                    onEditingFinished: root.editedRole = text.trim()
                }
            }
            StyledRect {
                Layout.fillWidth: true
                implicitHeight: 38
                radius: Tokens.rounding.medium
                color: Colours.tPalette.m3surfaceContainerHigh
                StyledTextField {
                    id: exactHex
                    anchors.fill: parent
                    anchors.leftMargin: Tokens.padding.small
                    anchors.rightMargin: Tokens.padding.small
                    placeholderText: qsTr("#RRGGBB")
                }
            }
        }
        RowLayout {
            Layout.fillWidth: true
            IconTextButton {
                icon: "check"
                text: qsTr("Set exact")
                enabled: !!root.profileState.activeProfileId
                    && root.cleanHex(exactHex.text) !== ""
                type: IconTextButton.Tonal
                onClicked: root.profileRun(["set-role", "--id", root.profileState.activeProfileId,
                                            "--role", exactRole.text.trim(),
                                            "--color", exactHex.text.trim()])
            }
            IconTextButton {
                icon: "restart_alt"
                text: qsTr("Reset role")
                enabled: !!root.profileState.activeProfileId
                type: IconTextButton.Text
                onClicked: root.profileRun(["reset-role", "--id", root.profileState.activeProfileId,
                                            "--role", exactRole.text.trim()])
            }
        }
        StyledText {
            Layout.fillWidth: true
            text: qsTr("Examples: primaryContainer, secondary, tertiaryContainer, onSurface, term0. Individual roles override generated colors; resetting restores generation.")
            color: Colours.palette.m3outline
            wrapMode: Text.Wrap
            font: Tokens.font.label.small
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
