using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.RenderGraphModule;
using UnityEngine.Rendering.RenderGraphModule.Util;
using UnityEngine.Rendering.Universal;

public class CustomRenderPass : ScriptableRenderPass
{
    const string k_ShaderPath = "Hidden/Test/CustomRenderPass";
    const string k_PassName = "Screen Coord Override";

    Material m_Material;

    public CustomRenderPass(RenderPassEvent renderPassEvent)
    {
        this.renderPassEvent = renderPassEvent;
        m_Material = CoreUtils.CreateEngineMaterial(k_ShaderPath);
    }

    public override void RecordRenderGraph(RenderGraph renderGraph, ContextContainer frameData)
    {
        // The API implied lifecycle has proved unreliable.
        if (m_Material == null)
        {
            return;
        }

        var resourceData = frameData.Get<UniversalResourceData>();
        var source = resourceData.activeColorTexture;

        var descriptor = renderGraph.GetTextureDesc(source);
        descriptor.name = "_TempTex";
        descriptor.clearBuffer = false;
        var temp = renderGraph.CreateTexture(descriptor);

        // Apply the material (screen coord dependent effect) in a temporary texture then copy it back.
        renderGraph.AddBlitPass(new RenderGraphUtils.BlitMaterialParameters(source, temp, m_Material, 0), k_PassName);
        renderGraph.AddCopyPass(temp, source, k_PassName + " Copy");
    }

    public void Cleanup()
    {
        CoreUtils.Destroy(m_Material);
    }
}
