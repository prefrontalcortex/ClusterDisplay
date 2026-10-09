# Aktuelles Netzwerkprotokoll des Cluster-Sync (Ist-Zustand)

Stand: aus dem Quellcode gelesen (Branch `dotnet-update`), nichts davon durch Laufzeit-Tests verifiziert.
Pfade relativ zu `source/com.unity.cluster-display/Runtime/` (Kürzel `R/`), sofern nicht anders angegeben.
"unklar" = aus dem Code allein nicht sicher ableitbar. Abschnitt 6 trennt Beobachtungen/Risiken von den Fakten.
Dies ist die Ist-Beschreibung, nicht die Soll-Vorlage aus `wire-format.md` (die ist ein Entwurf, den der Code nicht umsetzt).

> **Änderung 2026-10-09 (M-43a/M-43b), geht dem Rest dieses Dokuments vor:** Datagramme haben jetzt einen 3-Byte-Header `[Magic 0xCD][ProtocolVersion][MessageType]` (vorher nur `[MessageType]`; `UdpAgent.ProtocolVersion`, aktuell 1, bei jeder Wire-Änderung erhöhen). Datagramme ohne Magic werden still ignoriert, mit anderer Version verworfen und **einmal pro Version** als Warnung geloggt. `MaximumMessageSize` = `Mtu - 28 (IPv4+UDP) - 3` (vorher `Mtu - 1`, dadurch IP-Fragmentierung). Alle Angaben unten zu „kein Magic/keine Version“ und zur MTU sind damit überholt.
## 1. Topologie und Rollen

- Rollen (`NodeRole`): Emitter, Repeater, Backup (plus Unassigned). Genau ein Emitter, n Repeater, optional Backups. Auswahl über `ClusterParams.Role` -> `ClusterSync.TryInitialize` (`R/ClusterSync.cs:355-397`).
- Ein Backup ist technisch ein `RepeaterNode` mit `NodeRole.Backup` (`R/ClusterSync.cs:275-293`, `R/Node/RepeaterNode.cs:24`). Es verhält sich wie ein Repeater und kann per Topologieänderung zum Emitter werden.
- Node-IDs sind `byte` (0..255). Wartelisten sind 256-Bit-Vektoren (`NodeIdBitVector`, `EmitterWaitingToStartFrame.WaitingOn0..3`, `R/Networking/NetworkMessages.cs:263-308`). Mehr als 256 Nodes sind im Format nicht vorgesehen.
- Alle Nodes laufen im selben Frame-Takt; `FrameIndex` startet bei 0 (`ClusterNodeConfig.FirstFrameIndex`, nur beim Failover != 0) und wird in `PostFrame` erhöht (`R/Node/ClusterNode.cs:164-167`, `R/ClusterSync.cs:490-495`).

### 1.1 Zustandsautomaten (pro Node, `NodeState.DoFrame()`; `R/Node/ClusterNode.cs:138-159`)

| Rolle | Zustand | Datei | Wechsel |
|---|---|---|---|
| Emitter | `HardwareSyncInitState`/`QuadroSyncInitEmitterState` (nur `Fence=Hardware`) | `R/States/HardwareSyncInitState.cs` | -> `WelcomeRepeatersState` |
| Emitter | `WelcomeRepeatersState` | `R/States/EmitterStates/WelcomeRepeatersState.cs:22-59` | -> `EmitFrameState` |
| Emitter | `EmitFrameState` (bleibt dauerhaft) | `R/States/EmitterStates/EmitFrameState.cs:44-120` | -> `PropagateQuitState` bei Quit-Anforderung |
| Emitter | `PropagateQuitState` | `R/States/EmitterStates/PropagateQuitState.cs:25-67` | Ende (Quit) |
| Repeater/Backup | `HardwareSyncInitState`/`QuadroSyncInitRepeaterState` (nur `Fence=Hardware`) | `R/States/HardwareSyncInitState.cs` | -> `RegisterWithEmitterState` |
| Repeater/Backup | `RegisterWithEmitterState` | `R/States/RepeaterStates/RegisterWithEmitterState.cs:21-107` | -> `RepeatFrameState` (im selben Frame-Aufruf) |
| Repeater/Backup | `RepeatFrameState` (bleibt dauerhaft) | `R/States/RepeaterStates/RepeatFrameState.cs:50-145` | -> `ProcessQuitMessageState`, oder Ergebnis `BackupToEmitter` |
| Repeater/Backup | `ProcessQuitMessageState` | `R/States/RepeaterStates/ProcessQuitMessageState.cs:17-23` | Ende (Quit) |

`ClusterNode.DoFrame` iteriert, bis ein Zustand ein `DoFrameResult` liefert; Zustandswechsel passieren also innerhalb eines Frames.

### 1.2 Registrierung / Handshake

1. Emitter (`WelcomeRepeatersState`): wartet bis `HandshakeTimeout` auf `RegisteringWithEmitter`, antwortet jeweils mit `RepeaterRegistered` (`Accepted` laut `RepeatersStatus.ProcessRegisteringMessage`, `R/Node/EmitterNode.cs:48-74`). Schleife endet, wenn `ExpectedRepeaterCount` (= `RepeaterCount + BackupCount`, `R/ClusterSync.cs:239`) erreicht ist oder die Zeit abläuft (`WelcomeRepeatersState.cs:54-55`). Läuft die Zeit ab, startet der Emitter mit den bis dahin registrierten Repeatern (kein Fehler).
2. Repeater (`RegisterWithEmitterState`): sendet `RegisteringWithEmitter{NodeId, IPAddressBytes}` sofort und dann alle 250 ms erneut (`:115`), bis ein `RepeaterRegistered` mit gleicher NodeId und gleicher IP kommt. `Accepted=false` -> `InvalidOperationException` (`:70-73`). Ablauf `HandshakeTimeout` -> `TimeoutException` (`:100-104`).
3. Kommt vor der Bestätigung `FrameData` für Frame 0 an, wird es zwischengespeichert und die Registrierung im 5-ms-Intervall wiederholt (`:77-90, :120`); `FrameData` mit Frame != 0 -> `InvalidDataException`.
4. Ein NodeId-Konflikt wird nur über die IP erkannt: gleiche NodeId mit anderer IP wird abgelehnt (`EmitterNode.cs:54-58`). Nach dem Handshake nimmt `EmitFrameState` keine neuen Repeater mehr an (`acceptNew=false`), beantwortet aber wiederholte Registrierungen bereits bekannter Repeater (`EmitFrameState.cs:130-143`).
5. Ein Repeater, der zu spät kommt, erhält `Accepted=false` und bricht ab (Terminate, siehe 4.6).

