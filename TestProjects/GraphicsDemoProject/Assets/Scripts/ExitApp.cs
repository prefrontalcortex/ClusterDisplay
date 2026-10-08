using Unity.ClusterDisplay;
using Unity.ClusterDisplay.Utils;
using UnityEngine;

public class ExitApp : MonoBehaviour
{
    void Update()
    {
        // Prüfen, ob die Cluster-Logik aktiv ist (ersetzt früheres ClusterSync.Active)
        if (ClusterDisplayState.GetIsActive())
        {
            if (Input.GetKey(KeyCode.LeftControl) && Input.GetKeyDown(KeyCode.Q))
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
        }
        else
        {
            // Ermittelt, ob die Cluster-Logik terminiert ist (neue Try-API)
            ClusterDisplayState.TryGetIsTerminated(out var isTerminated);
            if (isTerminated)
                Application.Quit(0);
        }
    }
}
