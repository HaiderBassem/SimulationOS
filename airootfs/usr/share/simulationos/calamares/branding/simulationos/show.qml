/* SimulationOS installer slideshow (Calamares slideshow API 2). */
import QtQuick 2.5
import calamares.slideshow 1.0

Presentation {
    id: presentation

    function onActivate() {
        presentation.startAutoAdvance(12000);
    }

    function onLeave() {
        presentation.stopAutoAdvance();
    }

    Slide {
        Rectangle {
            anchors.fill: parent
            color: "#14161a"
            Column {
                anchors.centerIn: parent
                spacing: 18
                Text {
                    text: "SimulationOS"
                    color: "#33ccff"
                    font.pixelSize: 40
                    font.bold: true
                    anchors.horizontalCenter: parent.horizontalCenter
                }
                Text {
                    text: "An Arch-based system built around Hyprland."
                    color: "#e6e6e6"
                    font.pixelSize: 17
                    anchors.horizontalCenter: parent.horizontalCenter
                }
            }
        }
    }

    Slide {
        Rectangle {
            anchors.fill: parent
            color: "#14161a"
            Column {
                anchors.centerIn: parent
                spacing: 14
                Text {
                    text: "Built on the CachyOS kernel"
                    color: "#33ccff"
                    font.pixelSize: 30
                    anchors.horizontalCenter: parent.horizontalCenter
                }
                Text {
                    text: "linux-cachyos, tuned for desktop responsiveness."
                    color: "#e6e6e6"
                    font.pixelSize: 16
                    anchors.horizontalCenter: parent.horizontalCenter
                }
            }
        }
    }

    Slide {
        Rectangle {
            anchors.fill: parent
            color: "#14161a"
            Column {
                anchors.centerIn: parent
                spacing: 14
                Text {
                    text: "Almost done"
                    color: "#33ccff"
                    font.pixelSize: 30
                    anchors.horizontalCenter: parent.horizontalCenter
                }
                Text {
                    text: "After the reboot, log in at the SimulationOS greeter\nand Hyprland will start automatically."
                    color: "#e6e6e6"
                    font.pixelSize: 16
                    horizontalAlignment: Text.AlignHCenter
                    anchors.horizontalCenter: parent.horizontalCenter
                }
            }
        }
    }
}
