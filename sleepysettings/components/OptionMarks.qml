import QtQuick
import qs

// What an option of a Combo and its Picker may carry besides its label (used by the Theme tab): `strip`, a few colours drawn as small
// chips (a theme's colour strip), and `images`, a few small pictures (icon theme samples, cursor shapes; image sources). Draws nothing for
// an option that has neither.
Row {
    id: marks
    property var strip: []
    property var images: []
    property int imageSize: 16
    // at most this many pictures are drawn (the picker's list six, the closed picker four)
    property int maxImages: 6
    spacing: 4
    visible: marks.strip.length > 0 || marks.images.length > 0

    Repeater {
        model: marks.strip

        Rectangle {
            required property string modelData
            objectName: "optionChip"
            width: 12
            height: 12
            anchors.verticalCenter: parent.verticalCenter
            radius: Theme.radiusXs
            color: modelData
            border.width: 1
            border.color: Qt.alpha(Theme.fg, 0.25)
        }
    }

    Repeater {
        model: marks.images.slice(0, marks.maxImages)

        Image {
            required property string modelData
            objectName: "optionImage"
            width: marks.imageSize
            height: marks.imageSize
            anchors.verticalCenter: parent.verticalCenter
            source: modelData
            sourceSize: Qt.size(marks.imageSize * 2, marks.imageSize * 2)
            fillMode: Image.PreserveAspectFit
            asynchronous: true
        }
    }
}
