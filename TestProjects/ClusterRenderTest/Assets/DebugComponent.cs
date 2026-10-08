using Unity.ClusterDisplay;
using Unity.ClusterDisplay.Utils;
using UnityEngine;

[RequireComponent(typeof(UnityEngine.UI.Text))]
public class DebugComponent : MonoBehaviour
{
    UnityEngine.UI.Text m_Text;

    void Start()
    {
        m_Text = GetComponent<UnityEngine.UI.Text>();
        if (ClusterDisplayState.GetIsActive() && ClusterDisplayState.TryGetRuntimeNodeId(out var nodeId))
        {
            m_Text.text = $"Node {nodeId}";
        }
        else
        {
            m_Text.text = "Cluster Rendering inactive";
        }
    }

    void Update()
    {
        if (ClusterDisplayState.GetIsActive() && ServiceLocator.TryGet<IClusterSyncState>(out var state))
        {
            m_Text.text = state.GetDiagnostics();

            // Shutdown (the whole cluster, termination is propagated by the emitter)
            if (Input.GetKeyUp(KeyCode.K) || Input.GetKeyUp(KeyCode.Q))
            {
                state.Terminate();
            }
        }
        else
        {
            if (ClusterDisplayState.TryGetIsTerminated(out var isTerminated) && isTerminated)
            {
                Application.Quit(0);
            }

            m_Text.text = "Cluster Rendering inactive";
        }
    }
}
