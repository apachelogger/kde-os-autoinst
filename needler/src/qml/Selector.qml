/*
    Copyright © 2017 Harald Sitter <sitter@kde.org>

    This program is free software; you can redistribute it and/or
    modify it under the terms of the GNU General Public License as
    published by the Free Software Foundation; either version 2 of
    the License or (at your option) version 3 or any later version
    accepted by the membership of KDE e.V. (or its successor approved
    by the membership of KDE e.V.), which shall act as a proxy
    defined in Section 14 of version 3 of the license.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

import QtQuick 2.7
import QtQuick.Controls 2.2
import QtQml.Models 2.2
import QtQuick.Layouts 1.3

import org.kde.kirigami 2.3 as Kirigami

Rectangle {
    id: rect

    property ObjectModel model
    property string type: "match"
    property double match: 95
    property bool clickArea: false

    // This is the hard limit offset, we'll coerce the rect inside a given
    // maxX and maxY with this offset. As a result this is effectively the
    // minimal square length of the rect.
    property int minimumOffset: 12

    function dimensionHint() {
        dimensionText.text = width + "x" + height
        dimensionText.visible = true
    }

    function fromObject(obj) {
        console.debug("----- fromObject")
        type = obj.type
        x = obj.xpos
        y = obj.ypos
        width = obj.width
        height = obj.height
        match = obj.match || 95
    }

    function toObject() {
        console.debug("----- toObject")
        return {
            type: this.type,
            xpos: this.x,
            ypos: this.y,
            width: this.width,
            height: this.height,
            match: this.match,
        }
    }

    color: "transparent"
    width: 64
    height: 64

    border.width: 1
    border.color: "lightblue"

    onXChanged: {
        if (x < 0) {
            x = 0
        } else if (x > image.width) {
            x = image.width - minimumOffset
        }
        x = Math.round(x)
    }

    onYChanged: {
        if (y < 0) {
            y = 0
        } else if (y > image.height) {
            y = image.height - minimumOffset
        }
        y = Math.round(y)
    }

    onWidthChanged: {
        if (x + width > image.width) {
            width = image.width - x
        }
        width = Math.round(width)
        dimensionHint()
    }

    onHeightChanged:  {
        if (y + height > image.height) {
            height = image.height - y
        }
        height = Math.round(height)
        dimensionHint()
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true

        ToolTip.delay: 1500
        ToolTip.visible: containsMouse
        ToolTip.text: "x: %1\ny: %2\nw: %3\nh: %4\ntype: %5".arg(rect.x).arg(rect.y).arg(rect.width).arg(rect.height).arg(type)
    }

    Rectangle {
        id: fill
        anchors.fill: parent
        color:  (type === "exclude") ? "red" : (clickArea ? "yellow" : "steelblue")
        opacity: 0.6
    }

    Text {
        id: dimensionText
        visible: false
        anchors.centerIn: parent

        onVisibleChanged: {
            if (!visible) {
                return
            }
            timer.restart()
        }

        Timer {
            id: timer
            interval: 2500
            repeat: false
            onTriggered: {
                dimensionText.visible = false
            }
        }
    }

    Dialog {
        id: propDialog
        visible: false
        title: "Properties"
        modal: true
        standardButtons: Dialog.Ok | Dialog.Cancel

        Kirigami.FormLayout {
            ComboBox {
                id: typeBox
                Kirigami.FormData.label: "Type:"
                // Fixed types.
                // match: pixel matching
                // ocr: run through optical character recogniation
                // exclude: exclude from reference. not sure how this works
                model: [ 'match', 'ocr', 'exclude' ]

            }

            TextField {
                id: matchField
                Kirigami.FormData.label: "Similarity:"
                text: rect.match
                validator: IntValidator{ bottom: 0; top: 100; }
            }
        }

        onAccepted: {
            rect.type = typeBox.currentText
            rect.match = parseFloat(matchField.text)
        }
    }

    Menu {
        id: contextMenuComponent
        modal: true

        MenuItem {
            text: "properties"
            onTriggered: { propDialog.open() }
        }

        MenuItem {
            text: "mark as click target"
            onTriggered: { model.setClickArea(rect) }
        }

        MenuItem {
            text: "delete"
            onTriggered: { model.removeObject(rect) }
        }
    }

    MouseArea {
        id: dragArea
        anchors.fill: parent

        drag.target: parent
        drag.maximumX: image.x + image.width - rect.width
        drag.minimumX: image.x
        drag.maximumY: image.y + image.height - rect.height
        drag.minimumY: image.y
        preventStealing: true

        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onPressed: {
            if (mouse.button == Qt.RightButton) {
                contextMenuComponent.x = mouse.x
                contextMenuComponent.y = mouse.y
                contextMenuComponent.open()
                return;
            }
        }
    }

    RectangleTwiddler {
        anchors.fill: parent
        rect: parent
    }
}
