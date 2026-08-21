import QtQuick
import qs.Commons
import qs.Ui

Item {
  id: root

  property var action: null
  property bool selected: false
  property bool showKey: false
  property string overflowGlyph: ""

  // Off when a shared gliding highlight paints the selection instead.
  property bool paintSelection: true

  signal clicked()
  signal hovered()

  readonly property bool isOverflow: overflowGlyph !== ""
  readonly property string glyph: isOverflow ? overflowGlyph : (action ? String(action.icon || "") : "")
  readonly property string label: isOverflow ? "" : (action ? String(action.label || "") : "")
  readonly property string accelerator: showKey
    ? (isOverflow ? "⇥" : (action ? String(action.accelerator || "") : ""))
    : ""

  readonly property color ink: Color.popups.text
  readonly property color faint: Util.alpha(ink, 0.45)

  implicitWidth: body.implicitWidth + Style.spacing.controlPaddingX * 2
  implicitHeight: Math.max(Style.spacing.controlHeight, Style.font.body + Style.spacing.controlPaddingY * 2)

  Item {
    id: inner
    anchors.fill: parent
    scale: tap.pressed ? 0.93 : 1
    transformOrigin: Item.Center

    Behavior on scale { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }

    BorderSurface {
      anchors.fill: parent
      radius: Style.cornerRadius
      color: root.selected && root.paintSelection ? Style.selectedFillFor(root.ink, Color.accent) : "transparent"
      borderSpec: root.selected && root.paintSelection
        ? Border.controlSpec("selected", root.ink, Color.accent)
        : Border.none()

      Behavior on color { ColorAnimation { duration: 100 } }
    }

    Row {
      id: body
      anchors.centerIn: parent
      spacing: Style.spacing.md

      Row {
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.spacing.xs

        Text {
          textFormat: Text.PlainText
          visible: root.glyph !== ""
          anchors.verticalCenter: parent.verticalCenter
          text: root.glyph
          color: root.selected ? Color.accent : root.ink
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.icon

          Behavior on color { ColorAnimation { duration: 100 } }
        }

        Text {
          textFormat: Text.PlainText
          visible: root.label !== ""
          anchors.verticalCenter: parent.verticalCenter
          text: root.label
          color: root.ink
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.body
        }
      }

      BorderSurface {
        visible: root.accelerator !== ""
        anchors.verticalCenter: parent.verticalCenter
        implicitWidth: Math.max(keyText.implicitWidth + Style.space(8), implicitHeight)
        implicitHeight: keyText.implicitHeight + Style.space(4)
        radius: Math.max(2, Math.round(Style.cornerRadius / 2))
        color: Util.alpha(root.ink, 0.06)
        borderSpec: Border.controlSpec("normal", root.ink, Color.accent)

        Text {
          id: keyText
          textFormat: Text.PlainText
          anchors.centerIn: parent
          text: root.accelerator
          color: root.selected ? Color.accent : root.faint
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.caption
          font.bold: true
        }
      }
    }
  }

  HoverHandler {
    cursorShape: Qt.PointingHandCursor
    onHoveredChanged: if (hovered) root.hovered()
  }

  TapHandler {
    id: tap
    onTapped: root.clicked()
  }
}
