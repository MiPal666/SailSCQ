// SPDX-FileCopyrightText: 2026 Denis Robel
// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick 2.0
import Sailfish.Silica 1.0
import "../components"
import "../components/Strings.js" as Strings

// Shows all settings of one category with generic controls (SettingItem).
Page {
    id: page

    property var session
    property string categoryId

    readonly property var category: session ? session.category(categoryId) : null
    readonly property var settings: {
        var items = category && category.settings ? category.settings : []
        if (categoryId !== "miscellaneous")
            return items
        // Keep this general-purpose category in backend order, except for
        // the automatic shutdown option, which belongs at the bottom.
        var ordered = []
        var powerOff = []
        for (var i = 0; i < items.length; ++i) {
            if (items[i].settingId === "autoPowerOff")
                powerOff.push(items[i])
            else
                ordered.push(items[i])
        }
        return ordered.concat(powerOff)
    }

    // Only show controls relevant to the selected listening mode. The backend
    // still owns all settings and their values; these rules affect UI only.
    // When values are not known yet, leave controls visible (safe fallback).
    function showSetting(settingId) {
        if (page.categoryId !== "soundModes")
            return true

        var values = page.session && page.session.values ? page.session.values : ({})
        var ambient = values["ambientSoundMode"]
        if (ambient !== undefined && ambient !== null && ambient !== "") {
            var active = String(ambient).toLowerCase()
            var ancOnly = ["noiseCancelingMode", "manualNoiseCanceling",
                           "transportationMode", "windNoiseSuppression",
                           "windNoiseDetected"]
            var transparencyOnly = ["transparencyMode", "manualTransparency"]

            if (active === "normal")
                return ancOnly.indexOf(settingId) < 0
                       && transparencyOnly.indexOf(settingId) < 0
            if (active === "transparency" && ancOnly.indexOf(settingId) >= 0)
                return false
            if (active === "noisecanceling" && transparencyOnly.indexOf(settingId) >= 0)
                return false
        }

        // Within ANC, only one of its two mutually exclusive controls applies.
        // This also works for devices that don't expose ambientSoundMode.
        if (settingId === "manualNoiseCanceling" || settingId === "transportationMode") {
            var mode = values["noiseCancelingMode"]
            if (mode !== undefined && mode !== null && mode !== "") {
                var selected = String(mode).toLowerCase()
                if (selected === "manual")
                    return settingId === "manualNoiseCanceling"
                if (selected === "transportation")
                    return settingId === "transportationMode"
            }
        }
        return true
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        PullDownMenu {
            busy: page.session.busy
            MenuItem {
                text: qsTr("Refresh")
                onClicked: page.session.refreshValues()
            }
        }

        Column {
            id: column
            width: parent.width

            PageHeader {
                title: Strings.name(page.categoryId)
                description: page.session.title
            }

            WarningBanner {
                text: page.session.warning
                onDismissed: page.session.warning = ""
            }

            BusyIndicator {
                visible: running
                running: page.session.loading
                anchors.horizontalCenter: parent.horizontalCenter
                size: BusyIndicatorSize.Medium
            }

            Repeater {
                model: page.session.loading ? [] : page.settings
                SettingItem {
                    width: column.width
                    session: page.session
                    setting: modelData
                    shown: page.showSetting(modelData.settingId)
                }
            }
        }

        ViewPlaceholder {
            enabled: !page.session.loading && page.settings.length === 0
            text: page.session.connected ? qsTr("No settings available") : qsTr("Not connected")
        }

        VerticalScrollDecorator { }
    }
}
