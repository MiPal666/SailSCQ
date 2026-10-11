// SPDX-FileCopyrightText: 2026 Denis Robel
// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick 2.0
import Sailfish.Silica 1.0
import "../components"
import "../components/Strings.js" as Strings

// All models the installed openscq30 CLI supports (`openscq30 list-models --json`),
// grouped by form factor. Needs no Bluetooth connection.
Page {
    id: page

    property var allModels: []        // [{ model, name }]
    property string searchText: ""
    property string cliVersion: ""
    property string errorText: ""

    readonly property var groupOrder: ["inear", "overear", "speaker"]

    function groupTitle(group) {
        if (group === "overear") return qsTr("Over-ear headphones")
        if (group === "speaker") return qsTr("Speakers")
        return qsTr("In-ear headphones")
    }

    function groupDescription(group) {
        if (group === "overear") return qsTr("One battery, sound modes, equalizer")
        if (group === "speaker") return qsTr("Equalizer, volume, power off")
        return qsTr("Charging case, battery left/right/case, often noise canceling and button configuration")
    }

    // a model of this group, used for the group illustration
    function groupSample(group) {
        if (group === "overear") return "SoundcoreA3028"
        if (group === "speaker") return "SoundcoreA3116"
        return "SoundcoreA3947"
    }

    function groupCount(group) {
        var n = 0
        for (var i = 0; i < allModels.length; i++)
            if (Strings.formFactor(allModels[i].model) === group) n++
        return n
    }

    // Fills the ListModel (sections need model roles, a JS array has none).
    function rebuild() {
        listModel.clear()
        var q = searchText.trim().toLowerCase()
        for (var g = 0; g < groupOrder.length; g++) {
            var group = groupOrder[g]
            var items = []
            for (var i = 0; i < allModels.length; i++) {
                var m = allModels[i]
                if (Strings.formFactor(m.model) !== group)
                    continue
                if (q.length > 0
                        && String(m.name).toLowerCase().indexOf(q) < 0
                        && String(m.model).toLowerCase().indexOf(q) < 0)
                    continue
                items.push(m)
            }
            items.sort(function(a, b) { return String(a.name).localeCompare(String(b.name)) })
            for (var j = 0; j < items.length; j++)
                listModel.append({ group: group, modelId: items[j].model, name: items[j].name })
        }
    }

    onSearchTextChanged: rebuild()

    Component.onCompleted: {
        modelsCli.run(["list-models", "--json"])
        versionCli.run(["--version"])
    }

    ListModel { id: listModel }

    CliRunner {
        id: modelsCli
        onFinished: {
            if (!success || !json || json.length === undefined) {
                page.errorText = errorOutput
                return
            }
            var models = []
            for (var i = 0; i < json.length; i++) {
                // internal test model, not a real device
                if (String(json[i].model).indexOf("Development") >= 0)
                    continue
                models.push(json[i])
            }
            page.allModels = models
            page.rebuild()
        }
    }

    CliRunner {
        id: versionCli
        // output: "openscq30 2.12.0"
        onFinished: if (success) page.cliVersion = output.trim().replace(/^openscq30\s*/, "")
    }

    SilicaListView {
        id: listView
        anchors.fill: parent
        model: listModel

        header: Column {
            width: listView.width

            // Reserve a touch-free area above the header in portrait mode.
            // On displays with a camera cutout, the hardware otherwise
            // overlaps the first line of the Supported devices title.
            Item {
                width: 1
                height: page.isPortrait ? Theme.itemSizeSmall : 0
            }

            PageHeader {
                title: qsTr("Supported devices")
                description: page.allModels.length === 0 ? ""
                             : (page.cliVersion.length > 0
                                ? qsTr("%n models · OpenSCQ30 %1", "", page.allModels.length).arg(page.cliVersion)
                                : qsTr("%n models", "", page.allModels.length))
            }

            SearchField {
                width: parent.width
                placeholderText: qsTr("Search model")
                onTextChanged: page.searchText = text
            }

            Label {
                visible: page.errorText.length > 0
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                text: page.errorText
                color: Theme.errorColor
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeSmall
            }
        }

        section.property: "group"
        section.delegate: Column {
            width: listView.width
            spacing: Theme.paddingMedium

            Item { width: 1; height: Theme.paddingLarge }

            DeviceTile {
                anchors.horizontalCenter: parent.horizontalCenter
                width: Theme.itemSizeHuge
                large: true
                modelId: page.groupSample(section)
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                horizontalAlignment: Text.AlignHCenter
                text: page.groupTitle(section)
                color: Theme.highlightColor
                font.pixelSize: Theme.fontSizeLarge
                font.family: Theme.fontFamilyHeading
                wrapMode: Text.Wrap
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                horizontalAlignment: Text.AlignHCenter
                text: page.groupDescription(section) + " · "
                      + qsTr("%n models", "", page.groupCount(section))
                color: Theme.secondaryHighlightColor
                font.pixelSize: Theme.fontSizeExtraSmall
                wrapMode: Text.Wrap
            }

            Item { width: 1; height: Theme.paddingSmall }
        }

        delegate: Item {
            width: listView.width
            height: Theme.itemSizeMedium

            DeviceTile {
                id: tile
                x: Theme.horizontalPageMargin
                anchors.verticalCenter: parent.verticalCenter
                width: Theme.itemSizeSmall
                modelId: model.modelId
            }

            Column {
                anchors {
                    left: tile.right; leftMargin: Theme.paddingLarge
                    right: parent.right; rightMargin: Theme.horizontalPageMargin
                    verticalCenter: parent.verticalCenter
                }
                Label {
                    width: parent.width
                    text: model.name
                    truncationMode: TruncationMode.Fade
                }
                Label {
                    width: parent.width
                    text: model.modelId
                    font.pixelSize: Theme.fontSizeExtraSmall
                    color: Theme.secondaryColor
                    truncationMode: TruncationMode.Fade
                }
            }
        }

        ViewPlaceholder {
            enabled: listView.count === 0 && !modelsCli.running && page.allModels.length > 0
            text: qsTr("No matching model")
        }

        BusyIndicator {
            anchors.centerIn: parent
            size: BusyIndicatorSize.Large
            running: modelsCli.running
        }

        VerticalScrollDecorator { }
    }
}
