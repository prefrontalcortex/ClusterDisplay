using Unity.ClusterDisplay;
using UnityEngine;

[RequireComponent(typeof(UnityEngine.UI.Text))]
public class DebugComponent : MonoBehaviour
{
    private int frmaes;
    // Start is called before the first frame update
    void Start()
    {
        frmaes = 0;
        var text = this.GetComponent<UnityEngine.UI.Text>();
        if (ClusterDisplayState.GetIsActive())
        {
            text.text = $"Node {ClusterSync.Instance.DynamicLocalNodeId}";
        }
        else
        {
            text.text = "Cluster Rendering inactive";
        }
    }

    void Update()
    {
        frmaes++;
        var text = this.GetComponent<UnityEngine.UI.Text>();
        if (ClusterDisplayState.GetIsActive())
        {
            // Falls vorhanden, die Cluster-Instanz anweisen, sich zu terminieren
            if (ServiceLocator.TryGet<IClusterSyncState>(out var state))
            {
                state.Terminate();
            }
            else
            {
                // Fallback: kein Cluster-State vorhanden -> Anwendung beenden
                Application.Quit(0);
            }
        }
        else
        {
            // Ermittelt, ob die Cluster-Logik terminiert ist (neue Try-API)
            ClusterDisplayState.TryGetIsTerminated(out var isTerminated);
            if (isTerminated)
                Application.Quit(0);

            text.text = "Cluster Rendering inactive";
        }
    }

}
