import QtQuick
import qs.Commons
import qs.Ui

Item {
  id: root

  property var action: null
  property bool selected: false
  property bool showKey: false

  // Off when a shared gliding highlight paints the selection instead.
  property bool paintSelection: true

  signal clicked()
  signal hovered()

  readonly property string description: action ? String(action.description || "") : ""
  readonly property string accelerator: action ? String(action.accelerator || "") : ""
  readonly property color ink: Color.popups.text
  readonly property color faint: Util.alpha(ink, 0.5)

  implicitHeight: Math.max(Style.spacing.popupRowHeight, text.implicitHeight + Style.spacing.controlPaddingY * 2)

  CursorSurface {
    anchors.fill: parent
    hasCursor: root.selected && root.paintSelection
    foreground: root.ink
  }

  Text {
    id: glyph
    anchors.verticalCenter: parent.verticalCenter
    anchors.left: parent.left
    anchors.leftMargin: Style.spacing.rowPaddingX
    width: Style.font.icon
    horizontalAlignment: Text.AlignHCenter
    text: root.action ? String(root.action.icon || "") : ""
    color: root.selected ? Color.accent : root.ink
    font.family: Style.font.menuFamily
    font.pixelSize: Style.font.icon

    Behavior on color { ColorAnimation { duration: 100 } }
  }

  BorderSurface {
    id: key
    visible: root.showKey && root.accelerator !== ""
    anchors.verticalCenter: parent.verticalCenter
    anchors.right: parent.right
    anchors.rightMargin: Style.spacing.rowPaddingX
    implicitWidth: Math.max(keyText.implicitWidth + Style.space(8), implicitHeight)
    implicitHeight: keyText.implicitHeight + Style.space(4)
    radius: Math.max(2, Math.round(Style.cornerRadius / 2))
    color: Util.alpha(root.ink, 0.06)
    borderSpec: Border.controlSpec("normal", root.ink, Color.accent)

    Text {
      id: keyText
      anchors.centerIn: parent
      text: root.accelerator
      color: root.selected ? Color.accent : Util.alpha(root.ink, 0.45)
      font.family: Style.font.menuFamily
      font.pixelSize: Style.font.caption
      font.bold: true
    }
  }

  Column {
    id: text
    anchors.verticalCenter: parent.verticalCenter
    anchors.left: glyph.right
    anchors.leftMargin: Style.spacing.md
    anchors.right: key.visible ? key.left : parent.right
    anchors.rightMargin: Style.spacing.md
    spacing: 0

    Text {
      width: parent.width
      text: root.action ? String(root.action.label || "") : ""
      color: root.ink
      font.family: Style.font.menuFamily
      font.pixelSize: Style.font.body
      elide: Text.ElideRight
    }

    Text {
      visible: root.description !== ""
      width: parent.width
      text: root.description
      color: root.faint
      font.family: Style.font.menuFamily
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }
  }

  HoverHandler {
    cursorShape: Qt.PointingHandCursor
    onHoveredChanged: if (hovered) root.hovered()
  }

  TapHandler {
    onTapped: root.clicked()
  }
}
