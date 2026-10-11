// SPDX-FileCopyrightText: 2026 Denis Robel
// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick 2.0
import Sailfish.Silica 1.0
import "Strings.js" as Strings

// Renders one setting from `list-settings --json` with the matching control.
// Types: toggle, i32Range, select, optionalSelect, modifiableSelect,
//        multiSelect, multiSelectWithRemove, equalizer, hueColorPicker,
//        information, importString, action
Item {
    id: root

    property var session
    property var setting                     // { settingId, type, setting }
    readonly property string settingId: setting ? setting.settingId : ""
    readonly property string type: setting ? setting.type : ""
    readonly property var params: setting && setting.setting ? setting.setting : ({})
    readonly property var value: session ? session.values[settingId] : undefined
    readonly property bool pending: session ? !!session.pending[settingId] : false
    readonly property string label: Strings.name(settingId)
    property bool shown: true

    width: parent ? parent.width : Screen.width
    visible: shown
    height: shown && loader.item ? loader.item.height : 0

    // Short explanation below some settings (translated via Qt Linguist)
    function description() {
        switch (settingId) {
        case "limitHighVolume": return qsTr("Limits the level to protect your hearing.")
        case "ldac": return qsTr("LDAC can offer higher audio quality, but may increase power consumption and reduce Bluetooth connection stability. Changing modes may require reconnecting the headphones.")
        case "gamingMode": return qsTr("Lower latency for games and videos.")
        case "exportCustomEqualizerProfiles": return qsTr("Choose the profiles to export.")
        case "dualConnections": return qsTr("Connect the headphones to two devices at the same time.")
        case "dualConnectionsDevices": return qsTr("Devices known to the headphones. Long press to remove one.")
        }
        return ""
    }

    function options() { return params.options || [] }
    // Options are fixed values (translate them) except user-defined names:
    // equalizer profiles and dual-connection devices keep their names.
    readonly property bool userNamedOptions: type === "modifiableSelect"
                                             || type === "multiSelectWithRemove"
                                             || settingId === "exportCustomEqualizerProfiles"

    function localizedOption(i) {
        // OpenSCQ30 uses protocol values like "30m" and English display
        // strings like "30 minutes". Generate the localized label from
        // the stable protocol value, without changing what we send back.
        if (settingId === "autoPowerOff") {
            var minutes = /^(\d+)m$/i.exec(String(options()[i]))
            if (minutes)
                return Strings.translateText(minutes[1] + " minutes")
        }
        var lo = params.localizedOptions || []
        var text = lo[i] !== undefined && lo[i] !== "" ? lo[i] : Strings.name(options()[i])
        return userNamedOptions ? text : Strings.translateText(text)
    }
    function localizedValue(v) {
        var i = options().indexOf(v)
        return i >= 0 ? localizedOption(i) : Strings.formatValue(v)
    }

    Loader {
        id: loader
        width: parent.width
        sourceComponent: {
            switch (root.type) {
            case "toggle":           return toggleComponent
            case "i32Range":         return rangeComponent
            case "select":           return selectComponent
            case "optionalSelect":   return selectComponent
            case "modifiableSelect": return modifiableSelectComponent
            case "multiSelect":      return multiSelectComponent
            case "multiSelectWithRemove": return multiSelectWithRemoveComponent
            case "hueColorPicker":   return hueComponent
            case "equalizer":        return equalizerComponent
            case "importString":     return importComponent
            case "action":           return actionComponent
            default:                 return informationComponent
            }
        }
    }

    // ---- toggle ----------------------------------------------------------
    Component {
        id: toggleComponent
        TextSwitch {
            text: root.label
            description: root.description()
            automaticCheck: false
            checked: root.value === true
            busy: root.pending
            enabled: !root.pending
            onClicked: root.session.setValue(root.settingId, checked ? "false" : "true")
        }
    }

    // ---- i32Range --------------------------------------------------------
    Component {
        id: rangeComponent
        Column {
            width: parent.width

            // On Soundcore earbuds this level belongs to the manually
            // selected ANC mode. Show its label above the slider so the
            // relationship is clear rather than placing it below the scale.
            Label {
                visible: root.settingId === "manualNoiseCanceling"
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                text: root.settingId === "manualNoiseCanceling" ? root.label + ":" : root.label
                color: Theme.highlightColor
                font.pixelSize: Theme.fontSizeSmall
                wrapMode: Text.Wrap
            }

            Slider {
                id: slider
                width: parent.width
                label: root.settingId === "manualNoiseCanceling" ? "" : root.label
                minimumValue: root.params.start !== undefined ? root.params.start : 0
                maximumValue: root.params.end !== undefined ? root.params.end : 100
                stepSize: root.params.step || 1
                valueText: Math.round(value)
                enabled: !root.pending
                opacity: root.pending ? 0.6 : 1.0

                function sync() {
                    if (!down && typeof root.value === "number")
                        value = root.value
                }
                Component.onCompleted: sync()
                Connections { target: root.session; onValuesUpdated: slider.sync() }
                onDownChanged: {
                    if (!down && Math.round(value) !== root.value)
                        root.session.setValue(root.settingId, Math.round(value))
                }
            }
        }
    }

    // ---- select / optionalSelect -----------------------------------------
    Component {
        id: selectComponent
        ComboBox {
            id: combo
            readonly property bool optional: root.type === "optionalSelect"
            label: root.label
            enabled: !root.pending
            description: root.pending ? qsTr("Applying…") : ""
            // The backend can report the selected value as an English string.
            // Keep the displayed auto-off duration localized, even before the
            // ComboBox menu has been opened (without changing the CLI value).
            value: root.settingId === "autoPowerOff"
                   ? Strings.translateText(root.localizedValue(root.value))
                   : (currentItem ? currentItem.text : "")

            // optional selects get an extra "None" entry at index 0
            readonly property var entries: optional ? [null].concat(root.options()) : root.options()

            menu: ContextMenu {
                Repeater {
                    model: combo.entries.length
                    MenuItem {
                        readonly property var option: combo.entries[index]
                        text: option === null ? qsTr("None") : root.localizedValue(option)
                        onClicked: root.session.setValue(root.settingId, option === null ? "" : option)
                    }
                }
            }

            function sync() {
                var v = root.value
                if (optional && (v === null || v === undefined || v === ""))
                    currentIndex = 0
                else
                    currentIndex = entries.indexOf(v)
            }
            Component.onCompleted: sync()
            Connections { target: root.session; onValuesUpdated: combo.sync() }
        }
    }

    // ---- modifiableSelect (e.g. custom equalizer profiles) ----------------
    Component {
        id: modifiableSelectComponent
        Column {
            width: parent.width

            ComboBox {
                id: mcombo
                label: root.label
                enabled: !root.pending
                description: root.pending ? qsTr("Applying…") : ""
                menu: ContextMenu {
                    Repeater {
                        model: root.options().length
                        MenuItem {
                            text: root.localizedOption(index)
                            // '\' prefix: names starting with +/- are selected, not added/removed
                            onClicked: root.session.setValue(root.settingId, "\\" + root.options()[index])
                        }
                    }
                }
                function sync() { currentIndex = root.options().indexOf(root.value) }
                Component.onCompleted: sync()
                Connections { target: root.session; onValuesUpdated: mcombo.sync() }
            }

            ButtonLayout {
                width: parent.width
                Button {
                    text: qsTr("Save as…")
                    enabled: !root.pending
                    onClicked: {
                        var dialog = pageStack.push(Qt.resolvedUrl("TextInputDialog.qml"), {
                            title: qsTr("New profile"),
                            label: qsTr("Name"),
                            description: root.settingId === "customEqualizerProfile"
                                         ? qsTr("Saves the current equalizer values as a new profile.") : "",
                            text: ""
                        })
                        dialog.accepted.connect(function() {
                            if (dialog.text.trim().length > 0)
                                root.session.setValue(root.settingId, "+" + dialog.text.trim(), true)
                        })
                    }
                }
                Button {
                    text: qsTr("Delete")
                    enabled: !root.pending && typeof root.value === "string" && root.value.length > 0
                    onClicked: {
                        var name = root.value
                        Remorse.itemAction(root, qsTr("Deleting %1").arg(name), function() {
                            root.session.setValue(root.settingId, "-" + name, true)
                        })
                    }
                }
            }
            Item { width: 1; height: Theme.paddingMedium }
        }
    }

    // ---- multiSelect -----------------------------------------------------
    Component {
        id: multiSelectComponent
        Column {
            width: parent.width
            SectionHeader { text: root.label }
            Label {
                visible: text.length > 0
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                text: root.description()
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeExtraSmall
                color: Theme.secondaryHighlightColor
            }
            Repeater {
                model: root.options().length
                TextSwitch {
                    readonly property string option: root.options()[index]
                    text: root.localizedOption(index)
                    automaticCheck: false
                    enabled: !root.pending
                    checked: root.value && root.value.indexOf !== undefined && root.value.indexOf(option) >= 0
                    onClicked: {
                        var current = (root.value && root.value.length !== undefined) ? root.value : []
                        var next = []
                        for (var i = 0; i < current.length; i++)
                            if (current[i] !== option) next.push(current[i])
                        if (!checked) next.push(option)
                        // CSV, see `openscq30 device setting --help`
                        var csv = next.map(function(s) {
                            return /[",]/.test(s) ? '"' + s.replace(/"/g, '""') + '"' : s
                        }).join(",")
                        root.session.setValue(root.settingId, csv)
                    }
                }
            }
        }
    }

    // ---- multiSelectWithRemove (OpenSCQ30 2.9: dual connection devices) ---
    // options = MAC addresses, localizedOptions = device names,
    // value = MACs of the currently connected devices. The CLI can only
    // remove entries ("-MAC"), so this is a list with a remove action.
    Component {
        id: multiSelectWithRemoveComponent
        Column {
            width: parent.width

            SectionHeader { text: root.label }
            Label {
                visible: text.length > 0
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                text: root.description()
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeExtraSmall
                color: Theme.secondaryHighlightColor
                bottomPadding: Theme.paddingSmall
            }

            Repeater {
                model: root.options().length

                ListItem {
                    id: deviceItem
                    readonly property string mac: root.options()[index]
                    readonly property bool connected: root.value && root.value.indexOf !== undefined
                                                      && root.value.indexOf(mac) >= 0
                    width: parent.width
                    contentHeight: Theme.itemSizeMedium
                    enabled: !root.pending
                    menu: ContextMenu {
                        MenuItem {
                            text: qsTr("Remove")
                            onClicked: deviceItem.remorseDelete(function() {
                                root.session.setValue(root.settingId, "-" + deviceItem.mac, true)
                            })
                        }
                    }

                    Icon {
                        id: deviceIcon
                        x: Theme.horizontalPageMargin
                        anchors.verticalCenter: parent.verticalCenter
                        source: "image://theme/icon-m-device"
                        highlighted: deviceItem.highlighted || deviceItem.connected
                    }
                    Column {
                        anchors {
                            left: deviceIcon.right; leftMargin: Theme.paddingLarge
                            right: parent.right; rightMargin: Theme.horizontalPageMargin
                            verticalCenter: parent.verticalCenter
                        }
                        Label {
                            width: parent.width
                            text: root.localizedOption(index) || deviceItem.mac
                            truncationMode: TruncationMode.Fade
                            color: deviceItem.highlighted || deviceItem.connected
                                   ? Theme.highlightColor : Theme.primaryColor
                        }
                        Label {
                            width: parent.width
                            text: deviceItem.mac + (deviceItem.connected ? " · " + qsTr("connected") : "")
                            font.pixelSize: Theme.fontSizeExtraSmall
                            color: Theme.secondaryColor
                            truncationMode: TruncationMode.Fade
                        }
                    }
                }
            }

            Label {
                visible: root.options().length === 0
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                text: qsTr("No devices")
                color: Theme.secondaryColor
                bottomPadding: Theme.paddingMedium
            }
        }
    }

    // ---- hueColorPicker (OpenSCQ30 2.12: colorful lights) ----------------
    // Hue in degrees 0..360, value is sent as a number ("lightsColor=120").
    Component {
        id: hueComponent
        Column {
            id: hueColumn
            width: parent.width

            function currentHue() {
                if (typeof root.value === "number") return root.value
                if (root.setting && typeof root.setting.hue === "number") return root.setting.hue
                return 0
            }

            Item {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                height: Theme.itemSizeExtraSmall

                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.label
                    width: parent.width - swatch.width - Theme.paddingMedium
                    truncationMode: TruncationMode.Fade
                }
                Rectangle {
                    id: swatch
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    width: Theme.iconSizeMedium
                    height: width
                    radius: width / 2
                    color: Qt.hsla(hueSlider.value / 360, 1.0, 0.5, 1.0)
                    border.color: Theme.rgba(Theme.primaryColor, 0.6)
                    border.width: 2
                }
            }

            // hue strip: a vertical gradient rotated by -90° (Qt 5.6 has no horizontal gradients)
            Item {
                x: Theme.horizontalPageMargin + Theme.paddingLarge
                width: parent.width - 2 * x
                height: Theme.paddingMedium
                Rectangle {
                    anchors.centerIn: parent
                    width: parent.height
                    height: parent.width
                    rotation: -90
                    radius: width / 2
                    gradient: Gradient {
                        GradientStop { position: 0.0;   color: "#ff0000" }
                        GradientStop { position: 0.167; color: "#ffff00" }
                        GradientStop { position: 0.333; color: "#00ff00" }
                        GradientStop { position: 0.5;   color: "#00ffff" }
                        GradientStop { position: 0.667; color: "#0000ff" }
                        GradientStop { position: 0.833; color: "#ff00ff" }
                        GradientStop { position: 1.0;   color: "#ff0000" }
                    }
                }
            }

            Slider {
                id: hueSlider
                width: parent.width
                minimumValue: 0
                maximumValue: 360
                stepSize: 1
                valueText: Math.round(value) + "°"
                enabled: !root.pending
                opacity: root.pending ? 0.6 : 1.0

                function sync() {
                    if (!down)
                        value = hueColumn.currentHue()
                }
                Component.onCompleted: sync()
                Connections { target: root.session; onValuesUpdated: hueSlider.sync() }
                onDownChanged: {
                    if (!down && Math.round(value) !== Math.round(hueColumn.currentHue()))
                        root.session.setValue(root.settingId, Math.round(value))
                }
            }
        }
    }

    // ---- equalizer -------------------------------------------------------
    Component {
        id: equalizerComponent
        EqualizerEditor {
            session: root.session
            settingId: root.settingId
            params: root.params
            value: root.value
            pending: root.pending
        }
    }

    // ---- information (read only) -----------------------------------------
    Component {
        id: informationComponent
        Column {
            width: parent.width

            readonly property string text: {
                var v = root.value
                var yn = Strings.yesNo(v)
                if (yn === true) return qsTr("Yes")
                if (yn === false) return qsTr("No")
                if (root.options().length > 0) return root.localizedValue(v)
                return Strings.formatInformation(root.settingId, v)
            }
            // e.g. exported equalizer profiles (JSON): too long for a DetailItem
            readonly property bool isLong: text.length > 48

            DetailItem {
                visible: !parent.isLong
                label: root.label
                value: parent.text
            }

            SectionHeader {
                visible: parent.isLong
                text: root.label
            }
            Label {
                visible: parent.isLong
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                text: parent.text
                wrapMode: Text.WrapAnywhere
                maximumLineCount: 8
                elide: Text.ElideRight
                font.family: "monospace"
                font.pixelSize: Theme.fontSizeExtraSmall
                color: Theme.highlightColor
            }
            Button {
                visible: parent.isLong
                anchors.horizontalCenter: parent.horizontalCenter
                text: qsTr("Copy")
                onClicked: Clipboard.text = root.value
            }
            Item { visible: parent.isLong; width: 1; height: Theme.paddingMedium }
        }
    }

    // ---- importString ----------------------------------------------------
    Component {
        id: importComponent
        Column {
            width: parent.width
            SectionHeader { text: root.label }
            TextArea {
                id: importText
                width: parent.width
                placeholderText: qsTr("Paste text to import")
                label: root.label
            }
            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                text: qsTr("Import")
                enabled: !root.pending && importText.text.trim().length > 0
                onClicked: {
                    root.session.setValue(root.settingId, importText.text.trim(), true)
                    importText.text = ""
                }
            }
            Item { width: 1; height: Theme.paddingMedium }
        }
    }

    // ---- action ----------------------------------------------------------
    Component {
        id: actionComponent
        // Full-width row instead of a Button: Silica buttons never wrap their
        // text, so long labels ("Tasten auf Standardeinstellungen zurücksetzen")
        // would be wider than the screen.
        BackgroundItem {
            id: actionItem
            width: parent.width
            height: Math.max(Theme.itemSizeMedium, actionLabel.height + 2 * Theme.paddingMedium)
            enabled: !root.pending
            onClicked: Remorse.itemAction(actionItem, root.label, function() {
                root.session.setValue(root.settingId, "true", true)
            })

            Icon {
                id: actionIcon
                x: Theme.horizontalPageMargin
                anchors.verticalCenter: parent.verticalCenter
                source: root.settingId.toLowerCase().indexOf("reset") >= 0
                        ? "image://theme/icon-m-reset" : "image://theme/icon-m-play"
                highlighted: actionItem.highlighted
                opacity: actionItem.enabled ? 1.0 : Theme.opacityLow
            }

            Label {
                id: actionLabel
                anchors {
                    left: actionIcon.right; leftMargin: Theme.paddingLarge
                    right: busy.running ? busy.left : parent.right
                    rightMargin: Theme.horizontalPageMargin
                    verticalCenter: parent.verticalCenter
                }
                text: root.label
                wrapMode: Text.Wrap
                color: actionItem.highlighted || !actionItem.enabled ? Theme.highlightColor : Theme.primaryColor
                opacity: actionItem.enabled ? 1.0 : Theme.opacityLow
            }

            BusyIndicator {
                id: busy
                anchors {
                    right: parent.right; rightMargin: Theme.horizontalPageMargin
                    verticalCenter: parent.verticalCenter
                }
                size: BusyIndicatorSize.ExtraSmall
                running: root.pending
            }
        }
    }
}
