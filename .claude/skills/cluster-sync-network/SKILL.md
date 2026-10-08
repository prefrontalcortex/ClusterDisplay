---
name: cluster-sync-network
description: Regeln und Vorgehen für Transport-Layer, Wire-Format und Frame-Lock-Synchronisation im Cluster Display (Emitter/Repeater, UDP Unicast/Multicast, Unity Transport, PlayerLoop-Injektion, Zeit- und Random-Sync, Input-Replikation, Thread-Übergabe). Immer verwenden, wenn Code im Netzwerk-, Sync-, Timing- oder Replikationspfad gelesen oder geändert wird, wenn Pakete, Sockets, Serialisierung oder Latenz/Jitter/Desync zwischen Nodes Thema sind – auch bei scheinbar kleinen Änderungen.
---

# Cluster Sync & Network

Im Cluster muss jeder Node pro Frame denselben Zustand haben und das Bild zur selben Zeit zeigen. Ein Fehler hier zeigt sich als Tearing zwischen Displays, Ruckeln oder schleichender Desync – schwer reproduzierbar. Deshalb gelten hier strengere Regeln als im übrigen Code.

## 1. Erst verstehen, dann ändern

Vor jeder Änderung festhalten (im Backlog-Task oder in `references/current-protocol.md`, anlegen falls fehlend):
- Topologie: ein Emitter, n Repeater? Wer startet, wer wartet?
- Transport: Unicast oder Multicast, Ports, Pakete pro Frame, MTU/Fragmentierung.
- Was pro Frame übertragen wird (Framenummer, Zeit, `Random.state`, Input, Custom-Daten).
- Wo im PlayerLoop blockiert/gewartet wird und mit welchem Timeout.
- Verhalten bei Paketverlust und Node-Ausfall.

Nicht annehmen, dass der Legacy-Code UNet nutzt – Cluster-Rendering-Implementierungen nutzen häufig eigene UDP-Sockets.

## 2. Transportwahl

Entscheidung mit dem Nutzer treffen, nicht selbst. Entscheidungsvorlage:
- **`System.Net.Sockets` UDP**: volle Kontrolle, Multicast möglich (ein Paket an alle Repeater – skaliert gut bei vielen Nodes). Zuverlässigkeit (ACK/Resend) selbst bauen.
- **Unity Transport (UTP)**: gepflegt, Reliability-Pipelines eingebaut. Unterstützt nach meinem Kenntnisstand kein Multicast – bei vielen Repeatern bedeutet das n Unicast-Sends pro Frame. Vor der Entscheidung in der aktuellen Doku verifizieren.
- Netz der Installation prüfen: Erlauben Switches/IGMP Multicast?

## 3. Harte Invarianten

- **Sync-Pfad läuft synchron im PlayerLoop**, eingehängt über `UnityEngine.LowLevel.PlayerLoop` an fester Stelle (typisch früh in `EarlyUpdate`). Kein `async/await`, keine Coroutines, keine `Task.ContinueWith` – deren Fortsetzungszeitpunkt ist nicht an den Frame gebunden.
- **Warten mit Timeout**, nie unbegrenzt. Timeout und Verhalten (Frame überspringen, Node als ausgefallen markieren) sind Konfiguration, kein Magic Number.
- **Empfang im Hintergrund-Thread → `ConcurrentQueue`/Ringpuffer → Abarbeitung im Main Thread** an genau einer Stelle. Keine Unity-API im Hintergrund-Thread (auch kein `Debug.Log` in heißen Schleifen).
- **Keine Allokation pro Frame** im Sync-Pfad: Puffer vorallozieren, `Span<byte>`, `stackalloc` für kleine Puffer.
- **Determinismus**: `Time`-Werte vom Emitter übernehmen, `Random.state` mitsenden, keine Iteration über `FindObjectsByType` ohne stabile Sortierung, keine Abhängigkeit von InstanceIDs.

## 4. Wire-Format

Details und Vorlage: `references/wire-format.md`. Kurz:
- Fester Header: Magic, Protokollversion, Nachrichtentyp, Framenummer (`ulong`), Payload-Länge.
- Explizit Little-Endian über `BinaryPrimitives`; Structs `[StructLayout(LayoutKind.Sequential, Pack = 1)]`, nur blittable Felder.
- Jede Formatänderung → Version erhöhen; Repeater mit falscher Version verwerfen das Paket laut und deutlich (Log einmalig, nicht pro Frame).
- Kein `BinaryFormatter`, kein JSON im Frame-Pfad.

## 5. Tests (Pflicht bei Änderungen hier)

- EditMode: Roundtrip-Serialisierung jeder Nachricht (schreiben → lesen → gleich), inkl. Grenzwerte und falscher Version/Länge.
- EditMode/PlayMode: Loopback-Test mit Emitter und Repeater auf `127.0.0.1` (Unicast), simuliertem Paketverlust und Timeout.
- Danach `unity-compile-check` ausführen.

Was sich nur auf echter Hardware prüfen lässt (Genlock, Swap-Barrier/Present-Sync der GPU, Multicast im echten Netz), im Backlog als manuellen Abnahmeschritt für den Nutzer vermerken statt Erfolg zu behaupten.