### 1.3 Topologieänderung / Failover

- Eingang: `IClusterSyncState.ChangeClusterTopology(entries)` (`R/ClusterSyncState.cs:82-99`), thread-agnostisch, verlangt genau einen Emitter, setzt `LocalNode.UpdatedClusterTopology.Entries` und feuert `Changed` (`R/ClusterTopology.cs:33-46`). Wer das aufruft, liegt außerhalb von Runtime/Node: Tests und `FailOverProcessTests` (MissionControl/Capcom) deuten darauf; Produktionsaufrufer unklar (nicht gesucht). Es gibt im Protokoll keine automatische Ausfallerkennung des Emitters; der Anstoß kommt von außen.
- Emitter (`EmitterNode.ProcessTopologyChanges`, `:206-221`): Repeater, die nicht mehr in der Topologie stehen, werden aus `RepeatersStatus` gestrichen; ist der eigene Eintrag nicht mehr Emitter, Quit.
- `FrameWaitingToStartHandler` wacht bei `Changed` sofort auf und streicht entfernte Repeater aus der Warteliste (`R/Networking/FrameWaitingToStartHandler.cs:79-135, 254-273`).
- Repeater (`RepeaterNode.HandleChangesInNodeAssignment`, `:105-140`): kein eigener Eintrag -> Quit; sonst `NodeRole`/`RenderNodeId` übernehmen. Eine Änderung Backup -> Emitter startet einen `EmitterPlaceholder` mit geklontem `UdpAgent` (zweiter Socket + zweiter Empfangs-Thread, `UdpAgent.Clone`, `UDPAgent.cs:229-234`).
- `EmitterPlaceholder` (`R/Networking/EmitterPlaceholder.cs`): Work-Thread (`:125-146`) sendet alle 50 ms `SurveyRepeaters`, sammelt `RepeatersSurveyAnswer`, holt fehlende Frames per `RetransmitReceivedFrameData`/`RetransmittedReceivedFrameData` (Fenster 250 ms, Idle 25 ms, `:551-560`), beantwortet in der Zwischenzeit `RetransmitFrameData` aus seiner Historie und `RepeaterWaitingToStartFrame` (nur wenn `FrameIndex == min+1`, `:368-396`). Repeater antworten auf `SurveyRepeaters` per Pre-Process (`RepeaterNode.cs:147-162`).
- Umschalten (`RepeaterNode.IsBackupToEmitterSwitchReady`, `:53-73`): alle Antworten da, `min(LastReceivedFrameIndex) == max(...)` und Umfrage seit > 500 ms stabil. Dann `DoFrameResult.BackupToEmitter` -> `ClusterSync.TransitionBackupToEmitterNode` (`R/ClusterSync.cs:399-424`): neuer `EmitterNode` mit `FirstFrameIndex = alter FrameIndex`, `RepeatersSurveyResult` (ohne eigene ID), neuer Zustand `EmitFrameState(skipFirstNetworkSync=true)` (`EmitterNode.cs:143-153`) und sofortiges `LocalNode.DoFrame()` im selben Frame (`ClusterSync.cs:471-476`).
- Der alte Emitter wird nicht aktiv vom Protokoll abgeschaltet; ob er weiterläuft/gekillt wird, entscheidet die externe Steuerung (unklar).

## 2. Transport

| Aspekt | Ist-Zustand | Beleg |
|---|---|---|
| Protokoll | UDP über `System.Net.Sockets.UdpClient`, ausschließlich Multicast-Senden | `R/Networking/UDPAgent.cs:92, 118, 175` |
| Unicast | Nicht vorhanden. Jede Nachricht (auch "an einen Repeater") geht an die Multicast-Gruppe; Adressierung nur über Felder wie `NodeId` | `UDPAgent.cs:118` |
| Gruppe/Port | Default `224.0.1.0` : `25690` (gleicher Port zum Senden und Empfangen); überschreibbar über Settings, Kommandozeile, MissionControl (`ClusterParams.Default`) | `R/ClusterParams.cs:126-128`, `R/ClusterSync.cs:372-378` |
| Adapter | `AdapterName` oder erster Adapter mit Status Up, Multicast-Unterstützung, IPv4, nicht Loopback; keiner gefunden -> `IOException` | `UDPAgent.cs:241-317, 71-75` |
| Bind | Adapter-IP:Port (nicht `0.0.0.0`) | `UDPAgent.cs:110` |
| Socket-Optionen | `MulticastInterface` = Adapter-IP; `MulticastTimeToLive = 1`; `ReuseAddress = true`; `MulticastLoopback = true`; Send-/Receive-Puffer je 65535 | `UDPAgent.cs:95-115` |
| Gruppenbeitritt | `JoinMulticastGroup(MulticastIp)` | `UDPAgent.cs:112` |
| MTU | `GetIPv4Properties().Mtu` des Adapters, Fallback 1400; `MaximumMessageSize = Mtu - 1` | `UDPAgent.cs:81-89` |
| Sende-Puffer | `ConcurrentObjectPool<byte[]>` der Größe MTU; Nachricht = 1 Byte Typ + Struct + optionale Nutzdaten | `UDPAgent.cs:119, 145-184` |
| Sende-Allokation | `UdpClient.Send(byte[], int, IPEndPoint)` allokiert laut Kommentar ca. 104 Byte pro Send | `UDPAgent.cs:172-175` |
| Schutz gegen Übergröße | Wirft `ArgumentException`, wenn Struct + 1 + Nutzdaten > MTU | `UDPAgent.cs:155-158` |

### 2.1 Threads und Empfangspfad

