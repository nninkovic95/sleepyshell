import QtQuick

// One morph of an island's outline (IslandShape.qml) at a time. start(drawn) takes the shape the outline draws right
// now as the start and runs `t` from 0 to 1, so a change halfway goes on from where the outline is instead of jumping
// back to a fixed end. At rest (t 1) the outline is its target, followed live. Before the first start `from` is the
// target itself.
//   target    the skyline to end at ({ fillet, corner, cols }); duration, easing: the island's clock
//   from, t   what the outline is drawn from, and how far it is
QtObject {
    id: root

    required property var target
    required property int duration
    required property int easing
    property var startSky: null
    readonly property var from: startSky || target
    property real t: 1

    function start(drawn) {
        startSky = drawn;
        anim.restart();
    }

    readonly property NumberAnimation anim: NumberAnimation {
        target: root
        property: "t"
        from: 0
        to: 1
        duration: root.duration
        easing.type: root.easing
    }
}
