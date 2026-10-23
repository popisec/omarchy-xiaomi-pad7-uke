import QtQuick
import QtMultimedia

// Clic de tecla (ESCRITORIO-TACTIL 22-oct-2026). Se carga SOLO con el sonido activado (Loader en Keyboard.qml),
// asi QtMultimedia no entra en el proceso del shell si no se usa. click.wav: 12 ms, generado por gen-click.py.
SoundEffect {
  source: Qt.resolvedUrl("click.wav")
  volume: 0.35
}
