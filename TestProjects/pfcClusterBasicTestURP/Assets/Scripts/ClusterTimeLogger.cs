using System;
using System.Globalization;
using Unity.ClusterDisplay;
using UnityEngine;

/// <summary>
/// Test utility: when the player is started with <c>-logClusterTime</c>, writes one line per 30 cluster frames with the
/// values that must be identical on every node (cluster frame id, Time.frameCount, Time.time, unscaledTime,
/// deltaTime).  Used to compare the log of the emitter with the one of the repeaters (time synchronization check).
/// </summary>
public class ClusterTimeLogger : MonoBehaviour
{
    [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.AfterSceneLoad)]
    static void Create()
    {
        if (Array.IndexOf(Environment.GetCommandLineArgs(), "-logClusterTime") < 0)
        {
            return;
        }

        var go = new GameObject("ClusterTimeLogger") { hideFlags = HideFlags.HideAndDontSave };
        DontDestroyOnLoad(go);
        go.AddComponent<ClusterTimeLogger>();
    }

    void Update()
    {
        if (!ClusterDisplayState.GetIsActive() || !ClusterDisplayState.TryGetFrameId(out var frameId) || frameId % 30 != 0)
        {
            return;
        }

        var c = CultureInfo.InvariantCulture;
        Debug.Log($"CTL cframe={frameId} frameCount={Time.frameCount} time={Time.time.ToString("R", c)} " +
            $"unscaled={Time.unscaledTime.ToString("R", c)} dt={Time.deltaTime.ToString("R", c)}");
    }
}
