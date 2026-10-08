using System.Threading;
using Unity.ClusterDisplay;
using UnityEngine;

public class RandomSleep : MonoBehaviour
{
    int m_Frame;

    void Update()
    {
        m_Frame++;
        if (m_Frame % 100 == 0 && ClusterDisplayState.TryGetRuntimeNodeId(out var nodeId))
        {
            var rnd = new System.Random(nodeId + Time.frameCount);
            var sleepTime = rnd.Next(1, 20);
            Thread.Sleep(sleepTime);
        }
    }
}