1. Pro `UdpAgent` mit nicht-leerer `ReceivedMessagesType`-Liste ein dedizierter Empfangs-Thread (`ProcessIncomingDatagrams`, `UDPAgent.cs:122-128, 369-507`). Blockierendes `Socket.Receive` in einen vorallozierten `byte[MTU]` aus `ConcurrentObjectPool<ManagedReceivedMessageData>`.
2. Byte 0 = `MessageType`. Nachrichtentypen, für die dieser Agent keine Fabrik hat, werden stillschweigend verworfen (`:416-423`). Pro Typ gibt es eine per Reflection gebaute Fabrik `ReceivedMessage<T>.GetFromPool` (`:326-364`), die `MemoryMarshal.Read<T>` auf `bytes[1..]` ausführt (`R/Networking/IUdpAgent.cs:188-193`). Überstehende Bytes -> `ExtraData` (Buffer-Übernahme ohne Kopie, `UDPAgent.cs:439-447`).
3. Auf dem Empfangs-Thread laufen anschließend die registrierten Pre-Processors, absteigend nach Priorität (`:459-497`, Prioritäten `IUdpAgent.cs:279-301`):

| Priorität | Pre-Processor | Aufgabe |
|---|---|---|
| `MessageSniffing` (int.Max) | Quadro-Warmup-Sniffer | beobachten, immer PassThrough |
| 1000 | `FrameDataAssembler` | `FrameData` zusammensetzen, Retransmit-Anforderungen senden, `RetransmitReceivedFrameData` beantworten |
| 900 | `FrameDataSplitter` | `RetransmitFrameData` beantworten (sendet vom Empfangs-Thread aus) |
| 500 | `FrameWaitingToStartHandler` | `RepeaterWaitingToStartFrame` verbuchen und mit `EmitterWaitingToStartFrame` antworten |
| 300 | `EmitterPlaceholder` und `RepeaterNode` (Survey-Antwort) | Failover |
| 100 | `EmitFrameState.AnswerRegisteringWithEmitter` | Wiederholte Registrierung beantworten |

4. Was durch alle Pre-Processors kommt, geht per `BlockingQueue<ReceivedMessageBase>.Enqueue` an den Main Thread (`UDPAgent.cs:500-503, 667`). Der Main Thread holt per `TryConsumeNextReceivedMessage(timeout)` ab (`:196-199`), im Sync-Pfad nur in den Zuständen (Abschnitt 4).
5. Weitere Threads: `FrameDataAssembler`-Monitor (Repeater, pro `RepeatFrameState`, `R/Networking/FrameDataAssembler.cs:82-85, 394-452`); `EmitterPlaceholder`-Work-Thread; Quadro-Heartbeat-/Status-/DetectLongPresent-Threads (Abschnitt 5); ein Log-Thread nur mit `CLUSTER_DISPLAY_NETWORK_LOG` (`UDPAgent.cs:719-904`).
6. Unity-API auf Hintergrund-Threads: `Debug.LogError/LogWarning` aus Empfangs- und Monitor-Thread (z. B. `UDPAgent.cs:397, 453`, `FrameDataSplitter.cs:220`). Sonst nur System-/Native-Container-Zugriffe; `UnityEngine.Random`/`Time` werden nur im Main Thread berührt.

## 3. Wire-Format

### 3.1 Datagramm-Aufbau (es gibt keinen Header im üblichen Sinn)

```
Byte 0        : MessageType (byte)
Byte 1..1+S-1 : Struct (blittable, [StructLayout(Sequential, Pack = 1)], S = Marshal.SizeOf<T>)
Byte 1+S..    : optionale Nutzdaten (nur FrameData, RetransmittedReceivedFrameData)
```

- Byte-Reihenfolge: native Struct-Kopie (`MemoryMarshal.Read/TryWrite`), faktisch Little Endian auf x64. Keine explizite Endianness (`R/Networking/NetworkMessages.cs:27-45`).
- Länge: nur über die UDP-Datagrammlänge; Nutzdatenlänge = Rest hinter dem Struct.
- Zu kurz -> `MemoryMarshal.Read` wirft, wird auf dem Empfangs-Thread gefangen, geloggt, Paket verworfen (`UDPAgent.cs:451-455`). Zu lang bei Typen ohne Nutzdaten: Rest wird kommentarlos als `ExtraData` mitgeführt, nicht geprüft.

### 3.2 NICHT vorhanden (Lücken)

- **Kein Magic**, **keine Protokollversion**, **keine Längenangabe**, **keine Prüfsumme** (nur UDP-Checksum), **keine Cluster-/Session-ID**, **keine Authentifizierung**. Jedes UDP-Paket an Port 25690 der Gruppe, dessen erstes Byte ein bekannter Typ ist und das lang genug ist, wird verarbeitet. Ein Nicht-Cluster-Sender oder ein zweiter Cluster auf gleicher Gruppe/Port stört den Betrieb (z. B. fremdes `RegisteringWithEmitter`, fremdes `FrameData`). Folge: Wire-Format-Änderungen (Regel 4 in CLAUDE.md) lassen sich derzeit nicht erkennen; ein Repeater mit anderem Build interpretiert Bytes falsch statt sie "laut" zu verwerfen.
- Keine Fragmentnummerierung im Header: Fragmentierung steckt in `FrameData` selbst (3.4).
- Keine Sequenznummer für Steuernachrichten; Idempotenz entsteht durch Wiederholung mit `FrameIndex`/`NodeId`.
- Keine Verschlüsselung.

### 3.3 Nachrichten (alle `MessageType`-Werte, `NetworkMessages.cs:73-90`)

