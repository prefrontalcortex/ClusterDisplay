#if CLUSTER_DISPLAY_URP
using System;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.RenderGraphModule;
using UnityEngine.Rendering.Universal;

namespace Unity.ClusterDisplay.Graphics
{
    class UrpPresenter : SrpPresenter, IPresenter
    {
        const string k_PassName = "Present To Screen";

        public Color ClearColor
        {
            set => m_ClearColor = value;
        }

        public Camera Camera => m_Camera;

        public override void Enable(GameObject gameObject)
        {
            m_Camera = gameObject.GetOrAddComponent<Camera>();
            m_Camera.hideFlags = HideFlags.NotEditable | HideFlags.DontSave | HideFlags.HideInHierarchy;

            // We use the camera to blit to screen.
            // Configure it to minimize wasteful rendering.
            m_Camera.targetTexture = null;
            m_Camera.cullingMask = 0;
            m_Camera.clearFlags = CameraClearFlags.Nothing;
            m_Camera.depthTextureMode = DepthTextureMode.None;

            base.Enable(gameObject);
        }

        protected override void Bind(bool delayed)
        {
            if (delayed)
            {
                InjectionPointRenderPass.RecordRender += RecordPresentDelayed;
            }
            else
            {
                InjectionPointRenderPass.RecordRender += RecordPresent;
            }
        }

        protected override void Unbind(bool delayed)
        {
            if (delayed)
            {
                InjectionPointRenderPass.RecordRender -= RecordPresentDelayed;
            }
            else
            {
                InjectionPointRenderPass.RecordRender -= RecordPresent;
            }
        }

        class PassData
        {
            public UrpPresenter Presenter;
            public TextureHandle BackBuffer;
            public RenderTextureDescriptor Descriptor;
            public bool Delayed;
        }

        void RecordPresent(RenderGraph renderGraph, ContextContainer frameData) =>
            RecordPresent(renderGraph, frameData, false);

        void RecordPresentDelayed(RenderGraph renderGraph, ContextContainer frameData) =>
            RecordPresent(renderGraph, frameData, true);

        void RecordPresent(RenderGraph renderGraph, ContextContainer frameData, bool delayed)
        {
            var cameraData = frameData.Get<UniversalCameraData>();

            // The render pass gets invoked for all cameras so we need to filter.
            if (cameraData.camera != m_Camera)
            {
                return;
            }

            var resourceData = frameData.Get<UniversalResourceData>();

            // The work is done with a CommandBuffer (the Present event hands one to our subscribers), which is what an
            // unsafe pass gives access to.
            using (var builder = renderGraph.AddUnsafePass<PassData>(k_PassName, out var passData))
            {
                var descriptor = cameraData.cameraTargetDescriptor;
                descriptor.depthBufferBits = 0;
                descriptor.msaaSamples = 1;

                passData.Presenter = this;
                passData.BackBuffer = resourceData.activeColorTexture;
                passData.Descriptor = descriptor;
                passData.Delayed = delayed;

                builder.UseTexture(passData.BackBuffer, AccessFlags.Write);
                builder.AllowPassCulling(false);
                builder.SetRenderFunc(static (PassData data, UnsafeGraphContext context) =>
                    data.Presenter.ExecutePresent(data, context));
            }
        }

        void ExecutePresent(PassData data, UnsafeGraphContext context)
        {
            var cmd = CommandBufferHelpers.GetNativeCommandBuffer(context.cmd);
            RTHandle backBuffer = data.BackBuffer;
            if (data.Delayed)
            {
                DoPresentDelayed(cmd, data.Descriptor, backBuffer, false);
            }
            else
            {
                DoPresent(cmd, backBuffer, false);
            }
        }
    }
}
#endif
