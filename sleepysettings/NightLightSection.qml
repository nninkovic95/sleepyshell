import QtQuick
import QtQuick.Layouts
import qs
import qs.components
import qs.services
import qs.sleepysettings.components

// Night light settings: the warmth and the strength side by side (a PairRow), both staged Settings keys applied with the Display
// tab's Apply; services/NightLight.qml (the shell) turns them into the screen shader. The control centre's Night light tile is the switch.
// There is no schedule, place or fade.
Section {
    id: nl
    objectName: "nightLightSection"
    title: "Night light"

    PairRow {
        objectName: "pairNightLight"

        NumberRow {
            objectName: "rowNightWarmth"
            key: "nightWarmth"
            label: "Warmth"
            suffix: " K"
            sliderWidth: 110
            info: "How orange the screen gets while night light is on. Lower numbers are warmer; 6500 K changes nothing. The control centre's Night light tile switches it on and off."
            tags: "night light blue light kelvin temperature color colour"
        }

        NumberRow {
            objectName: "rowNightStrength"
            key: "nightStrength"
            label: "Strength"
            suffix: " %"
            sliderWidth: 110
            info: "How much of that warmth is used. 100 % is the full colour; lower blends it with the normal picture."
            tags: "night light intensity amount"
        }
    }
}