Größe = Struct-Bytes ohne Typ-Byte (aus Feldtypen berechnet, `bool` = `UnmanagedType.I1` = 1 Byte; leere Structs: C# `sizeof` ist 1, tatsächliche Wire-Größe unklar, ungeprüft). Alle Nachrichten gehen physisch an die Multicast-Gruppe; "Richtung" ist die logische.

| # | MessageType | Struct (Zeile) | Felder (Typ) | Größe | Richtung | Zweck |
|---|---|---|---|---|---|---|
| 0 | `None` | - | - | - | - | Platzhalter, wird nicht gesendet |
| 1 | `RegisteringWithEmitter` | `:131` | NodeId (byte), IPAddressBytes (uint) | 5 | Repeater -> Emitter | Beitrittswunsch, wiederholt alle 250 ms |
| 2 | `RepeaterRegistered` | `:156` | NodeId (byte), IPAddressBytes (uint), Accepted (bool) | 6 | Emitter -> Repeater | Bestätigung/Ablehnung; gleiche NodeId+IP wie Anfrage |
| 3 | `FrameData` | `:185` | FrameIndex (ulong), DataLength (int), DatagramIndex (int), DatagramDataOffset (int) + Nutzdaten | 20 + Nutzdaten | Emitter -> Repeater | ein Fragment der Frame-Nutzlast (3.4) |
| 4 | `RetransmitFrameData` | `:214` | FrameIndex (ulong), DatagramIndexIndexStart (int, inkl.), DatagramIndexIndexEnd (int, exkl.) | 16 | Repeater -> Emitter | fehlende Fragmente anfordern |
| 5 | `RepeaterWaitingToStartFrame` | `:239` | FrameIndex (ulong), NodeId (byte), WillUseNetworkSyncOnNextFrame (bool) | 10 | Repeater -> Emitter | "bereit für Frame N" (Netzwerk-Fence) |
| 6 | `EmitterWaitingToStartFrame` | `:263` | FrameIndex (ulong), WaitingOn0..3 (je ulong, 256-Bit-Vektor) | 40 | Emitter -> Repeater | Antwort: auf wen der Emitter noch wartet |
| 7 | `PropagateQuit` | `:320` | leer | 0 (unklar, s. o.) | Emitter -> alle | Quit auslösen, alle 100 ms wiederholt |
| 8 | `QuitReceived` | `:330` | NodeId (byte) | 1 | Repeater -> Emitter | Quit-Quittung |
| 9 | `QuadroBarrierWarmupHeartbeat` | `:367` | Stage (byte-Enum), AdditionalPresentCount (uint) | 5 | Emitter -> Repeater | Warmup-Phase (Abschnitt 5) |
| 10 | `QuadroBarrierWarmupStatus` | `:390` | NodeId (byte), Stage (byte-Enum), Completed (bool) | 3 | Repeater -> Emitter | Warmup-Status (Abschnitt 5) |
| 11 | `SurveyRepeaters` | `:417` | leer | 0 (unklar) | Backup-Emitter-Placeholder -> alle | Zustandsabfrage beim Failover |
| 12 | `RepeatersSurveyAnswer` | `:426` | NodeId (byte), IPAddressBytes (uint), LastReceivedFrameIndex (ulong), StillUseNetworkSync (bool) | 14 | Repeater/Backup -> Placeholder | Antwort auf Survey |
| 13 | `RetransmitReceivedFrameData` | `:468` | NodeId (byte), FrameIndex (ulong) | 9 | Placeholder -> Repeater | alten, empfangenen Frame von einem Repeater holen |
| 14 | `RetransmittedReceivedFrameData` | `:492` | wie `FrameData`: FrameIndex, DataLength (int, -1 = nicht vorhanden), DatagramIndex, DatagramDataOffset + Nutzdaten | 20 + Nutzdaten | Repeater -> Placeholder | Antwort auf 13 |

Empfangsfilter pro Rolle (`MessageType[]` je Agent, nur diese Typen werden überhaupt geparst):
- Emitter: 1, 4, 5, 8, 10 (`R/Node/EmitterNode.cs:283-285`).
- Repeater/Backup: 2, 3, 6, 7, 9, 11, 13 (`R/Node/RepeaterNode.cs:167-171`).
- `EmitterPlaceholder`-Agent: 4, 5, 12, 14 (`EmitterPlaceholder.cs:564-566`).
- Folge: Ein Repeater empfängt die eigenen Multicast-Sendungen (Loopback an) nicht als Nachrichten, die er filtert; Typen außerhalb seiner Liste werden vor dem Parsen verworfen. Repeater sehen aber `FrameData` aller Fragmente, auch ihre Retransmits (mehrere Repeater können dieselbe Anforderung auslösen, Abschnitt 3.5).

### 3.4 Frame-Nutzlast, Fragmentierung, Retransmit

Frame-Nutzlast (`FrameDataBuffer`, `R/Networking/Node/FrameDataBuffer.cs`): Folge von Blöcken `int id | int size | byte[size]`, Abschluss mit `id = StateID.End (0)` und `size = 0` (`:98-157, 256, 274-305`). Initiale Kapazität 65535 Byte, harte Obergrenze 1 MiB (`k_MaximumCapacity`, `:252`), Überschreitung -> `OutOfMemoryException`. Die Blockfolge ist ohne Längenangabe im Paket; die Gesamtlänge steht nur in `FrameData.DataLength`.

Fragmentierung (Emitter, `FrameDataSplitter`):
- `m_MaxDataPerMessage = UdpAgent.MaximumMessageSize - sizeof(FrameData) = (MTU - 1) - 20` (`R/Networking/FrameDataSplitter.cs:38`).
- Datagramme pro Frame = ceil(Länge / MaxDataPerMessage); Fragment i trägt `DatagramIndex=i`, `DatagramDataOffset=i*MaxDataPerMessage` (`:132-139, 176-186`).
- UDP-Nutzlast je volles Fragment = 1 + 20 + (MTU-21) = **MTU Byte**; zuzüglich 28 Byte IP+UDP-Header liegt das IP-Paket über der MTU (IP-Fragmentierung, Abschnitt 6).
- Sendereihenfolge: alle Fragmente sofort hintereinander, kein Pacing.
- Frame-Index muss lückenlos aufsteigen, sonst `ArgumentException` (`:109-113`).

Retransmit (Repeater -> Emitter):
- `FrameDataAssembler` führt pro Frame `PartialFrameData` (BitArray der empfangenen Fragmente, Start 32 Bit, wächst in 32er-Schritten; `FrameDataAssembler.cs:845, 683-695`) und zusätzlich `m_NextPartialFrame` für ein vorgezogenes Frame N+1 (`:197-204`).
- Auslöser (a): Lückenerkennung bei Fragmentankunft, nur wenn `orderedReception`, d. h. nur mit Define `CLUSTER_DISPLAY_ORDER_PRESERVING_NETWORK`; standardmäßig **aus** (`RepeatFrameState.cs:31-35`, `FrameDataAssembler.cs:717-725`).
- Auslöser (b): Monitor-Thread, aktiv ab `WillNeedFrame(n)` (`:136-154`), prüft alle `FrameCompletionDelay` = **4 ms** (`:515`); ist seit dem letzten Fragment > 4 ms vergangen, sendet er `RetransmitFrameData` für jede Lücke plus "Rest" (`DatagramIndexIndexEnd = int.MaxValue`, `:785-795`). Wurde für den Frame noch gar nichts empfangen, wird die Wartezeit mal 10 genommen (40 ms, `:415-428`).
- Emitter beantwortet im Pre-Process (Empfangs-Thread): prüft Frame-Index gegen die Historie, sendet Fragmente erneut; dasselbe Fragment wird frühestens nach **2 ms** erneut gesendet (Entprellung gegen mehrere Repeater, `FrameDataSplitter.cs:171-174, 384`).
- Historie Emitter: `retransmitHistory` Frames (Default `DefaultRetransmitHistoryLength = 2`, Minimum 2; `NetworkMessages.cs:66`, `FrameDataSplitter.cs:28`). `EmitFrameState` benutzt den Default (`:26`). Ältere Anforderungen -> Warnung, keine Antwort (`:213-225`).
- Historie Repeater: nur wenn `HasAtLeastOneBackupNode`, sonst 0 (`RepeatFrameState.cs:37-39`); dient `RetransmitReceivedFrameData` beim Failover (`FrameDataAssembler.cs:267-301`).
- Zusammengesetzte Frames liegen in `NativeArray<byte>` (Persistent-Pool, Startgröße 65535, verdoppelt bei Bedarf; `:487, 340-355`).

### 3.5 Wiederholungen / Zuverlässigkeit der Steuernachrichten

Es gibt keine allgemeine ACK-/Resend-Schicht (`UDPAgent.cs:59-60`). Zuverlässigkeit je Nachricht:

| Nachricht | Mechanismus |
|---|---|
| `RegisteringWithEmitter` | Sender wiederholt alle 250 ms (5 ms nach Erkennen von Verspätung) bis `RepeaterRegistered` |
| `RepeaterRegistered` | wird bei jeder (Wieder-)Anfrage erneut gesendet |
| `RepeaterWaitingToStartFrame` | Repeater wiederholt jede **1 ms**, bis `EmitterWaitingToStartFrame` ohne ihn in `WaitingOn` kommt (`RepeatFrameState.cs:272`) |
| `EmitterWaitingToStartFrame` | wird bei jeder Wiederholung des Repeaters neu gesendet; alte Frame-Indizes werden mit "wartet auf niemanden" beantwortet (`FrameWaitingToStartHandler.cs:218-228`) |
| `FrameData` | Anforderung per `RetransmitFrameData` (3.4) |
| `PropagateQuit` | alle 100 ms wiederholt, bis alle `QuitReceived` (`PropagateQuitState.cs:91`) |
| `QuitReceived` | einmalig, kein Resend (Repeater beendet sich danach); Verlust -> Emitter wiederholt `PropagateQuit` ohne Ende (unklar, ob dort ein Gesamt-Timeout greift; im Zustand selbst keiner) |
| `SurveyRepeaters` | Placeholder sendet alle 50 ms |
| Quadro-Nachrichten | alle 25 ms (Abschnitt 5) |

## 4. Pro-Frame-Ablauf

### 4.1 Einhängepunkte im PlayerLoop (`R/ClusterSyncLooper.cs`, `R/Utils/PlayerLoopExtensions.cs:26-60`)

| Haken | Ort im PlayerLoop | Aufruf |
|---|---|---|
| `SystemUpdate` | als eigenes Subsystem `ClusterDisplayStartFrame` unter `TimeUpdate.WaitForLastPresentationAndUpdateTime` angehängt (Index = Ende, `ClusterSyncLooper.cs:33-38`) | `PreFrame` -> `DoFrame` -> `PostFrame` (`:46-62`) |
| `SystemLateUpdate` | Subsystem `ClusterDisplayLateUpdate` unter `PostLateUpdate` (Ende) | `DoLateFrame` (nur Messungen) |
| `InputSystemReplicator.UpdateInputSystem` | unter `Update.ScriptRunBehaviourUpdate`, Index 0 (vor allen Skript-Updates) | `R/Scripting/InputSystemReplicator.cs:81` |

- `DoFrame` (Main Thread, blockierend) wartet also direkt nach dem Presentation-Wait und vor Update/FixedUpdate/Skripten. Ob Unity-seitiger Zeitfortschritt dort bereits berechnet ist ("...AndUpdateTime"), ist von der Reihenfolge der Kindsysteme abhängig: unklar.
- Fehler: jede Exception in `PreFrame/DoFrame/PostFrame` -> `OnException` -> `Terminate()` (setzt `IsTerminated`, `Application.Quit()`), danach `CleanUp` (`R/ClusterSync.cs:529-543`, `R/ClusterSyncState.cs:101-109`).

### 4.2 Emitter, Frame N (`EmitFrameState.DoFrameImplementation`, `:44-120`)

1. Quit angefordert (`InternalMessageQueue<InternalQuitMessage>`)? -> `PropagateQuitState`.
2. Delay-Sonderfall (`RepeatersDelayed` und erster Frame): nur `GatherPreFrameState`, kein Warten, kein Senden (`:55-59`).
3. `effectiveFrameIndex = RepeatersDelayed ? N-1 : N`.
4. Netzwerk-Fence (solange `m_UsingNetworkSync`): `FrameWaitingToStartHandler.TryWaitForAllRepeatersReady(effectiveFrameIndex, EffectiveCommunicationTimeout)` blockiert auf `Monitor.Wait`, bis alle `RepeaterWaitingToStartFrame` für diesen Index da sind (`FrameWaitingToStartHandler.cs:79-135`). Beim Failover-Start wird der erste Wait übersprungen (`skipFirstNetworkSync`).
5. Danach `PrepareForNextFrame(effectiveFrameIndex+1)`; liefert `false`, wenn kein Repeater mehr Netzwerksync nutzt -> Fence entfällt dauerhaft (`:105`).
6. `GatherFrameState()` und `PublishCurrentState(effectiveFrameIndex, splitter)`: serialisiert und sendet alle Fragmente (`EmitterStateWriter.cs:107-198`).

Der Emitter wartet also vor dem Senden auf die Repeater (diese melden "bereit für Frame N", nachdem sie Frame N-1 beendet haben), sendet dann Frame N.

### 4.3 Repeater, Frame N (`RepeatFrameState.DoFrameImplementation`, `:50-145`)

1. Deadline für alles: `EffectiveCommunicationTimeout + 1 s` (`:57-58`).
2. Falls der Emitter eine Bereit-Meldung erwartet (`m_EmitterExpectingNotificationOnStart`, initial true): `PerformNetworkSynchronization` (`:155-253`): sendet `RepeaterWaitingToStartFrame{N, NodeId, WillUseNetworkSyncOnNextFrame=UsingNetworkSync}`, wiederholt alle 1 ms; wartet auf `EmitterWaitingToStartFrame` für N. Kommt `FrameData` für N vorher an (Verlust der Antwort), wird es direkt übernommen. Andere Frame-Indizes: `FrameData` != N oder `EmitterWaitingToStartFrame` > N -> `InvalidDataException`; ältere werden ignoriert.
3. `FrameDataAssembler.WillNeedFrame(N)` aktiviert den Retransmit-Monitor (`:84`).
4. Schleife bis Deadline: `TryConsumeNextReceivedMessage` mit maximal 200 ms je Warteschritt (`s_MaxWaitForSingleMessage`, `:279`); `FrameData` -> weiter, `PropagateQuit` -> `ProcessQuitMessageState`, alles andere wird verworfen.
5. Kein `FrameData` vor Deadline -> `TimeoutException`; `FrameIndex != N` -> `InvalidDataException`.
6. `RepeaterStateReader.RestoreEmitterFrameData(extraData)` wendet die Blöcke an (4.5), `LastReceivedFrameIndex = N`. Frame ist erledigt; Unity läuft weiter.

### 4.4 Delay-Modus (`DelayRepeaters`)

Der Emitter gathert den Zustand des Frames N-1 und sendet ihn im Frame N mit Index N-1 (`EmitFrameState.cs:55-61`, `EmitterStateWriter.GatherFrameState`, `:186-198`: erst stagen, dann neu sammeln). Repeater laufen dadurch einen Frame hinter dem Emitter. Details des Zusammenspiels mit Present/Quadro siehe `QuadroSyncInitEmitterState.cs:28-32` (`m_PresentToSkip`).

### 4.5 Reihenfolge und Inhalt der Nutzlast-Blöcke (`StateID`, `NetworkMessages.cs:13-22`)

| StateID | Wert | Wer schreibt | Wer liest | Inhalt/Format | Zeitpunkt |
|---|---|---|---|---|---|
| `End` | 0 | `EmitterStateWriter.StageCurrentStateBuffer` (`:163`) | `FrameDataEnumerator` beendet die Iteration (`FrameDataBuffer.cs:303`) | `id=0,size=0` | zuletzt |
| `Time` | 1 | `ClusterSerialization.SaveTimeManagerState` (`EmitterStateWriter.cs:24`) | `ClusterSerialization.RestoreTimeManagerState` (`RepeaterStateReader.cs:20`) | Format und Größe unklar: Methoden sind Teil der Unity-Engine-API (`[Obsolete]`, in diesem Repo nicht definiert), Binärlayout nicht einsehbar | 1. Block (`GatherPreFrameState`) |
| `Input` | 2 | niemand (reserviert, ehemals Legacy Input Manager, entfernt in M-25) | niemand | darf nicht wiederverwendet werden; unbekannte IDs werden vom Reader ignoriert | - |
| `Random` | 3 | `SaveRandomState` = `UnityEngine.Random.state` als Struct (`EmitterStateWriter.cs:180-184`) | `RestoreRndGeneratorState`: memcpy in `Random.State`, setzt `Random.state` (`RepeaterStateReader.cs:77-90`) | `Random.State` (vier `int`, 16 Byte nach Struktur; Größe zur Laufzeit per `Marshal.SizeOf`) | 2. Block |
| `CustomEvents` | 4 | `EventBus.SerializeAndFlush` (`R/Events/EventBus.cs:61-83, 213-228`) | `EventBus.DeserializeAndPublish` | `IdType` (Typkennung) + Array von `TEvent` blittable | Custom-Phase |
| `InputSystem` | 5 | `InputSystemReplicator.WriteInputData` (`R/Scripting/InputSystemReplicator.cs:110, 256-268`) | `LoadInputData` (`:115, 209-254`) | serialisierter `InputEventTrace`-Strom (Länge variabel, 0 erlaubt); wird nur bei `InputSync.InputSystem` registriert | Custom-Phase |
| 128 (kein Enum-Eintrag) | 128 | `RPCBufferIO.Latch` (`source/com.unity.cluster-display.rpc/Runtime/Buffer/RPCBufferIO.cs:25, 76`) | `Unlatch` (`:75`) | RPC-Puffer (bis `ushort.MaxValue`) | Custom-Phase |

Reihenfolge im Puffer: erst die fest eingebauten Zustände `Time`, `Random` (`GatherPreFrameState`, `EmitterStateWriter.cs:22-26, 123-144`), dann die registrierten Custom-Writer (`StageCurrentStateBuffer`, `:146-172`) in der Iterationsreihenfolge des `Dictionary<int, List<...>>` (`:36`), dann `End`. Die Reihenfolge der Custom-Blöcke hängt also von der Registrierreihenfolge der Schlüssel ab (bei `Dictionary` ohne Entfernungen praktisch Einfügereihenfolge, nicht garantiert: unklar).
Leseseite: `RestoreEmitterFrameData` iteriert die Blöcke in Paketreihenfolge; je ID werden alle registrierten Delegates aufgerufen; Rückgabewerte (`bool`) werden ignoriert (`RepeaterStateReader.cs:62-75`).

### 4.6 Timeouts und Fehlverhalten

| Parameter | Default | Quelle | Bedeutung |
|---|---|---|---|
| `HandshakeTimeout` | 10 000 ms | `ClusterParams.Default` (`R/ClusterParams.cs:129`) | Registrierung; zusätzlich Effektiv-Timeout für Frame 0 und 1 |
| `CommunicationTimeout` | 5 000 ms | `ClusterParams.Default` (`:130`) | ab Frame 2 für Emitter-Wait und Repeater-Wait |
| `EffectiveCommunicationTimeout` | - | `R/Node/ClusterNode.cs:103-104` | `FrameIndex > 1 ? Communication : Handshake` |
| Repeater-Gesamtdeadline | Effektiv + 1 s | `RepeatFrameState.cs:57` | Absicht: Emitter soll zuerst ausfallende Repeater droppen |
| Einzelwarten Repeater | 200 ms | `RepeatFrameState.cs:279` | nur zum Prüfen externer Änderungen |
| Quadro-Warmup-Deadline | `HandshakeTimeout` | `QuadroSyncInit*State` | siehe Abschnitt 5 |

Überschreibung: Settings-Asset (`ClusterDisplaySettings.Current.ClusterParams`), Kommandozeile (`-handshakeTimeout`, `-communicationTimeout`, in ms; `ClusterParams.cs:206-214`), MissionControl (`R/MissionControl/MissionControlClusterParamExtensions.cs:46-53`). Ob der Settings-Asset-Wert vom Default abweicht, wurde nicht geprüft (unklar).

Verhalten:
- **Paketverlust FrameData**: Repeater fordert nach 4 ms Stille Fragmente nach (Abschnitt 3.4), Emitter sendet erneut. Verlust von `RepeaterWaitingToStartFrame`/`EmitterWaitingToStartFrame` -> Wiederholung alle 1 ms.
- **Repeater fällt aus/antwortet nicht**: Emitter-Wait läuft ab -> `Debug.LogError`, Repeater werden aus Warteliste und `RepeatersStatus` entfernt, Emitter macht weiter (`EmitFrameState.cs:74-100`). Es gibt keine Neuaufnahme (`Accepted=false`).
- **Emitter fällt aus**: Repeater läuft in `TimeoutException` (Effektiv-Timeout + 1 s) -> `OnException` -> `Terminate()` -> Anwendung beendet sich (Backups können vorher per Topologieänderung übernehmen, 1.3).
- **Rest-Nodes bei Emitter-Wait-Timeout, falls Emitter nicht mehr Emitter ist** (Topologie): Emitter beendet sich, statt zu droppen (`:80-86`).
- **Frame-Index-Abweichung** (Repeater sieht zu hohen Index): `InvalidDataException` -> Terminate. Es gibt keinen Resync-Pfad.
- **Hardware-Fence** (`Fence=Hardware`): `UsingNetworkSync` wird nach der Quadro-Initialisierung auf `false` gesetzt (`QuadroSyncInitState.cs:101`); Repeater melden dann `WillUseNetworkSyncOnNextFrame=false`, und der Emitter lässt die Fence fallen, sobald alle abgemeldet sind. Eine Rückkehr zum Netzwerksync gibt es nicht ("no getting back in", `NetworkMessages.cs:250-252`). `External` setzt `UsingNetworkSync=false` von Anfang an (`ClusterNode.cs:248-252`).

## 5. Quadro-Barrier-Warmup (nur `Fence=Hardware`, Windows)

- Auslöser: `HardwareSyncInitState.Create` liefert unter `UNITY_STANDALONE_WIN` `QuadroSyncInitEmitterState`/`QuadroSyncInitRepeaterState`, sonst eine leere Warnung (`R/States/HardwareSyncInitState.cs:18-30`). Init setzt `vSyncCount=1`, `maxQueuedFrames=1` und ruft die Gfx-Plugin-Initialisierung (`R/QuadroSync/QuadroSyncInitState.cs:19-37`).
- Ablauf (3 Phasen, `QuadroBarrierWarmupStage`, `NetworkMessages.cs:341-360`):
  1. `RepeaterFastPresent`: Repeater present so schnell wie möglich; ein Present > 150 ms (`k_BlockDelay`) zeigt: Barrier steht -> `Status{Stage=0, Completed=true}`.
  2. `RepeatersPaused`: Emitter setzt die Phase per `Heartbeat`, Repeater pausieren und bestätigen; der Emitter zählt Presents bis zum Blockieren (Queue-Länge, `AdditionalPresentCount = präsentierte / 2`).
  3. `LastRepeatersBurst`: Repeater präsentieren `AdditionalPresentCount` weitere Frames, melden `Completed`; Barrier gilt als aufgewärmt.
- Wiederholung: Emitter-Thread sendet den Heartbeat alle 25 ms (`k_RepeatMessageInterval`, `QuadroSyncInitState.cs:126`; `QuadroSyncInitEmitterState.cs:299-343`); Repeater-Thread sendet den Status alle 25 ms (`QuadroSyncInitRepeaterState.cs:135-180`).
- Abbruch: Deadline `HandshakeTimeout` ab Start -> `BarrierWarmupTimeout` -> `Terminate()` (Emitter); bei Terminierung `UnexpectedTermination`.
- Die Warmup-Callbacks laufen im Render-Thread (`BarrierWarmupCallback`, Kommentar "Called from the rendering thread", `QuadroSyncInitEmitterState.cs:49-53`), blockieren dort (`Thread.Sleep`, `AutoResetEvent.WaitOne`) und sperren mit `m_Lock`; Sniffer laufen im Empfangs-Thread.
- Wechsel Backup -> Emitter bei `RepeatersDelayedOneFrame` löst ein einmaliges `QuadroSyncSkipSyncForNextFrame` aus (`QuadroSyncInitRepeaterState.cs:346-366`).

## 6. Beobachtungen und Risiken (keine Fakten über Soll-Verhalten; bewertet für Änderungen)

Aus dem Code ableitbare Folgerungen bzw. Hinweise. Sie sind kein Test-Ergebnis.

Protokoll/Format
1. Kein Magic und keine Protokollversion (3.2). CLAUDE.md fordert "Wire-Format nur mit Protokollversion ändern": dafür fehlt zuerst das Feld; ein Header-Byte oder ein Handshake-Check (z. B. in `RegisteringWithEmitter`/`RepeaterRegistered`) muss selbst eingeführt werden und ändert das Format.
2. `MaximumMessageSize = Mtu - 1` zieht IP-/UDP-Header (28 Byte) nicht ab (`UDPAgent.cs:89`) -> volle `FrameData`-Fragmente überschreiten bei MTU 1500 den Ethernet-Frame und werden IP-fragmentiert; ein verlorenes IP-Fragment verliert das ganze Datagramm. `wire-format.md` empfiehlt ~1400 Byte Nutzlast. Fix würde `m_MaxDataPerMessage` und damit die Fragmentgrenzen ändern (nur geräteweit konsistent).
3. Empfangspuffer ist `byte[MTU]` (`UDPAgent.cs:124`); gleichen MTU-Wert auf allen Nodes vorausgesetzt (Jumbo-/gemischte MTU: größere Datagramme werden abgeschnitten/werfen `SocketException`, Verhalten unklar).
4. Keine Endianness-Festlegung, `bool` als 1 Byte, `Random.State` als opaques Struct der Engine: Format hängt von Unity-Version ab (Cluster mit gemischten Unity-Versionen nicht tragfähig).
5. `Time`-Zustand ist Engine-intern (`ClusterSerialization`, obsolet, M-41/M-42). Ersatz ändert das Format -> Protokollversion einführen (Backlog M-42).
6. Alle Nachrichten gehen über Multicast, auch "Unicast-artige". Ein Wechsel auf Unicast pro Repeater verändert die Skalierung (n Sends pro Frame).
7. IGMP/TTL=1: nur ein Hop; Router-/VLAN-Setups funktionieren nicht ohne Codeänderung (`UDPAgent.cs:100-102`).

Threads/Zustand
8. Mehrere Threads rufen `UdpAgent.SendMessage` parallel (Main Thread, Empfangs-Thread-Pre-Processors, Monitor-Thread, Quadro-Threads); der Send-Pfad nutzt einen `ConcurrentObjectPool`, der gemeinsame `UdpClient` wird ohne weiteres Locking benutzt (thread-sicher laut .NET-Dokumentation für Send, nicht geprüft).
9. Pre-Processors dürfen nicht lange blockieren: `FrameDataSplitter` hält während des Wiedersendens ein Lock (`:206-268`); `FrameWaitingToStartHandler` sendet unter Lock (`:188-234`). Der Kommentar in `QuadroSyncInitRepeaterState.cs:122-127` nennt ein bekanntes Deadlock-Risiko beim `RemovePreProcess` aus einem Pre-Process.
10. Statische Zustände: `EmitterStateWriter.k_CustomDataDelegates`, `RepeaterStateReader.k_LoadDataDelegates`, statische Pools in `ReceivedMessage<T>` (`IUdpAgent.cs:229`), `ClusterSyncLooper`-Events, `InputSystemReplicator.s_InjectedReplicator`, `UdpAgent.s_EmptyNativeArray`, `s_ReceiveMessageTypes`. Mehrere `ClusterSync`-Instanzen im selben Prozess teilen sich diese Zustände (Tests: `StaticStateResetTests`).
11. `ReceivedMessage<T>`-Fabriken per Reflection (`SetupReceiveMessageFactory`) -> bei IL2CPP/Stripping anfällig; im Scope ist Mono, daher vermutlich unkritisch (unklar).
12. `UsingNetworkSync` und `LastReceivedFrameIndex` werden vom Empfangs-Thread gelesen (Survey-Antwort, `RepeaterNode.cs:155-160`) und im Main Thread geschrieben, ohne Synchronisation.
13. `ClusterTopology.Changed` kommt auf beliebigem Thread (Kommentar `ClusterTopology.cs:43-45`); Handler nehmen Locks (`EmitterPlaceholder.cs:421-456`).

Allokationen im Pfad
14. `UdpClient.Send(..., IPEndPoint)` allokiert pro Send (Kommentar im Code). Pro Frame mehrere Sends (Fragmente, WaitingToStart, Retransmits).
15. `BitArray`/`bool[]`-Wachstum in `PartialFrameData` und `GrowDatagramSentTimestampArrayIfNeeded` allokiert nur bei größeren Frames (selten).
16. `ReceivedMessage<T>` und Puffer sind gepoolt; `AsManagedArray()` im `NativeExtraData` allokiert bei Aufruf (`FrameDataAssembler.cs:573-584`), der Normalpfad nutzt `AsNativeArray`.
17. `EmitterPlaceholder` und die Fehlerpfade (LINQ, Dictionaries) allokieren bewusst (Kommentar `EmitterPlaceholder.cs:28-31`).
18. `InputSystemReplicator.LoadInputData` kopiert via `MemoryStream` und `ReadFrom` ("not alloc-free", Kommentar `:226`).

Sync-Semantik
19. `EmitterStateWriter`: Schlägt `Store` irgendeines Blocks fehl (Exception), wird nur geloggt und der Frame **nicht** gesendet (`m_StagedFrameDataValid=false`, `:153-170`, `:109-112`). Repeater laufen dann in den Timeout (Terminate nach Timeout). Kein Fehlerpaket und keine Warnung über `ClusterDebug.Log` hinaus.
20. Reader ignoriert unbekannte `StateID`s und Rückgabewerte der Delegates; ein Block, den ein Repeater nicht registriert hat, geht still verloren (z. B. `InputSync`-Mismatch Emitter/Repeater, `ClusterSync.cs:295-333`).
21. Die Reihenfolge der Custom-Blöcke ist nicht explizit festgelegt (4.5).
22. `RepeaterWaitingToStartFrame` mit Frame-Index > Emitter-Index wirft `InvalidDataException` auf dem Empfangs-Thread (`FrameWaitingToStartHandler.cs:229-232`); die Exception wird im Pre-Process-Loop gefangen und nur geloggt (`UDPAgent.cs:485-488`), das Paket geht nicht weiter. Ob der Repeater dadurch hängt, ist unklar.
23. Nachrichten gelten für jeden Sender im Netz (3.2); `NodeId`-Konflikte werden über IP erkannt, nicht über Authentifizierung.
24. Der Handshake blockiert den Main Thread im ersten Frame bis zu `HandshakeTimeout` (10 s Default). Kein async; entspricht Regel 3.
25. Dokumentations-Drift: `wire-format.md` und `SKILL.md` §4 beschreiben ein anderes (Soll-)Format (Header mit Magic/Version/Länge, 20 Byte, `FrameState`-Struct). Der Ist-Code kennt davon nichts.

## 7. Offene Punkte / unklar

- Wire-Größe der leeren Structs `PropagateQuit` und `SurveyRepeaters` (C# `sizeof` 1 vs. 0).
- Binärformat des `Time`-Blocks (Engine-API `ClusterSerialization`).
- Reihenfolge innerhalb von `TimeUpdate.WaitForLastPresentationAndUpdateTime` relativ zum Zeitupdate.
- Produktiver Aufrufer von `ChangeClusterTopology` (Capcom/MissionControl vermutet, nicht verfolgt).
- Tatsächliche Default-Werte im Settings-Asset (`ClusterDisplaySettings`).
- Verhalten bei abweichender MTU zwischen Nodes und bei IP-Fragmentverlust (nicht getestet).
