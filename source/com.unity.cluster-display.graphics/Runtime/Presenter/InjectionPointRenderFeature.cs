#if CLUSTER_DISPLAY_URP
using System;
using UnityEngine.Rendering;
using UnityEngine.Rendering.RenderGraphModule;
using UnityEngine.Rendering.Universal;

namespace Unity.ClusterDisplay.Graphics
{
    /// <summary>
    /// A render pass whose purpose is to invoke an event at the desired stage of rendering.
    /// </summary>
    /// <remarks>Records its work in the Render Graph, the only path left in Unity 6.3+ (URP Compatibility Mode, the
    /// <c>Execute</c> based path, is deprecated and removed from Unity 6.4).  Subscribers add their own passes to the
    /// render graph from the event.</remarks>
    class InjectionPointRenderPass : ScriptableRenderPass
    {
        public static event Action<RenderGraph, ContextContainer> RecordRender = delegate {};

        public override void RecordRenderGraph(RenderGraph renderGraph, ContextContainer frameData)
        {
            RecordRender.Invoke(renderGraph, frameData);
        }
    }

    /// <summary>
    /// A render feature whose purpose is to provide an event invoked at a given rendering stage.
    /// Meant to abstract away the render feature mechanism and allow for simple graphics code injection.
    /// </summary>
    [DisallowMultipleRendererFeature("InjectionPoint")]
    public class InjectionPointRenderFeature : ScriptableRendererFeature
    {
        InjectionPointRenderPass m_Pass;

        public override void Create()
        {
            m_Pass = new InjectionPointRenderPass
            {
                // HACK: This is a temporary workaround for a URP bug so tests that use ScreenCapture can pass.
                renderPassEvent = RenderPassEvent.AfterRenderingPostProcessing,
                // Remove the line above and uncomment the line below once the the URP bug is resolved.
                // renderPassEvent = RenderPassEvent.AfterRendering,
            };
        }

        public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
        {
            renderer.EnqueuePass(m_Pass);
        }
    }
}
#endif
