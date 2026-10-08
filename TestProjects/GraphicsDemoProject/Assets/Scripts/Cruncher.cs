using System;
using Unity.ClusterDisplay;
using UnityEngine;
using Random = UnityEngine.Random;

// just crunch numbers to slow the machine down
public class Cruncher : MonoBehaviour
{
    void Update()
    {
        // if cluster is active and we are master (node id == 0)
        if (ClusterDisplayState.GetIsActive() &&
            ClusterDisplayState.TryGetRuntimeNodeId(out var nodeId) &&
            nodeId == 0 &&
            Input.GetKey(KeyCode.Space))
        {
            var sum = 0f;
            for (var i = 0; i != 10000000; ++i)
                sum += Random.value;
            Debug.Log(sum);
        }
    }
}
