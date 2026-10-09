# Changes in Cluster Display Graphics

## [Unreleased] - Unity 6.3 LTS migration

### Changed
* Requires Unity 6.3 LTS (URP / HDRP 17.3).
* URP: the present pass is recorded in the Render Graph (URP Compatibility Mode is no longer needed; it is removed in Unity 6.4). The Render Graph present path is covered by the URP image tests (43/43).
* Editor: reflection on URP internals replaced with public APIs where they exist.

### Fixed
* The check that refuses player builds stripping the Screen Coord Override shader variants never worked with URP 17 (and logged an error per shader).
* `NullReferenceException` in `ClusterRendererMissionControlUtils` when the player is not started by Mission Control.

### Tested
* HDRP: 50/50 graphics tests, URP: 43/43 (Forward and Forward+ rendering paths, with point lights).

## [0.1.0-preview] 2020-08-01

Initial public release
