import QtQuick
import qs.Ui

// uke: KeyboardPanel de Omarchy 4.0.6 con el contenido perezoso de la rama dev (`content`, `loadedContent`,
// `ensureContent()`), que es lo que usa Elsewhen. El contenido se construye la primera vez que el panel se abre
// y se queda cargado. Lo copia port-elsewhen.py junto al plugin.
KeyboardPanel {
  id: lazyRoot

  property Component content: null
  property bool contentRequested: false
  readonly property Item loadedContent: contentLoader.item
  readonly property real loadedContentHeight: contentLoader.item ? contentLoader.item.implicitHeight : 0

  function ensureContent() {
    if (content) contentRequested = true
    return contentLoader.item
  }

  onOpenChanged: if (open && content) contentRequested = true

  Loader {
    id: contentLoader
    anchors.fill: parent
    focus: true
    active: !!lazyRoot.content && (lazyRoot.open || lazyRoot.contentRequested)
    sourceComponent: lazyRoot.content
  }
}
