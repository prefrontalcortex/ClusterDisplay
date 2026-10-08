using System;
using UnityEngine;
using Unity.ClusterDisplay.Graphics.Example;

public class RuntimeGUI
{
}

[ExecuteAlways]
public class CustomRuntimeGUI : RuntimeGUI
{
    [SerializeField]
    SwitchAntiAliasing m_SwitchAntiAliasing;
    
    [SerializeField]
    SwitchVolumeProfiles m_SwitchVolumeProfiles;

    public void OnCustomGUI()
    {
        if (m_SwitchVolumeProfiles != null)
            m_SwitchVolumeProfiles.DrawGUI();
        
        if (m_SwitchAntiAliasing != null)
            m_SwitchAntiAliasing.DrawGUI();
    }
}
