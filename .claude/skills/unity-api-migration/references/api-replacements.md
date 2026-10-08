# API-Ersatztabelle (Startpunkt)

Stand: Wissen bis Mitte 2026. Versionsangaben ungefähr – bei Abweichung gilt die `[Obsolete]`-Meldung des Compilers bzw. die Unity-Doku der Zielversion.

## Objektsuche
| Alt | Neu | Achtung |
|---|---|---|
| `FindObjectsOfType<T>()` | `FindObjectsByType<T>(FindObjectsSortMode.None)` | Alte Variante war nach InstanceID sortiert. Wenn Reihenfolge relevant ist (z. B. deterministische Iteration auf allen Nodes!), `FindObjectsSortMode.InstanceID` nehmen. InstanceIDs sind zwischen Nodes nicht garantiert gleich – für Cluster-Determinismus eigene stabile IDs verwenden. |
| `FindObjectOfType<T>()` | `FindFirstObjectByType<T>()` oder `FindAnyObjectByType<T>()` | `Any` ist schneller, aber nicht deterministisch. |
| `FindObjectsOfType<T>(true)` | `FindObjectsByType<T>(FindObjectsInactive.Include, …)` | |

## Player Loop / Timing
| Alt | Neu | Achtung |
|---|---|---|
| `UnityEngine.Experimental.LowLevel.PlayerLoop` | `UnityEngine.LowLevel.PlayerLoop` | `PlayerLoopSystem` liegt in `UnityEngine.LowLevel`, die Subsystem-Typen in `UnityEngine.PlayerLoop`. Zentral für Frame-Lock-Injektion. |
| `Experimental.PlayerLoop.*` Typen | `UnityEngine.PlayerLoop.*` | |

## Input
| Alt | Neu | Achtung |
|---|---|---|
| `Input.GetKey/GetAxis/mousePosition` | `Keyboard.current`, `Mouse.current`, `InputAction` | Im Cluster über Snapshot replizieren (siehe SKILL.md). Player Settings → Active Input Handling prüfen. |
| `Input.GetTouch` | `EnhancedTouch` / `Touchscreen.current` | |

## Rendering (Built-in → SRP)
| Alt | Neu (URP/HDRP) | Achtung |
|---|---|---|
| `OnPreRender` / `Camera.onPreRender` | `RenderPipelineManager.beginCameraRendering` | Feuert für jede Kamera, inkl. Scene-View/Reflection – Kamera filtern. |
| `OnPostRender` / `Camera.onPostRender` | `RenderPipelineManager.endCameraRendering` | |
| `Camera.onPreCull` | `beginCameraRendering` (vor Culling in URP) | Zeitpunkt pipelineabhängig prüfen. |
| `OnRenderImage` | URP: `ScriptableRendererFeature`; HDRP: Custom Pass / Custom Post Process | Kein 1:1-Ersatz; eigener Task. URP-Renderer-Feature-API hat sich in Unity 6 (Render Graph) geändert. |
| `GraphicsSettings.renderPipelineAsset` | `GraphicsSettings.defaultRenderPipeline` (bzw. `currentRenderPipeline` zum Lesen des aktiven) | |
| `Display.displays[i].Activate()` | weiterhin gültig | Multi-Display pro Node meist unkritisch. |

## Netzwerk
| Alt | Neu | Achtung |
|---|---|---|
| `UnityEngine.Networking` (UNet HLAPI/LLAPI, `NetworkTransport`) | in aktuellen Unity-Versionen nicht verfügbar → `System.Net.Sockets` oder Unity Transport | Entscheidung gehört zu `cluster-sync-network`, nicht hier. Nur Compile-Blocker isolieren. |
| `WWW` | `UnityWebRequest` | |

## Serialisierung
| Alt | Neu | Achtung |
|---|---|---|
| `BinaryFormatter` | `BinaryPrimitives` / `MemoryMarshal` auf blittable structs | BinaryFormatter ist unsicher und in .NET obsolet. |

## Sonstiges
| Alt | Neu |
|---|---|
| `Application.isPlayer` / alte Plattform-Enums | Compiler-Meldung folgen |
| `PrefabUtility` Legacy-Methoden | Compiler-Meldung folgen |
| `AssetDatabase` Experimental-APIs | Compiler-Meldung folgen |
