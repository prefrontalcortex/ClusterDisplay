# Changes in Cluster Display

## [Unreleased] - Unity 6.3 LTS migration

### Changed
* Requires Unity 6.3 LTS (6000.3). Package dependencies updated (Collections 2.6, Newtonsoft Json 3.2, Input System, Mono Cecil 1.11).
* **Network protocol**: datagrams now have a header with a magic byte and a protocol version (all nodes must run the same version) and no longer exceed the network MTU (they were fragmented by the IP layer before).
* URP: the present pass is now recorded in the Render Graph (URP Compatibility Mode, removed in Unity 6.4, is no longer needed).
* Mission Control: .NET 8, clearer error messages when an asset (build) is refused, assets in an old format are refused, file paths are restricted to the asset folder.

### Added
* `TimeSync.FixedStep` / `-timeSync fixedStep`: time synchronization without `ClusterSerialization`.

### Removed
* Legacy Input Manager synchronization (`InputSync.Legacy`).

### Fixed
* Cluster logic did not start in the second play session when entering play mode without domain reload.
* Numbers in launch parameters and configuration were read according to the machine's culture.
* `NullReferenceException` in `ClusterRendererMissionControlUtils` when the player is not started by Mission Control.
* The check that refuses builds stripping the Screen Coord Override shader variants never worked with URP 17.

## [0.1.0-preview] 2023-08-01

Initial public release.
